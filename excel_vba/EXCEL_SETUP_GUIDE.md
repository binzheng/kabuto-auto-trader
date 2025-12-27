# Kabuto Auto Trader - Excelブック セットアップガイド

完全無人稼働Excel自動売買システムのセットアップ手順

---

## 目次

1. [前提条件](#前提条件)
2. [Excelブック作成](#excelブック作成)
3. [シート作成](#シート作成)
4. [VBAモジュールインポート](#vbaモジュールインポート)
5. [JsonConverterライブラリ導入](#jsonconverterライブラリ導入)
6. [システム設定](#システム設定)
7. [テスト](#テスト)
8. [自動起動設定](#自動起動設定)

---

## 前提条件

- Windows 10/11
- Microsoft Excel 2016以上（マクロ有効）
- MarketSpeed II（楽天証券）インストール済み
- Relay Server稼働中

---

## Excelブック作成

### 1. 新規ブック作成

1. Excelを起動
2. 新規ブックを作成
3. **名前を付けて保存** → `C:\Kabuto\kabuto_auto_trader.xlsm`
4. ファイルの種類: **Excel マクロ有効ブック (.xlsm)**

### 2. マクロ設定

1. **ファイル** → **オプション** → **トラストセンター**
2. **トラストセンターの設定**
3. **マクロの設定** → **すべてのマクロを有効にする**（開発用）
   - 本番: **VBAプロジェクト オブジェクト モデルへのアクセスを信頼する**のみチェック

### 3. 開発タブ表示

1. **ファイル** → **オプション** → **リボンのユーザー設定**
2. **開発** にチェック → **OK**

---

## シート作成

### 1. シート追加（11シート）

デフォルトの`Sheet1`を含め、合計11シート作成:

| # | シート名 | タブ色 | 可視性 |
|---|----------|--------|--------|
| 1 | Dashboard | 青 | Visible |
| 2 | SignalQueue | 緑 | Visible |
| 3 | OrderHistory | オレンジ | Visible |
| 4 | ExecutionLog | 黄 | Visible |
| 5 | ErrorLog | 赤 | Visible |
| 6 | PositionManager | 紫 | Visible |
| 7 | Config | グレー | Hidden |
| 8 | MarketCalendar | グレー | Hidden |
| 9 | BlacklistTickers | グレー | Hidden |
| 10 | SystemState | - | VeryHidden |
| 11 | RSSInterface | - | VeryHidden |

**シート可視性設定** (VeryHidden):
```vba
' VBE（Alt+F11）のイミディエイトウィンドウで実行
ThisWorkbook.Sheets("SystemState").Visible = xlSheetVeryHidden
ThisWorkbook.Sheets("RSSInterface").Visible = xlSheetVeryHidden
```

---

### 2. Dashboard シート設計

**A1:G30範囲**に以下のレイアウトを作成:

```
A1: Kabuto Auto Trader - Dashboard
A2:
A3: システム状態
B3: =SystemState!$B$1   (system_status)
A4: 最終更新
B4: =SystemState!$B$2   (last_update)
...（詳細は doc/13_excel_workbook_design.md 参照）
```

**制御ボタン配置**:
1. **開発** → **挿入** → **ボタン（フォームコントロール）**
2. ボタン作成 → マクロ割り当て:
   - `[▶ 開始]` → `StartAutoTrading`
   - `[⏸ 一時停止]` → `PauseAutoTrading`
   - `[⏹ 停止]` → `StopAutoTrading`

---

### 3. SignalQueue シート設計

**ヘッダー行（A1:M1）**:
```
A1: signal_id
B1: received_at
C1: action
D1: ticker
E1: quantity
F1: entry_price
G1: stop_loss
H1: take_profit
I1: atr
J1: checksum
K1: state
L1: processed_at
M1: error_message
```

**データ形式設定**:
- B列: 日付時刻 (`yyyy-mm-dd hh:mm:ss`)
- E列: 数値（整数）
- F-I列: 数値（小数点2桁）

---

### 4. OrderHistory シート設計

**ヘッダー行（A1:O1）**:
```
A1: order_internal_id
B1: timestamp
C1: signal_id
D1: action
E1: ticker
F1: quantity
G1: order_type
H1: limit_price
I1: rss_order_id
J1: status
K1: filled_price
L1: filled_quantity
M1: commission
N1: execution_time
O1: error_message
```

---

### 5. ExecutionLog シート設計

**ヘッダー行（A1:L1）**:
```
A1: execution_id
B1: execution_time
C1: order_internal_id
D1: action
E1: ticker
F1: quantity
G1: price
H1: commission
I1: total_amount
J1: position_effect
K1: realized_pnl
L1: notes
```

---

### 6. ErrorLog シート設計

**ヘッダー行（A1:K1）**:
```
A1: error_id
B1: timestamp
C1: error_type
D1: module
E1: ticker
F1: error_code
G1: error_message
H1: stack_trace
I1: severity
J1: resolved
K1: notes
```

---

### 7. PositionManager シート設計

**ヘッダー行（A1:L1）**:
```
A1: ticker
B1: ticker_name
C1: quantity
D1: avg_cost
E1: current_price
F1: unrealized_pnl
G1: unrealized_pnl_pct
H1: stop_loss
I1: take_profit
J1: position_value
K1: entry_date
L1: holding_days
```

**計算式**:
- F2: `=(E2-D2)*C2` (含み損益)
- G2: `=F2/(D2*C2)` (含み損益率)
- J2: `=E2*C2` (ポジション評価額)
- L2: `=TODAY()-K2` (保有日数)

---

### 8. Config シート設計

**A列: 設定キー、B列: 設定値**:

```
A1: API_BASE_URL          | B1: http://localhost:5000/api
A2: API_KEY               | B2: your-api-key-here
A3: CLIENT_ID             | B3: excel_vm_01
A4: POLLING_INTERVAL_SEC  | B4: 5
A5: MAX_POSITION_VALUE    | B5: 1000000
A6: MAX_DAILY_ENTRIES     | B6: 5
A7: MAX_POSITIONS         | B7: 5
A8: ENABLE_AUTO_START     | B8: TRUE
A9: ENABLE_MARKET_HOURS_CHECK | B9: TRUE
A10: LOG_RETENTION_DAYS   | B10: 90
A11: RSS_CONNECTION_TIMEOUT_SEC | B11: 30
A12: ALERT_EMAIL          | B12:
A13: ENABLE_CRITICAL_ALERT | B13: TRUE
```

**シートを非表示**:
1. Config シートを右クリック → **非表示**

---

### 9. MarketCalendar シート設計

**ヘッダー行（A1:I1）**:
```
A1: date
B1: day_of_week
C1: is_trading_day
D1: session_type
E1: morning_open
F1: morning_close
G1: afternoon_open
H1: afternoon_close
I1: notes
```

**初期データ例**:
```
A2: 2025-12-26 | B2: 金 | C2: TRUE | D2: full | E2: 09:00 | F2: 11:30 | G2: 12:30 | H2: 15:00
A3: 2025-12-27 | B3: 土 | C3: FALSE | D3: closed
A4: 2025-12-28 | B4: 日 | C4: FALSE | D4: closed
```

**2025年分のデータを手動入力** または スクリプトで生成

---

### 10. BlacklistTickers シート設計

**ヘッダー行（A1:F1）**:
```
A1: ticker
B1: ticker_name
C1: reason
D1: added_date
E1: expiry_date
F1: added_by
```

**初期状態**: データなし（空シート）

---

### 11. SystemState シート設計

**A列: ラベル、B列: 値**:

```
A1: system_status      | B1: Stopped
A2: last_update        | B2:
A3: next_poll_time     | B3:
A4: api_connection_status | B4: OK
A5: rss_connection_status | B5: OK
A6: market_session     | B6:
A7: daily_entry_count  | B7: 0
A8: daily_trade_count  | B8: 0
A9: daily_error_count  | B9: 0
A10: total_position_value | B10: 0
A11: last_signal_time  | B11:
A12: workbook_start_time | B12:
```

---

### 12. RSSInterface シート設計

**入力セル（A列）**:
```
A1: function_name
A2: param_ticker
A3: param_side
A4: param_quantity
A5: param_price_type
A6: param_price
```

**出力セル（B列）**:
```
B1: =RSS.ORDER(A2,A3,A4,A5,A6)  (実際は数式で設定)
B2: result_status
B3: result_message
```

---

## VBAモジュールインポート

### 1. VBE起動

1. **Alt + F11** または **開発** → **Visual Basic**

### 2. モジュールインポート

**標準モジュール（8個）**:

1. **ファイル** → **ファイルのインポート**
2. 以下のファイルを順次インポート:
   - `Module_Main.bas`
   - `Module_API.bas`
   - `Module_RSS.bas`
   - `Module_SignalProcessor.bas`
   - `Module_Config.bas`
   - `Module_OrderManager.bas`
   - `Module_Logger.bas`

### 3. ThisWorkbook置き換え

1. 左ペインの `ThisWorkbook` をダブルクリック
2. 既存コードを全て削除
3. `ThisWorkbook.cls` の内容をコピー＆ペースト

### 4. 参照設定

1. **ツール** → **参照設定**
2. 以下にチェック:
   - ✅ Visual Basic For Applications
   - ✅ Microsoft Excel XX.0 Object Library
   - ✅ Microsoft Scripting Runtime

---

## JsonConverterライブラリ導入

### 1. ダウンロード

```
https://github.com/VBA-tools/VBA-JSON
```

1. **Code** → **Download ZIP**
2. 解凍して `JsonConverter.bas` を取得

### 2. インポート

1. VBE → **ファイル** → **ファイルのインポート**
2. `JsonConverter.bas` を選択

### 3. 参照設定追加

1. **ツール** → **参照設定**
2. ✅ **Microsoft Scripting Runtime** にチェック

### 4. 動作確認

**イミディエイトウィンドウ**（Ctrl+G）で実行:
```vba
Dim json As String
json = "{""test"":""value""}"
Dim obj As Object
Set obj = JsonConverter.ParseJson(json)
Debug.Print obj("test")  ' "value" と表示されればOK
```

---

## システム設定

### 1. Config シート編集

**B列の値を環境に合わせて変更**:

```
B1: http://192.168.1.10:5000/api  ← Relay ServerのIPアドレス
B2: your-actual-api-key-here      ← Relay ServerのAPI_KEY（config.yamlと一致）
B3: excel_vm_01                   ← クライアントID（任意）
```

### 2. MarketCalendar データ投入

**2025年の取引日カレンダーを入力** (245営業日分)

または以下のVBAスクリプトで生成:

```vba
Sub GenerateMarketCalendar()
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("MarketCalendar")

    Dim startDate As Date
    startDate = DateSerial(2025, 1, 1)

    Dim i As Long
    Dim currentRow As Long
    currentRow = 2

    For i = 0 To 364  ' 1年分
        Dim targetDate As Date
        targetDate = DateAdd("d", i, startDate)

        Dim dayOfWeek As Integer
        dayOfWeek = Weekday(targetDate)

        ws.Cells(currentRow, 1).Value = targetDate
        ws.Cells(currentRow, 2).Value = Format(targetDate, "aaa")
        ws.Cells(currentRow, 3).Value = (dayOfWeek <> vbSaturday And dayOfWeek <> vbSunday)
        ws.Cells(currentRow, 4).Value = IIf(dayOfWeek = vbSaturday Or dayOfWeek = vbSunday, "closed", "full")

        If dayOfWeek <> vbSaturday And dayOfWeek <> vbSunday Then
            ws.Cells(currentRow, 5).Value = "09:00"
            ws.Cells(currentRow, 6).Value = "11:30"
            ws.Cells(currentRow, 7).Value = "12:30"
            ws.Cells(currentRow, 8).Value = "15:00"
        End If

        currentRow = currentRow + 1
    Next i

    MsgBox "Market calendar generated", vbInformation
End Sub
```

---

## テスト

### 1. Relay Server起動確認

```bash
# Relay Server側
curl http://localhost:5000/health
```

**期待値**: `{"status":"healthy",...}`

### 2. API接続テスト

**Excelイミディエイトウィンドウ**で実行:

```vba
Debug.Print CheckAPIConnection()  ' True と表示されればOK
```

### 3. シグナル取得テスト

```vba
Dim signals As Collection
Set signals = FetchPendingSignals()
Debug.Print signals.Count  ' シグナル数が表示される
```

### 4. RSS接続テスト

```vba
Debug.Print CheckRSSConnection()  ' True と表示されればOK
```

### 5. 手動起動テスト

1. Dashboardシートで **[▶ 開始]** ボタンをクリック
2. イミディエイトウィンドウに以下が表示されればOK:
   ```
   =========================================
   Kabuto Auto Trading Started
   =========================================
   ```
3. **[⏹ 停止]** ボタンでstop停止

---

## 自動起動設定

### 1. Windowsタスクスケジューラ設定

1. **タスクスケジューラ** 起動
2. **基本タスクの作成**
3. **トリガー**: ログオン時
4. **操作**: プログラムの開始
5. **プログラム**: `C:\Program Files\Microsoft Office\root\Office16\EXCEL.EXE`
6. **引数**: `C:\Kabuto\kabuto_auto_trader.xlsm`

### 2. 自動ログオン設定（オプション）

**netplwiz** で自動ログオン設定:

1. Win+R → `netplwiz`
2. ユーザー選択
3. ☐ **ユーザーがこのコンピューターを使うには、ユーザー名とパスワードの入力が必要** のチェックを外す
4. パスワード入力 → **OK**

### 3. スリープ無効化

1. **設定** → **システム** → **電源とスリープ**
2. スリープ: **なし**
3. ディスプレイの電源を切る: **なし**（または30分）

---

## トラブルシューティング

### JsonConverterエラー

**症状**: `Compile error: Sub or Function not defined`

**対処**:
1. **ツール** → **参照設定**
2. ✅ **Microsoft Scripting Runtime** にチェック

### RSS.ORDER エラー

**症状**: `Application.Run("RSS.ORDER", ...) でエラー`

**対処**:
1. MarketSpeed II が起動しているか確認
2. RSSアドインが有効か確認
3. 銘柄コードが正しいか確認（4桁数字）

### API接続エラー

**症状**: `CheckAPIConnection() が False`

**対処**:
1. Relay Serverが起動しているか確認
2. Config シートのAPI_BASE_URL が正しいか確認
3. ファイアウォール設定を確認

---

## まとめ

以上でExcelブックのセットアップが完了です。

**次のステップ**:
1. TradingView Pine Scriptデプロイ
2. Relay Server起動
3. Excel自動売買開始
4. 動作確認・監視

**重要**:
- 初めは **ENABLE_AUTO_START = FALSE** で手動テストを推奨
- 本番運用前に必ず紙取引（ドライラン）でテスト
- ログを定期的に確認

**サポート**:
- 設計書: `doc/13_excel_workbook_design.md`
- VBAコード: `excel_vba/modules/*.bas`
