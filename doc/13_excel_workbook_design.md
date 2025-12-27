# 13. MarketSpeed II RSS 全自動売買用 Excel ブック設計

## 目的

MarketSpeed II RSSを用いた完全自動売買システムのExcelブック構成を設計する。

- **無人稼働**: 人手介入なしで24時間稼働
- **Signal管理**: サーバーからのシグナルを受信・処理
- **Order実行**: MarketSpeed II RSSで自動発注
- **Log記録**: 全ての操作を詳細ログに記録
- **監視**: リアルタイム状態表示とアラート
- **復旧**: Excel再起動時の自動復旧

---

## 1. Excel ブック全体構成

### 1.1 ファイル構成

**ファイル名**: `kabuto_auto_trader.xlsm` (マクロ有効ブック)
**保存場所**: `C:\Kabuto\kabuto_auto_trader.xlsm`

**VBAプロジェクト保護**: パスワード設定推奨

---

### 1.2 シート一覧（11シート）

| # | シート名 | 用途 | 可視性 | 備考 |
|---|----------|------|--------|------|
| 1 | **Dashboard** | リアルタイム監視ダッシュボード | Visible | 最前面表示 |
| 2 | **SignalQueue** | 未処理シグナルキュー | Visible | 発注待ちシグナル一覧 |
| 3 | **OrderHistory** | 発注履歴 | Visible | 全注文の履歴 |
| 4 | **ExecutionLog** | 約定履歴 | Visible | 約定済み注文 |
| 5 | **ErrorLog** | エラーログ | Visible | 全エラー記録 |
| 6 | **PositionManager** | ポジション管理 | Visible | 現在のポジション状況 |
| 7 | **Config** | システム設定 | Hidden | API Key, パラメータ |
| 8 | **MarketCalendar** | 市場カレンダー | Hidden | 取引日・休日管理 |
| 9 | **BlacklistTickers** | 銘柄ブラックリスト | Hidden | 取引禁止銘柄 |
| 10 | **SystemState** | システム状態管理 | VeryHidden | 内部状態変数 |
| 11 | **RSSInterface** | RSS関数インターフェース | VeryHidden | RSS.ORDER()呼び出し用 |

---

## 2. 各シート詳細設計

### 2.1 Dashboard（ダッシュボード）

**目的**: システム全体のリアルタイム監視

#### レイアウト

```
┌─────────────────────────────────────────────────────────────┐
│  Kabuto Auto Trader - Dashboard                            │
│─────────────────────────────────────────────────────────────│
│                                                             │
│  【システム状態】                                             │
│  ┌────────────────────┬────────────────────┐                │
│  │ 稼働状態           │ ●Running           │                │
│  │ 最終更新           │ 2025-12-27 09:45:32│                │
│  │ 次回ポーリング     │ 3秒後              │                │
│  │ API接続            │ ✓ OK               │                │
│  │ MarketSpeed接続    │ ✓ OK               │                │
│  │ 市場状態           │ 前場取引中         │                │
│  └────────────────────┴────────────────────┘                │
│                                                             │
│  【本日の取引状況】                                           │
│  ┌────────────────────┬────────────────────┐                │
│  │ シグナル受信数     │ 5                  │                │
│  │ 発注済み           │ 3                  │                │
│  │ 約定済み           │ 2                  │                │
│  │ エラー             │ 0                  │                │
│  │ 本日損益           │ +12,500円          │                │
│  │ 本日手数料         │ -450円             │                │
│  └────────────────────┴────────────────────┘                │
│                                                             │
│  【リスク管理】                                               │
│  ┌────────────────────┬────────────────────┬─────────┐      │
│  │ 総ポジション評価額 │ 582,000円          │ 58.2%   │      │
│  │ 利用可能残高       │ 418,000円          │ 41.8%   │      │
│  │ 本日エントリー数   │ 3 / 5              │ 60%     │      │
│  │ 保有銘柄数         │ 2 / 5              │ 40%     │      │
│  └────────────────────┴────────────────────┴─────────┘      │
│                                                             │
│  【最新シグナル】                                             │
│  ┌────────┬──────┬────┬─────┬──────────┬─────────┐        │
│  │ 時刻   │ 銘柄 │ 動作│ 数量│ 価格     │ 状態    │        │
│  ├────────┼──────┼────┼─────┼──────────┼─────────┤        │
│  │09:43:12│ 9984 │ BUY │ 100 │ 3,000    │ 約定済み│        │
│  │09:41:05│ 6758 │ BUY │  50 │ 12,500   │ 発注中  │        │
│  │09:38:47│ 7203 │ SELL│ 200 │ 2,800    │ 約定済み│        │
│  └────────┴──────┴────┴─────┴──────────┴─────────┘        │
│                                                             │
│  【制御ボタン】                                               │
│  [▶ 開始]  [⏸ 一時停止]  [⏹ 停止]  [🔄 再読込]  [📋 レポート]│
└─────────────────────────────────────────────────────────────┘
```

#### データ構造

**セル定義**:
```
B2: システム状態     =SystemState!$B$1  ("Running" / "Paused" / "Stopped")
B3: 最終更新         =SystemState!$B$2  (NOW()をVBAで更新)
B4: 次回ポーリング   =TEXT(SystemState!$B$3-NOW(),"s""秒後""")
B5: API接続          =IF(SystemState!$B$4="OK","✓ OK","✗ Error")
B6: MarketSpeed接続  =IF(SystemState!$B$5="OK","✓ OK","✗ Error")
B7: 市場状態         =SystemState!$B$6

B10: シグナル受信数  =COUNTIF(SignalQueue!$A:$A,"sig_*")
B11: 発注済み        =COUNTIFS(OrderHistory!$H:$H,">="&TODAY(),OrderHistory!$F:$F,"submitted")
B12: 約定済み        =COUNTROWS(ExecutionLog,TODAY())
B13: エラー          =COUNTIFS(ErrorLog!$A:$A,">="&TODAY())
B14: 本日損益        =SUM(ExecutionLog!$M:$M,TODAY())
B15: 本日手数料      =SUM(OrderHistory!$L:$L,TODAY())

B18: 総ポジション評価額  =SUM(PositionManager!$J:$J)
B19: 利用可能残高        =Config!$B$5 - B18
B20: 本日エントリー数    =COUNTIFS(OrderHistory!$H:$H,">="&TODAY(),OrderHistory!$C:$C,"buy")
B21: 保有銘柄数          =COUNTA(PositionManager!$A:$A) - 1
```

**最新シグナル表（B25:G30）**:
```vba
' VBAで動的更新（最新5件）
Sub UpdateDashboardSignals()
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("Dashboard")

    ' OrderHistoryから最新5件取得
    Dim lastRow As Long
    lastRow = Sheets("OrderHistory").Cells(Rows.Count, 1).End(xlUp).Row

    If lastRow < 2 Then Exit Sub

    Dim startRow As Long
    startRow = Application.Max(2, lastRow - 4)

    ' データコピー（降順）
    Dim i As Long
    Dim targetRow As Long
    targetRow = 26

    For i = lastRow To startRow Step -1
        ws.Cells(targetRow, 2).Value = Sheets("OrderHistory").Cells(i, 2).Value  ' 時刻
        ws.Cells(targetRow, 3).Value = Sheets("OrderHistory").Cells(i, 3).Value  ' 銘柄
        ws.Cells(targetRow, 4).Value = Sheets("OrderHistory").Cells(i, 4).Value  ' 動作
        ws.Cells(targetRow, 5).Value = Sheets("OrderHistory").Cells(i, 5).Value  ' 数量
        ws.Cells(targetRow, 6).Value = Sheets("OrderHistory").Cells(i, 6).Value  ' 価格
        ws.Cells(targetRow, 7).Value = Sheets("OrderHistory").Cells(i, 9).Value  ' 状態
        targetRow = targetRow + 1
    Next i
End Sub
```

#### 制御ボタン

**VBA実装**:
```vba
Sub Button_Start_Click()
    Call StartAutoTrading
End Sub

Sub Button_Pause_Click()
    Call PauseAutoTrading
End Sub

Sub Button_Stop_Click()
    Call StopAutoTrading
End Sub

Sub Button_Reload_Click()
    Call ReloadConfiguration
End Sub

Sub Button_Report_Click()
    Call GenerateDailyReport
End Sub
```

---

### 2.2 SignalQueue（シグナルキュー）

**目的**: サーバーから取得した未処理シグナルを一時保存

#### データ構造

| 列 | 項目名 | データ型 | 例 | 備考 |
|----|--------|----------|-----|------|
| A | signal_id | String | sig_20251227_093510_9984_buy | 一意キー |
| B | received_at | DateTime | 2025-12-27 09:35:10 | 受信時刻 |
| C | action | String | buy / sell | 売買区分 |
| D | ticker | String | 9984 | 銘柄コード |
| E | quantity | Integer | 100 | 数量 |
| F | entry_price | Double | 3000.50 | エントリー価格 |
| G | stop_loss | Double | 2940.25 | 損切価格 |
| H | take_profit | Double | 3120.75 | 利確価格 |
| I | atr | Double | 30.12 | ATR値 |
| J | checksum | String | a3f8b9c2e1d4 | チェックサム |
| K | state | String | pending / processing / completed | 処理状態 |
| L | processed_at | DateTime | 2025-12-27 09:35:15 | 処理完了時刻 |
| M | error_message | String | - | エラー時のメッセージ |

**ヘッダー行**: 1行目（固定）

**データ保持期間**:
- `completed`: 処理完了後1時間で自動削除
- `error`: 24時間保持（手動確認用）

#### VBA関数

```vba
Sub AddSignalToQueue(signal As Dictionary)
    '
    ' サーバーから取得したシグナルをキューに追加
    '
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("SignalQueue")

    ' 重複チェック
    If IsSignalInQueue(signal("signal_id")) Then
        Debug.Print "Duplicate signal: " & signal("signal_id")
        Exit Sub
    End If

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    ws.Cells(lastRow, 1).Value = signal("signal_id")
    ws.Cells(lastRow, 2).Value = Now
    ws.Cells(lastRow, 3).Value = signal("action")
    ws.Cells(lastRow, 4).Value = signal("ticker")
    ws.Cells(lastRow, 5).Value = signal("quantity")
    ws.Cells(lastRow, 6).Value = signal("entry_price")
    ws.Cells(lastRow, 7).Value = signal("stop_loss")
    ws.Cells(lastRow, 8).Value = signal("take_profit")
    ws.Cells(lastRow, 9).Value = signal("atr")
    ws.Cells(lastRow, 10).Value = signal("checksum")
    ws.Cells(lastRow, 11).Value = "pending"

    Debug.Print "Signal added to queue: " & signal("signal_id")
End Sub

Function IsSignalInQueue(signalId As String) As Boolean
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("SignalQueue")

    Dim foundCell As Range
    Set foundCell = ws.Columns(1).Find(signalId, LookIn:=xlValues, LookAt:=xlWhole)

    IsSignalInQueue = Not foundCell Is Nothing
End Function

Sub ProcessNextSignal()
    '
    ' キューから次のシグナルを取得して処理
    '
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("SignalQueue")

    ' stateが"pending"の最古シグナルを取得
    Dim i As Long
    For i = 2 To ws.Cells(ws.Rows.Count, 1).End(xlUp).Row
        If ws.Cells(i, 11).Value = "pending" Then
            ' 処理中にマーク
            ws.Cells(i, 11).Value = "processing"

            ' シグナルデータ構築
            Dim signal As New Dictionary
            signal("signal_id") = ws.Cells(i, 1).Value
            signal("action") = ws.Cells(i, 3).Value
            signal("ticker") = ws.Cells(i, 4).Value
            signal("quantity") = ws.Cells(i, 5).Value
            signal("entry_price") = ws.Cells(i, 6).Value
            signal("stop_loss") = ws.Cells(i, 7).Value
            signal("take_profit") = ws.Cells(i, 8).Value

            ' 発注処理
            Dim orderId As String
            orderId = ExecuteOrder(signal)

            If orderId <> "" Then
                ' 成功
                ws.Cells(i, 11).Value = "completed"
                ws.Cells(i, 12).Value = Now
            Else
                ' 失敗
                ws.Cells(i, 11).Value = "error"
                ws.Cells(i, 13).Value = "Order execution failed"
            End If

            Exit For
        End If
    Next i
End Sub

Sub CleanupCompletedSignals()
    '
    ' 完了済みシグナルを削除（1時間経過後）
    '
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("SignalQueue")

    Dim i As Long
    For i = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row To 2 Step -1
        If ws.Cells(i, 11).Value = "completed" Then
            Dim processedAt As Date
            processedAt = ws.Cells(i, 12).Value

            If DateDiff("h", processedAt, Now) >= 1 Then
                ws.Rows(i).Delete
                Debug.Print "Deleted old signal: " & ws.Cells(i, 1).Value
            End If
        End If
    Next i
End Sub
```

---

### 2.3 OrderHistory（発注履歴）

**目的**: 全ての発注を記録（成功・失敗問わず）

#### データ構造

| 列 | 項目名 | データ型 | 例 | 備考 |
|----|--------|----------|-----|------|
| A | order_internal_id | String | ORD_20251227_093512_001 | 内部管理ID |
| B | timestamp | DateTime | 2025-12-27 09:35:12 | 発注時刻 |
| C | signal_id | String | sig_20251227_093510_9984_buy | 元シグナルID |
| D | action | String | buy / sell | 売買区分 |
| E | ticker | String | 9984 | 銘柄コード |
| F | quantity | Integer | 100 | 数量 |
| G | order_type | String | market / limit | 注文種別 |
| H | limit_price | Double | - | 指値価格（成行は空白） |
| I | rss_order_id | String | 20251227-00123456 | RSS返却の注文番号 |
| J | status | String | submitted / filled / rejected / cancelled | 注文状態 |
| K | filled_price | Double | 3001.00 | 約定価格 |
| L | filled_quantity | Integer | 100 | 約定数量 |
| M | commission | Double | 150 | 手数料 |
| N | execution_time | DateTime | 2025-12-27 09:35:18 | 約定時刻 |
| O | error_message | String | - | エラー時のメッセージ |

**インデックス**: A列（order_internal_id）をキーとして昇順ソート

**データ保持期間**:
- 当日分: 全て保持
- 過去分: 90日間保持（それ以降はアーカイブ）

#### VBA関数

```vba
Function RecordOrder(signal As Dictionary, rssOrderId As String, status As String) As String
    '
    ' 発注を履歴に記録
    '
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("OrderHistory")

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    ' 内部管理ID生成
    Dim internalId As String
    internalId = "ORD_" & Format(Now, "yyyymmdd_hhnnss") & "_" & Format(lastRow - 1, "000")

    ws.Cells(lastRow, 1).Value = internalId
    ws.Cells(lastRow, 2).Value = Now
    ws.Cells(lastRow, 3).Value = signal("signal_id")
    ws.Cells(lastRow, 4).Value = signal("action")
    ws.Cells(lastRow, 5).Value = signal("ticker")
    ws.Cells(lastRow, 6).Value = signal("quantity")
    ws.Cells(lastRow, 7).Value = "market"
    ws.Cells(lastRow, 8).Value = ""  ' 成行なので空白
    ws.Cells(lastRow, 9).Value = rssOrderId
    ws.Cells(lastRow, 10).Value = status

    RecordOrder = internalId

    Debug.Print "Order recorded: " & internalId & " RSS_ID=" & rssOrderId
End Function

Sub UpdateOrderStatus(internalId As String, status As String, Optional filledPrice As Double = 0, Optional filledQty As Integer = 0, Optional commission As Double = 0)
    '
    ' 注文状態を更新
    '
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("OrderHistory")

    Dim foundCell As Range
    Set foundCell = ws.Columns(1).Find(internalId, LookIn:=xlValues, LookAt:=xlWhole)

    If Not foundCell Is Nothing Then
        Dim rowNum As Long
        rowNum = foundCell.Row

        ws.Cells(rowNum, 10).Value = status

        If filledPrice > 0 Then
            ws.Cells(rowNum, 11).Value = filledPrice
            ws.Cells(rowNum, 12).Value = filledQty
            ws.Cells(rowNum, 13).Value = commission
            ws.Cells(rowNum, 14).Value = Now  ' execution_time
        End If

        Debug.Print "Order status updated: " & internalId & " -> " & status
    End If
End Sub

Sub PollOrderStatus(internalId As String)
    '
    ' RSSで注文状態をポーリング（約定確認）
    '
    On Error GoTo ErrorHandler

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("OrderHistory")

    Dim foundCell As Range
    Set foundCell = ws.Columns(1).Find(internalId, LookIn:=xlValues, LookAt:=xlWhole)

    If foundCell Is Nothing Then Exit Sub

    Dim rssOrderId As String
    rssOrderId = ws.Cells(foundCell.Row, 9).Value

    If rssOrderId = "" Then Exit Sub

    ' RSS.STATUS関数で注文状態照会
    Dim result As Variant
    result = Application.Run("RSS.STATUS", rssOrderId)

    ' result形式: "約定済み|価格:3001|数量:100|手数料:150"
    If InStr(result, "約定済み") > 0 Then
        Dim parts() As String
        parts = Split(result, "|")

        Dim price As Double
        Dim quantity As Integer
        Dim commission As Double

        price = CDbl(Split(parts(1), ":")(1))
        quantity = CInt(Split(parts(2), ":")(1))
        commission = CDbl(Split(parts(3), ":")(1))

        Call UpdateOrderStatus(internalId, "filled", price, quantity, commission)

        ' 約定ログに記録
        Call RecordExecution(internalId)
    End If

    Exit Sub

ErrorHandler:
    Debug.Print "Error polling order status: " & Err.Description
End Sub
```

---

### 2.4 ExecutionLog（約定履歴）

**目的**: 約定済み注文を記録（損益計算用）

#### データ構造

| 列 | 項目名 | データ型 | 例 | 備考 |
|----|--------|----------|-----|------|
| A | execution_id | String | EXE_20251227_093518_001 | 約定ID |
| B | execution_time | DateTime | 2025-12-27 09:35:18 | 約定時刻 |
| C | order_internal_id | String | ORD_20251227_093512_001 | 発注履歴とリンク |
| D | action | String | buy / sell | 売買区分 |
| E | ticker | String | 9984 | 銘柄コード |
| F | quantity | Integer | 100 | 約定数量 |
| G | price | Double | 3001.00 | 約定価格 |
| H | commission | Double | 150 | 手数料 |
| I | total_amount | Double | 300,250 | 約定代金（価格×数量+手数料） |
| J | position_effect | String | open / close | ポジション影響 |
| K | realized_pnl | Double | +12,500 | 実現損益（決済時のみ） |
| L | notes | String | - | 備考 |

**計算式**:
- `I列（約定代金）`: `=G列*F列 + H列` （買いの場合）
- `I列（約定代金）`: `=G列*F列 - H列` （売りの場合）
- `K列（実現損益）`: 売却時に計算（売却価格 - 平均取得単価）× 数量 - 手数料

#### VBA関数

```vba
Sub RecordExecution(orderInternalId As String)
    '
    ' OrderHistoryから約定情報を取得してExecutionLogに記録
    '
    Dim wsOrder As Worksheet
    Dim wsExec As Worksheet

    Set wsOrder = ThisWorkbook.Sheets("OrderHistory")
    Set wsExec = ThisWorkbook.Sheets("ExecutionLog")

    ' OrderHistoryから該当行検索
    Dim foundCell As Range
    Set foundCell = wsOrder.Columns(1).Find(orderInternalId, LookIn:=xlValues)

    If foundCell Is Nothing Then Exit Sub

    Dim orderRow As Long
    orderRow = foundCell.Row

    ' 約定データ取得
    Dim action As String
    Dim ticker As String
    Dim quantity As Integer
    Dim price As Double
    Dim commission As Double
    Dim execTime As Date

    action = wsOrder.Cells(orderRow, 4).Value
    ticker = wsOrder.Cells(orderRow, 5).Value
    quantity = wsOrder.Cells(orderRow, 12).Value
    price = wsOrder.Cells(orderRow, 11).Value
    commission = wsOrder.Cells(orderRow, 13).Value
    execTime = wsOrder.Cells(orderRow, 14).Value

    ' ExecutionLogに追加
    Dim lastRow As Long
    lastRow = wsExec.Cells(wsExec.Rows.Count, 1).End(xlUp).Row + 1

    Dim execId As String
    execId = "EXE_" & Format(execTime, "yyyymmdd_hhnnss") & "_" & Format(lastRow - 1, "000")

    wsExec.Cells(lastRow, 1).Value = execId
    wsExec.Cells(lastRow, 2).Value = execTime
    wsExec.Cells(lastRow, 3).Value = orderInternalId
    wsExec.Cells(lastRow, 4).Value = action
    wsExec.Cells(lastRow, 5).Value = ticker
    wsExec.Cells(lastRow, 6).Value = quantity
    wsExec.Cells(lastRow, 7).Value = price
    wsExec.Cells(lastRow, 8).Value = commission

    ' 約定代金計算
    Dim totalAmount As Double
    If action = "buy" Then
        totalAmount = price * quantity + commission
        wsExec.Cells(lastRow, 10).Value = "open"  ' 新規建て
    Else
        totalAmount = price * quantity - commission
        wsExec.Cells(lastRow, 10).Value = "close"  ' 決済

        ' 実現損益計算
        Dim pnl As Double
        pnl = CalculateRealizedPnL(ticker, quantity, price, commission)
        wsExec.Cells(lastRow, 11).Value = pnl
    End If

    wsExec.Cells(lastRow, 9).Value = totalAmount

    ' ポジション管理を更新
    Call UpdatePosition(ticker, action, quantity, price)

    Debug.Print "Execution recorded: " & execId
End Sub

Function CalculateRealizedPnL(ticker As String, sellQty As Integer, sellPrice As Double, commission As Double) As Double
    '
    ' 実現損益計算（FIFO方式）
    '
    Dim wsPos As Worksheet
    Set wsPos = ThisWorkbook.Sheets("PositionManager")

    ' PositionManagerから該当銘柄の平均取得単価を取得
    Dim foundCell As Range
    Set foundCell = wsPos.Columns(1).Find(ticker, LookIn:=xlValues)

    If foundCell Is Nothing Then
        CalculateRealizedPnL = 0
        Exit Function
    End If

    Dim avgCost As Double
    avgCost = wsPos.Cells(foundCell.Row, 4).Value  ' 平均取得単価

    ' 損益 = (売却価格 - 平均取得単価) × 数量 - 手数料
    CalculateRealizedPnL = (sellPrice - avgCost) * sellQty - commission
End Function
```

---

### 2.5 ErrorLog（エラーログ）

**目的**: 全てのエラーを記録（トラブルシューティング用）

#### データ構造

| 列 | 項目名 | データ型 | 例 | 備考 |
|----|--------|----------|-----|------|
| A | error_id | String | ERR_20251227_093520_001 | エラーID |
| B | timestamp | DateTime | 2025-12-27 09:35:20 | 発生時刻 |
| C | error_type | String | API_ERROR / RSS_ERROR / VALIDATION_ERROR | エラー種別 |
| D | module | String | PollAndExecuteSignals | 発生モジュール |
| E | ticker | String | 9984 | 関連銘柄（あれば） |
| F | error_code | String | HTTP_401 / RSS_REJECT | エラーコード |
| G | error_message | String | API authentication failed | エラーメッセージ |
| H | stack_trace | String | Err.Source, Err.Number | スタックトレース |
| I | severity | String | CRITICAL / ERROR / WARNING | 重要度 |
| J | resolved | Boolean | FALSE | 解決済みフラグ |
| K | notes | String | - | 対処メモ |

#### VBA関数

```vba
Sub LogError(errorType As String, module As String, errorMsg As String, Optional ticker As String = "", Optional severity As String = "ERROR")
    '
    ' エラーログに記録
    '
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("ErrorLog")

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    Dim errorId As String
    errorId = "ERR_" & Format(Now, "yyyymmdd_hhnnss") & "_" & Format(lastRow - 1, "000")

    ws.Cells(lastRow, 1).Value = errorId
    ws.Cells(lastRow, 2).Value = Now
    ws.Cells(lastRow, 3).Value = errorType
    ws.Cells(lastRow, 4).Value = module
    ws.Cells(lastRow, 5).Value = ticker
    ws.Cells(lastRow, 6).Value = ""  ' エラーコードは後で設定
    ws.Cells(lastRow, 7).Value = errorMsg
    ws.Cells(lastRow, 8).Value = Err.Source & " (" & Err.Number & ")"
    ws.Cells(lastRow, 9).Value = severity
    ws.Cells(lastRow, 10).Value = False  ' 未解決

    Debug.Print "Error logged: " & errorId & " - " & errorMsg

    ' CRITICAL エラーの場合はアラート
    If severity = "CRITICAL" Then
        Call SendCriticalAlert(errorMsg)
    End If
End Sub

Sub SendCriticalAlert(errorMsg As String)
    '
    ' 重大エラー時のアラート送信
    '
    ' 方法1: メールボックスで通知
    MsgBox "【重大エラー】" & vbCrLf & errorMsg, vbCritical, "Kabuto Auto Trader"

    ' 方法2: サーバーにアラート送信（TODO）
    ' Call SendAlertToServer(errorMsg)

    ' 方法3: システム停止
    Call StopAutoTrading
End Sub
```

---

### 2.6 PositionManager（ポジション管理）

**目的**: 現在のポジション状況をリアルタイム管理

#### データ構造

| 列 | 項目名 | データ型 | 例 | 備考 |
|----|--------|----------|-----|------|
| A | ticker | String | 9984 | 銘柄コード |
| B | ticker_name | String | SoftBank Group | 銘柄名（手動入力 or API取得） |
| C | quantity | Integer | 100 | 保有数量 |
| D | avg_cost | Double | 3000.50 | 平均取得単価 |
| E | current_price | Double | 3015.00 | 現在価格（RSS取得） |
| F | unrealized_pnl | Double | +1,450 | 含み損益 |
| G | unrealized_pnl_pct | Double | +0.48% | 含み損益率 |
| H | stop_loss | Double | 2940.25 | 損切価格（元シグナルから） |
| I | take_profit | Double | 3120.75 | 利確価格（元シグナルから） |
| J | position_value | Double | 301,500 | ポジション評価額 |
| K | entry_date | Date | 2025-12-27 | エントリー日 |
| L | holding_days | Integer | 0 | 保有日数 |

**計算式**:
- `F列（含み損益）`: `=(E列 - D列) * C列`
- `G列（含み損益率）`: `=F列 / (D列 * C列)`
- `J列（ポジション評価額）`: `=E列 * C列`
- `L列（保有日数）`: `=TODAY() - K列`

#### VBA関数

```vba
Sub UpdatePosition(ticker As String, action As String, quantity As Integer, price As Double)
    '
    ' ポジションを更新
    '
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("PositionManager")

    Dim foundCell As Range
    Set foundCell = ws.Columns(1).Find(ticker, LookIn:=xlValues)

    If action = "buy" Then
        If foundCell Is Nothing Then
            ' 新規ポジション
            Dim lastRow As Long
            lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

            ws.Cells(lastRow, 1).Value = ticker
            ws.Cells(lastRow, 2).Value = GetTickerName(ticker)  ' 銘柄名取得
            ws.Cells(lastRow, 3).Value = quantity
            ws.Cells(lastRow, 4).Value = price
            ws.Cells(lastRow, 5).Value = price  ' 初期価格
            ws.Cells(lastRow, 11).Value = Date  ' エントリー日
        Else
            ' 既存ポジションに追加（平均取得単価を再計算）
            Dim posRow As Long
            posRow = foundCell.Row

            Dim currentQty As Integer
            Dim currentAvgCost As Double

            currentQty = ws.Cells(posRow, 3).Value
            currentAvgCost = ws.Cells(posRow, 4).Value

            ' 平均取得単価 = (既存金額 + 新規金額) / (既存数量 + 新規数量)
            Dim newAvgCost As Double
            newAvgCost = ((currentAvgCost * currentQty) + (price * quantity)) / (currentQty + quantity)

            ws.Cells(posRow, 3).Value = currentQty + quantity
            ws.Cells(posRow, 4).Value = newAvgCost
        End If
    ElseIf action = "sell" Then
        If Not foundCell Is Nothing Then
            Dim posRow As Long
            posRow = foundCell.Row

            Dim currentQty As Integer
            currentQty = ws.Cells(posRow, 3).Value

            If currentQty <= quantity Then
                ' 全決済 → 行削除
                ws.Rows(posRow).Delete
            Else
                ' 一部決済 → 数量減少
                ws.Cells(posRow, 3).Value = currentQty - quantity
            End If
        End If
    End If

    Debug.Print "Position updated: " & ticker & " " & action & " " & quantity
End Sub

Sub UpdateCurrentPrices()
    '
    ' RSSで現在価格を取得してポジションを更新
    '
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("PositionManager")

    Dim i As Long
    For i = 2 To ws.Cells(ws.Rows.Count, 1).End(xlUp).Row
        Dim ticker As String
        ticker = ws.Cells(i, 1).Value

        If ticker <> "" Then
            On Error Resume Next

            ' RSS.PRICE関数で現在価格取得
            Dim currentPrice As Variant
            currentPrice = Application.Run("RSS.PRICE", ticker)

            If Not IsError(currentPrice) And currentPrice > 0 Then
                ws.Cells(i, 5).Value = CDbl(currentPrice)
            End If

            On Error GoTo 0
        End If
    Next i

    Debug.Print "Current prices updated"
End Sub

Function GetTickerName(ticker As String) As String
    '
    ' 銘柄コードから銘柄名を取得
    '
    On Error Resume Next

    ' RSS.NAMEまたは静的マッピング
    Dim tickerName As Variant
    tickerName = Application.Run("RSS.NAME", ticker)

    If IsError(tickerName) Or tickerName = "" Then
        ' フォールバック: 静的マッピング
        Select Case ticker
            Case "9984": GetTickerName = "SoftBank Group"
            Case "6758": GetTickerName = "Sony Group"
            Case "7203": GetTickerName = "Toyota"
            Case Else: GetTickerName = ticker
        End Select
    Else
        GetTickerName = CStr(tickerName)
    End If

    On Error GoTo 0
End Function
```

---

### 2.7 Config（システム設定）

**可視性**: Hidden（通常は非表示）

**目的**: API Key、パラメータ、設定値を集中管理

#### データ構造

| セル | 項目名 | 値 | 備考 |
|------|--------|-----|------|
| A1 | API_BASE_URL | http://relay-server.local:5000/api | サーバーURL |
| A2 | API_KEY | your-api-key-here | Bearer Token |
| A3 | CLIENT_ID | excel_vm_01 | クライアント識別子 |
| A4 | POLLING_INTERVAL_SEC | 5 | ポーリング間隔（秒） |
| A5 | MAX_POSITION_VALUE | 1000000 | 最大ポジション評価額（円） |
| A6 | MAX_DAILY_ENTRIES | 5 | 1日最大エントリー数 |
| A7 | MAX_POSITIONS | 5 | 最大保有銘柄数 |
| A8 | ENABLE_AUTO_START | TRUE | Excelブック起動時に自動開始 |
| A9 | ENABLE_MARKET_HOURS_CHECK | TRUE | 市場時間外は停止 |
| A10 | LOG_RETENTION_DAYS | 90 | ログ保持期間（日） |
| A11 | RSS_CONNECTION_TIMEOUT_SEC | 30 | RSSタイムアウト（秒） |
| A12 | ALERT_EMAIL | user@example.com | アラート送信先メール |
| A13 | ENABLE_CRITICAL_ALERT | TRUE | 重大エラー時のアラート |

**アクセス方法**（VBA）:
```vba
Function GetConfig(key As String) As Variant
    '
    ' 設定値を取得
    '
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("Config")

    Dim foundCell As Range
    Set foundCell = ws.Columns(1).Find(key, LookIn:=xlValues, LookAt:=xlWhole)

    If Not foundCell Is Nothing Then
        GetConfig = ws.Cells(foundCell.Row, 2).Value
    Else
        GetConfig = ""
    End If
End Function

' 使用例
Dim apiKey As String
apiKey = GetConfig("API_KEY")

Dim maxPositions As Integer
maxPositions = CInt(GetConfig("MAX_POSITIONS"))
```

---

### 2.8 MarketCalendar（市場カレンダー）

**可視性**: Hidden

**目的**: 日本市場の営業日・休日を管理

#### データ構造

| 列 | 項目名 | データ型 | 例 | 備考 |
|----|--------|----------|-----|------|
| A | date | Date | 2025-12-31 | 日付 |
| B | day_of_week | String | 水 | 曜日 |
| C | is_trading_day | Boolean | TRUE | 取引日フラグ |
| D | session_type | String | full / half / closed | セッション種別 |
| E | morning_open | Time | 09:00 | 前場開始 |
| F | morning_close | Time | 11:30 | 前場終了 |
| G | afternoon_open | Time | 12:30 | 後場開始 |
| H | afternoon_close | Time | 15:00 | 後場終了 |
| I | notes | String | 大納会 | 備考 |

**初期データ**: 2025年1年分を手動入力 or スクリプトで生成

**VBA関数**:
```vba
Function IsTradingDay(targetDate As Date) As Boolean
    '
    ' 指定日が取引日かチェック
    '
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("MarketCalendar")

    Dim foundCell As Range
    Set foundCell = ws.Columns(1).Find(targetDate, LookIn:=xlValues, LookAt:=xlWhole)

    If Not foundCell Is Nothing Then
        IsTradingDay = ws.Cells(foundCell.Row, 3).Value
    Else
        ' データがない場合は平日を取引日とみなす
        Dim dayOfWeek As Integer
        dayOfWeek = Weekday(targetDate)
        IsTradingDay = (dayOfWeek <> vbSaturday And dayOfWeek <> vbSunday)
    End If
End Function

Function IsMarketOpen() As Boolean
    '
    ' 現在時刻が取引時間内かチェック
    '
    If Not IsTradingDay(Date) Then
        IsMarketOpen = False
        Exit Function
    End If

    Dim currentTime As Date
    currentTime = Time

    ' 前場: 9:00-11:30
    If currentTime >= TimeValue("09:00:00") And currentTime <= TimeValue("11:30:00") Then
        IsMarketOpen = True
        Exit Function
    End If

    ' 後場: 12:30-15:00
    If currentTime >= TimeValue("12:30:00") And currentTime <= TimeValue("15:00:00") Then
        IsMarketOpen = True
        Exit Function
    End If

    IsMarketOpen = False
End Function
```

---

### 2.9 BlacklistTickers（銘柄ブラックリスト）

**可視性**: Hidden

**目的**: 取引禁止銘柄を管理

#### データ構造

| 列 | 項目名 | データ型 | 例 | 備考 |
|----|--------|----------|-----|------|
| A | ticker | String | 1234 | 銘柄コード |
| B | ticker_name | String | ABC株式会社 | 銘柄名 |
| C | reason | String | 連続損失 | ブラックリスト理由 |
| D | added_date | Date | 2025-12-20 | 追加日 |
| E | expiry_date | Date | 2026-01-20 | 有効期限（空白=永久） |
| F | added_by | String | manual / auto | 追加方法 |

**VBA関数**:
```vba
Function IsTickerBlacklisted(ticker As String) As Boolean
    '
    ' 銘柄がブラックリストに含まれるかチェック
    '
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("BlacklistTickers")

    Dim foundCell As Range
    Set foundCell = ws.Columns(1).Find(ticker, LookIn:=xlValues, LookAt:=xlWhole)

    If foundCell Is Nothing Then
        IsTickerBlacklisted = False
        Exit Function
    End If

    ' 有効期限チェック
    Dim expiryDate As Variant
    expiryDate = ws.Cells(foundCell.Row, 5).Value

    If IsEmpty(expiryDate) Then
        ' 有効期限なし（永久ブラックリスト）
        IsTickerBlacklisted = True
    ElseIf expiryDate >= Date Then
        ' 有効期限内
        IsTickerBlacklisted = True
    Else
        ' 有効期限切れ
        IsTickerBlacklisted = False
        ' TODO: 期限切れエントリを削除
    End If
End Function

Sub AddToBlacklist(ticker As String, reason As String, Optional expiryDays As Integer = 0)
    '
    ' ブラックリストに追加
    '
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("BlacklistTickers")

    ' 重複チェック
    If IsTickerBlacklisted(ticker) Then Exit Sub

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    ws.Cells(lastRow, 1).Value = ticker
    ws.Cells(lastRow, 2).Value = GetTickerName(ticker)
    ws.Cells(lastRow, 3).Value = reason
    ws.Cells(lastRow, 4).Value = Date

    If expiryDays > 0 Then
        ws.Cells(lastRow, 5).Value = DateAdd("d", expiryDays, Date)
    End If

    ws.Cells(lastRow, 6).Value = "auto"

    Debug.Print "Ticker added to blacklist: " & ticker
End Sub
```

---

### 2.10 SystemState（システム状態管理）

**可視性**: VeryHidden（VBEからのみアクセス可能）

**目的**: システムの内部状態を保持

#### データ構造

| セル | 項目名 | 値 | 備考 |
|------|--------|-----|------|
| B1 | system_status | Running / Paused / Stopped | システム状態 |
| B2 | last_update | 2025-12-27 09:45:32 | 最終更新時刻 |
| B3 | next_poll_time | 2025-12-27 09:45:37 | 次回ポーリング時刻 |
| B4 | api_connection_status | OK / Error | API接続状態 |
| B5 | rss_connection_status | OK / Error | RSS接続状態 |
| B6 | market_session | 前場取引中 | 市場セッション |
| B7 | daily_entry_count | 3 | 本日エントリー数 |
| B8 | daily_trade_count | 5 | 本日取引数 |
| B9 | daily_error_count | 0 | 本日エラー数 |
| B10 | total_position_value | 582000 | 総ポジション評価額 |
| B11 | last_signal_time | 2025-12-27 09:43:12 | 最終シグナル受信時刻 |
| B12 | workbook_start_time | 2025-12-27 08:55:00 | ブック起動時刻 |

**アクセス方法**:
```vba
Function GetSystemState(key As String) As Variant
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("SystemState")

    Select Case key
        Case "system_status": GetSystemState = ws.Range("B1").Value
        Case "last_update": GetSystemState = ws.Range("B2").Value
        Case "daily_entry_count": GetSystemState = ws.Range("B7").Value
        ' ... 他のキー
        Case Else: GetSystemState = ""
    End Select
End Function

Sub SetSystemState(key As String, value As Variant)
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("SystemState")

    Select Case key
        Case "system_status": ws.Range("B1").Value = value
        Case "last_update": ws.Range("B2").Value = value
        Case "daily_entry_count": ws.Range("B7").Value = value
        ' ... 他のキー
    End Select
End Sub
```

---

### 2.11 RSSInterface（RSS関数インターフェース）

**可視性**: VeryHidden

**目的**: MarketSpeed II RSS関数を呼び出すための専用シート

**背景**: RSS関数はExcelシート上で実行する必要があるため、VBAから呼び出す際のインターフェースシートとして使用

#### データ構造

**入力セル**（VBAから書き込み）:
| セル | 項目名 | 例 | 備考 |
|------|--------|-----|------|
| A1 | function_name | ORDER | 呼び出すRSS関数名 |
| A2 | param_ticker | 9984 | パラメータ: 銘柄コード |
| A3 | param_side | 1 | パラメータ: 売買区分（1=買い, 2=売り） |
| A4 | param_quantity | 100 | パラメータ: 数量 |
| A5 | param_price_type | 0 | パラメータ: 価格種別（0=成行, 1=指値） |
| A6 | param_price | 0 | パラメータ: 価格 |

**出力セル**（RSS関数の結果）:
| セル | 項目名 | 例 | 備考 |
|------|--------|-----|------|
| B1 | rss_result | 注文番号:20251227-00123456 | RSS関数の返却値 |
| B2 | result_status | SUCCESS / ERROR | 結果ステータス |
| B3 | result_message | 注文を受け付けました | 結果メッセージ |

**VBA関数**:
```vba
Function CallRSS_ORDER(ticker As String, side As Integer, quantity As Integer, priceType As Integer, price As Double) As String
    '
    ' RSS.ORDER関数を呼び出し
    '
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("RSSInterface")

    ' 入力セットアップ
    ws.Range("A1").Value = "ORDER"
    ws.Range("A2").Value = ticker
    ws.Range("A3").Value = side
    ws.Range("A4").Value = quantity
    ws.Range("A5").Value = priceType
    ws.Range("A6").Value = price

    ' RSS関数実行（B1セルに数式を設定）
    ws.Range("B1").Formula = "=RSS.ORDER(A2,A3,A4,A5,A6)"

    ' 結果待機（最大10秒）
    Dim startTime As Double
    startTime = Timer

    Do While Timer - startTime < 10
        DoEvents
        If ws.Range("B1").Value <> "" And Not IsError(ws.Range("B1").Value) Then
            Exit Do
        End If
        Application.Wait Now + TimeValue("00:00:00.5")  ' 0.5秒待機
    Loop

    ' 結果取得
    Dim result As Variant
    result = ws.Range("B1").Value

    If IsError(result) Then
        ws.Range("B2").Value = "ERROR"
        ws.Range("B3").Value = "RSS function error"
        CallRSS_ORDER = ""
    Else
        ws.Range("B2").Value = "SUCCESS"
        ws.Range("B3").Value = CStr(result)
        CallRSS_ORDER = CStr(result)
    End If
End Function
```

---

## 3. VBA モジュール構成

### 3.1 モジュール一覧

| モジュール名 | 種別 | 目的 |
|------------|------|------|
| **Module_Main** | 標準モジュール | メインルーチン（ポーリング、自動実行） |
| **Module_API** | 標準モジュール | サーバーAPI通信 |
| **Module_RSS** | 標準モジュール | MarketSpeed II RSS連携 |
| **Module_SignalProcessor** | 標準モジュール | シグナル処理ロジック |
| **Module_PositionManager** | 標準モジュール | ポジション管理 |
| **Module_RiskControl** | 標準モジュール | リスク管理チェック |
| **Module_Logger** | 標準モジュール | ログ記録 |
| **Module_Utils** | 標準モジュール | ユーティリティ関数 |
| **Class_Signal** | クラスモジュール | Signalオブジェクト |
| **Class_Order** | クラスモジュール | Orderオブジェクト |
| **ThisWorkbook** | Workbookモジュール | ブック起動・終了イベント |

---

### 3.2 Module_Main（メインルーチン）

```vba
Option Explicit

' ----- グローバル変数 -----
Public nextPollingTime As Date
Public isAutoTradingRunning As Boolean

' ----- 自動売買開始 -----
Sub StartAutoTrading()
    If isAutoTradingRunning Then
        Debug.Print "Auto trading is already running"
        Exit Sub
    End If

    isAutoTradingRunning = True
    Call SetSystemState("system_status", "Running")
    Call SetSystemState("workbook_start_time", Now)

    Debug.Print "Auto trading started"

    ' 初回ポーリング実行
    Call PollAndProcessSignals
End Sub

' ----- 自動売買一時停止 -----
Sub PauseAutoTrading()
    isAutoTradingRunning = False
    Call SetSystemState("system_status", "Paused")

    On Error Resume Next
    Application.OnTime nextPollingTime, "PollAndProcessSignals", , False
    On Error GoTo 0

    Debug.Print "Auto trading paused"
End Sub

' ----- 自動売買停止 -----
Sub StopAutoTrading()
    isAutoTradingRunning = False
    Call SetSystemState("system_status", "Stopped")

    On Error Resume Next
    Application.OnTime nextPollingTime, "PollAndProcessSignals", , False
    On Error GoTo 0

    Debug.Print "Auto trading stopped"
End Sub

' ----- メインポーリングルーチン -----
Sub PollAndProcessSignals()
    On Error GoTo ErrorHandler

    ' システム状態チェック
    If Not isAutoTradingRunning Then Exit Sub

    ' 市場時間チェック
    If GetConfig("ENABLE_MARKET_HOURS_CHECK") = True Then
        If Not IsMarketOpen() Then
            Debug.Print "Market is closed - skipping poll"
            GoTo ScheduleNext
        End If
    End If

    ' 最終更新時刻
    Call SetSystemState("last_update", Now)

    ' API接続チェック
    If Not CheckAPIConnection() Then
        Call SetSystemState("api_connection_status", "Error")
        Call LogError("API_ERROR", "PollAndProcessSignals", "API connection failed", "", "ERROR")
        GoTo ScheduleNext
    Else
        Call SetSystemState("api_connection_status", "OK")
    End If

    ' サーバーからシグナル取得
    Dim signals As Collection
    Set signals = FetchPendingSignals()

    If signals.Count > 0 Then
        Debug.Print "Fetched " & signals.Count & " signals"
        Call SetSystemState("last_signal_time", Now)

        ' 各シグナルをキューに追加
        Dim signal As Dictionary
        For Each signal In signals
            Call AddSignalToQueue(signal)
        Next signal
    End If

    ' キューからシグナルを処理
    Call ProcessNextSignal

    ' ポジションの現在価格を更新
    Call UpdateCurrentPrices

    ' ダッシュボード更新
    Call UpdateDashboardSignals

ScheduleNext:
    ' 次回実行スケジュール
    Dim interval As Integer
    interval = CInt(GetConfig("POLLING_INTERVAL_SEC"))

    nextPollingTime = Now + TimeValue("00:00:" & Format(interval, "00"))
    Call SetSystemState("next_poll_time", nextPollingTime)

    Application.OnTime nextPollingTime, "PollAndProcessSignals"

    Exit Sub

ErrorHandler:
    Debug.Print "Error in PollAndProcessSignals: " & Err.Description
    Call LogError("SYSTEM_ERROR", "PollAndProcessSignals", Err.Description, "", "CRITICAL")

    ' エラーでも継続（10秒後に再試行）
    nextPollingTime = Now + TimeValue("00:00:10")
    Application.OnTime nextPollingTime, "PollAndProcessSignals"
End Sub
```

---

### 3.3 ThisWorkbook（ブックイベント）

```vba
Option Explicit

' ----- ブック起動時 -----
Private Sub Workbook_Open()
    ' 自動開始設定チェック
    If GetConfig("ENABLE_AUTO_START") = True Then
        ' 3秒後に自動開始（ブック読み込み完了を待つ）
        Application.OnTime Now + TimeValue("00:00:03"), "StartAutoTrading"
        Debug.Print "Auto trading will start in 3 seconds..."
    Else
        Debug.Print "Auto start is disabled. Use [Start] button to begin."
    End If

    ' Dashboard シートをアクティブ化
    ThisWorkbook.Sheets("Dashboard").Activate
End Sub

' ----- ブック終了時 -----
Private Sub Workbook_BeforeClose(Cancel As Boolean)
    ' 自動売買停止
    If isAutoTradingRunning Then
        Call StopAutoTrading
        Debug.Print "Auto trading stopped before closing workbook"
    End If
End Sub

' ----- ブック保存時 -----
Private Sub Workbook_BeforeSave(ByVal SaveAsUI As Boolean, Cancel As Boolean)
    ' ログのクリーンアップ（保持期間超過）
    Call CleanupOldLogs
End Sub
```

---

## 4. 無人稼働のための追加機能

### 4.1 自動復旧（Excel再起動時）

**復旧シナリオ**:
1. Windows Updateによる再起動
2. Excelクラッシュ
3. 停電後の復旧

**実装**:

#### A. Windows起動時にExcel自動起動

**Windowsタスクスケジューラ設定**:
```xml
<Task>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
    </LogonTrigger>
  </Triggers>
  <Actions>
    <Exec>
      <Command>C:\Program Files\Microsoft Office\root\Office16\EXCEL.EXE</Command>
      <Arguments>C:\Kabuto\kabuto_auto_trader.xlsm</Arguments>
    </Exec>
  </Actions>
</Task>
```

#### B. ブック起動時の状態復旧

```vba
Private Sub Workbook_Open()
    ' 前回の状態を確認
    Dim lastStatus As String
    lastStatus = GetSystemState("system_status")

    If lastStatus = "Running" Then
        ' 前回稼働中だった場合は自動再開
        Debug.Print "Resuming auto trading (previous status: Running)"
        Call StartAutoTrading
    Else
        Debug.Print "Previous status: " & lastStatus & " - Manual start required"
    End If
End Sub
```

---

### 4.2 ハートビート監視

**サーバー側でExcel VBAの稼働状態を監視**

**VBA実装**:
```vba
Sub SendHeartbeat()
    '
    ' サーバーにハートビートを送信（60秒毎）
    '
    Dim http As Object
    Set http = CreateObject("MSXML2.XMLHTTP.6.0")

    Dim url As String
    url = GetConfig("API_BASE_URL") & "/heartbeat"

    Dim payload As String
    payload = "{""client_id"":""" & GetConfig("CLIENT_ID") & """,""timestamp"":""" & Format(Now, "yyyy-mm-ddThh:nn:ss+09:00") & """}"

    http.Open "POST", url, False
    http.setRequestHeader "Authorization", "Bearer " & GetConfig("API_KEY")
    http.setRequestHeader "Content-Type", "application/json"

    On Error Resume Next
    http.send payload
    On Error GoTo 0

    Set http = Nothing
End Sub

' PollAndProcessSignals内で呼び出し
Sub PollAndProcessSignals()
    ' ...

    ' 60秒毎にハートビート送信
    Static lastHeartbeat As Date
    If DateDiff("s", lastHeartbeat, Now) >= 60 Or lastHeartbeat = 0 Then
        Call SendHeartbeat
        lastHeartbeat = Now
    End If

    ' ...
End Sub
```

**サーバー側**: ハートビートが5分間途絶えたらアラート送信

---

### 4.3 自己診断機能

**定期的にシステム状態をチェック**

```vba
Sub SelfDiagnosis()
    '
    ' システム自己診断（1時間毎に実行）
    '
    Dim diagnosticResults As Collection
    Set diagnosticResults = New Collection

    ' 1. API接続チェック
    If CheckAPIConnection() Then
        diagnosticResults.Add "API: OK"
    Else
        diagnosticResults.Add "API: ERROR"
        Call LogError("DIAGNOSTIC", "SelfDiagnosis", "API connection failed", "", "WARNING")
    End If

    ' 2. RSS接続チェック
    If CheckRSSConnection() Then
        diagnosticResults.Add "RSS: OK"
    Else
        diagnosticResults.Add "RSS: ERROR"
        Call LogError("DIAGNOSTIC", "SelfDiagnosis", "RSS connection failed", "", "CRITICAL")
    End If

    ' 3. ポジション整合性チェック
    If ValidatePositionIntegrity() Then
        diagnosticResults.Add "Position: OK"
    Else
        diagnosticResults.Add "Position: MISMATCH"
        Call LogError("DIAGNOSTIC", "SelfDiagnosis", "Position mismatch detected", "", "ERROR")
    End If

    ' 4. ディスク容量チェック
    If CheckDiskSpace() Then
        diagnosticResults.Add "Disk: OK"
    Else
        diagnosticResults.Add "Disk: LOW"
        Call LogError("DIAGNOSTIC", "SelfDiagnosis", "Low disk space", "", "WARNING")
    End If

    Debug.Print "Self-diagnosis completed: " & Join(diagnosticResults.ToArray, ", ")
End Sub
```

---

## 5. まとめ

### 5.1 Excel ブック構成概要

**11シート構成**:
- **表示シート（6）**: Dashboard, SignalQueue, OrderHistory, ExecutionLog, ErrorLog, PositionManager
- **非表示シート（3）**: Config, MarketCalendar, BlacklistTickers
- **完全非表示シート（2）**: SystemState, RSSInterface

**8 VBAモジュール** + **2クラスモジュール** + **Workbookモジュール**

---

### 5.2 データフロー

```
1. サーバーポーリング（5秒毎）
   ↓
2. SignalQueue に追加
   ↓
3. リスクチェック（ブラックリスト、ポジション上限）
   ↓
4. RSS.ORDER() 実行
   ↓
5. OrderHistory に記録
   ↓
6. 約定確認ポーリング（RSS.STATUS）
   ↓
7. ExecutionLog + PositionManager 更新
   ↓
8. Dashboard リアルタイム表示
```

---

### 5.3 無人稼働チェックリスト

- [x] 自動起動（Windowsログオン時）
- [x] 自動復旧（前回状態から再開）
- [x] ハートビート監視（サーバー連携）
- [x] 自己診断（1時間毎）
- [x] エラーログ記録
- [x] 市場時間外は自動停止
- [x] ブラックリスト自動管理
- [x] ポジション上限チェック
- [x] アラート送信（重大エラー時）

---

### 5.4 次のステップ

1. **Excel ブック作成**
   - 11シートの作成
   - データ構造の設定
   - 数式の設定

2. **VBA実装**
   - 8モジュールのコード実装
   - JsonConverterライブラリ導入

3. **MarketSpeed II連携テスト**
   - RSS.ORDER() 動作確認
   - RSS.STATUS() ポーリングテスト
   - RSS.PRICE() 現在価格取得

4. **統合テスト**
   - サーバー → Excel → RSS の全体フロー
   - 自動復旧テスト
   - 24時間稼働テスト

5. **Windows VM設定**
   - タスクスケジューラ設定
   - 自動ログオン設定
   - スリープ無効化

---

**これで完全無人稼働可能なExcel自動売買システムの設計が完成しました。**
