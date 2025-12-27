# 日本株自動売買システム - 取引時間・休場・祝日制御ロジック

## 概要

日本株式市場の取引時間、休場日、祝日を正確に管理し、**時間外シグナルの適切な処理**と**誤発注の防止**を実現するロジックを設計します。サーバー側での実装を想定した詳細設計を提供します。

---

## 1. 日本株式市場の基本仕様

### 1.1 取引時間（東京証券取引所）

```yaml
market_hours:
  timezone: "Asia/Tokyo"  # JST (UTC+9)

  trading_days:
    - Monday
    - Tuesday
    - Wednesday
    - Thursday
    - Friday

  sessions:
    morning:
      name: "前場"
      opening_auction: "08:00 - 09:00"  # 板寄せ
      continuous_trading: "09:00 - 11:30"
      closing_auction: "11:30"

    lunch_break:
      duration: "11:30 - 12:30"
      status: "closed"

    afternoon:
      name: "後場"
      opening_auction: "12:00 - 12:30"  # 板寄せ
      continuous_trading: "12:30 - 15:00"
      closing_auction: "15:00"

  after_hours:
    name: "時間外取引"
    available: false  # 現物株は時間外取引なし
    note: "ToSTNeT（立会外取引）は別システム"
```

### 1.2 年間スケジュール

```yaml
annual_schedule:
  regular_holidays:
    - "土曜日"
    - "日曜日"
    - "国民の祝日"
    - "年末年始（12/31, 1/1, 1/2, 1/3）"

  special_closures:
    - "大納会翌日（通常12/31または12/30）"
    - "システムメンテナンス日（事前告知）"
    - "台風等による臨時休場（稀）"

  partial_trading_days:
    - "大納会（12月最終営業日）: 12:30終了"
    - "※ただし2024年以降は通常通り15:00まで"
```

---

## 2. 取引時間制御ロジック

### 2.1 セッション判定

#### セッション状態の定義

```python
from enum import Enum
from datetime import datetime, time
import pytz

class MarketSession(Enum):
    """市場セッション状態"""
    PRE_MARKET = "pre_market"              # 市場前（0:00 - 8:00）
    MORNING_AUCTION = "morning_auction"    # 前場板寄せ（8:00 - 9:00）
    MORNING_TRADING = "morning_trading"    # 前場取引（9:00 - 11:30）
    LUNCH_BREAK = "lunch_break"            # 昼休み（11:30 - 12:30）
    AFTERNOON_AUCTION = "afternoon_auction"# 後場板寄せ（12:00 - 12:30）
    AFTERNOON_TRADING = "afternoon_trading"# 後場取引（12:30 - 15:00）
    POST_MARKET = "post_market"            # 市場後（15:00 - 24:00）
    CLOSED = "closed"                      # 休場日

class TradingStatus(Enum):
    """取引可否状態"""
    OPEN = "open"           # 取引可能
    CLOSED = "closed"       # 取引不可
    RESTRICTED = "restricted"  # 制限付き（板寄せ中等）
```

#### セッション判定ロジック

```python
class MarketHoursManager:
    def __init__(self):
        self.timezone = pytz.timezone('Asia/Tokyo')

        # 取引時間の定義
        self.morning_start = time(9, 0)
        self.morning_end = time(11, 30)
        self.afternoon_start = time(12, 30)
        self.afternoon_end = time(15, 0)

        # 板寄せ時間
        self.morning_auction_start = time(8, 0)
        self.afternoon_auction_start = time(12, 0)

    def get_current_session(self, dt: datetime = None) -> MarketSession:
        """現在のセッションを取得"""
        if dt is None:
            dt = datetime.now(self.timezone)
        else:
            dt = dt.astimezone(self.timezone)

        current_time = dt.time()
        weekday = dt.weekday()  # 0=Monday, 6=Sunday

        # 土日チェック
        if weekday >= 5:  # Saturday or Sunday
            return MarketSession.CLOSED

        # 祝日チェック（後述）
        if self.is_holiday(dt.date()):
            return MarketSession.CLOSED

        # 時間帯判定
        if current_time < self.morning_auction_start:
            return MarketSession.PRE_MARKET

        elif self.morning_auction_start <= current_time < self.morning_start:
            return MarketSession.MORNING_AUCTION

        elif self.morning_start <= current_time < self.morning_end:
            return MarketSession.MORNING_TRADING

        elif self.morning_end <= current_time < self.afternoon_auction_start:
            return MarketSession.LUNCH_BREAK

        elif self.afternoon_auction_start <= current_time < self.afternoon_start:
            return MarketSession.AFTERNOON_AUCTION

        elif self.afternoon_start <= current_time < self.afternoon_end:
            return MarketSession.AFTERNOON_TRADING

        else:  # >= 15:00
            return MarketSession.POST_MARKET

    def get_trading_status(self, session: MarketSession = None) -> TradingStatus:
        """セッションから取引可否を判定"""
        if session is None:
            session = self.get_current_session()

        # 取引可能セッション
        if session in [MarketSession.MORNING_TRADING, MarketSession.AFTERNOON_TRADING]:
            return TradingStatus.OPEN

        # 板寄せ中は制限付き
        elif session in [MarketSession.MORNING_AUCTION, MarketSession.AFTERNOON_AUCTION]:
            return TradingStatus.RESTRICTED

        # その他は取引不可
        else:
            return TradingStatus.CLOSED

    def is_market_open(self, dt: datetime = None) -> bool:
        """市場が開いているか（取引可能か）"""
        session = self.get_current_session(dt)
        status = self.get_trading_status(session)
        return status == TradingStatus.OPEN

    def is_trading_allowed(self, dt: datetime = None) -> bool:
        """自動売買を許可するか（板寄せ中は除外）"""
        session = self.get_current_session(dt)

        # 前場・後場の連続取引時間のみ許可
        allowed_sessions = [
            MarketSession.MORNING_TRADING,
            MarketSession.AFTERNOON_TRADING
        ]

        return session in allowed_sessions
```

### 2.2 推奨取引時間帯

```python
class SafeTradingWindows:
    """誤発注リスクを避けるための安全な取引時間帯"""

    def __init__(self):
        # 前場の推奨時間帯（寄付後30分〜引け前10分）
        self.morning_safe_start = time(9, 30)
        self.morning_safe_end = time(11, 20)

        # 後場の推奨時間帯（寄付後30分〜引け前30分）
        self.afternoon_safe_start = time(13, 0)
        self.afternoon_safe_end = time(14, 30)

    def is_safe_trading_time(self, dt: datetime = None) -> tuple[bool, str]:
        """
        安全な取引時間帯かチェック

        Returns:
            tuple[bool, str]: (is_safe, reason)
        """
        if dt is None:
            dt = datetime.now(pytz.timezone('Asia/Tokyo'))

        current_time = dt.time()

        # 前場の安全時間帯
        if self.morning_safe_start <= current_time <= self.morning_safe_end:
            return True, "morning_safe_window"

        # 後場の安全時間帯
        if self.afternoon_safe_start <= current_time <= self.afternoon_safe_end:
            return True, "afternoon_safe_window"

        # 寄付直後
        if time(9, 0) <= current_time < time(9, 30):
            return False, "too_close_to_morning_open"

        if time(12, 30) <= current_time < time(13, 0):
            return False, "too_close_to_afternoon_open"

        # 引け間際
        if time(11, 20) < current_time < time(11, 30):
            return False, "too_close_to_morning_close"

        if time(14, 30) < current_time < time(15, 0):
            return False, "too_close_to_afternoon_close"

        # その他の時間（取引時間外）
        return False, "outside_trading_hours"
```

---

## 3. 休場日・祝日管理

### 3.1 祝日データソース

#### 方式A: 静的データファイル（推奨・初期実装）

```yaml
# config/market_holidays.yaml
market_holidays:
  2025:
    - "2025-01-01"  # 元日
    - "2025-01-02"  # 年始休場
    - "2025-01-03"  # 年始休場
    - "2025-01-13"  # 成人の日
    - "2025-02-11"  # 建国記念の日
    - "2025-02-23"  # 天皇誕生日
    - "2025-03-20"  # 春分の日
    - "2025-04-29"  # 昭和の日
    - "2025-05-03"  # 憲法記念日
    - "2025-05-04"  # みどりの日
    - "2025-05-05"  # こどもの日
    - "2025-07-21"  # 海の日
    - "2025-08-11"  # 山の日
    - "2025-09-15"  # 敬老の日
    - "2025-09-23"  # 秋分の日
    - "2025-10-13"  # スポーツの日
    - "2025-11-03"  # 文化の日
    - "2025-11-23"  # 勤労感謝の日
    - "2025-12-31"  # 大納会翌日

  2026:
    # 2026年の祝日リスト
```

```python
import yaml
from datetime import date

class HolidayManager:
    def __init__(self, config_path: str = "config/market_holidays.yaml"):
        with open(config_path, 'r') as f:
            self.holidays_data = yaml.safe_load(f)

    def is_holiday(self, dt: date) -> bool:
        """指定日が祝日（休場日）か判定"""
        year = dt.year
        date_str = dt.strftime("%Y-%m-%d")

        if year not in self.holidays_data.get("market_holidays", {}):
            # データがない年は警告
            logger.warning(f"Holiday data not available for year {year}")
            return False

        return date_str in self.holidays_data["market_holidays"][year]

    def get_holidays(self, year: int) -> list[date]:
        """指定年の祝日一覧を取得"""
        holiday_strings = self.holidays_data["market_holidays"].get(year, [])
        return [date.fromisoformat(h) for h in holiday_strings]

    def get_next_trading_day(self, dt: date) -> date:
        """次の営業日を取得"""
        next_day = dt + timedelta(days=1)

        while True:
            # 土日チェック
            if next_day.weekday() >= 5:
                next_day += timedelta(days=1)
                continue

            # 祝日チェック
            if self.is_holiday(next_day):
                next_day += timedelta(days=1)
                continue

            # 営業日
            return next_day
```

#### 方式B: 外部API利用（拡張実装）

```python
import requests
from functools import lru_cache
from datetime import date, timedelta

class JapanHolidayAPI:
    """内閣府の祝日APIを使用（仮想的な例）"""

    def __init__(self):
        self.base_url = "https://api.example.com/japan-holidays"
        self.cache_ttl = 86400  # 1日キャッシュ

    @lru_cache(maxsize=365)
    def is_holiday(self, dt: date) -> bool:
        """APIで祝日判定（キャッシュ付き）"""
        try:
            response = requests.get(
                f"{self.base_url}/{dt.year}/{dt.month:02d}/{dt.day:02d}",
                timeout=5
            )
            response.raise_for_status()
            data = response.json()
            return data.get("is_holiday", False)

        except requests.RequestException as e:
            logger.error(f"Holiday API error: {e}")
            # Fallback: 静的データを使用
            return self._fallback_check(dt)

    def _fallback_check(self, dt: date) -> bool:
        """API障害時のフォールバック"""
        # 基本的な祝日のみチェック（固定日）
        fixed_holidays = [
            (1, 1),   # 元日
            (2, 11),  # 建国記念の日
            (4, 29),  # 昭和の日
            (5, 3),   # 憲法記念日
            (5, 4),   # みどりの日
            (5, 5),   # こどもの日
            (11, 3),  # 文化の日
            (11, 23), # 勤労感謝の日
        ]

        return (dt.month, dt.day) in fixed_holidays
```

#### 方式C: jpholiday ライブラリ使用（Python）

```python
import jpholiday

class JPHolidayManager:
    """jpholidayライブラリを使用した祝日管理"""

    def is_holiday(self, dt: date) -> bool:
        """祝日判定"""
        # jpholiday は日本の祝日を自動計算
        return jpholiday.is_holiday(dt)

    def get_holiday_name(self, dt: date) -> str | None:
        """祝日名を取得"""
        return jpholiday.is_holiday_name(dt)

    def is_market_holiday(self, dt: date) -> bool:
        """市場休場日判定（祝日 + 年末年始）"""
        # 祝日チェック
        if self.is_holiday(dt):
            return True

        # 年末年始（12/31, 1/2, 1/3）
        if (dt.month == 12 and dt.day == 31) or \
           (dt.month == 1 and dt.day in [2, 3]):
            return True

        return False
```

### 3.2 統合休場日判定

```python
class IntegratedMarketCalendar:
    """統合的な市場カレンダー管理"""

    def __init__(self):
        # プライマリ：静的データ
        self.holiday_manager = HolidayManager()

        # フォールバック：jpholiday
        self.jpholiday = JPHolidayManager()

    def is_trading_day(self, dt: date) -> bool:
        """営業日（取引日）か判定"""
        # 土日チェック
        if dt.weekday() >= 5:
            return False

        # 祝日チェック（静的データ）
        if self.holiday_manager.is_holiday(dt):
            return False

        # Fallback: jpholiday
        if self.jpholiday.is_market_holiday(dt):
            logger.warning(f"Holiday detected by fallback: {dt}")
            return False

        return True

    def get_market_status(self, dt: datetime = None) -> dict:
        """市場の総合ステータスを取得"""
        if dt is None:
            dt = datetime.now(pytz.timezone('Asia/Tokyo'))

        market_hours = MarketHoursManager()
        safe_windows = SafeTradingWindows()

        is_trading_day = self.is_trading_day(dt.date())
        current_session = market_hours.get_current_session(dt)
        trading_status = market_hours.get_trading_status(current_session)
        is_safe, safe_reason = safe_windows.is_safe_trading_time(dt)

        return {
            "datetime": dt.isoformat(),
            "is_trading_day": is_trading_day,
            "current_session": current_session.value,
            "trading_status": trading_status.value,
            "is_safe_trading_time": is_safe,
            "safe_time_reason": safe_reason,
            "can_trade": (
                is_trading_day and
                trading_status == TradingStatus.OPEN and
                is_safe
            )
        }
```

---

## 4. 時間外シグナルの扱い

### 4.1 時間外シグナル処理方針

```yaml
signal_handling_policy:
  during_trading_hours:
    action: "immediate_execution"
    validation: "all_checks"

  pre_market:
    action: "queue_for_opening"
    execution_time: "09:00 market open"
    note: "寄付成行として扱う可能性"

  lunch_break:
    action: "queue_for_afternoon"
    execution_time: "12:30 afternoon open"

  post_market:
    action: "reject_with_log"
    reason: "too_late_for_today"
    alternative: "queue_for_next_day (optional)"

  non_trading_days:
    action: "reject"
    reason: "market_closed"
```

### 4.2 実装例

```python
from enum import Enum

class SignalAction(Enum):
    EXECUTE = "execute"          # 即座に実行
    QUEUE = "queue"              # キューに入れて後で実行
    REJECT = "reject"            # 拒否

class SignalHandler:
    def __init__(self):
        self.market_calendar = IntegratedMarketCalendar()
        self.market_hours = MarketHoursManager()
        self.queue = SignalQueue()  # 後述

    def handle_signal(self, signal: dict) -> dict:
        """
        シグナルを処理

        Returns:
            dict: {
                "action": SignalAction,
                "reason": str,
                "execution_time": datetime | None
            }
        """
        current_time = datetime.now(pytz.timezone('Asia/Tokyo'))
        status = self.market_calendar.get_market_status(current_time)

        # 1. 営業日チェック
        if not status["is_trading_day"]:
            return {
                "action": SignalAction.REJECT,
                "reason": "market_closed_today",
                "message": "Today is not a trading day",
                "next_trading_day": self.market_calendar.get_next_trading_day(
                    current_time.date()
                )
            }

        # 2. セッション別の処理
        session = MarketSession(status["current_session"])

        if session == MarketSession.PRE_MARKET:
            # 市場前：キューに入れて9:00に実行
            return self._handle_pre_market_signal(signal, current_time)

        elif session in [MarketSession.MORNING_TRADING, MarketSession.AFTERNOON_TRADING]:
            # 取引時間内：即座に実行
            if status["is_safe_trading_time"]:
                return {
                    "action": SignalAction.EXECUTE,
                    "reason": "safe_trading_hours",
                    "execution_time": current_time
                }
            else:
                # 安全時間帯外（引け間際等）
                return {
                    "action": SignalAction.REJECT,
                    "reason": status["safe_time_reason"],
                    "message": "Outside safe trading window"
                }

        elif session == MarketSession.LUNCH_BREAK:
            # 昼休み：後場開始時に実行
            return self._handle_lunch_break_signal(signal, current_time)

        elif session == MarketSession.POST_MARKET:
            # 市場後：拒否（または翌日キュー）
            return {
                "action": SignalAction.REJECT,
                "reason": "post_market",
                "message": "Market already closed for today",
                "next_trading_day": self.market_calendar.get_next_trading_day(
                    current_time.date()
                )
            }

        else:
            # その他（板寄せ中等）
            return {
                "action": SignalAction.REJECT,
                "reason": "restricted_session",
                "message": f"Trading restricted during {session.value}"
            }

    def _handle_pre_market_signal(self, signal: dict, current_time: datetime) -> dict:
        """市場前シグナルの処理"""
        # 9:00まで待機
        execution_time = current_time.replace(hour=9, minute=0, second=0)

        # オプション：キューに登録
        # self.queue.enqueue(signal, execution_time)

        return {
            "action": SignalAction.QUEUE,
            "reason": "pre_market_queued",
            "execution_time": execution_time,
            "message": "Signal queued for market open at 09:00"
        }

    def _handle_lunch_break_signal(self, signal: dict, current_time: datetime) -> dict:
        """昼休みシグナルの処理"""
        # 12:30まで待機
        execution_time = current_time.replace(hour=12, minute=30, second=0)

        return {
            "action": SignalAction.QUEUE,
            "reason": "lunch_break_queued",
            "execution_time": execution_time,
            "message": "Signal queued for afternoon session at 12:30"
        }
```

### 4.3 シグナルキュー実装

```python
from datetime import datetime
import threading
import time

class SignalQueue:
    """時間指定でシグナルを実行するキュー"""

    def __init__(self):
        self.queue = []  # [(execution_time, signal), ...]
        self.lock = threading.Lock()
        self.running = False
        self.worker_thread = None

    def enqueue(self, signal: dict, execution_time: datetime):
        """シグナルをキューに追加"""
        with self.lock:
            self.queue.append((execution_time, signal))
            self.queue.sort(key=lambda x: x[0])  # 時刻順にソート

        logger.info(f"Signal queued for {execution_time}: {signal}")

    def start(self):
        """キュー処理を開始"""
        if self.running:
            return

        self.running = True
        self.worker_thread = threading.Thread(target=self._worker)
        self.worker_thread.daemon = True
        self.worker_thread.start()

    def stop(self):
        """キュー処理を停止"""
        self.running = False
        if self.worker_thread:
            self.worker_thread.join()

    def _worker(self):
        """キューのワーカースレッド"""
        while self.running:
            now = datetime.now(pytz.timezone('Asia/Tokyo'))

            with self.lock:
                # 実行時刻を過ぎたシグナルを取得
                ready_signals = [
                    (exec_time, sig) for exec_time, sig in self.queue
                    if exec_time <= now
                ]

                # キューから削除
                for item in ready_signals:
                    self.queue.remove(item)

            # 実行
            for exec_time, signal in ready_signals:
                try:
                    logger.info(f"Executing queued signal: {signal}")
                    execute_order(signal)
                except Exception as e:
                    logger.error(f"Queued signal execution failed: {e}")

            # 1秒待機
            time.sleep(1)
```

---

## 5. エッジケース処理

### 5.1 大納会・大発会

```python
class SpecialTradingDays:
    """特殊営業日の処理"""

    def is_year_end_session(self, dt: date) -> bool:
        """大納会か判定"""
        # 12月最終営業日
        if dt.month != 12:
            return False

        # この日以降に営業日があるかチェック
        next_day = dt + timedelta(days=1)
        while next_day.year == dt.year:
            if IntegratedMarketCalendar().is_trading_day(next_day):
                return False
            next_day += timedelta(days=1)

        return True

    def get_year_end_close_time(self, dt: date) -> time:
        """大納会の終了時刻"""
        # ※2024年以降は通常通り15:00
        # 2023年以前は12:30で終了
        if dt.year >= 2024:
            return time(15, 0)
        else:
            return time(12, 30)
```

### 5.2 システムメンテナンス日

```python
class MaintenanceSchedule:
    """システムメンテナンス管理"""

    def __init__(self):
        # 予定されたメンテナンス日時
        self.scheduled_maintenance = [
            # (start_datetime, end_datetime)
            (
                datetime(2025, 5, 3, 0, 0),  # GW中のメンテナンス
                datetime(2025, 5, 5, 23, 59)
            ),
        ]

    def is_maintenance_period(self, dt: datetime) -> bool:
        """メンテナンス期間中か判定"""
        for start, end in self.scheduled_maintenance:
            if start <= dt <= end:
                return True
        return False
```

---

## 6. 統合判定API

### 6.1 統合判定関数

```python
class TradingPermissionChecker:
    """取引許可の統合判定"""

    def __init__(self):
        self.market_calendar = IntegratedMarketCalendar()
        self.signal_handler = SignalHandler()
        self.maintenance = MaintenanceSchedule()

    def can_trade_now(self) -> tuple[bool, dict]:
        """
        現在取引可能か総合判定

        Returns:
            tuple[bool, dict]: (can_trade, details)
        """
        now = datetime.now(pytz.timezone('Asia/Tokyo'))

        # 1. メンテナンス中チェック
        if self.maintenance.is_maintenance_period(now):
            return False, {
                "reason": "system_maintenance",
                "message": "System is under maintenance"
            }

        # 2. 市場ステータス取得
        status = self.market_calendar.get_market_status(now)

        # 3. 総合判定
        can_trade = status["can_trade"]

        details = {
            "timestamp": now.isoformat(),
            "can_trade": can_trade,
            "market_status": status,
            "restrictions": []
        }

        if not status["is_trading_day"]:
            details["restrictions"].append("market_closed_today")

        if status["trading_status"] != "open":
            details["restrictions"].append(f"trading_status_{status['trading_status']}")

        if not status["is_safe_trading_time"]:
            details["restrictions"].append(status["safe_time_reason"])

        return can_trade, details

    def validate_signal(self, signal: dict) -> dict:
        """シグナルの有効性を検証"""
        can_trade, details = self.can_trade_now()

        if can_trade:
            return {
                "valid": True,
                "action": "execute",
                "details": details
            }
        else:
            # 時間外処理
            handling = self.signal_handler.handle_signal(signal)
            return {
                "valid": False,
                "action": handling["action"].value,
                "reason": handling["reason"],
                "details": details,
                "handling": handling
            }
```

### 6.2 Webhook エンドポイントでの使用例

```python
from fastapi import FastAPI, HTTPException

app = FastAPI()
permission_checker = TradingPermissionChecker()

@app.post("/webhook")
async def webhook_handler(signal: dict):
    # 取引許可チェック
    validation = permission_checker.validate_signal(signal)

    if validation["valid"]:
        # 即座に実行
        order_result = execute_order(signal)
        return {
            "status": "success",
            "action": "executed",
            "order_result": order_result
        }

    elif validation["action"] == "queue":
        # キューに登録
        handling = validation["handling"]
        return {
            "status": "queued",
            "action": "queued",
            "execution_time": handling["execution_time"],
            "message": handling["message"]
        }

    else:  # reject
        return {
            "status": "rejected",
            "action": "rejected",
            "reason": validation["reason"],
            "restrictions": validation["details"]["restrictions"],
            "message": validation["handling"]["message"]
        }
```

---

## 7. モニタリング・通知

### 7.1 市場開閉通知

```python
import schedule

class MarketEventNotifier:
    """市場イベント通知"""

    def __init__(self):
        self.scheduler = schedule

    def setup_notifications(self):
        """定期通知の設定"""

        # 市場開始15分前
        schedule.every().day.at("08:45").do(self.notify_market_opening)

        # 前場終了5分前
        schedule.every().day.at("11:25").do(self.notify_morning_close)

        # 後場終了30分前
        schedule.every().day.at("14:30").do(self.notify_afternoon_close)

        # 後場終了（全ポジション確認）
        schedule.every().day.at("15:00").do(self.notify_market_close)

    def notify_market_opening(self):
        """市場開始通知"""
        calendar = IntegratedMarketCalendar()
        today = date.today()

        if not calendar.is_trading_day(today):
            return  # 休場日はスキップ

        send_notification({
            "event": "market_opening_soon",
            "message": "Market opens in 15 minutes (09:00)",
            "timestamp": datetime.now().isoformat()
        })

    def notify_market_close(self):
        """市場終了通知"""
        # 現在のポジションを確認
        positions = get_current_positions()

        if positions:
            send_notification({
                "event": "market_closed_with_positions",
                "message": f"Market closed. {len(positions)} position(s) held overnight",
                "positions": positions,
                "risk": "overnight_risk"
            })
```

---

## 8. テストケース

### 8.1 ユニットテスト例

```python
import unittest
from datetime import datetime, date

class TestMarketHours(unittest.TestCase):

    def setUp(self):
        self.manager = MarketHoursManager()

    def test_morning_session(self):
        """前場セッション判定"""
        dt = datetime(2025, 12, 27, 10, 30, tzinfo=pytz.timezone('Asia/Tokyo'))
        session = self.manager.get_current_session(dt)
        self.assertEqual(session, MarketSession.MORNING_TRADING)

    def test_lunch_break(self):
        """昼休み判定"""
        dt = datetime(2025, 12, 27, 12, 0, tzinfo=pytz.timezone('Asia/Tokyo'))
        session = self.manager.get_current_session(dt)
        self.assertIn(session, [MarketSession.LUNCH_BREAK, MarketSession.AFTERNOON_AUCTION])

    def test_weekend(self):
        """土日判定"""
        # 2025-12-27は土曜日
        dt = datetime(2025, 12, 27, 10, 0, tzinfo=pytz.timezone('Asia/Tokyo'))
        session = self.manager.get_current_session(dt)
        self.assertEqual(session, MarketSession.CLOSED)

    def test_holiday(self):
        """祝日判定"""
        calendar = IntegratedMarketCalendar()
        new_year = date(2025, 1, 1)
        self.assertFalse(calendar.is_trading_day(new_year))

    def test_safe_trading_time(self):
        """安全時間帯判定"""
        safe_windows = SafeTradingWindows()

        # 前場安全時間帯
        dt = datetime(2025, 12, 26, 10, 0, tzinfo=pytz.timezone('Asia/Tokyo'))
        is_safe, reason = safe_windows.is_safe_trading_time(dt)
        self.assertTrue(is_safe)

        # 引け間際
        dt = datetime(2025, 12, 26, 14, 45, tzinfo=pytz.timezone('Asia/Tokyo'))
        is_safe, reason = safe_windows.is_safe_trading_time(dt)
        self.assertFalse(is_safe)
        self.assertEqual(reason, "too_close_to_afternoon_close")
```

---

## まとめ

### 実装チェックリスト

```
✅ セッション判定（7種類）
✅ 取引可否判定（OPEN/CLOSED/RESTRICTED）
✅ 安全時間帯フィルター
✅ 祝日管理（静的データ + jpholiday）
✅ 時間外シグナル処理（EXECUTE/QUEUE/REJECT）
✅ シグナルキュー実装
✅ 大納会・システムメンテナンス対応
✅ 統合判定API
✅ 市場イベント通知
✅ ユニットテスト
```

### 推奨実装順序

```
1. MarketHoursManager（基本セッション判定）
2. HolidayManager（祝日データ管理）
3. SafeTradingWindows（安全時間帯）
4. SignalHandler（時間外シグナル処理）
5. TradingPermissionChecker（統合判定）
6. MarketEventNotifier（通知機能）
```

---

*最終更新: 2025-12-27*
