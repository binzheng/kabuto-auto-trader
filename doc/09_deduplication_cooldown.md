# 日本株自動売買システム - 重複防止・冷却ロジック設計

## 概要

全自動売買システムにおいて、**誤発注・過剰取引を防止**するための重複排除（Deduplication）とクールダウン（Cooldown）ロジックを設計します。疑似コードを含めた実装可能な詳細設計を提供します。

---

## 1. 重複防止の必要性

### 1.1 重複発生の原因

```yaml
原因1_ネットワークリトライ:
  - TradingViewからのWebhookが遅延
  - タイムアウト後に再送される
  - 同一シグナルが2回届く

原因2_システム障害:
  - 中継サーバーのクラッシュ
  - 再起動時に未処理リクエストを再実行
  - 既に処理済みの可能性

原因3_手動操作ミス:
  - Alertの手動再発火
  - テスト用シグナルを誤送信
  - 同一条件のAlertを複数設定

原因4_Pine Script の問題:
  - 条件判定のバグで連続発火
  - barstate.isconfirmed の使い忘れ
  - 複数足で同一条件成立
```

### 1.2 重複による問題

```
問題1: 同一銘柄への過剰発注
  → 意図しないポジション倍増
  → リスク管理の破綻
  → 資金不足エラー

問題2: 手数料の無駄
  → 重複注文で往復手数料発生
  → 収益性の低下

問題3: 日次制限の消費
  → 1日3回制限が無駄に消費される
  → 本来のシグナルが処理できない

問題4: クールダウンの無効化
  → 連続注文でクールダウンが機能しない
  → 感情的な連続取引と同じ状態
```

---

## 2. 重複防止戦略（3層防御）

### 2.1 全体フロー

```
Layer 1: リクエストID重複排除（最優先）
  ↓ 通過
Layer 2: 同一銘柄・同一方向の時間窓制御
  ↓ 通過
Layer 3: 日次・週次の累積制限
  ↓ 通過
注文実行
```

---

## 3. Layer 1: リクエストID重複排除

### 3.1 設計原則

**目的：** 完全に同一のリクエストを検出して排除

**方式：** ユニークキー生成 + キャッシュ

**保持期間：** 5-10分（短期間）

### 3.2 ユニークキー生成方式

#### 方式A: timestamp + ticker + action（推奨）

```python
def generate_idempotency_key(request_body):
    """冪等性キーを生成"""
    components = [
        request_body["timestamp"],      # TradingViewのタイムスタンプ
        request_body["ticker"],          # 銘柄コード
        request_body["action"]           # buy or sell
    ]

    # SHA256ハッシュ化
    key_string = "|".join(str(c) for c in components)
    hash_value = hashlib.sha256(key_string.encode()).hexdigest()

    return f"idempotency:{hash_value}"
```

**例：**
```
timestamp: "1735279200000"
ticker: "9984"
action: "buy"

key_string = "1735279200000|9984|buy"
hash = sha256(key_string) = "a1b2c3d4..."
idempotency_key = "idempotency:a1b2c3d4..."
```

#### 方式B: Alert ID（TradingViewが提供する場合）

```python
def generate_idempotency_key_v2(request_body):
    """Alert IDベースの冪等性キー"""
    alert_id = request_body.get("alert_id")

    if alert_id:
        # TradingViewが一意のAlert IDを提供する場合
        return f"idempotency:{alert_id}"
    else:
        # Fallback: timestamp + ticker + action
        return generate_idempotency_key(request_body)
```

### 3.3 Redis実装例

```python
class IdempotencyManager:
    def __init__(self, redis_client):
        self.redis = redis_client
        self.ttl_seconds = 300  # 5分

    def check_and_set(self, request_body):
        """
        重複チェックと登録を原子的に実行

        Returns:
            tuple[bool, dict]: (is_duplicate, cached_response or None)
        """
        key = self.generate_key(request_body)

        # 既存チェック
        cached = self.redis.get(key)
        if cached:
            # 重複検出
            return True, json.loads(cached)

        # 新規リクエスト
        # まず「処理中」フラグを立てる
        processing_flag = {"status": "processing", "timestamp": time.time()}
        self.redis.setex(key, self.ttl_seconds, json.dumps(processing_flag))

        return False, None

    def store_response(self, request_body, response):
        """処理結果をキャッシュに保存"""
        key = self.generate_key(request_body)
        self.redis.setex(key, self.ttl_seconds, json.dumps(response))

    def generate_key(self, request_body):
        """冪等性キー生成"""
        return generate_idempotency_key(request_body)


# 使用例
idempotency = IdempotencyManager(redis_client)

def handle_webhook(request_body):
    # 重複チェック
    is_duplicate, cached_response = idempotency.check_and_set(request_body)

    if is_duplicate:
        logger.info("Duplicate request detected, returning cached response")
        return cached_response

    # 新規リクエスト処理
    try:
        response = process_trading_signal(request_body)
        idempotency.store_response(request_body, response)
        return response

    except Exception as e:
        # エラー時はキャッシュを削除（再試行可能にする）
        key = idempotency.generate_key(request_body)
        redis_client.delete(key)
        raise
```

### 3.4 処理フロー図

```
┌──────────────────────────────────┐
│   Webhook リクエスト受信          │
└────────────┬─────────────────────┘
             │
             ▼
    ┌────────────────────┐
    │ 冪等性キー生成      │
    │ SHA256(ts+ticker+action) │
    └────────┬───────────┘
             │
             ▼
    ┌────────────────────┐
    │ Redis SETNX チェック│
    └────┬───────┬────────┘
         │       │
    存在する│  存在しない│
         │       │
         ▼       ▼
    ┌────────┐ ┌────────┐
    │重複検出│ │新規処理│
    │        │ │        │
    │cached  │ │set TTL │
    │response│ │5分     │
    │を返却  │ │        │
    └────────┘ └────┬───┘
                    │
                    ▼
            ┌────────────────┐
            │ 注文処理実行    │
            └────┬───────────┘
                 │
                 ▼
            ┌────────────────┐
            │ 結果をキャッシュ│
            │ Redis SETEX    │
            └────────────────┘
```

---

## 4. Layer 2: 同一銘柄・同一方向の時間窓制御

### 4.1 設計原則

**目的：** 類似のシグナルを短時間に複数回処理しない

**方式：** 銘柄×方向ごとの最終実行時刻を記録

**時間窓：** 設定可能（デフォルト: 買い30分、売り15分）

### 4.2 時間窓ルール

```yaml
time_window_rules:
  # 買い注文のクールダウン
  buy:
    same_ticker: 30_minutes      # 同一銘柄への買い注文は30分空ける
    any_ticker: 5_minutes        # 任意銘柄への買い注文は5分空ける

  # 売り注文のクールダウン
  sell:
    same_ticker: 15_minutes      # 同一銘柄への売り注文は15分空ける
    any_ticker: 0_minutes        # 売りはグローバル制限なし（決済優先）

  # 特殊ケース
  opposite_direction:
    allowed: true                # 反対方向（買い→売り、売り→買い）は制限なし
    reason: "決済注文は即座に実行すべき"
```

### 4.3 実装例

```python
class CooldownManager:
    def __init__(self, redis_client):
        self.redis = redis_client

    def check_cooldown(self, ticker, action):
        """
        クールダウンチェック

        Returns:
            tuple[bool, dict]: (is_in_cooldown, cooldown_info)
        """
        # 1. 同一銘柄・同一方向のチェック
        same_ticker_key = f"cooldown:{ticker}:{action}"
        last_execution = self.redis.get(same_ticker_key)

        if last_execution:
            last_time = float(last_execution)
            elapsed = time.time() - last_time
            cooldown_period = self._get_cooldown_period(action, "same_ticker")

            if elapsed < cooldown_period:
                remaining = cooldown_period - elapsed
                return True, {
                    "reason": f"same_ticker_{action}_cooldown",
                    "remaining_seconds": int(remaining),
                    "message": f"{ticker}への{action}注文は{int(remaining)}秒後に可能"
                }

        # 2. 任意銘柄へのグローバルクールダウン
        global_key = f"cooldown:global:{action}"
        last_global = self.redis.get(global_key)

        if last_global:
            last_time = float(last_global)
            elapsed = time.time() - last_time
            cooldown_period = self._get_cooldown_period(action, "any_ticker")

            if elapsed < cooldown_period:
                remaining = cooldown_period - elapsed
                return True, {
                    "reason": f"global_{action}_cooldown",
                    "remaining_seconds": int(remaining),
                    "message": f"任意銘柄への{action}注文は{int(remaining)}秒後に可能"
                }

        # クールダウン期間外
        return False, {"status": "ready"}

    def record_execution(self, ticker, action):
        """実行時刻を記録"""
        current_time = time.time()

        # 同一銘柄・同一方向
        same_ticker_key = f"cooldown:{ticker}:{action}"
        cooldown_period = self._get_cooldown_period(action, "same_ticker")
        self.redis.setex(same_ticker_key, int(cooldown_period), str(current_time))

        # グローバル
        global_key = f"cooldown:global:{action}"
        global_cooldown = self._get_cooldown_period(action, "any_ticker")
        if global_cooldown > 0:
            self.redis.setex(global_key, int(global_cooldown), str(current_time))

    def _get_cooldown_period(self, action, level):
        """クールダウン期間を取得（秒）"""
        config = {
            "buy": {
                "same_ticker": 30 * 60,  # 30分
                "any_ticker": 5 * 60     # 5分
            },
            "sell": {
                "same_ticker": 15 * 60,  # 15分
                "any_ticker": 0          # 制限なし
            }
        }
        return config[action][level]

    def get_remaining_time(self, ticker, action):
        """残りクールダウン時間を取得"""
        is_cooldown, info = self.check_cooldown(ticker, action)
        if is_cooldown:
            return info["remaining_seconds"]
        return 0


# 使用例
cooldown = CooldownManager(redis_client)

def process_trading_signal(request_body):
    ticker = request_body["ticker"]
    action = request_body["action"]

    # クールダウンチェック
    is_cooldown, info = cooldown.check_cooldown(ticker, action)

    if is_cooldown:
        logger.warning(f"Cooldown active: {info['message']}")
        return {
            "status": "rejected",
            "reason": "cooldown",
            "details": info
        }

    # 注文処理
    order_result = execute_order(request_body)

    # 成功したら記録
    if order_result["status"] == "success":
        cooldown.record_execution(ticker, action)

    return order_result
```

### 4.4 反対方向の処理

```python
class EnhancedCooldownManager(CooldownManager):
    def check_cooldown_with_position(self, ticker, action, current_positions):
        """
        ポジション状態を考慮したクールダウンチェック

        current_positions: {"9984": {"quantity": 100, "side": "long"}}
        """
        # 反対方向（決済）の場合はクールダウンをスキップ
        if self._is_closing_trade(ticker, action, current_positions):
            logger.info(f"Closing trade detected for {ticker}, skipping cooldown")
            return False, {"status": "closing_trade", "cooldown_skipped": True}

        # 通常のクールダウンチェック
        return super().check_cooldown(ticker, action)

    def _is_closing_trade(self, ticker, action, positions):
        """決済注文かどうか判定"""
        if ticker not in positions:
            return False

        position = positions[ticker]

        # ロングポジションの売り = 決済
        if position["side"] == "long" and action == "sell":
            return True

        # ショートポジションの買い = 決済（空売りする場合）
        if position["side"] == "short" and action == "buy":
            return True

        return False
```

---

## 5. Layer 3: 日次・週次累積制限

### 5.1 設計原則

**目的：** 過剰取引を長期的に防止

**方式：** 日次カウンター + リセット機構

**リセット時刻：** 日本時間00:00（翌営業日）

### 5.2 日次制限ルール

```yaml
daily_limits:
  max_entries_per_day: 3        # 1日最大3回エントリー
  max_entries_per_ticker: 1     # 同一銘柄は1日1回まで
  max_total_trades: 10          # 売買合計10回まで

  reset_time: "00:00 JST"
  reset_on_weekends: false      # 土日はカウントしない
```

### 5.3 実装例

```python
from datetime import datetime, timezone
import pytz

class DailyLimitManager:
    def __init__(self, redis_client):
        self.redis = redis_client
        self.jst = pytz.timezone('Asia/Tokyo')

    def check_daily_limit(self, ticker, action):
        """
        日次制限チェック

        Returns:
            tuple[bool, dict]: (limit_exceeded, limit_info)
        """
        today = self._get_today_key()

        # 1. 全体エントリー数チェック
        total_entries_key = f"daily:entries:{today}"
        total_entries = int(self.redis.get(total_entries_key) or 0)
        max_entries = 3

        if action == "buy" and total_entries >= max_entries:
            return True, {
                "reason": "daily_entry_limit_exceeded",
                "current": total_entries,
                "max": max_entries,
                "reset_at": self._get_next_reset_time()
            }

        # 2. 同一銘柄エントリーチェック
        ticker_entries_key = f"daily:ticker:{ticker}:{today}"
        ticker_entries = int(self.redis.get(ticker_entries_key) or 0)

        if action == "buy" and ticker_entries >= 1:
            return True, {
                "reason": "ticker_daily_limit_exceeded",
                "ticker": ticker,
                "message": f"{ticker}は今日既に取引済み",
                "reset_at": self._get_next_reset_time()
            }

        # 3. 全体取引数チェック
        total_trades_key = f"daily:trades:{today}"
        total_trades = int(self.redis.get(total_trades_key) or 0)
        max_trades = 10

        if total_trades >= max_trades:
            return True, {
                "reason": "daily_trade_limit_exceeded",
                "current": total_trades,
                "max": max_trades,
                "reset_at": self._get_next_reset_time()
            }

        return False, {"status": "ok"}

    def record_trade(self, ticker, action):
        """取引を記録"""
        today = self._get_today_key()
        ttl = self._get_seconds_until_reset()

        # 全体取引数
        total_trades_key = f"daily:trades:{today}"
        self.redis.incr(total_trades_key)
        self.redis.expire(total_trades_key, ttl)

        # エントリーの場合
        if action == "buy":
            # 全体エントリー数
            total_entries_key = f"daily:entries:{today}"
            self.redis.incr(total_entries_key)
            self.redis.expire(total_entries_key, ttl)

            # 銘柄別エントリー数
            ticker_entries_key = f"daily:ticker:{ticker}:{today}"
            self.redis.incr(ticker_entries_key)
            self.redis.expire(ticker_entries_key, ttl)

    def get_current_stats(self):
        """現在の統計を取得"""
        today = self._get_today_key()

        total_entries_key = f"daily:entries:{today}"
        total_trades_key = f"daily:trades:{today}"

        return {
            "date": today,
            "total_entries": int(self.redis.get(total_entries_key) or 0),
            "total_trades": int(self.redis.get(total_trades_key) or 0),
            "max_entries": 3,
            "max_trades": 10,
            "reset_at": self._get_next_reset_time()
        }

    def _get_today_key(self):
        """今日の日付キーを取得（JST）"""
        now = datetime.now(self.jst)
        return now.strftime("%Y-%m-%d")

    def _get_next_reset_time(self):
        """次のリセット時刻を取得"""
        now = datetime.now(self.jst)
        next_day = now.replace(hour=0, minute=0, second=0, microsecond=0)
        next_day += timedelta(days=1)
        return next_day.isoformat()

    def _get_seconds_until_reset(self):
        """リセットまでの秒数"""
        now = datetime.now(self.jst)
        next_reset = self._get_next_reset_time()
        next_reset_dt = datetime.fromisoformat(next_reset)
        return int((next_reset_dt - now).total_seconds())
```

---

## 6. 統合実装例

### 6.1 全層を統合したフィルター

```python
class DuplicationAndCooldownFilter:
    def __init__(self, redis_client):
        self.idempotency = IdempotencyManager(redis_client)
        self.cooldown = EnhancedCooldownManager(redis_client)
        self.daily_limit = DailyLimitManager(redis_client)

    def filter_request(self, request_body, current_positions):
        """
        3層フィルターを実行

        Returns:
            dict: {
                "allowed": bool,
                "reason": str,
                "details": dict
            }
        """
        ticker = request_body["ticker"]
        action = request_body["action"]

        # Layer 1: 冪等性チェック
        is_duplicate, cached_response = self.idempotency.check_and_set(request_body)
        if is_duplicate:
            logger.info("Layer 1: Duplicate request detected")
            return {
                "allowed": False,
                "reason": "duplicate_request",
                "details": {"cached_response": cached_response}
            }

        # Layer 2: クールダウンチェック
        is_cooldown, cooldown_info = self.cooldown.check_cooldown_with_position(
            ticker, action, current_positions
        )
        if is_cooldown:
            logger.warning(f"Layer 2: Cooldown active - {cooldown_info}")
            return {
                "allowed": False,
                "reason": "cooldown",
                "details": cooldown_info
            }

        # Layer 3: 日次制限チェック
        limit_exceeded, limit_info = self.daily_limit.check_daily_limit(ticker, action)
        if limit_exceeded:
            logger.warning(f"Layer 3: Daily limit exceeded - {limit_info}")
            return {
                "allowed": False,
                "reason": "daily_limit",
                "details": limit_info
            }

        # 全てクリア
        return {
            "allowed": True,
            "reason": "all_checks_passed",
            "details": {}
        }

    def record_successful_trade(self, request_body):
        """取引成功時の記録"""
        ticker = request_body["ticker"]
        action = request_body["action"]

        # 冪等性キャッシュ（既に check_and_set で設定済み）
        # クールダウン記録
        self.cooldown.record_execution(ticker, action)

        # 日次カウンター更新
        self.daily_limit.record_trade(ticker, action)


# 使用例
def handle_trading_signal(request_body):
    # 現在のポジション取得
    current_positions = get_current_positions()

    # フィルター実行
    filter_result = dedup_filter.filter_request(request_body, current_positions)

    if not filter_result["allowed"]:
        logger.warning(f"Request rejected: {filter_result['reason']}")
        return {
            "status": "rejected",
            "reason": filter_result["reason"],
            "details": filter_result["details"]
        }

    # 注文処理
    try:
        order_result = execute_order(request_body)

        if order_result["status"] == "success":
            dedup_filter.record_successful_trade(request_body)

        return order_result

    except Exception as e:
        logger.error(f"Order execution failed: {e}")
        # エラー時は冪等性キャッシュを削除（再試行可能に）
        key = dedup_filter.idempotency.generate_key(request_body)
        redis_client.delete(key)
        raise
```

---

## 7. 再送対策（TradingView側）

### 7.1 Pine Script のベストプラクティス

```pinescript
//@version=5
strategy("Deduplication Example", overlay=true)

// === 重複防止のための変数 ===
var int lastEntryBar = 0           // 最後にエントリーしたバー番号
var string lastEntryTimestamp = "" // 最後のタイムスタンプ

// === エントリー条件 ===
longCondition = ta.crossover(ta.ema(close, 5), ta.ema(close, 25))

// === 重複防止チェック ===
// 1. 確定足のみで判定
if barstate.isconfirmed
    // 2. 前回エントリーから最低10バー空ける
    barsSinceEntry = bar_index - lastEntryBar

    if longCondition and barsSinceEntry >= 10
        // 3. タイムスタンプ生成（ユニーク性保証）
        currentTimestamp = str.tostring(time)

        // 4. 同じタイムスタンプで発火しない
        if currentTimestamp != lastEntryTimestamp
            strategy.entry("Long", strategy.long)

            // Alert送信
            alert('{"action":"buy","ticker":"9984","timestamp":"' + currentTimestamp + '"}',
                  alert.freq_once_per_bar)

            // 記録
            lastEntryBar := bar_index
            lastEntryTimestamp := currentTimestamp
```

**重要ポイント：**
1. **`barstate.isconfirmed`** を使用（確定足のみ）
2. **`alert.freq_once_per_bar`** を指定（1バー1回のみ）
3. **最小バー間隔**を設定（10バー = 15分足なら150分）
4. **タイムスタンプ記録**で同一時刻の重複を防止

---

## 8. モニタリング・アラート

### 8.1 重複検知アラート

```python
class DuplicationMonitor:
    def __init__(self):
        self.duplicate_threshold = 3  # 3回重複で警告

    def check_duplicate_pattern(self, ticker, action, time_window_minutes=60):
        """重複パターンを検知"""
        # 過去1時間の重複回数を取得
        key = f"duplicate_count:{ticker}:{action}:{time_window_minutes}min"
        count = int(redis_client.get(key) or 0)

        if count >= self.duplicate_threshold:
            # アラート送信
            send_alert({
                "level": "warning",
                "message": f"Duplicate pattern detected for {ticker} {action}",
                "count": count,
                "time_window": time_window_minutes,
                "action_required": "Check TradingView Alert configuration"
            })

        # カウント更新
        redis_client.incr(key)
        redis_client.expire(key, time_window_minutes * 60)
```

### 8.2 クールダウン統計

```python
def get_cooldown_statistics(hours=24):
    """クールダウンによる拒否統計"""
    stats = {
        "total_requests": 0,
        "cooldown_rejections": 0,
        "duplicate_rejections": 0,
        "daily_limit_rejections": 0,
        "accepted_requests": 0
    }

    # ログから集計
    logs = fetch_logs(hours=hours)
    for log in logs:
        stats["total_requests"] += 1

        if log["reason"] == "cooldown":
            stats["cooldown_rejections"] += 1
        elif log["reason"] == "duplicate_request":
            stats["duplicate_rejections"] += 1
        elif log["reason"] == "daily_limit":
            stats["daily_limit_rejections"] += 1
        elif log["status"] == "success":
            stats["accepted_requests"] += 1

    stats["rejection_rate"] = (
        (stats["total_requests"] - stats["accepted_requests"]) /
        stats["total_requests"] * 100
    ) if stats["total_requests"] > 0 else 0

    return stats
```

---

## 9. 設定ファイル例

```yaml
# config/deduplication.yaml

idempotency:
  enabled: true
  backend: "redis"
  ttl_seconds: 300              # 5分間キャッシュ
  key_algorithm: "sha256"

cooldown:
  enabled: true
  rules:
    buy:
      same_ticker_minutes: 30   # 同一銘柄への買いは30分空ける
      any_ticker_minutes: 5     # 任意銘柄への買いは5分空ける
    sell:
      same_ticker_minutes: 15   # 同一銘柄への売りは15分空ける
      any_ticker_minutes: 0     # グローバル制限なし

  skip_for_closing_trades: true # 決済注文はクールダウンをスキップ

daily_limits:
  enabled: true
  max_entries_per_day: 3
  max_entries_per_ticker: 1
  max_total_trades: 10
  reset_time: "00:00 JST"
  count_weekends: false

monitoring:
  duplicate_threshold: 3        # 3回重複で警告
  alert_channels:
    - slack
    - email
```

---

## まとめ

### 3層防御の重要性

| Layer | 目的 | 方式 | 効果 |
|-------|------|------|------|
| **Layer 1** | 完全同一リクエスト排除 | 冪等性キー（5分TTL） | ネットワークリトライ対策 |
| **Layer 2** | 類似シグナル抑制 | クールダウン（30分） | 過剰取引防止 |
| **Layer 3** | 長期的制限 | 日次カウンター | 1日3回制限 |

### 実装チェックリスト

```
✅ Layer 1: 冪等性キー生成（SHA256）
✅ Redis SETNX での重複チェック
✅ Layer 2: 同一銘柄クールダウン（30分）
✅ 反対方向（決済）の例外処理
✅ Layer 3: 日次エントリー制限（3回）
✅ 同一銘柄1日1回制限
✅ Pine Script の barstate.isconfirmed
✅ モニタリング・アラート機能
```

---

*最終更新: 2025-12-27*
