# Excel VBA ログ出力ガイド

## 概要

全てのVBAログ出力にタイムスタンプが付くようになりました。

---

## ログモジュール

### Module_Logger_Simple.bas

タイムスタンプ付きログ出力用の関数を提供します。

**使用方法**:
```vba
' 通常のログ
Call LogDebug("デバッグメッセージ")

' レベル別ログ
Call LogInfo("情報メッセージ")
Call LogWarning("警告メッセージ")
Call LogError("エラーメッセージ")
Call LogSuccess("成功メッセージ")

' セクション区切り
Call LogSectionStart("セクション名")
' ... 処理 ...
Call LogSectionEnd()
```

---

## ログレベル

### LogDebug(message)
通常のデバッグ情報

**出力例**:
```
[2026-01-10 12:34:56] Signal ID: sig_20260110_120000_7203_buy
```

### LogInfo(message)
情報レベル（重要な情報）

**出力例**:
```
[2026-01-10 12:34:56] [INFO] Received 1 validated signal(s) from Relay Server
```

### LogWarning(message)
警告レベル

**出力例**:
```
[2026-01-10 12:34:56] [WARNING] RSS orders are MOCKED - no real execution
```

### LogError(message)
エラーレベル

**出力例**:
```
[2026-01-10 12:34:56] [ERROR] Order execution failed
```

### LogSuccess(message)
成功メッセージ

**出力例**:
```
[2026-01-10 12:34:56] [SUCCESS] Order executed successfully: MOCK_ORD_20260110120005_7203
```

### LogSectionStart(sectionName)
セクション開始（区切り線付き）

**出力例**:
```
[2026-01-10 12:34:56] ==================================================
[2026-01-10 12:34:56] Kabuto Auto Trader (Simplified - MOCK MODE) Started
[2026-01-10 12:34:56] ==================================================
```

### LogSectionEnd()
セクション終了（区切り線）

**出力例**:
```
[2026-01-10 12:34:56] --------------------------------------------------
```

---

## 実際のログ出力例

### テスト実行時のログ

```vba
StartPolling
```

**VBAデバッグウィンドウ（Ctrl+G）出力**:

```
[2026-01-10 12:34:56] ==================================================
[2026-01-10 12:34:56] Kabuto Auto Trader (Simplified - MOCK MODE) Started
[2026-01-10 12:34:56] ==================================================
[2026-01-10 12:34:56] [INFO] Excel VBA: Order Execution Only (MOCK RSS)
[2026-01-10 12:34:56] [INFO] All validation done by Relay Server
[2026-01-10 12:34:56] [WARNING] RSS orders are MOCKED - no real execution
[2026-01-10 12:35:01] [INFO] Received 1 validated signal(s) from Relay Server
[2026-01-10 12:35:01] ==================================================
[2026-01-10 12:35:01] Executing Validated Signal
[2026-01-10 12:35:01] ==================================================
[2026-01-10 12:35:01] Signal ID: sig_20260110_120000_7203_buy
[2026-01-10 12:35:01] Ticker: 7203
[2026-01-10 12:35:01] Action: buy
[2026-01-10 12:35:01] Quantity: 100
[2026-01-10 12:35:01] === MOCK: RSS Order Execution ===
[2026-01-10 12:35:01] [WARNING] This is a MOCK execution - no real order placed
[2026-01-10 12:35:01] Ticker: 7203
[2026-01-10 12:35:01] Action: buy
[2026-01-10 12:35:01] Quantity: 100
[2026-01-10 12:35:01] Side: 現物買(3)
[2026-01-10 12:35:01] Price Type: 成行(0)
[2026-01-10 12:35:01] Processing... (2 seconds)
[2026-01-10 12:35:03] [SUCCESS] MOCK: Order executed successfully
[2026-01-10 12:35:03] [SUCCESS] Order executed successfully: MOCK_ORD_20260110120503_7203
[2026-01-10 12:35:03] ACK sent for signal: sig_20260110_120000_7203_buy
[2026-01-10 12:35:03] Execution reported for signal: sig_20260110_120000_7203_buy
[2026-01-10 12:35:03] --------------------------------------------------
```

### エラー発生時のログ

```
[2026-01-10 12:36:10] ==================================================
[2026-01-10 12:36:10] Executing Validated Signal
[2026-01-10 12:36:10] ==================================================
[2026-01-10 12:36:10] Signal ID: sig_20260110_120000_6758_buy
[2026-01-10 12:36:10] Ticker: 6758
[2026-01-10 12:36:10] Action: buy
[2026-01-10 12:36:10] Quantity: 200
[2026-01-10 12:36:10] === MOCK: RSS Order Execution ===
[2026-01-10 12:36:10] [WARNING] This is a MOCK execution - no real order placed
[2026-01-10 12:36:10] Ticker: 6758
[2026-01-10 12:36:10] Action: buy
[2026-01-10 12:36:10] Quantity: 200
[2026-01-10 12:36:10] Processing... (2 seconds)
[2026-01-10 12:36:12] [ERROR] MOCK: Order execution failed (random failure for testing)
[2026-01-10 12:36:12] [ERROR] Order execution failed
[2026-01-10 12:36:12] Failure reported for signal: sig_20260110_120000_6758_buy
[2026-01-10 12:36:12] --------------------------------------------------
```

---

## ファイルログ出力（オプション）

### LogToFile関数

デバッグウィンドウだけでなく、ファイルにもログを保存できます。

**使用方法**:
```vba
' ファイルにログ出力
Call LogToFile("注文を実行しました", "INFO")
Call LogToFile("エラーが発生しました", "ERROR")
```

**ログファイル**:
- 場所: Excelファイルと同じフォルダ
- ファイル名: `kabuto_vba_20260110.log`
- フォーマット: `[2026-01-10 12:34:56] [INFO] メッセージ`

**ログファイル例**:
```
[2026-01-10 12:34:56] [INFO] Kabuto Auto Trader started
[2026-01-10 12:35:01] [INFO] Signal received: sig_20260110_120000_7203_buy
[2026-01-10 12:35:03] [SUCCESS] Order executed: MOCK_ORD_20260110120503_7203
[2026-01-10 12:36:12] [ERROR] Order execution failed: sig_20260110_120000_6758_buy
```

---

## 更新されたモジュール

### 1. Module_Main_Simple_MockRSS.bas
全てのログ出力にタイムスタンプが追加されました。

**変更前**:
```vba
Debug.Print "Order executed successfully: " & orderId
```

**変更後**:
```vba
Call LogSuccess("Order executed successfully: " & orderId)
```

### 2. Module_API_Simple.bas
API通信ログにタイムスタンプが追加されました。

**変更前**:
```vba
Debug.Print "API Connection OK"
```

**変更後**:
```vba
Call LogSuccess("API Connection OK")
```

---

## セットアップ

### 1. Module_Logger_Simple.basをインポート

VBAエディタ（Alt+F11）で:
1. ファイル → ファイルのインポート
2. `Module_Logger_Simple.bas` を選択
3. OK

### 2. 既存のモジュールを更新

以下のモジュールを最新版に更新:
- `Module_Main_Simple_MockRSS.bas`
- `Module_API_Simple.bas`

または、古いモジュールを削除して新しいバージョンをインポート。

---

## ログの確認方法

### VBAデバッグウィンドウ

1. VBAエディタを開く（Alt+F11）
2. Ctrl+G でイミディエイトウィンドウを開く
3. マクロ実行中にログがリアルタイムで表示される

### ファイルログ

1. Excelファイルと同じフォルダを開く
2. `kabuto_vba_YYYYMMDD.log` ファイルを確認
3. テキストエディタで開く

---

## カスタムログ関数の作成

独自のログ関数を追加できます。

**例: トレード専用ログ**:
```vba
Sub LogTrade(ticker As String, action As String, quantity As Long, orderId As String)
    Dim timestamp As String
    timestamp = Format(Now, "yyyy-mm-dd HH:nn:ss")

    Dim message As String
    message = "TRADE | " & ticker & " | " & action & " | " & quantity & " | " & orderId

    Debug.Print "[" & timestamp & "] " & message

    ' ファイルにも出力
    Call LogToFile(message, "TRADE")
End Sub
```

**使用**:
```vba
Call LogTrade("7203", "buy", 100, "ORD_001")
```

**出力**:
```
[2026-01-10 12:34:56] TRADE | 7203 | buy | 100 | ORD_001
```

---

## まとめ

### タイムスタンプ付きログの利点

- ✅ いつ発生したかが明確
- ✅ 問題のデバッグが容易
- ✅ パフォーマンス分析が可能
- ✅ 監査ログとして使用可能

### 標準フォーマット

```
[YYYY-MM-DD HH:mm:ss] [LEVEL] メッセージ
```

**例**:
```
[2026-01-10 12:34:56] [INFO] System started
[2026-01-10 12:35:03] [SUCCESS] Order executed
[2026-01-10 12:36:12] [ERROR] Connection failed
```

---

**作成日**: 2026-01-10
**バージョン**: 1.0.0
