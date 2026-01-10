# Excel単体テストガイド（サーバー不要）

## 概要

**完全にExcel単体で**、サーバー・Redis・データベースなしでKabuto VBAのロジックをテストできます。

---

## 必要なもの

- ✅ Excel（VBAが動作する環境）

**不要なもの**:
- ❌ Relay Server
- ❌ モックAPIサーバー
- ❌ Redis
- ❌ PostgreSQL / SQLite
- ❌ Python
- ❌ インターネット接続

---

## セットアップ（3分）

### ステップ1: 新しいExcelファイル作成

`Kabuto_Standalone_Test.xlsm` という名前でマクロ有効ブックを作成

### ステップ2: シート作成

#### OrderLogシート

ヘッダー行を作成:
```
Timestamp | Signal ID | Ticker | Action | Order ID | Status | Reason
```

### ステップ3: VBAモジュールインポート

Alt+F11でVBAエディタを開き、以下をインポート:

**Module_Standalone_Test.bas**
- 場所: `excel_vba_simplified/Module_Standalone_Test.bas`
- 全てのテスト機能が含まれています

### ステップ4: 参照設定

VBAエディタで:
- ツール → 参照設定
- `Microsoft Scripting Runtime` をチェック（Dictionary用）
- OK

---

## テスト実行（1分）

### 完全テストスイート実行

VBAエディタで以下を実行:

```vba
RunStandaloneTest
```

**または**:
1. Excelシートに戻る
2. Alt+F8でマクロダイアログを開く
3. `RunStandaloneTest` を選択
4. 実行

### 実行結果

**VBAデバッグウィンドウ（Ctrl+G）**:
```
==================================
🧪 Kabuto - Standalone Unit Test
==================================

📋 Initializing test environment...
✅ Environment initialized

Test 1: Create Mock Signal
----------------------------
Signal ID: sig_test_20260110120000_7203
Ticker: 7203
Action: buy
Quantity: 100
✅ Test 1 passed

Test 2: Process Signal
-----------------------
  Processing: 6758 buy 200
  ✅ Order executed: STANDALONE_ORD_20260110120001_6758
✅ Test 2 passed

Test 3: Execute Mock Order
---------------------------
Order ID: STANDALONE_ORD_20260110120002_9984
✅ Test 3 passed

Test 4: Log Order
------------------
✅ Test 4 passed (check OrderLog sheet)

Test 5: Multiple Signals
-------------------------
Created 5 mock signals
  Processing: 7203 buy 100
  ✅ Order executed: STANDALONE_ORD_20260110120003_7203
  Processing: 6758 buy 200
  ✅ Order executed: STANDALONE_ORD_20260110120004_6758
  ...
✅ Test 5 passed

Test 6: Error Handling
-----------------------
✅ Test 6 passed (check OrderLog sheet for failure)

==================================
✅ All tests completed!
==================================

Check OrderLog sheet for results.
```

**OrderLogシート**:

| Timestamp | Signal ID | Ticker | Action | Order ID | Status | Reason |
|-----------|-----------|--------|--------|----------|--------|--------|
| 2026-01-10 12:00:01 | sig_test_... | 7201 | buy | ORD_TEST_001 | SUCCESS | Standalone Test |
| 2026-01-10 12:00:02 | sig_test_... | 6758 | buy | STANDALONE_ORD_... | SUCCESS | Standalone Test |
| 2026-01-10 12:00:03 | sig_test_... | 9984 | buy | STANDALONE_ORD_... | SUCCESS | Standalone Test |
| ... | ... | ... | ... | ... | ... | ... |
| 2026-01-10 12:00:10 | sig_test_... | 4063 | buy | | FAILED | Test: Simulated failure |

成功行は**緑色**、失敗行は**赤色**でハイライトされます。

---

## 個別テスト実行

### クイックテスト: 1つのシグナル

```vba
QuickTest_SingleSignal
```

**出力**:
```
🧪 Quick Test: Single Signal
  Processing: 7203 buy 100
  ✅ Order executed: STANDALONE_ORD_20260110120000_7203
✅ Quick test completed
```

### クイックテスト: 買い→売り

```vba
QuickTest_BuySell
```

**出力**:
```
🧪 Quick Test: Buy -> Sell
  Processing: 7203 buy 100
  ✅ Order executed: STANDALONE_ORD_20260110120000_7203
  Processing: 7203 sell 100
  ✅ Order executed: STANDALONE_ORD_20260110120002_7203
✅ Quick test completed
```

### クイックテスト: 複数注文

```vba
QuickTest_MultipleOrders
```

**出力**:
```
🧪 Quick Test: Multiple Orders
  Processing: 7203 buy 100
  ✅ Order executed: STANDALONE_ORD_...
  Processing: 6758 buy 100
  ✅ Order executed: STANDALONE_ORD_...
  Processing: 9984 buy 100
  ✅ Order executed: STANDALONE_ORD_...
✅ Quick test completed
```

### パフォーマンステスト: 50シグナル

```vba
PerformanceTest
```

**出力**:
```
🚀 Performance Test: 50 signals
  Processing: TEST0001 buy 100
  ✅ Order executed: STANDALONE_ORD_...
  ...
✅ Processed 50 signals in 25.32 seconds
Average: 0.506 seconds per signal
```

---

## テストされる機能

### ✅ 含まれているテスト

1. **モックシグナル作成** (`CreateMockSignal`)
   - シグナルIDの生成
   - ティッカー、数量、価格の設定

2. **シグナル処理** (`ProcessSignalStandalone`)
   - シグナルの受信
   - 注文実行
   - ログ記録

3. **モック注文実行** (`ExecuteRSSOrder_StandaloneMock`)
   - 注文IDの生成
   - 成功/失敗のシミュレーション（90%成功率）

4. **ログ記録** (`LogOrderSuccess_Standalone`, `LogOrderFailure_Standalone`)
   - OrderLogシートへの記録
   - 色分け（緑=成功、赤=失敗）

5. **エラーハンドリング**
   - 失敗シグナルの処理
   - エラーメッセージの記録

6. **複数シグナル処理**
   - 5つのシグナルを連続処理
   - ループ処理のテスト

### ❌ 含まれていないテスト（サーバー側の機能）

- 5段階セーフティ検証
- API通信
- Kill Switch管理
- クールダウン管理
- リスク制限チェック
- 通知送信

---

## カスタムテスト作成

### 独自のシグナルでテスト

VBAエディタに以下を追加:

```vba
Sub MyCustomTest()
    Debug.Print "🧪 My Custom Test"

    ' 独自のモックシグナル作成
    Dim signal As Dictionary
    Set signal = CreateMockSignal("1234", "buy", 500)

    ' 価格をカスタマイズ
    signal("price") = 2500.0
    signal("entry_price") = 2500.0
    signal("stop_loss") = 2400.0
    signal("take_profit") = 2700.0

    ' 処理
    Call ProcessSignalStandalone(signal)

    Debug.Print "✅ Custom test completed"
End Sub
```

実行:
```vba
MyCustomTest
```

### 特定の銘柄をテスト

```vba
Sub TestSpecificTicker()
    Debug.Print "🧪 Test Specific Ticker"

    Dim tickers As Variant
    tickers = Array("7203", "6758", "9984", "8306", "9432")

    Dim i As Integer
    For i = 0 To UBound(tickers)
        Dim signal As Dictionary
        Set signal = CreateMockSignal(CStr(tickers(i)), "buy", 100)

        Debug.Print "Testing: " & tickers(i)
        Call ProcessSignalStandalone(signal)
    Next i

    Debug.Print "✅ Test completed"
End Sub
```

---

## トラブルシューティング

### エラー: "コンパイルエラー: ユーザー定義型は定義されていません"

**原因**: Dictionary型が認識されない

**解決**:
1. VBAエディタ → ツール → 参照設定
2. `Microsoft Scripting Runtime` をチェック
3. OK

### エラー: "実行時エラー '9': インデックスが有効範囲にありません"

**原因**: OrderLogシートが存在しない

**解決**:
1. 新しいシートを作成
2. シート名を `OrderLog` に変更
3. ヘッダー行を追加（上記参照）

### OrderLogシートに何も記録されない

**確認**:
1. VBAデバッグウィンドウ（Ctrl+G）でエラーがないか確認
2. OrderLogシートが正しく存在するか確認
3. マクロのセキュリティ設定を確認（マクロが有効になっているか）

---

## テスト完了チェックリスト

- [ ] `RunStandaloneTest` が正常に完了する
- [ ] VBAデバッグウィンドウに結果が表示される
- [ ] OrderLogシートに記録が追加される
- [ ] 成功行が緑色でハイライトされる
- [ ] 失敗行が赤色でハイライトされる
- [ ] クイックテストが動作する
- [ ] パフォーマンステストが動作する

---

## 次のステップ

### Excel単体テストが完了したら

1. **モックAPIサーバーでテスト**
   - `EXCEL_VBA_UNIT_TEST.md` を参照
   - API通信をテスト

2. **完全なRelay Serverでテスト**
   - `TEST_GUIDE.md` を参照
   - 5段階セーフティをテスト

3. **本番環境へデプロイ**
   - MarketSpeed IIと統合
   - TradingViewと連携

---

## まとめ

### スタンドアローンテストの利点

| 項目 | スタンドアローンテスト | モックサーバー | 完全版 |
|-----|----------------------|--------------|--------|
| 必要なもの | Excel | Excel + Python | Excel + Python + Redis + DB |
| 起動時間 | 即座 | 1分 | 数分 |
| インターネット | 不要 | 不要 | 推奨 |
| テスト範囲 | VBAロジック | API通信 + VBAロジック | 全機能 |
| 用途 | VBA開発中 | 統合テスト準備 | 本番前テスト |

### 所要時間

- セットアップ: 3分
- テスト実行: 1分
- **合計: 約4分**

---

**Excel単体で完結する最も簡単なテスト方法です！**

**作成日**: 2026-01-10
**バージョン**: 1.0.0
