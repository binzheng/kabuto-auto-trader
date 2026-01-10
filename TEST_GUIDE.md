# Kabuto Auto Trader - テストガイド

## 概要

このガイドでは、**実際のMarketSpeed IIなしで**新しい簡略化されたExcel VBAの注文実行機能をテストする手順を説明します。

---

## テスト環境の準備

### 前提条件

- Python 3.9+
- Redis
- Excel（VBAが動作する環境）
- curl または Postman（APIテスト用）

---

## ステップ1: Relay Serverのセットアップ

### 1-1. 設定ファイル作成

```bash
cd relay_server
cp config.yaml.example config.yaml
```

### 1-2. テスト用config.yaml編集

最小限の設定でテスト：

```yaml
server:
  host: "0.0.0.0"
  port: 5000
  debug: true
  workers: 1

security:
  webhook_secret: "test_secret"
  api_key: "test_api_key_12345"
  admin_password: "admin123"
  allowed_ips: []

database:
  url: "sqlite:///./data/test_kabuto.db"
  echo: false

redis:
  host: "localhost"
  port: 6379
  db: 1  # テスト用に別のDB使用
  password: null
  decode_responses: true

risk_control:
  max_total_exposure: 1000000
  max_position_per_ticker: 200000
  max_open_positions: 5
  max_daily_entries: 10
  max_daily_trades: 30
  max_consecutive_losses: 10
  max_daily_loss: -100000

cooldown:
  buy_same_ticker: 10  # テスト用に短縮（10秒）
  buy_any_ticker: 5
  sell_same_ticker: 5
  sell_any_ticker: 0

signal:
  expiration_minutes: 30
  max_pending_signals: 100

market_hours:
  timezone: "Asia/Tokyo"
  safe_trading_windows:
    morning:
      start: "00:00"  # テスト用に24時間許可
      end: "23:59"
    afternoon:
      start: "00:00"
      end: "23:59"
  off_hours_action: "ACCEPT"

logging:
  level: "DEBUG"
  format: "text"
  file: "./data/logs/test_kabuto_{time:YYYY-MM-DD}.log"
  rotation: "1 day"
  retention: "7 days"
  compression: "gz"

alerts:
  enabled: false  # テスト中は通知無効

heartbeat:
  timeout_seconds: 600
  alert_enabled: false
```

### 1-3. Redis起動

```bash
# macOS/Linux
redis-server

# Docker
docker run -d -p 6379:6379 redis:latest

# 接続確認
redis-cli ping
# → PONG が返ればOK
```

### 1-4. Relay Server起動

```bash
cd relay_server
python app/main.py
```

**確認**:
```
=============================================================
Kabuto Relay Server Starting...
=============================================================
...
Kabuto Relay Server Started Successfully
=============================================================
```

### 1-5. API動作確認

```bash
# Pingテスト
curl http://localhost:5000/ping

# ヘルスチェック
curl http://localhost:5000/health

# ステータス確認
curl http://localhost:5000/status
```

---

## ステップ2: Excel VBAのセットアップ

### 2-1. 新しいExcelファイル作成

`Kabuto_Test.xlsm` という名前でExcelファイルを作成（マクロ有効）

### 2-2. シート作成

**1. Configシート**

| A列（キー） | B列（値） |
|------------|----------|
| API_BASE_URL | http://localhost:5000 |
| API_KEY | test_api_key_12345 |
| CLIENT_ID | excel_test_01 |

**2. OrderLogシート**

ヘッダー行:
| A | B | C | D | E | F | G |
|---|---|---|---|---|---|---|
| Timestamp | Signal ID | Ticker | Action | Order ID | Status | Reason |

### 2-3. VBAモジュールインポート

VBAエディタ（Alt+F11）を開き、以下をインポート：

1. `excel_vba_simplified/Module_Main_Simple.bas`
2. `excel_vba_simplified/Module_API_Simple.bas`
3. `excel_vba_simplified/Module_Config_Simple.bas`

### 2-4. テスト用にRSS実行をモック化

`Module_Main_Simple.bas` に以下のモック関数を追加：

```vba
' ========================================
' RSS注文実行（モック版 - テスト用）
' ========================================
Function ExecuteRSSOrder_Mock(signal As Dictionary) As String
    '
    ' テスト用: 実際のRSSを呼ばずに成功を返す
    '
    On Error GoTo ErrorHandler

    Debug.Print "=== MOCK: RSS Order Execution ==="
    Debug.Print "Ticker: " & signal("ticker")
    Debug.Print "Action: " & signal("action")
    Debug.Print "Quantity: " & signal("quantity")

    ' モック注文ID生成
    Dim orderId As String
    orderId = "MOCK_ORD_" & Format(Now, "yyyymmddhhnnss") & "_" & signal("ticker")

    ' 2秒待機（実際のRSS処理をシミュレート）
    Application.Wait Now + TimeValue("00:00:02")

    ' 成功を返す
    Debug.Print "MOCK: Order executed successfully"
    ExecuteRSSOrder_Mock = orderId

    Exit Function

ErrorHandler:
    Debug.Print "Error in ExecuteRSSOrder_Mock: " & Err.Description
    ExecuteRSSOrder_Mock = ""
End Function
```

次に、`ExecuteValidatedSignal` サブルーチンを修正：

```vba
' ExecuteRSSOrder(signal) を ExecuteRSSOrder_Mock(signal) に変更
Dim orderId As String
orderId = ExecuteRSSOrder_Mock(signal)  ' ← モック版を使用
```

---

## ステップ3: テストシグナル送信スクリプト

### 3-1. テストスクリプト作成

`test_send_signal.py` を作成：

```python
#!/usr/bin/env python3
"""
Kabuto Auto Trader - Test Signal Sender
テスト用シグナル送信スクリプト
"""
import requests
import json
from datetime import datetime

# Relay Server設定
BASE_URL = "http://localhost:5000"
WEBHOOK_SECRET = "test_secret"

def send_buy_signal(ticker: str = "7203", quantity: int = 100):
    """買いシグナル送信"""
    url = f"{BASE_URL}/webhook"

    signal = {
        "passphrase": WEBHOOK_SECRET,
        "action": "buy",
        "ticker": ticker,
        "quantity": quantity,
        "price": 1850.0,
        "entry_price": 1850.0,
        "stop_loss": 1800.0,
        "take_profit": 1950.0,
        "atr": 50.0,
        "rr_ratio": 2.0,
        "rsi": 45.0,
        "timestamp": datetime.now().isoformat()
    }

    print(f"📤 Sending BUY signal: {ticker} x {quantity}")
    print(f"Signal: {json.dumps(signal, indent=2)}")

    response = requests.post(url, json=signal)

    print(f"\n✅ Response [{response.status_code}]:")
    print(json.dumps(response.json(), indent=2))

    return response.json()

def send_sell_signal(ticker: str = "7203", quantity: int = 100):
    """売りシグナル送信"""
    url = f"{BASE_URL}/webhook"

    signal = {
        "passphrase": WEBHOOK_SECRET,
        "action": "sell",
        "ticker": ticker,
        "quantity": quantity,
        "price": 1900.0,
        "entry_price": 1850.0,
        "stop_loss": 1800.0,
        "take_profit": 1950.0,
        "atr": 50.0,
        "rr_ratio": 2.0,
        "rsi": 65.0,
        "timestamp": datetime.now().isoformat()
    }

    print(f"📤 Sending SELL signal: {ticker} x {quantity}")
    print(f"Signal: {json.dumps(signal, indent=2)}")

    response = requests.post(url, json=signal)

    print(f"\n✅ Response [{response.status_code}]:")
    print(json.dumps(response.json(), indent=2))

    return response.json()

def check_pending_signals():
    """保留中のシグナル確認"""
    url = f"{BASE_URL}/api/signals/pending"
    headers = {"Authorization": "Bearer test_api_key_12345"}

    response = requests.get(url, headers=headers)

    if response.status_code == 204:
        print("📭 No pending signals")
        return []

    print(f"📬 Pending signals [{response.status_code}]:")
    data = response.json()
    print(json.dumps(data, indent=2))

    return data.get("signals", [])

if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("Usage:")
        print("  python test_send_signal.py buy [ticker] [quantity]")
        print("  python test_send_signal.py sell [ticker] [quantity]")
        print("  python test_send_signal.py check")
        print("\nExamples:")
        print("  python test_send_signal.py buy 7203 100")
        print("  python test_send_signal.py sell 7203 100")
        print("  python test_send_signal.py check")
        sys.exit(1)

    command = sys.argv[1].lower()

    if command == "buy":
        ticker = sys.argv[2] if len(sys.argv) > 2 else "7203"
        quantity = int(sys.argv[3]) if len(sys.argv) > 3 else 100
        send_buy_signal(ticker, quantity)

    elif command == "sell":
        ticker = sys.argv[2] if len(sys.argv) > 2 else "7203"
        quantity = int(sys.argv[3]) if len(sys.argv) > 3 else 100
        send_sell_signal(ticker, quantity)

    elif command == "check":
        check_pending_signals()

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)
```

実行権限付与：
```bash
chmod +x test_send_signal.py
```

---

## ステップ4: エンドツーエンドテスト

### テスト1: 買い注文（成功パターン）

#### 4-1. テストシグナル送信

```bash
cd /Users/h.tei/Workspace/source/python/kabuto
python test_send_signal.py buy 7203 100
```

**期待される出力**:
```
📤 Sending BUY signal: 7203 x 100
Signal: {
  "passphrase": "test_secret",
  "action": "buy",
  "ticker": "7203",
  ...
}

✅ Response [200]:
{
  "status": "success",
  "signal_id": "sig_20260110_120000_7203_buy",
  ...
}
```

#### 4-2. Relay Serverログ確認

```bash
tail -f relay_server/data/logs/test_kabuto_*.log
```

**期待されるログ**:
```
Signal received: sig_20260110_120000_7203_buy
5-level validation: PASS
Signal saved: PENDING
```

#### 4-3. Excel VBA実行

VBAエディタで以下を実行：

```vba
Sub TestPolling()
    ' API接続テスト
    If Not API_TestConnection() Then
        MsgBox "Relay Server接続失敗"
        Exit Sub
    End If

    MsgBox "Relay Server接続成功！ポーリングを開始します。"

    ' ポーリング開始
    Call StartPolling
End Sub
```

**または**、イミディエイトウィンドウ（Ctrl+G）で：
```vba
StartPolling
```

#### 4-4. VBAデバッグウィンドウ確認

**期待される出力**:
```
=== Kabuto Auto Trader (Simplified) Started ===
Excel VBA: Order Execution Only
All validation done by Relay Server

Received 1 validated signal(s) from Relay Server

=== Executing Validated Signal ===
Signal ID: sig_20260110_120000_7203_buy
Ticker: 7203
Action: buy
Quantity: 100

=== MOCK: RSS Order Execution ===
Ticker: 7203
Action: buy
Quantity: 100
MOCK: Order executed successfully

Order executed successfully: MOCK_ORD_20260110120005_7203
```

#### 4-5. OrderLogシート確認

| Timestamp | Signal ID | Ticker | Action | Order ID | Status | Reason |
|-----------|-----------|--------|--------|----------|--------|--------|
| 2026-01-10 12:00:05 | sig_20260110_120000_7203_buy | 7203 | buy | MOCK_ORD_20260110120005_7203 | SUCCESS | |

#### 4-6. Relay Serverで実行確認

```bash
python test_send_signal.py check
```

**期待される出力**:
```
📭 No pending signals
```

シグナルが消えていれば、Excel VBAが正常に取得・実行したことを確認できます。

---

### テスト2: 売り注文（ポジションなしエラー）

#### 4-7. 売りシグナル送信（ポジションなし）

```bash
python test_send_signal.py sell 7203 100
```

**期待される出力**:
```
✅ Response [400]:
{
  "detail": "Cannot sell 7203: No position held"
}
```

Relay Serverの5段階セーフティでブロックされます。

---

### テスト3: 5段階セーフティのテスト

#### 4-8. Kill Switchをテスト

```bash
# Kill Switch発動
curl -X POST http://localhost:5000/api/admin/kill-switch/activate \
  -H "Content-Type: application/json" \
  -d '{"reason": "Test", "password": "admin123"}'

# 買いシグナル送信
python test_send_signal.py buy 7203 100
```

**期待される動作**: シグナルは受信されるが、Excel VBAには配信されない（5段階セーフティでブロック）

```bash
# 確認
python test_send_signal.py check
# → No pending signals
```

Relay Serverログ:
```
Signal sig_XXX failed validation: kill_switch_active
Signal marked as REJECTED
```

#### 4-9. Kill Switch解除

```bash
curl -X POST http://localhost:5000/api/admin/kill-switch/deactivate \
  -H "Content-Type: application/json" \
  -d '{"password": "admin123"}'
```

---

### テスト4: 数量検証エラー

#### 4-10. 無効な数量（150株 - 100株単位でない）

TradingViewからのWebhookを想定したテスト：

```bash
curl -X POST http://localhost:5000/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "passphrase": "test_secret",
    "action": "buy",
    "ticker": "7203",
    "quantity": 150,
    "price": 1850.0,
    "entry_price": 1850.0,
    "stop_loss": 1800.0,
    "take_profit": 1950.0,
    "timestamp": "2026-01-10T12:00:00"
  }'
```

**期待される動作**: Relay Serverで受信されるが、Excel VBAには配信されない

```bash
python test_send_signal.py check
# → No pending signals
```

Relay Serverログ:
```
Signal sig_XXX failed validation: parameter_validation_failed: Quantity must be multiple of 100 (got 150)
Signal marked as REJECTED
```

---

## ステップ5: 完全なテストシナリオ

### 5-1. シナリオスクリプト作成

`test_full_scenario.sh` を作成：

```bash
#!/bin/bash
# Kabuto Auto Trader - 完全テストシナリオ

echo "🚀 Kabuto Auto Trader - Full Test Scenario"
echo "=========================================="

# 1. Kill Switch解除
echo "\n1️⃣ Deactivating Kill Switch..."
curl -s -X POST http://localhost:5000/api/admin/kill-switch/deactivate \
  -H "Content-Type: application/json" \
  -d '{"password": "admin123"}' | jq .

sleep 2

# 2. 買いシグナル送信（7203 トヨタ）
echo "\n2️⃣ Sending BUY signal: 7203 x 100..."
python test_send_signal.py buy 7203 100

sleep 3

# 3. 保留中のシグナル確認
echo "\n3️⃣ Checking pending signals..."
python test_send_signal.py check

sleep 10

# 4. 再度確認（Excel VBAが取得したか）
echo "\n4️⃣ Checking if Excel VBA fetched signal..."
python test_send_signal.py check

echo "\n✅ Test scenario completed!"
echo "Check Excel OrderLog sheet for results."
```

実行権限付与：
```bash
chmod +x test_full_scenario.sh
```

### 5-2. シナリオ実行

```bash
# Relay Server起動（別ターミナル）
cd relay_server
python app/main.py

# Excel VBAでポーリング開始（VBAエディタで実行）
StartPolling

# テストシナリオ実行
./test_full_scenario.sh
```

---

## ステップ6: トラブルシューティング

### Excel VBAがシグナルを取得しない

**確認1**: Relay Serverが起動しているか
```bash
curl http://localhost:5000/ping
```

**確認2**: API_KEYが一致しているか
- ExcelのConfigシート: `test_api_key_12345`
- `config.yaml` の `security.api_key`: `test_api_key_12345`

**確認3**: シグナルがPENDING状態か
```bash
python test_send_signal.py check
```

**確認4**: VBAのデバッグウィンドウでエラー確認
- VBAエディタ → イミディエイトウィンドウ（Ctrl+G）

### Relay Serverがシグナルを受け付けない

**確認1**: Passphraseが一致しているか
- テストスクリプト: `test_secret`
- `config.yaml` の `security.webhook_secret`: `test_secret`

**確認2**: Redisが起動しているか
```bash
redis-cli ping
```

**確認3**: ログ確認
```bash
tail -f relay_server/data/logs/test_kabuto_*.log
```

---

## ステップ7: クリーンアップ

### テストデータ削除

```bash
# テスト用DB削除
rm relay_server/data/test_kabuto.db

# Redis テストDB削除
redis-cli -n 1 FLUSHDB

# ログ削除
rm relay_server/data/logs/test_kabuto_*.log
```

---

## まとめ

### テスト完了チェックリスト

- [ ] Relay Serverが起動する
- [ ] `/ping` エンドポイントが応答する
- [ ] テストシグナルがRelay Serverに届く
- [ ] シグナルが5段階セーフティを通過する
- [ ] Excel VBAがシグナルを取得する
- [ ] モックRSS注文が実行される
- [ ] 実行結果がRelay Serverに報告される
- [ ] OrderLogシートに記録される
- [ ] Kill Switchでシグナルがブロックされる
- [ ] 無効な数量でシグナルが拒否される

### 次のステップ

テストが成功したら：

1. **実際のRSS統合**:
   - `ExecuteRSSOrder_Mock` を `ExecuteRSSOrder` に戻す
   - MarketSpeed IIを起動してテスト

2. **本番環境準備**:
   - `config.yaml` の `market_hours` を実際の取引時間に戻す
   - `cooldown` を適切な値に戻す（30分、15分など）
   - Slack/メール通知を有効化

3. **TradingView連携**:
   - TradingView AlertのWebhook URLを設定
   - Passphraseを本番用に変更

---

**作成日**: 2026-01-10
**バージョン**: 1.0.0
