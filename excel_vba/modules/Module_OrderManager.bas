Attribute VB_Name = "Module_OrderManager"
'
' Kabuto Auto Trader - Order Manager Module
' 注文管理とポジション管理
'

Option Explicit

' ========================================
' 注文を履歴に記録
' ========================================
Function RecordOrder(signal As Object, rssOrderId As String, status As String) As String
    On Error GoTo ErrorHandler

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
    ws.Cells(lastRow, 8).Value = ""  ' limit_price (成行なので空白)
    ws.Cells(lastRow, 9).Value = rssOrderId
    ws.Cells(lastRow, 10).Value = status

    RecordOrder = internalId

    Debug.Print "Order recorded: " & internalId & " RSS_ID=" & rssOrderId

    Exit Function

ErrorHandler:
    Debug.Print "Error in RecordOrder: " & Err.Description
    RecordOrder = ""
End Function

' ========================================
' 注文状態を更新
' ========================================
Sub UpdateOrderStatus(internalId As String, status As String, Optional filledPrice As Double = 0, Optional filledQty As Long = 0, Optional commission As Double = 0)
    On Error GoTo ErrorHandler

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("OrderHistory")

    Dim foundCell As Range
    Set foundCell = ws.Columns(1).Find(internalId, LookIn:=xlValues, LookAt:=xlWhole)

    If Not foundCell Is Nothing Then
        Dim rowNum As Long
        rowNum = foundCell.Row

        ws.Cells(rowNum, 10).Value = status  ' J列: status

        If filledPrice > 0 Then
            ws.Cells(rowNum, 11).Value = filledPrice     ' K列: filled_price
            ws.Cells(rowNum, 12).Value = filledQty       ' L列: filled_quantity
            ws.Cells(rowNum, 13).Value = commission      ' M列: commission
            ws.Cells(rowNum, 14).Value = Now             ' N列: execution_time
        End If

        Debug.Print "Order status updated: " & internalId & " -> " & status
    End If

    Exit Sub

ErrorHandler:
    Debug.Print "Error in UpdateOrderStatus: " & Err.Description
End Sub

' ========================================
' 約定を ExecutionLog に記録
' ========================================
Sub RecordExecution(orderInternalId As String)
    On Error GoTo ErrorHandler

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
    Dim quantity As Long
    Dim price As Double
    Dim commission As Double
    Dim execTime As Date
    Dim signalId As String

    action = wsOrder.Cells(orderRow, 4).Value
    ticker = wsOrder.Cells(orderRow, 5).Value
    quantity = wsOrder.Cells(orderRow, 12).Value
    price = wsOrder.Cells(orderRow, 11).Value
    commission = wsOrder.Cells(orderRow, 13).Value
    execTime = wsOrder.Cells(orderRow, 14).Value
    signalId = wsOrder.Cells(orderRow, 3).Value

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
        wsExec.Cells(lastRow, 10).Value = "open"  ' position_effect
    Else
        totalAmount = price * quantity - commission
        wsExec.Cells(lastRow, 10).Value = "close"

        ' 実現損益計算
        Dim pnl As Double
        pnl = CalculateRealizedPnL(ticker, quantity, price, commission)
        wsExec.Cells(lastRow, 11).Value = pnl  ' realized_pnl
    End If

    wsExec.Cells(lastRow, 9).Value = totalAmount

    ' ポジション管理を更新
    Call UpdatePosition(ticker, action, quantity, price)

    ' サーバーに執行報告
    Dim rssOrderId As String
    rssOrderId = wsOrder.Cells(orderRow, 9).Value
    Call ReportExecution(signalId, rssOrderId, price, quantity)

    Debug.Print "Execution recorded: " & execId

    Exit Sub

ErrorHandler:
    Debug.Print "Error in RecordExecution: " & Err.Description
End Sub

' ========================================
' ポジション更新
' ========================================
Sub UpdatePosition(ticker As String, action As String, quantity As Long, price As Double)
    On Error GoTo ErrorHandler

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
            ws.Cells(lastRow, 2).Value = GetTickerName(ticker)
            ws.Cells(lastRow, 3).Value = quantity
            ws.Cells(lastRow, 4).Value = price
            ws.Cells(lastRow, 5).Value = price  ' current_price (初期値)
            ws.Cells(lastRow, 11).Value = Date  ' entry_date
        Else
            ' 既存ポジションに追加
            Dim posRow As Long
            posRow = foundCell.Row

            Dim currentQty As Long
            Dim currentAvgCost As Double

            currentQty = ws.Cells(posRow, 3).Value
            currentAvgCost = ws.Cells(posRow, 4).Value

            ' 平均取得単価再計算
            Dim newAvgCost As Double
            newAvgCost = ((currentAvgCost * currentQty) + (price * quantity)) / (currentQty + quantity)

            ws.Cells(posRow, 3).Value = currentQty + quantity
            ws.Cells(posRow, 4).Value = newAvgCost
        End If
    ElseIf action = "sell" Then
        If Not foundCell Is Nothing Then
            Dim posRow As Long
            posRow = foundCell.Row

            Dim currentQty As Long
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

    Exit Sub

ErrorHandler:
    Debug.Print "Error in UpdatePosition: " & Err.Description
End Sub

' ========================================
' 現在価格を更新
' ========================================
Sub UpdateCurrentPrices()
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("PositionManager")

    Dim i As Long
    For i = 2 To ws.Cells(ws.Rows.Count, 1).End(xlUp).Row
        Dim ticker As String
        ticker = ws.Cells(i, 1).Value

        If ticker <> "" Then
            Dim currentPrice As Double
            currentPrice = GetCurrentPrice(ticker)

            If currentPrice > 0 Then
                ws.Cells(i, 5).Value = currentPrice  ' E列: current_price
            End If
        End If
    Next i

    Debug.Print "Current prices updated"
End Sub

' ========================================
' 実現損益計算
' ========================================
Function CalculateRealizedPnL(ticker As String, sellQty As Long, sellPrice As Double, commission As Double) As Double
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("PositionManager")

    ' 該当銘柄の平均取得単価を取得
    Dim foundCell As Range
    Set foundCell = ws.Columns(1).Find(ticker, LookIn:=xlValues)

    If foundCell Is Nothing Then
        CalculateRealizedPnL = 0
        Exit Function
    End If

    Dim avgCost As Double
    avgCost = ws.Cells(foundCell.Row, 4).Value  ' D列: avg_cost

    ' 損益 = (売却価格 - 平均取得単価) × 数量 - 手数料
    CalculateRealizedPnL = (sellPrice - avgCost) * sellQty - commission
End Function
