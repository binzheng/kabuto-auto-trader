# 日本株自動売買システム - セキュリティ・安全設計

## 1. Webhook 認証

### 1.1 基本認証方式

#### 1.1.1 パスフレーズ認証（推奨）
```python
# TradingView Alert メッセージ例
{
  "passphrase": "your-secret-passphrase-2025",
  "ticker": "9984",
  "action": "buy",
  "quantity": 100
}

# 中継サーバー側検証
import os
from fastapi import HTTPException

WEBHOOK_SECRET = os.getenv("WEBHOOK_SECRET")

def verify_webhook(payload: dict):
    if payload.get("passphrase") != WEBHOOK_SECRET:
        raise HTTPException(status_code=401, detail="Invalid passphrase")
```

**実装ポイント：**
- 環境変数 `.env` にパスフレーズを保存（Git にコミットしない）
- パスフレーズは20文字以上のランダム文字列を推奨
- 定期的な変更（3ヶ月ごと推奨）

#### 1.1.2 IP アドレスホワイトリスト（追加防御層）
```python
# TradingView の IP 範囲を許可
ALLOWED_IPS = [
    "52.89.214.238",
    "34.212.75.30",
    "54.218.53.128",
    "52.32.178.7",
    # TradingView の最新 IP リストを確認
]

from fastapi import Request

def verify_ip(request: Request):
    client_ip = request.client.host
    if client_ip not in ALLOWED_IPS:
        raise HTTPException(status_code=403, detail="IP not allowed")
```

**注意事項：**
- TradingView は IP が変更される可能性あり
- 過度に依存せず、パスフレーズと組み合わせて使用

#### 1.1.3 署名検証（高度な実装）
```python
import hmac
import hashlib

def generate_signature(payload: dict, secret: str) -> str:
    message = json.dumps(payload, sort_keys=True)
    return hmac.new(
        secret.encode(),
        message.encode(),
        hashlib.sha256
    ).hexdigest()

# TradingView Alert（Pine Script で署名生成は不可能なため非推奨）
# 代わりに中継サーバー側でタイムスタンプ検証を実施
```

### 1.2 タイムスタンプ検証（リプレイ攻撃防止）

```python
from datetime import datetime, timedelta

def verify_timestamp(payload: dict):
    timestamp_str = payload.get("timestamp")
    if not timestamp_str:
        raise HTTPException(status_code=400, detail="Missing timestamp")

    timestamp = datetime.fromisoformat(timestamp_str.replace("Z", "+00:00"))
    now = datetime.now(timezone.utc)

    # 5分以内のリクエストのみ受付
    if abs((now - timestamp).total_seconds()) > 300:
        raise HTTPException(status_code=400, detail="Request expired")
```

**TradingView Alert メッセージに追加：**
```json
{
  "passphrase": "your-secret",
  "timestamp": "{{timenow}}",
  "ticker": "{{ticker}}",
  "action": "buy"
}
```

### 1.3 HTTPS 必須化

```python
# 本番環境では必ず HTTPS を使用
# Let's Encrypt で無料 SSL 証明書を取得

# Nginx 設定例
server {
    listen 443 ssl;
    server_name your-domain.com;

    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

    location /webhook {
        proxy_pass http://localhost:8000;
    }
}

# HTTP → HTTPS リダイレクト
server {
    listen 80;
    server_name your-domain.com;
    return 301 https://$server_name$request_uri;
}
```

---

## 2. Excel 誤発注防止

### 2.1 注文前バリデーション

#### 2.1.1 パラメータ検証
```python
from pydantic import BaseModel, validator

class OrderRequest(BaseModel):
    ticker: str
    action: str  # "buy" or "sell"
    quantity: int
    price: float | str  # float or "market"

    @validator('ticker')
    def validate_ticker(cls, v):
        # 4桁の数字コードのみ許可
        if not v.isdigit() or len(v) != 4:
            raise ValueError("Invalid ticker format")
        return v

    @validator('action')
    def validate_action(cls, v):
        if v not in ["buy", "sell"]:
            raise ValueError("Action must be buy or sell")
        return v

    @validator('quantity')
    def validate_quantity(cls, v):
        if v <= 0:
            raise ValueError("Quantity must be positive")
        if v > 10000:  # 1回の注文上限
            raise ValueError("Quantity exceeds maximum")
        # 単元株チェック（100株単位）
        if v % 100 != 0:
            raise ValueError("Quantity must be multiple of 100")
        return v

    @validator('price')
    def validate_price(cls, v):
        if isinstance(v, str):
            if v != "market":
                raise ValueError("String price must be 'market'")
        elif isinstance(v, float):
            if v <= 0:
                raise ValueError("Price must be positive")
        return v
```

#### 2.1.2 二重チェック（VBA 側でも検証）
```vba
' Excel VBA 側の検証関数
Function ValidateOrder(ticker As String, action As String, _
                      quantity As Long, price As Variant) As Boolean
    ' 銘柄コード検証
    If Len(ticker) <> 4 Or Not IsNumeric(ticker) Then
        MsgBox "無効な銘柄コード: " & ticker
        ValidateOrder = False
        Exit Function
    End If

    ' 売買区分検証
    If action <> "buy" And action <> "sell" Then
        MsgBox "無効な売買区分: " & action
        ValidateOrder = False
        Exit Function
    End If

    ' 数量検証
    If quantity <= 0 Or quantity > 10000 Then
        MsgBox "無効な数量: " & quantity
        ValidateOrder = False
        Exit Function
    End If

    If quantity Mod 100 <> 0 Then
        MsgBox "数量は100株単位で指定してください: " & quantity
        ValidateOrder = False
        Exit Function
    End If

    ValidateOrder = True
End Function
```

### 2.2 注文前確認ログ

```python
import logging

# 注文実行前に必ずログ記録
def log_order_intent(order: OrderRequest):
    logger.info(
        f"ORDER_INTENT: "
        f"ticker={order.ticker} "
        f"action={order.action} "
        f"quantity={order.quantity} "
        f"price={order.price} "
        f"estimated_amount={estimate_order_amount(order)}"
    )

def estimate_order_amount(order: OrderRequest) -> float:
    """注文金額の概算を計算"""
    # 最新株価を取得して概算
    current_price = get_current_price(order.ticker)
    return current_price * order.quantity
```

### 2.3 注文額上限チェック

```python
# config.yaml
risk_limits:
  max_order_amount: 500000  # 1注文あたり最大50万円
  max_position_amount: 1000000  # 全ポジション合計最大100万円

def check_order_amount_limit(order: OrderRequest):
    estimated_amount = estimate_order_amount(order)

    if estimated_amount > config.max_order_amount:
        raise ValueError(
            f"Order amount {estimated_amount} exceeds limit "
            f"{config.max_order_amount}"
        )

    # 現在のポジション金額を取得
    current_position_amount = get_current_position_amount()

    if order.action == "buy":
        total_amount = current_position_amount + estimated_amount
        if total_amount > config.max_position_amount:
            raise ValueError(
                f"Total position {total_amount} would exceed limit "
                f"{config.max_position_amount}"
            )
```

### 2.4 ドライランモード（テスト実行）

```python
# 環境変数で制御
DRY_RUN = os.getenv("DRY_RUN", "false").lower() == "true"

def execute_order(order: OrderRequest):
    if DRY_RUN:
        logger.info(f"[DRY_RUN] Would execute order: {order}")
        return {
            "status": "dry_run",
            "order_id": "DRY_" + str(uuid.uuid4()),
            "message": "Order not actually executed (dry run mode)"
        }

    # 実際の注文実行
    return send_order_to_excel(order)
```

---

## 3. Kill Switch（緊急停止機能）

### 3.1 多層 Kill Switch 設計

#### レベル1: TradingView Alert 無効化（最も安全）
- TradingView の Web UI で Alert を一時停止
- 手動操作、即座に反映
- **推奨：**緊急時の第一手段

#### レベル2: 中継サーバー停止
```bash
# systemd サービスの停止
sudo systemctl stop kabuto-webhook

# または Docker コンテナの停止
docker stop kabuto-webhook

# プロセス直接終了
pkill -f "python.*webhook"
```

#### レベル3: 中継サーバー Kill Switch API
```python
# グローバル停止フラグ
SYSTEM_ENABLED = True

@app.post("/admin/kill-switch")
async def kill_switch(password: str):
    global SYSTEM_ENABLED

    if password != os.getenv("ADMIN_PASSWORD"):
        raise HTTPException(status_code=401)

    SYSTEM_ENABLED = False
    logger.critical("KILL SWITCH ACTIVATED - All trading stopped")

    return {"status": "killed", "message": "System disabled"}

@app.post("/webhook")
async def webhook_handler(payload: dict):
    if not SYSTEM_ENABLED:
        logger.warning("Webhook rejected - system disabled")
        raise HTTPException(status_code=503, detail="System disabled")

    # 通常処理
    ...
```

**CLI ツールでの Kill Switch 発動：**
```bash
# kill_switch.sh
#!/bin/bash
curl -X POST https://your-server.com/admin/kill-switch \
  -H "Content-Type: application/json" \
  -d "{\"password\": \"$ADMIN_PASSWORD\"}"
```

#### レベル4: Windows VM シャットダウン
```bash
# macOS から VM を強制シャットダウン
# Parallels の場合
prlctl stop "Windows 11" --kill

# VMware Fusion の場合
vmrun stop "/path/to/Windows 11.vmx" hard
```

### 3.2 自動 Kill Switch トリガー

```python
# 損失上限による自動停止
class AutoKillSwitch:
    def __init__(self):
        self.daily_loss_limit = -100000  # -10万円
        self.consecutive_loss_limit = 5  # 連続5回損失

    def check_triggers(self, execution_result: dict):
        # 当日損失チェック
        daily_pnl = self.get_daily_pnl()
        if daily_pnl < self.daily_loss_limit:
            self.activate_kill_switch(
                reason=f"Daily loss limit exceeded: {daily_pnl}"
            )

        # 連続損失チェック
        consecutive_losses = self.get_consecutive_losses()
        if consecutive_losses >= self.consecutive_loss_limit:
            self.activate_kill_switch(
                reason=f"Consecutive losses: {consecutive_losses}"
            )

        # 市場時間外チェック
        if not self.is_market_hours():
            self.activate_kill_switch(
                reason="Trading outside market hours detected"
            )

    def activate_kill_switch(self, reason: str):
        global SYSTEM_ENABLED
        SYSTEM_ENABLED = False

        logger.critical(f"AUTO KILL SWITCH: {reason}")

        # 緊急通知送信
        self.send_emergency_alert(reason)
```

### 3.3 緊急通知

```python
import requests

def send_emergency_alert(message: str):
    """Slack/Email/SMS で緊急通知"""

    # Slack 通知
    slack_webhook = os.getenv("SLACK_WEBHOOK_URL")
    if slack_webhook:
        requests.post(slack_webhook, json={
            "text": f"🚨 EMERGENCY ALERT 🚨\n{message}",
            "username": "Kabuto Trading Bot",
            "icon_emoji": ":rotating_light:"
        })

    # Email 通知（Gmail SMTP 例）
    import smtplib
    from email.message import EmailMessage

    msg = EmailMessage()
    msg["Subject"] = "🚨 Trading System Emergency"
    msg["From"] = os.getenv("ALERT_EMAIL_FROM")
    msg["To"] = os.getenv("ALERT_EMAIL_TO")
    msg.set_content(message)

    with smtplib.SMTP_SSL("smtp.gmail.com", 465) as smtp:
        smtp.login(
            os.getenv("SMTP_USER"),
            os.getenv("SMTP_PASSWORD")
        )
        smtp.send_message(msg)
```

---

## 4. ログと監査

### 4.1 ログレベル設計

```python
import logging
from logging.handlers import RotatingFileHandler
import json

# ログディレクトリ構成
# logs/
#   ├── signals/      # TradingView シグナル受信ログ
#   ├── orders/       # 注文実行ログ
#   ├── executions/   # 約定ログ
#   ├── errors/       # エラーログ
#   └── audit/        # 監査ログ（全イベント）

def setup_logging():
    # 監査ログ（全イベント記録）
    audit_logger = logging.getLogger("audit")
    audit_handler = RotatingFileHandler(
        "logs/audit/audit.log",
        maxBytes=10*1024*1024,  # 10MB
        backupCount=100
    )
    audit_handler.setFormatter(
        logging.Formatter('%(asctime)s - %(message)s')
    )
    audit_logger.addHandler(audit_handler)
    audit_logger.setLevel(logging.INFO)

    # シグナルログ
    signal_logger = logging.getLogger("signal")
    signal_handler = RotatingFileHandler(
        "logs/signals/signal.log",
        maxBytes=10*1024*1024,
        backupCount=50
    )
    signal_logger.addHandler(signal_handler)

    # 注文ログ
    order_logger = logging.getLogger("order")
    order_handler = RotatingFileHandler(
        "logs/orders/order.log",
        maxBytes=10*1024*1024,
        backupCount=50
    )
    order_logger.addHandler(order_handler)

    # エラーログ
    error_logger = logging.getLogger("error")
    error_handler = RotatingFileHandler(
        "logs/errors/error.log",
        maxBytes=10*1024*1024,
        backupCount=30
    )
    error_logger.addHandler(error_handler)
    error_logger.setLevel(logging.ERROR)
```

### 4.2 構造化ログ（JSON 形式）

```python
def log_signal_received(payload: dict, request_id: str):
    """シグナル受信時のログ"""
    signal_logger.info(json.dumps({
        "event": "signal_received",
        "request_id": request_id,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "source_ip": payload.get("source_ip"),
        "ticker": payload.get("ticker"),
        "action": payload.get("action"),
        "quantity": payload.get("quantity"),
        "price": payload.get("price"),
        "alert_id": payload.get("alert_id")
    }))

def log_order_executed(order: OrderRequest, result: dict, request_id: str):
    """注文実行時のログ"""
    order_logger.info(json.dumps({
        "event": "order_executed",
        "request_id": request_id,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "order": order.dict(),
        "result": result,
        "estimated_amount": estimate_order_amount(order)
    }))

def log_execution_confirmed(execution: dict, request_id: str):
    """約定確認時のログ"""
    execution_logger.info(json.dumps({
        "event": "execution_confirmed",
        "request_id": request_id,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "order_id": execution.get("order_id"),
        "ticker": execution.get("ticker"),
        "executed_price": execution.get("price"),
        "executed_quantity": execution.get("quantity"),
        "execution_time": execution.get("time")
    }))
```

### 4.3 監査証跡の保持期間

```yaml
# log_retention_policy.yaml
retention:
  audit_logs: 7_years      # 税務調査対応（7年保存）
  order_logs: 3_years      # 取引記録
  execution_logs: 3_years  # 約定記録
  signal_logs: 1_year      # シグナル履歴
  error_logs: 1_year       # エラー履歴
```

**自動ログアーカイブスクリプト：**
```bash
#!/bin/bash
# archive_old_logs.sh

ARCHIVE_DIR="/backup/trading_logs"
LOG_DIR="/var/log/kabuto"

# 1年以上前のシグナルログを圧縮・アーカイブ
find "$LOG_DIR/signals" -name "*.log.*" -mtime +365 \
  -exec gzip {} \; \
  -exec mv {}.gz "$ARCHIVE_DIR/signals/" \;

# 3年以上前の注文ログを圧縮・アーカイブ
find "$LOG_DIR/orders" -name "*.log.*" -mtime +1095 \
  -exec gzip {} \; \
  -exec mv {}.gz "$ARCHIVE_DIR/orders/" \;

# 7年以上前の監査ログを外部ストレージに移動
find "$LOG_DIR/audit" -name "*.log.*" -mtime +2555 \
  -exec gzip {} \; \
  -exec rclone move {} remote:trading-archive/ \;
```

### 4.4 ログ分析ツール

```python
# log_analyzer.py
import json
from datetime import datetime, timedelta
from collections import defaultdict

class LogAnalyzer:
    def __init__(self, log_file: str):
        self.log_file = log_file

    def get_daily_summary(self, date: str):
        """日次サマリーを生成"""
        summary = {
            "total_signals": 0,
            "total_orders": 0,
            "total_executions": 0,
            "errors": 0,
            "pnl": 0.0,
            "tickers": defaultdict(int)
        }

        with open(self.log_file, 'r') as f:
            for line in f:
                try:
                    log = json.loads(line)
                    if not log.get("timestamp", "").startswith(date):
                        continue

                    event = log.get("event")
                    if event == "signal_received":
                        summary["total_signals"] += 1
                        summary["tickers"][log.get("ticker")] += 1
                    elif event == "order_executed":
                        summary["total_orders"] += 1
                    elif event == "execution_confirmed":
                        summary["total_executions"] += 1
                    elif event == "error":
                        summary["errors"] += 1
                except json.JSONDecodeError:
                    continue

        return summary

    def detect_anomalies(self):
        """異常パターンを検出"""
        anomalies = []

        # 同一銘柄への短時間連続注文
        # 異常に高い注文頻度
        # 市場時間外の注文試行
        # 等をチェック

        return anomalies
```

### 4.5 リアルタイム監視ダッシュボード（Optional）

```python
# dashboard.py (Streamlit 例)
import streamlit as st
import pandas as pd

st.title("Kabuto Trading System - Live Monitor")

# 最新10件のシグナル
st.header("Recent Signals")
signals = get_recent_signals(limit=10)
st.dataframe(signals)

# 当日統計
st.header("Today's Statistics")
col1, col2, col3 = st.columns(3)
col1.metric("Total Orders", get_today_order_count())
col2.metric("Total Executions", get_today_execution_count())
col3.metric("Realized P&L", f"¥{get_today_pnl():,.0f}")

# エラーアラート
st.header("Errors & Alerts")
errors = get_recent_errors(limit=5)
if errors:
    st.error(f"⚠️ {len(errors)} errors detected")
    st.dataframe(errors)

# Kill Switch ボタン
if st.button("🚨 EMERGENCY STOP"):
    activate_kill_switch("Manual activation from dashboard")
    st.success("Kill Switch activated")
```

---

## 5. セキュリティチェックリスト

### 5.1 運用開始前の確認事項

- [ ] `.env` ファイルが `.gitignore` に含まれている
- [ ] Webhook パスフレーズが20文字以上
- [ ] HTTPS 証明書が正しく設定されている
- [ ] IP ホワイトリストが最新
- [ ] ログディレクトリの権限が適切（`chmod 700`）
- [ ] Kill Switch の動作を確認済み
- [ ] 緊急連絡先が設定済み（Slack/Email）
- [ ] バックアップスクリプトが動作している
- [ ] ドライランモードで最低1週間テスト済み

### 5.2 定期メンテナンス

**毎日：**
- [ ] ログファイルサイズの確認
- [ ] エラーログの確認
- [ ] 当日取引サマリーの確認

**毎週：**
- [ ] 週次 P&L レポート作成
- [ ] 異常パターンの検出
- [ ] ログバックアップの確認

**毎月：**
- [ ] Webhook パスフレーズの変更検討
- [ ] システムアップデート適用
- [ ] ログアーカイブの実施

**四半期ごと：**
- [ ] 全コンポーネントのセキュリティ監査
- [ ] Kill Switch の実地テスト
- [ ] 災害復旧計画の見直し

---

## 6. インシデント対応手順

### 6.1 誤発注が発生した場合

```
1. Kill Switch 発動（即座にシステム停止）
2. MarketSpeed II で手動取消/決済
3. インシデントログに記録
4. 原因調査（ログ分析）
5. 再発防止策の実施
6. テスト環境で検証後、システム再開
```

### 6.2 不正アクセスの疑いがある場合

```
1. Kill Switch 発動
2. 中継サーバーのネットワークを遮断
3. アクセスログの分析
4. Webhook パスフレーズの変更
5. IP ホワイトリストの見直し
6. 異常なログエントリの特定と報告
```

### 6.3 システム障害の場合

```
1. Windows VM の再起動
2. 中継サーバーの再起動
3. ログで障害時刻のポジション状態を確認
4. 必要に応じて手動ポジション調整
5. 障害原因の特定と修正
6. ドライランモードで動作確認後、再開
```

---

*最終更新: 2025-12-27*
