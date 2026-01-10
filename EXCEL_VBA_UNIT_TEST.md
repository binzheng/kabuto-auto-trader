# Excel VBA 単体テストガイド

## 概要

このガイドでは、**Relay Server、Redis、PostgreSQLなし**で、Excel VBA（Kabuto_Test.xlsm）のみを単体テストする方法を説明します。

軽量なモックAPIサーバーを使用して、Excel VBAのロジックだけをテストできます。

---

## 必要なもの

- Excel（VBAが動作する環境）
- Python 3.9+
- Flask（`pip install flask`）

**不要なもの**:
- ❌ Relay Server（完全版）
- ❌ Redis
- ❌ PostgreSQL / SQLite
- ❌ 設定ファイル（config.yaml）

---

## ステップ1: モックAPIサーバー起動（1分）

### 1-1. Flask インストール

```bash
pip install flask
```

### 1-2. モックサーバー起動

```bash
cd /Users/h.tei/Workspace/source/python/kabuto
python mock_relay_server.py
```

**確認**:
```
============================================================
🧪 Kabuto Mock Relay Server
============================================================
Purpose: Excel VBA Unit Testing
Mode: MOCK (no validation, no database, no Redis)

Configuration:
  Webhook Secret: test_secret
  API Key: test_api_key_12345

Starting server on http://localhost:5000
============================================================

 * Running on http://0.0.0.0:5000
```

### 1-3. 動作確認

別ターミナルで:
```bash
curl http://localhost:5000/ping
```

**期待される出力**:
```json
{
  "status": "pong",
  "timestamp": "2026-01-10T12:00:00"
}
```

---

## ステップ2: Excel VBA準備（3分）

### 2-1. 新しいExcelファイル作成

`Kabuto_Test.xlsm` という名前でマクロ有効ブックを作成

### 2-2. シート作成

#### Configシート

| A列（キー） | B列（値） |
|------------|----------|
| API_BASE_URL | http://localhost:5000 |
| API_KEY | test_api_key_12345 |
| CLIENT_ID | excel_unit_test_01 |

#### OrderLogシート

ヘッダー行:
```
Timestamp | Signal ID | Ticker | Action | Order ID | Status | Reason
```

### 2-3. VBAモジュールインポート

Alt+F11でVBAエディタを開き、以下をインポート:

1. **Module_API_Simple.bas**
   - 場所: `excel_vba_simplified/Module_API_Simple.bas`

2. **Module_Config_Simple.bas**
   - 場所: `excel_vba_simplified/Module_Config_Simple.bas`

3. **Module_Main_Simple_MockRSS.bas**（モック版）
   - 場所: `excel_vba_simplified/Module_Main_Simple_MockRSS.bas`

### 2-4. 参照設定

VBAエディタで:
- ツール → 参照設定
- `Microsoft Scripting Runtime` をチェック（Dictionary用）

---

## ステップ3: 単体テスト実行

### テスト1: API接続テスト

VBAエディタのイミディエイトウィンドウ（Ctrl+G）で:

```vba
? API_TestConnection()
```

**期待される出力**:
```
API Connection OK
True
```

### テスト2: シグナル取得テスト（空）

```vba
Dim signals As Collection
Set signals = API_GetPendingSignals()

If signals Is Nothing Then
    Debug.Print "No signals (expected)"
Else
    Debug.Print "Found " & signals.Count & " signals"
End If
```

**期待される出力**:
```
No signals (expected)
```

### テスト3: 1回だけポーリングテスト

VBAに以下のテストサブルーチンを追加:

```vba
Sub TestSingleFetch()
    Debug.Print "=== Test: Single Fetch ==="

    ' API接続テスト
    If Not API_TestConnection() Then
        MsgBox "Mock Server接続失敗"
        Exit Sub
    End If

    ' 1回だけポーリング
    Call PollAndExecuteSignals

    Debug.Print "=== Test completed ==="
End Sub
```

実行:
```vba
TestSingleFetch
```

**期待される出力**:
```
=== Test: Single Fetch ===
API Connection OK
📭 (シグナルなし)
=== Test completed ===
```

### テスト4: シグナル送信 → 取得 → 実行

#### 4-1. テストシグナル送信

別ターミナルで:
```bash
python test_send_signal.py buy 7203 100
```

#### 4-2. VBAでポーリング実行

```vba
TestSingleFetch
```

**期待される出力**:
```
=== Test: Single Fetch ===
API Connection OK
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
Processing... (2 seconds)
✅ MOCK: Order executed successfully

✅ Order executed successfully: MOCK_ORD_20260110120005_7203
=== Test completed ===
```

#### 4-3. OrderLogシート確認

| Timestamp | Signal ID | Ticker | Action | Order ID | Status | Reason |
|-----------|-----------|--------|--------|----------|--------|--------|
| 2026-01-10 12:00:05 | sig_20260110_120000_7203_buy | 7203 | buy | MOCK_ORD_20260110120005_7203 | SUCCESS | |

行が緑色でハイライトされていれば成功！

### テスト5: 連続ポーリングテスト

```vba
StartPolling
```

VBAが5秒ごとにポーリングを開始します。

別ターミナルで複数シグナルを送信:
```bash
python test_send_signal.py buy 7203 100
sleep 10
python test_send_signal.py buy 6758 200
sleep 10
python test_send_signal.py buy 9984 100
```

VBAデバッグウィンドウで、各シグナルが順次処理されることを確認。

停止:
```vba
StopPolling
```

---

## ステップ4: 個別機能のテスト

### テスト6: ACK送信テスト

```vba
Sub TestACK()
    ' テストシグナルID
    Dim testSignalId As String
    testSignalId = "sig_20260110_120000_7203_buy"

    Dim testChecksum As String
    testChecksum = "a1b2c3d4e5f6g7h8"

    Call API_AcknowledgeSignal(testSignalId, testChecksum)

    Debug.Print "ACK sent"
End Sub
```

### テスト7: 実行報告テスト

```vba
Sub TestExecutionReport()
    Dim testSignalId As String
    testSignalId = "sig_20260110_120000_7203_buy"

    Dim testOrderId As String
    testOrderId = "TEST_ORD_001"

    Dim testPrice As Double
    testPrice = 1850.0

    Dim testQuantity As Long
    testQuantity = 100

    Call API_ReportExecution(testSignalId, testOrderId, testPrice, testQuantity)

    Debug.Print "Execution reported"
End Sub
```

### テスト8: 失敗報告テスト

```vba
Sub TestFailureReport()
    Dim testSignalId As String
    testSignalId = "sig_20260110_120000_7203_buy"

    Dim testError As String
    testError = "Test error message"

    Call API_ReportFailure(testSignalId, testError)

    Debug.Print "Failure reported"
End Sub
```

---

## ステップ5: エラーハンドリングのテスト

### テスト9: 無効なAPI Key

Configシートの `API_KEY` を一時的に変更:
```
API_KEY | invalid_key_123
```

```vba
? API_TestConnection()
```

**期待される出力**:
```
API Connection Failed: HTTP 401
False
```

元に戻す:
```
API_KEY | test_api_key_12345
```

### テスト10: サーバー停止時の動作

モックサーバーを停止（Ctrl+C）してから:

```vba
? API_TestConnection()
```

**期待される出力**:
```
Error in API_TestConnection: (connection error)
False
```

モックサーバーを再起動して元に戻す。

---

## ステップ6: モックサーバーのステータス確認

### ターミナルで確認

```bash
# システムステータス
curl http://localhost:5000/status

# シグナル一覧
python test_send_signal.py check
```

**ステータス出力例**:
```json
{
  "status": "active",
  "trading_enabled": true,
  "market_open": true,
  "signals": {
    "total": 5,
    "pending": 0,
    "fetched": 2,
    "executed": 2,
    "failed": 1
  },
  "mock_mode": true,
  "message": "This is a MOCK server for Excel VBA unit testing"
}
```

---

## モックサーバーの特徴

### ✅ 含まれている機能

- Webhook受信（`POST /webhook`）
- シグナル取得（`GET /api/signals/pending`）
- ACK受信（`POST /api/signals/{id}/ack`）
- 実行報告（`POST /api/signals/{id}/executed`）
- 失敗報告（`POST /api/signals/{id}/failed`）
- ステータス確認（`GET /status`）

### ❌ 含まれていない機能（本番Relay Serverのみ）

- 5段階セーフティ検証（全て許可）
- Kill Switch管理（機能しない）
- クールダウン管理（機能しない）
- リスク制限チェック（機能しない）
- データベース永続化（メモリのみ）
- Redis連携（不要）
- 通知送信（機能しない）

### 用途

✅ **適している**:
- Excel VBAのロジックテスト
- API通信のテスト
- ポーリングループのテスト
- エラーハンドリングのテスト
- UI/UXのテスト（OrderLogシートへの記録など）

❌ **適していない**:
- 5段階セーフティのテスト
- リスク制限のテスト
- Kill Switchのテスト
- 本番環境での使用

---

## テスト完了チェックリスト

Excel VBA単体テストが成功したら、以下を確認:

- [ ] モックサーバーが起動する
- [ ] Excel VBAがAPI接続できる
- [ ] シグナルを取得できる
- [ ] ACKを送信できる
- [ ] モック注文を実行できる
- [ ] 実行報告を送信できる
- [ ] OrderLogシートに記録される
- [ ] エラーハンドリングが動作する
- [ ] ポーリングループが正常に動作する

---

## トラブルシューティング

### モックサーバーに接続できない

**原因**: Flask がインストールされていない

**解決**:
```bash
pip install flask
```

### VBAでエラーが出る

**エラー**: "コンパイルエラー: ユーザー定義型は定義されていません"

**原因**: Dictionary型が認識されない

**解決**:
1. VBAエディタ → ツール → 参照設定
2. `Microsoft Scripting Runtime` をチェック
3. OK

### シグナルが取得できない

**確認1**: モックサーバーが起動しているか
```bash
curl http://localhost:5000/ping
```

**確認2**: シグナルが送信されているか
```bash
python test_send_signal.py check
```

**確認3**: API_KEYが一致しているか
- Configシート: `test_api_key_12345`
- モックサーバー: `test_api_key_12345`（固定）

---

## 次のステップ

### Excel VBA単体テストが完了したら

1. **完全なRelay Serverでテスト**
   - `TEST_GUIDE.md` を参照
   - Redis + PostgreSQL環境でテスト
   - 5段階セーフティシステムをテスト

2. **本番環境へデプロイ**
   - MarketSpeed IIと統合
   - TradingViewと連携
   - Slack/メール通知を有効化

---

## まとめ

### モックサーバーの利点

| 項目 | モックサーバー | 完全版Relay Server |
|-----|--------------|-------------------|
| 起動時間 | 即座（<1秒） | 数秒 |
| 依存関係 | Python + Flask | Python + Redis + DB |
| 設定ファイル | 不要 | 必要（config.yaml） |
| 5段階セーフティ | なし（全て許可） | あり |
| 用途 | Excel VBA単体テスト | 統合テスト・本番 |

### 所要時間

- モックサーバー起動: 1分
- Excel VBA準備: 3分
- テスト実行: 5分
- **合計: 約10分**

---

**作成日**: 2026-01-10
**バージョン**: 1.0.0
