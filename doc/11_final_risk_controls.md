# 日本株自動売買システム - 最終リスク管理ルール（最後の砦）

## 概要

本文書では、TradingView戦略やPine Scriptとは**完全に独立した**サーバー側の最終リスク管理ルールを設計します。これは全ての注文を実行前に通過させる「最後の砦」として機能し、戦略のバグや想定外の事態から資金を保護します。

---

## 1. 設計哲学

### 1.1 基本原則

```yaml
design_principles:
  independence:
    description: "戦略ロジックとは完全に独立"
    implementation: "サーバー側で強制的にチェック"
    override: "不可（管理者のみ一時的に変更可能）"

  fail_safe:
    description: "疑わしい場合は拒否"
    motto: "When in doubt, reject"
    priority: "資金保護 > 機会損失"

  transparency:
    description: "全ての拒否理由を記録"
    logging: "監査ログに永久保存"
    notification: "重大な制限違反はアラート送信"

  simplicity:
    description: "シンプルで明確なルール"
    avoid: "複雑な条件分岐、戦略依存の判定"
    prefer: "固定閾値、絶対的な制限"
```

### 1.2 4層防御モデル

```
┌────────────────────────────────────────┐
│ Layer 1: TradingView Pine Script      │
│  - エントリー/エグジット条件           │
│  - RSI, ATR フィルター                 │
│  - クールダウン（Pine Script側）       │
└────────────┬───────────────────────────┘
             │ Webhook
             ▼
┌────────────────────────────────────────┐
│ Layer 2: Webhook 受信・基本検証        │
│  - JSON バリデーション                 │
│  - 認証（Passphrase）                  │
│  - タイムスタンプ検証                   │
└────────────┬───────────────────────────┘
             │
             ▼
┌────────────────────────────────────────┐
│ Layer 3: 戦略レベルのリスク管理        │
│  - 冪等性チェック                      │
│  - クールダウン（サーバー側）          │
│  - 日次制限（3回/日）                  │
│  - 市場時間チェック                    │
└────────────┬───────────────────────────┘
             │
             ▼
┌────────────────────────────────────────┐
│ 🛡️ Layer 4: 最終リスク管理（最後の砦）│  ← 本文書
│  - 最大建玉チェック                    │
│  - 絶対的な日次制限                    │
│  - ブラックリスト銘柄                  │
│  - Kill Switch                         │
└────────────┬───────────────────────────┘
             │ OK → 注文実行
             ▼
┌────────────────────────────────────────┐
│ Windows VM (Excel + MarketSpeed II)   │
└────────────────────────────────────────┘
```

---

## 2. 最大建玉制御

### 2.1 建玉制限の設計

```yaml
position_limits:
  # 絶対的な上限
  max_total_exposure:
    amount: 1000000              # 全体で最大100万円
    reason: "口座資金の保護"
    override: "不可"

  max_position_per_ticker:
    amount: 200000               # 1銘柄最大20万円
    reason: "集中リスクの回避"
    override: "不可"

  max_open_positions:
    count: 5                     # 同時保有5銘柄まで
    reason: "管理容易性"
    override: "不可"

  # 相対的な制限
  max_position_pct_of_capital:
    percentage: 20               # 口座資金の20%まで/1銘柄
    capital_base: "available_balance"

  max_sector_exposure:
    percentage: 30               # 同一セクター30%まで
    example: "電機セクターに3銘柄で30万円まで"
```

### 2.2 実装例

```python
from dataclasses import dataclass
from typing import Dict, List
from decimal import Decimal

@dataclass
class PositionLimit:
    """ポジション制限の定義"""
    max_total_exposure: Decimal = Decimal("1000000")      # 100万円
    max_position_per_ticker: Decimal = Decimal("200000")  # 20万円
    max_open_positions: int = 5
    max_position_pct: Decimal = Decimal("0.20")           # 20%
    max_sector_exposure_pct: Decimal = Decimal("0.30")    # 30%


class PositionManager:
    """建玉管理"""

    def __init__(self, limits: PositionLimit = None):
        self.limits = limits or PositionLimit()
        self.positions: Dict[str, dict] = {}  # {ticker: position_info}

    def calculate_exposure(self, ticker: str, quantity: int, price: float) -> Decimal:
        """エクスポージャー計算"""
        return Decimal(str(quantity)) * Decimal(str(price))

    def get_total_exposure(self) -> Decimal:
        """全ポジションの合計エクスポージャー"""
        total = Decimal("0")
        for ticker, pos in self.positions.items():
            total += Decimal(str(pos["quantity"])) * Decimal(str(pos["current_price"]))
        return total

    def get_sector_exposure(self, sector: str) -> Decimal:
        """特定セクターのエクスポージャー"""
        total = Decimal("0")
        for ticker, pos in self.positions.items():
            if pos.get("sector") == sector:
                total += Decimal(str(pos["quantity"])) * Decimal(str(pos["current_price"]))
        return total

    def can_open_position(
        self,
        ticker: str,
        quantity: int,
        price: float,
        sector: str = None
    ) -> tuple[bool, dict]:
        """
        新規ポジションを開けるかチェック

        Returns:
            tuple[bool, dict]: (allowed, details)
        """
        new_exposure = self.calculate_exposure(ticker, quantity, price)

        # 1. 既存ポジション数チェック
        if ticker not in self.positions and len(self.positions) >= self.limits.max_open_positions:
            return False, {
                "reason": "max_positions_exceeded",
                "current_positions": len(self.positions),
                "max_positions": self.limits.max_open_positions,
                "message": f"最大{self.limits.max_open_positions}銘柄まで"
            }

        # 2. 1銘柄あたりのエクスポージャーチェック
        current_ticker_exposure = Decimal("0")
        if ticker in self.positions:
            pos = self.positions[ticker]
            current_ticker_exposure = Decimal(str(pos["quantity"])) * Decimal(str(pos["current_price"]))

        total_ticker_exposure = current_ticker_exposure + new_exposure

        if total_ticker_exposure > self.limits.max_position_per_ticker:
            return False, {
                "reason": "ticker_exposure_exceeded",
                "ticker": ticker,
                "current_exposure": float(current_ticker_exposure),
                "new_exposure": float(new_exposure),
                "total_exposure": float(total_ticker_exposure),
                "max_allowed": float(self.limits.max_position_per_ticker),
                "message": f"{ticker}のエクスポージャーが上限{self.limits.max_position_per_ticker}円を超過"
            }

        # 3. 全体エクスポージャーチェック
        current_total_exposure = self.get_total_exposure()
        new_total_exposure = current_total_exposure + new_exposure

        if new_total_exposure > self.limits.max_total_exposure:
            return False, {
                "reason": "total_exposure_exceeded",
                "current_exposure": float(current_total_exposure),
                "new_exposure": float(new_exposure),
                "total_exposure": float(new_total_exposure),
                "max_allowed": float(self.limits.max_total_exposure),
                "message": f"全体エクスポージャーが上限{self.limits.max_total_exposure}円を超過"
            }

        # 4. セクター集中チェック
        if sector:
            current_sector_exposure = self.get_sector_exposure(sector)
            new_sector_exposure = current_sector_exposure + new_exposure
            sector_limit = self.limits.max_total_exposure * self.limits.max_sector_exposure_pct

            if new_sector_exposure > sector_limit:
                return False, {
                    "reason": "sector_exposure_exceeded",
                    "sector": sector,
                    "current_exposure": float(current_sector_exposure),
                    "new_exposure": float(new_exposure),
                    "total_exposure": float(new_sector_exposure),
                    "max_allowed": float(sector_limit),
                    "message": f"{sector}セクターのエクスポージャーが上限を超過"
                }

        # 5. 口座資金比率チェック
        available_balance = self.get_available_balance()
        if available_balance > 0:
            position_pct = new_exposure / Decimal(str(available_balance))
            if position_pct > self.limits.max_position_pct:
                return False, {
                    "reason": "position_percentage_exceeded",
                    "position_amount": float(new_exposure),
                    "available_balance": float(available_balance),
                    "position_pct": float(position_pct * 100),
                    "max_pct": float(self.limits.max_position_pct * 100),
                    "message": f"ポジションが口座資金の{self.limits.max_position_pct * 100}%を超過"
                }

        # 全てのチェックをパス
        return True, {"status": "approved"}

    def get_available_balance(self) -> Decimal:
        """利用可能残高を取得（実装は外部APIから）"""
        # 実際はMarketSpeed II APIから取得
        return Decimal("1000000")  # 仮の値
```

---

## 3. 日次最大取引数制御

### 3.1 絶対的な日次制限

```yaml
daily_hard_limits:
  # 戦略の日次制限（3回）とは別の絶対制限
  max_daily_entries:
    count: 5                     # 1日最大5回エントリー（絶対上限）
    strategy_limit: 3            # 戦略レベルは3回
    buffer: 2                    # 緊急時のバッファ

  max_daily_trades:
    count: 15                    # 1日最大15取引（売買合計）
    reason: "異常な頻度の検知"

  max_trades_per_hour:
    count: 5                     # 1時間最大5取引
    reason: "短時間の過剰取引防止"

  max_consecutive_losses:
    count: 5                     # 連続5回損失で即停止
    action: "activate_kill_switch"
    reason: "戦略の致命的な問題検知"

  max_daily_loss:
    amount: -50000               # 1日最大損失 -5万円
    action: "activate_kill_switch"
    reason: "資金保護"
```

### 3.2 実装例

```python
from datetime import datetime, date, timedelta
from collections import defaultdict
import pytz

class DailyHardLimits:
    """日次絶対制限"""

    def __init__(self, redis_client):
        self.redis = redis_client
        self.jst = pytz.timezone('Asia/Tokyo')

        # 絶対上限
        self.max_daily_entries = 5
        self.max_daily_trades = 15
        self.max_trades_per_hour = 5
        self.max_consecutive_losses = 5
        self.max_daily_loss = -50000

    def check_hard_limits(self, action: str) -> tuple[bool, dict]:
        """
        絶対制限をチェック

        Returns:
            tuple[bool, dict]: (limit_exceeded, details)
        """
        today = self._get_today_key()
        current_hour = self._get_current_hour_key()

        # 1. 日次エントリー数チェック
        if action == "buy":
            daily_entries = int(self.redis.get(f"hard:entries:{today}") or 0)
            if daily_entries >= self.max_daily_entries:
                return True, {
                    "reason": "hard_daily_entry_limit",
                    "current": daily_entries,
                    "max": self.max_daily_entries,
                    "severity": "critical",
                    "message": f"絶対上限{self.max_daily_entries}回に到達"
                }

        # 2. 日次取引数チェック
        daily_trades = int(self.redis.get(f"hard:trades:{today}") or 0)
        if daily_trades >= self.max_daily_trades:
            return True, {
                "reason": "hard_daily_trade_limit",
                "current": daily_trades,
                "max": self.max_daily_trades,
                "severity": "critical",
                "message": "異常な取引頻度を検知"
            }

        # 3. 時間あたり取引数チェック
        hourly_trades = int(self.redis.get(f"hard:hourly:{current_hour}") or 0)
        if hourly_trades >= self.max_trades_per_hour:
            return True, {
                "reason": "hard_hourly_trade_limit",
                "current": hourly_trades,
                "max": self.max_trades_per_hour,
                "severity": "warning",
                "message": "短時間の過剰取引を検知"
            }

        # 4. 連続損失チェック
        consecutive_losses = self._get_consecutive_losses()
        if consecutive_losses >= self.max_consecutive_losses:
            return True, {
                "reason": "hard_consecutive_loss_limit",
                "consecutive_losses": consecutive_losses,
                "max": self.max_consecutive_losses,
                "severity": "critical",
                "action": "kill_switch_activated",
                "message": "連続損失上限に到達、システム停止"
            }

        # 5. 日次損失チェック
        daily_pnl = self._get_daily_pnl()
        if daily_pnl < self.max_daily_loss:
            return True, {
                "reason": "hard_daily_loss_limit",
                "daily_pnl": daily_pnl,
                "max_loss": self.max_daily_loss,
                "severity": "critical",
                "action": "kill_switch_activated",
                "message": f"日次損失が上限{self.max_daily_loss}円を超過"
            }

        return False, {"status": "within_limits"}

    def record_trade(self, action: str, pnl: float = 0):
        """取引を記録"""
        today = self._get_today_key()
        current_hour = self._get_current_hour_key()
        ttl = self._get_seconds_until_reset()

        # 日次取引数
        self.redis.incr(f"hard:trades:{today}")
        self.redis.expire(f"hard:trades:{today}", ttl)

        # 時間あたり取引数
        self.redis.incr(f"hard:hourly:{current_hour}")
        self.redis.expire(f"hard:hourly:{current_hour}", 3600)  # 1時間

        # エントリーの場合
        if action == "buy":
            self.redis.incr(f"hard:entries:{today}")
            self.redis.expire(f"hard:entries:{today}", ttl)

        # 損益記録
        if pnl != 0:
            self._record_pnl(pnl)

    def _get_consecutive_losses(self) -> int:
        """連続損失回数を取得"""
        key = "hard:consecutive_losses"
        return int(self.redis.get(key) or 0)

    def _get_daily_pnl(self) -> float:
        """当日の損益を取得"""
        today = self._get_today_key()
        key = f"hard:daily_pnl:{today}"
        return float(self.redis.get(key) or 0)

    def _record_pnl(self, pnl: float):
        """損益を記録"""
        today = self._get_today_key()
        ttl = self._get_seconds_until_reset()

        # 日次損益に加算
        key = f"hard:daily_pnl:{today}"
        current_pnl = float(self.redis.get(key) or 0)
        new_pnl = current_pnl + pnl
        self.redis.set(key, str(new_pnl))
        self.redis.expire(key, ttl)

        # 連続損失カウンター
        if pnl < 0:
            self.redis.incr("hard:consecutive_losses")
        else:
            self.redis.set("hard:consecutive_losses", "0")

    def _get_today_key(self) -> str:
        now = datetime.now(self.jst)
        return now.strftime("%Y-%m-%d")

    def _get_current_hour_key(self) -> str:
        now = datetime.now(self.jst)
        return now.strftime("%Y-%m-%d-%H")

    def _get_seconds_until_reset(self) -> int:
        now = datetime.now(self.jst)
        tomorrow = (now + timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
        return int((tomorrow - now).total_seconds())
```

---

## 4. ブラックリスト銘柄

### 4.1 ブラックリスト設計

```yaml
blacklist_types:
  permanent:
    description: "恒久的な除外"
    examples:
      - "過去に誤発注した銘柄"
      - "流動性が極端に低い銘柄"
      - "取引停止中の銘柄"
    storage: "database"
    override: "管理者のみ可能"

  temporary:
    description: "一時的な除外"
    examples:
      - "ストップ高/安に連続した銘柄"
      - "決算発表前後の銘柄"
      - "急激な出来高増加（仕手株の疑い）"
    duration: "24時間 - 7日"
    auto_removal: true

  dynamic:
    description: "動的な除外"
    triggers:
      - "3日連続で損失を出した銘柄"
      - "1日で2回損切りされた銘柄"
    duration: "30日"
    auto_removal: true
```

### 4.2 実装例

```python
from enum import Enum
from datetime import datetime, timedelta

class BlacklistType(Enum):
    PERMANENT = "permanent"
    TEMPORARY = "temporary"
    DYNAMIC = "dynamic"


class BlacklistManager:
    """ブラックリスト管理"""

    def __init__(self, db_connection, redis_client):
        self.db = db_connection
        self.redis = redis_client

    def is_blacklisted(self, ticker: str) -> tuple[bool, dict]:
        """
        銘柄がブラックリストに入っているかチェック

        Returns:
            tuple[bool, dict]: (is_blacklisted, details)
        """
        # 1. 恒久的ブラックリスト（DB）
        permanent = self._check_permanent_blacklist(ticker)
        if permanent:
            return True, {
                "blacklist_type": "permanent",
                "ticker": ticker,
                "reason": permanent["reason"],
                "added_at": permanent["added_at"],
                "added_by": permanent["added_by"],
                "message": f"{ticker}は恒久的にブロックされています"
            }

        # 2. 一時的ブラックリスト（Redis）
        temporary = self._check_temporary_blacklist(ticker)
        if temporary:
            return True, {
                "blacklist_type": "temporary",
                "ticker": ticker,
                "reason": temporary["reason"],
                "expires_at": temporary["expires_at"],
                "message": f"{ticker}は一時的にブロックされています（{temporary['expires_at']}まで）"
            }

        # 3. 動的ブラックリスト（Redis）
        dynamic = self._check_dynamic_blacklist(ticker)
        if dynamic:
            return True, {
                "blacklist_type": "dynamic",
                "ticker": ticker,
                "reason": dynamic["reason"],
                "trigger": dynamic["trigger"],
                "expires_at": dynamic["expires_at"],
                "message": f"{ticker}は動的にブロックされています（{dynamic['reason']}）"
            }

        return False, {"status": "not_blacklisted"}

    def add_to_blacklist(
        self,
        ticker: str,
        blacklist_type: BlacklistType,
        reason: str,
        duration_hours: int = None,
        metadata: dict = None
    ):
        """ブラックリストに追加"""
        if blacklist_type == BlacklistType.PERMANENT:
            self._add_permanent(ticker, reason, metadata)
        elif blacklist_type == BlacklistType.TEMPORARY:
            self._add_temporary(ticker, reason, duration_hours or 24, metadata)
        elif blacklist_type == BlacklistType.DYNAMIC:
            self._add_dynamic(ticker, reason, duration_hours or 720, metadata)  # 30日

        logger.warning(f"Blacklist added: {ticker} ({blacklist_type.value}) - {reason}")

    def _check_permanent_blacklist(self, ticker: str) -> dict | None:
        """恒久的ブラックリストをチェック"""
        query = "SELECT * FROM permanent_blacklist WHERE ticker = ?"
        result = self.db.execute(query, (ticker,)).fetchone()
        return dict(result) if result else None

    def _check_temporary_blacklist(self, ticker: str) -> dict | None:
        """一時的ブラックリストをチェック"""
        key = f"blacklist:temp:{ticker}"
        data = self.redis.get(key)
        if data:
            import json
            return json.loads(data)
        return None

    def _check_dynamic_blacklist(self, ticker: str) -> dict | None:
        """動的ブラックリストをチェック"""
        key = f"blacklist:dynamic:{ticker}"
        data = self.redis.get(key)
        if data:
            import json
            return json.loads(data)
        return None

    def _add_permanent(self, ticker: str, reason: str, metadata: dict):
        """恒久的ブラックリストに追加"""
        query = """
            INSERT INTO permanent_blacklist (ticker, reason, added_at, added_by, metadata)
            VALUES (?, ?, ?, ?, ?)
        """
        self.db.execute(
            query,
            (ticker, reason, datetime.now(), "system", json.dumps(metadata or {}))
        )
        self.db.commit()

    def _add_temporary(self, ticker: str, reason: str, hours: int, metadata: dict):
        """一時的ブラックリストに追加"""
        key = f"blacklist:temp:{ticker}"
        expires_at = datetime.now() + timedelta(hours=hours)

        data = {
            "reason": reason,
            "added_at": datetime.now().isoformat(),
            "expires_at": expires_at.isoformat(),
            "metadata": metadata or {}
        }

        self.redis.setex(key, hours * 3600, json.dumps(data))

    def _add_dynamic(self, ticker: str, reason: str, hours: int, metadata: dict):
        """動的ブラックリストに追加"""
        key = f"blacklist:dynamic:{ticker}"
        expires_at = datetime.now() + timedelta(hours=hours)

        data = {
            "reason": reason,
            "trigger": metadata.get("trigger", "unknown"),
            "added_at": datetime.now().isoformat(),
            "expires_at": expires_at.isoformat(),
            "metadata": metadata or {}
        }

        self.redis.setex(key, hours * 3600, json.dumps(data))

    def auto_blacklist_on_losses(self, ticker: str, loss_count: int):
        """連続損失時の自動ブラックリスト"""
        if loss_count >= 3:
            self.add_to_blacklist(
                ticker,
                BlacklistType.DYNAMIC,
                f"{loss_count}回連続損失",
                duration_hours=720,  # 30日
                metadata={"trigger": "consecutive_losses", "count": loss_count}
            )
```

---

## 5. Kill Switch（緊急停止機能）

### 5.1 Kill Switch 設計

```yaml
kill_switch:
  triggers:
    manual:
      - "管理者による手動発動"
      - "Webダッシュボードからのボタンクリック"
      - "管理APIへのPOSTリクエスト"

    automatic:
      - "連続5回損失"
      - "1日損失が-5万円を超過"
      - "異常な取引頻度（15回/日超過）"
      - "Windows VMとの接続断"
      - "MarketSpeed IIエラー連続3回"

  actions:
    immediate:
      - "全ての新規注文を拒否"
      - "システム状態を DISABLED に変更"
      - "緊急アラート送信（Slack/Email）"

    optional:
      - "既存ポジションの強制決済（設定により）"
      - "TradingView Alertの一時停止（手動）"

  recovery:
    manual_only: true
    require_confirmation: true
    checklist:
      - "問題の原因特定"
      - "ログの確認"
      - "必要に応じて設定変更"
      - "管理者による明示的な再開"
```

### 5.2 実装例

```python
from enum import Enum
import threading

class SystemState(Enum):
    ENABLED = "enabled"
    DISABLED = "disabled"
    MAINTENANCE = "maintenance"


class KillSwitch:
    """緊急停止機能"""

    def __init__(self, redis_client, notification_service):
        self.redis = redis_client
        self.notification = notification_service
        self.lock = threading.Lock()

    def get_system_state(self) -> SystemState:
        """システム状態を取得"""
        state = self.redis.get("system:state")
        if state:
            return SystemState(state.decode())
        return SystemState.ENABLED

    def is_trading_enabled(self) -> bool:
        """取引が有効か"""
        return self.get_system_state() == SystemState.ENABLED

    def activate_kill_switch(
        self,
        reason: str,
        triggered_by: str = "system",
        auto_trigger: bool = True
    ) -> dict:
        """
        Kill Switchを発動

        Args:
            reason: 発動理由
            triggered_by: 発動者（"system", "admin", "user"）
            auto_trigger: 自動発動か手動発動か

        Returns:
            dict: 発動結果
        """
        with self.lock:
            # 現在の状態を確認
            current_state = self.get_system_state()
            if current_state == SystemState.DISABLED:
                return {
                    "status": "already_disabled",
                    "message": "System is already disabled"
                }

            # システム状態を DISABLED に変更
            self.redis.set("system:state", SystemState.DISABLED.value)

            # 発動履歴を記録
            activation_record = {
                "timestamp": datetime.now().isoformat(),
                "reason": reason,
                "triggered_by": triggered_by,
                "auto_trigger": auto_trigger,
                "previous_state": current_state.value
            }

            self.redis.lpush("kill_switch:history", json.dumps(activation_record))

            # 緊急アラート送信
            self._send_emergency_alert(activation_record)

            logger.critical(f"🚨 KILL SWITCH ACTIVATED: {reason}")

            return {
                "status": "activated",
                "activation_time": activation_record["timestamp"],
                "reason": reason,
                "message": "All trading stopped"
            }

    def deactivate_kill_switch(
        self,
        admin_password: str,
        confirmation: bool = False
    ) -> dict:
        """
        Kill Switchを解除（管理者のみ）

        Args:
            admin_password: 管理者パスワード
            confirmation: 確認フラグ
        """
        # パスワード検証
        if not self._verify_admin_password(admin_password):
            return {
                "status": "error",
                "message": "Invalid admin password"
            }

        # 確認フラグチェック
        if not confirmation:
            return {
                "status": "error",
                "message": "Confirmation required. Set confirmation=True"
            }

        with self.lock:
            # システム状態を ENABLED に変更
            self.redis.set("system:state", SystemState.ENABLED.value)

            # 解除履歴を記録
            deactivation_record = {
                "timestamp": datetime.now().isoformat(),
                "action": "deactivated",
                "by": "admin"
            }

            self.redis.lpush("kill_switch:history", json.dumps(deactivation_record))

            logger.warning("✅ Kill Switch deactivated by admin")

            # 通知
            self.notification.send_notification({
                "level": "info",
                "message": "Kill Switch deactivated - Trading resumed",
                "timestamp": deactivation_record["timestamp"]
            })

            return {
                "status": "deactivated",
                "message": "System re-enabled",
                "timestamp": deactivation_record["timestamp"]
            }

    def check_auto_triggers(self, context: dict) -> bool:
        """
        自動発動条件をチェック

        Args:
            context: {
                "consecutive_losses": int,
                "daily_pnl": float,
                "daily_trade_count": int,
                "vm_connection": bool,
                "rss_errors": int
            }

        Returns:
            bool: 発動すべきかどうか
        """
        # 連続損失
        if context.get("consecutive_losses", 0) >= 5:
            self.activate_kill_switch(
                reason=f"連続{context['consecutive_losses']}回損失",
                auto_trigger=True
            )
            return True

        # 日次損失
        if context.get("daily_pnl", 0) < -50000:
            self.activate_kill_switch(
                reason=f"日次損失{context['daily_pnl']}円",
                auto_trigger=True
            )
            return True

        # 異常な取引頻度
        if context.get("daily_trade_count", 0) >= 15:
            self.activate_kill_switch(
                reason=f"異常な取引頻度（{context['daily_trade_count']}回/日）",
                auto_trigger=True
            )
            return True

        # VM接続断
        if not context.get("vm_connection", True):
            self.activate_kill_switch(
                reason="Windows VMとの接続断",
                auto_trigger=True
            )
            return True

        # RSSエラー連続
        if context.get("rss_errors", 0) >= 3:
            self.activate_kill_switch(
                reason=f"MarketSpeed IIエラー連続{context['rss_errors']}回",
                auto_trigger=True
            )
            return True

        return False

    def _send_emergency_alert(self, record: dict):
        """緊急アラート送信"""
        self.notification.send_notification({
            "level": "critical",
            "title": "🚨 KILL SWITCH ACTIVATED 🚨",
            "message": f"Reason: {record['reason']}",
            "triggered_by": record["triggered_by"],
            "auto_trigger": record["auto_trigger"],
            "timestamp": record["timestamp"],
            "action_required": "Check system logs and resolve issue before re-enabling"
        })

    def _verify_admin_password(self, password: str) -> bool:
        """管理者パスワード検証"""
        import os
        import bcrypt
        stored_hash = os.getenv("ADMIN_PASSWORD_HASH")
        return bcrypt.checkpw(password.encode(), stored_hash.encode())
```

---

## 6. 統合最終リスク管理システム

### 6.1 全チェックの統合

```python
class FinalRiskControl:
    """最終リスク管理（最後の砦）"""

    def __init__(self, redis_client, db_connection, notification_service):
        self.position_manager = PositionManager()
        self.daily_limits = DailyHardLimits(redis_client)
        self.blacklist = BlacklistManager(db_connection, redis_client)
        self.kill_switch = KillSwitch(redis_client, notification_service)

    def validate_order(
        self,
        ticker: str,
        action: str,
        quantity: int,
        price: float,
        sector: str = None
    ) -> dict:
        """
        注文を最終検証（全チェックを統合）

        Returns:
            dict: {
                "allowed": bool,
                "reason": str,
                "severity": str,  # "info", "warning", "critical"
                "details": dict
            }
        """
        # 0. Kill Switch チェック（最優先）
        if not self.kill_switch.is_trading_enabled():
            return {
                "allowed": False,
                "reason": "kill_switch_active",
                "severity": "critical",
                "details": {
                    "message": "System disabled by Kill Switch",
                    "system_state": self.kill_switch.get_system_state().value
                }
            }

        # 1. ブラックリストチェック
        is_blacklisted, blacklist_info = self.blacklist.is_blacklisted(ticker)
        if is_blacklisted:
            return {
                "allowed": False,
                "reason": "ticker_blacklisted",
                "severity": "warning",
                "details": blacklist_info
            }

        # 2. 日次絶対制限チェック
        limit_exceeded, limit_info = self.daily_limits.check_hard_limits(action)
        if limit_exceeded:
            # Critical な制限違反の場合は Kill Switch 発動
            if limit_info.get("severity") == "critical":
                self.kill_switch.activate_kill_switch(
                    reason=limit_info["message"],
                    auto_trigger=True
                )

            return {
                "allowed": False,
                "reason": limit_info["reason"],
                "severity": limit_info["severity"],
                "details": limit_info
            }

        # 3. 建玉制限チェック（買いのみ）
        if action == "buy":
            can_open, position_info = self.position_manager.can_open_position(
                ticker, quantity, price, sector
            )
            if not can_open:
                return {
                    "allowed": False,
                    "reason": position_info["reason"],
                    "severity": "warning",
                    "details": position_info
                }

        # 4. 自動Kill Switchトリガーチェック
        context = self._build_context()
        if self.kill_switch.check_auto_triggers(context):
            return {
                "allowed": False,
                "reason": "auto_kill_switch_triggered",
                "severity": "critical",
                "details": {
                    "message": "System automatically disabled",
                    "context": context
                }
            }

        # 全てのチェックをパス
        return {
            "allowed": True,
            "reason": "all_checks_passed",
            "severity": "info",
            "details": {
                "message": "Order approved by final risk control"
            }
        }

    def record_execution(
        self,
        ticker: str,
        action: str,
        quantity: int,
        price: float,
        pnl: float = 0
    ):
        """注文実行を記録"""
        # 日次制限に記録
        self.daily_limits.record_trade(action, pnl)

        # ポジション更新
        if action == "buy":
            self.position_manager.add_position(ticker, quantity, price)
        elif action == "sell":
            self.position_manager.reduce_position(ticker, quantity, pnl)

    def _build_context(self) -> dict:
        """自動Kill Switch用のコンテキスト構築"""
        return {
            "consecutive_losses": self.daily_limits._get_consecutive_losses(),
            "daily_pnl": self.daily_limits._get_daily_pnl(),
            "daily_trade_count": int(
                self.daily_limits.redis.get(
                    f"hard:trades:{self.daily_limits._get_today_key()}"
                ) or 0
            ),
            "vm_connection": self._check_vm_connection(),
            "rss_errors": self._get_rss_error_count()
        }

    def _check_vm_connection(self) -> bool:
        """VM接続状態を確認"""
        # 実装は環境に依存
        return True

    def _get_rss_error_count(self) -> int:
        """RSSエラー回数を取得"""
        # 実装は環境に依存
        return 0
```

---

## 7. Webhook エンドポイントでの使用

```python
from fastapi import FastAPI, HTTPException

app = FastAPI()
final_risk_control = FinalRiskControl(redis_client, db_connection, notification_service)

@app.post("/webhook")
async def webhook_handler(signal: dict):
    # ... 既存のバリデーション、冪等性、クールダウン等

    # 【最終リスク管理チェック】
    validation = final_risk_control.validate_order(
        ticker=signal["ticker"],
        action=signal["action"],
        quantity=signal["quantity"],
        price=signal.get("entry_price", 0),
        sector=signal.get("sector")
    )

    if not validation["allowed"]:
        logger.error(f"Final risk control rejected: {validation}")

        # Critical な拒否の場合はアラート
        if validation["severity"] == "critical":
            send_critical_alert(validation)

        return {
            "status": "rejected",
            "layer": "final_risk_control",
            "reason": validation["reason"],
            "severity": validation["severity"],
            "details": validation["details"]
        }

    # 注文実行
    try:
        order_result = execute_order(signal)

        # 実行記録
        final_risk_control.record_execution(
            ticker=signal["ticker"],
            action=signal["action"],
            quantity=signal["quantity"],
            price=order_result.get("executed_price", 0),
            pnl=order_result.get("pnl", 0)
        )

        return {
            "status": "success",
            "order_result": order_result
        }

    except Exception as e:
        logger.error(f"Order execution failed: {e}")
        raise
```

---

## まとめ

### 最終リスク管理の4本柱

| 柱 | 目的 | 主要制限 |
|---|------|---------|
| **建玉制限** | 資金保護 | 全体100万円、1銘柄20万円 |
| **日次制限** | 過剰取引防止 | 5回/日、15取引/日、連続5損失 |
| **ブラックリスト** | 問題銘柄排除 | 恒久・一時・動的 |
| **Kill Switch** | 緊急停止 | 手動・自動発動 |

### 実装チェックリスト

```
✅ PositionManager（建玉制限）
✅ DailyHardLimits（絶対制限）
✅ BlacklistManager（3種類）
✅ KillSwitch（手動・自動）
✅ FinalRiskControl（統合）
✅ Webhook統合
✅ 緊急アラート機能
```

### Kill Switch 自動発動条件

```
1. 連続5回損失
2. 日次損失 < -5万円
3. 異常な取引頻度（15回/日超）
4. VM接続断
5. RSSエラー連続3回
```

---

*最終更新: 2025-12-27*

**これで日本株全自動売買システムの完全設計が完成しました。**
