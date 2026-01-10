# Kabuto Auto Trader - クイックスタートガイド

## 最速でテストを始める（10分）

このガイドでは、実際のMarketSpeed IIなしで新しい簡略化システムをテストします。

---

## ステップ1: Relay Server起動（3分）

### 1. 設定ファイル準備

```bash
cd relay_server
cp config.yaml.example config.yaml
```

### 2. テスト用に設定を簡略化

`config.yaml` を編集（最小限の変更）:

```yaml
server:
  host: "0.0.0.0"
  port: 5000
  debug: true

security:
  webhook_secret: "test_secret"
  api_key: "test_api_key_12345"
  admin_password: "admin123"

database:
  url: "sqlite:///./data/test_kabuto.db"

redis:
  host: "localhost"
  port: 6379
  db: 1

market_hours:
  safe_trading_windows:
    morning:
      start: "00:00"  # 24時間許可（テスト用）
      end: "23:59"
    afternoon:
      start: "00:00"
      end: "23:59"

cooldown:
  buy_same_ticker: 10  # テスト用に短縮
  buy_any_ticker: 5
  sell_same_ticker: 5
  sell_any_ticker: 0

alerts:
  enabled: false  # テスト中は通知無効
```

### 3. Redis起動

```bash
redis-server
```

### 4. Relay Server起動

```bash
cd relay_server
python app/main.py
```

**確認**: `http://localhost:5000/ping` にアクセスして `{"status":"pong"}` が返ればOK

---

## ステップ2: Excel準備（3分）

### 1. 新しいExcelファイル作成

`Kabuto_Test.xlsm` という名前でマクロ有効ブックを作成

### 2. シート作成

**Configシート**:

| A | B |
|---|---|
| API_BASE_URL | http://localhost:5000 |
| API_KEY | test_api_key_12345 |
| CLIENT_ID | excel_test_01 |

**OrderLogシート**:

ヘッダー行を作成:
```
Timestamp | Signal ID | Ticker | Action | Order ID | Status | Reason
```

### 3. VBAモジュールインポート

Alt+F11でVBAエディタを開き、以下をインポート:

1. `excel_vba_simplified/Module_API_Simple.bas`
2. `excel_vba_simplified/Module_Config_Simple.bas`
3. `excel_vba_simplified/Module_Main_Simple_MockRSS.bas`（モック版）

**重要**: `Module_Main_Simple_MockRSS.bas` を使用すると、実際のRSSなしでテストできます。

### 4. 必要なライブラリ参照追加

VBAエディタで:
- ツール → 参照設定
- 以下をチェック:
  - `Microsoft Scripting Runtime`（Dictionary用）

---

## ステップ3: テスト実行（4分）

### 1. Excel VBA起動

VBAエディタのイミディエイトウィンドウ（Ctrl+G）で:

```vba
StartPolling
```

**または** 標準モジュールに以下を追加して実行:

```vba
Sub TestStart()
    If Not API_TestConnection() Then
        MsgBox "Relay Server接続失敗"
        Exit Sub
    End If

    MsgBox "Relay Server接続成功！ポーリング開始します。"
    Call StartPolling
End Sub
```

**確認**: デバッグウィンドウに以下が表示される:

```
=== Kabuto Auto Trader (Simplified - MOCK MODE) Started ===
Excel VBA: Order Execution Only (MOCK RSS)
All validation done by Relay Server
⚠️ RSS orders are MOCKED - no real execution
```

### 2. テストシグナル送信

新しいターミナルで:

```bash
cd /Users/h.tei/Workspace/source/python/kabuto
python test_send_signal.py buy 7203 100
```

**期待される出力**:

```
📤 Sending BUY signal: 7203 x 100
...
✅ Response [200]:
{
  "status": "success",
  "signal_id": "sig_20260110_120000_7203_buy",
  ...
}
```

### 3. Excel VBAで処理確認

VBAデバッグウィンドウに以下が表示される（5秒以内）:

```
Received 1 validated signal(s) from Relay Server

=== Executing Validated Signal ===
Signal ID: sig_20260110_120000_7203_buy
Ticker: 7203
Action: buy
Quantity: 100

=== MOCK: RSS Order Execution ===
⚠️ This is a MOCK execution - no real order placed
Ticker: 7203
Action: buy
Quantity: 100
Side: 現物買(3)
Price Type: 成行(0)
Processing... (2 seconds)
✅ MOCK: Order executed successfully

✅ Order executed successfully: MOCK_ORD_20260110120005_7203
```

### 4. OrderLogシート確認

OrderLogシートに新しい行が追加される:

| Timestamp | Signal ID | Ticker | Action | Order ID | Status | Reason |
|-----------|-----------|--------|--------|----------|--------|--------|
| 2026-01-10 12:00:05 | sig_20260110_120000_7203_buy | 7203 | buy | MOCK_ORD_20260110120005_7203 | SUCCESS | |

行が緑色でハイライトされていれば成功！

---

## ステップ4: 追加テスト

### Kill Switchテスト

```bash
# Kill Switch発動
python test_send_signal.py kill-on

# シグナル送信（ブロックされるはず）
python test_send_signal.py buy 7201 100

# 確認
python test_send_signal.py check
# → 空（シグナルが配信されない）

# Kill Switch解除
python test_send_signal.py kill-off
```

### 無効な数量テスト

```bash
curl -X POST http://localhost:5000/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "passphrase": "test_secret",
    "action": "buy",
    "ticker": "6758",
    "quantity": 150,
    "price": 3000.0,
    "entry_price": 3000.0,
    "stop_loss": 2900.0,
    "take_profit": 3200.0,
    "timestamp": "2026-01-10T12:00:00"
  }'
```

**期待される動作**: シグナルは受信されるが、Excel VBAには配信されない（5段階セーフティでブロック）

### 完全シナリオテスト

```bash
chmod +x test_full_scenario.sh
./test_full_scenario.sh
```

---

## トラブルシューティング

### Excel VBAがシグナルを取得しない

**確認1**: Relay Serverが起動しているか
```bash
curl http://localhost:5000/ping
```

**確認2**: VBAデバッグウィンドウでエラーがないか
- VBAエディタ → イミディエイトウィンドウ（Ctrl+G）

**確認3**: API_KEYが一致しているか
- ExcelのConfigシート: `test_api_key_12345`
- config.yaml: `test_api_key_12345`

### Relay Serverが起動しない

**原因**: Redisが起動していない

**解決**:
```bash
redis-cli ping
# → PONG が返らない場合
redis-server
```

### VBAでエラーが出る

**エラー**: "コンパイルエラー: ユーザー定義型は定義されていません"

**原因**: Dictionary型が認識されない

**解決**:
1. VBAエディタ → ツール → 参照設定
2. `Microsoft Scripting Runtime` をチェック
3. OK

---

## 次のステップ

### 本番環境への移行

1. **Module_Main_Simple.bas（本番版）に切り替え**
   - `Module_Main_Simple_MockRSS.bas` をアンインポート
   - `Module_Main_Simple.bas` をインポート
   - `ExecuteRSSOrder()` を使用

2. **config.yaml を本番用に変更**
   - `market_hours` を実際の取引時間に戻す（9:30-11:20, 13:00-14:30）
   - `cooldown` を適切な値に戻す（30分、15分など）
   - `alerts.enabled: true` に変更してSlack/メール通知を有効化

3. **TradingView連携**
   - TradingView AlertのWebhook URLを `http://YOUR_SERVER:5000/webhook` に設定
   - Passphraseを本番用に変更（`config.yaml` の `webhook_secret` と一致させる）

---

## まとめ

### テストが成功したら確認できること

- ✅ Relay Serverがシグナルを受信
- ✅ 5段階セーフティシステムで検証
- ✅ 検証済みシグナルのみExcelに配信
- ✅ Excel VBAがモック注文を実行
- ✅ 実行結果をRelay Serverに報告
- ✅ OrderLogシートに記録
- ✅ Kill Switchでブロック
- ✅ 無効な数量で拒否

### 所要時間

- Relay Server準備: 3分
- Excel VBA準備: 3分
- テスト実行: 4分
- **合計: 約10分**

---

**詳細なテスト手順**: `TEST_GUIDE.md` を参照
**アーキテクチャ説明**: `ARCHITECTURE_MIGRATION.md` を参照
