Attribute VB_Name = "Module_Main_Simple"
'
' Kabuto Auto Trader - Simplified Main Module
' シンプルなポーリングループ（注文実行に特化）
'
' 変更点:
' - 5段階セーフティチェックは削除（Relay Serverで実行済み）
' - シグナル処理はRelay Serverで完結
' - Excel側はRSS注文実行のみ
'

Option Explicit

Public IsRunning As Boolean

' ========================================
' メインループ開始
' ========================================
Sub StartPolling()
    On Error GoTo ErrorHandler

    If IsRunning Then
        Debug.Print "Already running"
        Exit Sub
    End If

    IsRunning = True
    Debug.Print "=== Kabuto Auto Trader (Simplified) Started ==="
    Debug.Print "Excel VBA: Order Execution Only"
    Debug.Print "All validation done by Relay Server"

    ' ポーリングループ
    Do While IsRunning
        ' 1. Relay Serverから検証済みシグナルを取得
        Call PollAndExecuteSignals

        ' 2. 待機（5秒）
        Application.Wait Now + TimeValue("00:00:05")

        ' 処理を継続
        DoEvents
    Loop

    Debug.Print "=== Polling Stopped ==="
    Exit Sub

ErrorHandler:
    Debug.Print "Error in StartPolling: " & Err.Description
    IsRunning = False
End Sub

' ========================================
' ポーリング停止
' ========================================
Sub StopPolling()
    IsRunning = False
    Debug.Print "Stopping polling..."
End Sub

' ========================================
' シグナル取得と実行
' ========================================
Sub PollAndExecuteSignals()
    On Error Resume Next

    ' Relay Serverから検証済みシグナルを取得
    Dim signals As Collection
    Set signals = API_GetPendingSignals()

    If signals Is Nothing Then
        Exit Sub
    End If

    If signals.Count = 0 Then
        Exit Sub
    End If

    Debug.Print "Received " & signals.Count & " validated signal(s) from Relay Server"

    ' 各シグナルを処理
    Dim i As Integer
    For i = 1 To signals.Count
        Dim signal As Dictionary
        Set signal = signals(i)

        ' ACK送信
        Call API_AcknowledgeSignal(signal("signal_id"), signal("checksum"))

        ' 注文実行（Relay Serverで検証済み）
        Call ExecuteValidatedSignal(signal)
    Next i
End Sub

' ========================================
' 検証済みシグナルの実行
' ========================================
Sub ExecuteValidatedSignal(signal As Dictionary)
    '
    ' Relay Serverで5段階セーフティ検証済みのシグナルを実行
    ' Excel側では追加の検証なし
    '
    On Error GoTo ErrorHandler

    Debug.Print "=== Executing Validated Signal ==="
    Debug.Print "Signal ID: " & signal("signal_id")
    Debug.Print "Ticker: " & signal("ticker")
    Debug.Print "Action: " & signal("action")
    Debug.Print "Quantity: " & signal("quantity")

    ' RSS注文実行
    Dim orderId As String
    orderId = ExecuteRSSOrder(signal)

    If orderId <> "" Then
        ' 成功 - Relay Serverに報告
        Debug.Print "Order executed successfully: " & orderId

        ' 実行価格を取得（簡略化のため市場価格を使用）
        Dim executionPrice As Double
        executionPrice = signal("price")

        Call API_ReportExecution( _
            signal("signal_id"), _
            orderId, _
            executionPrice, _
            CLng(signal("quantity")) _
        )

        ' ローカルログ記録
        Call LogOrderSuccess(signal("signal_id"), signal("ticker"), signal("action"), orderId)
    Else
        ' 失敗 - Relay Serverに報告
        Debug.Print "Order execution failed"
        Call API_ReportFailure(signal("signal_id"), "RSS execution failed")

        ' ローカルログ記録
        Call LogOrderFailure(signal("signal_id"), signal("ticker"), signal("action"), "RSS execution failed")
    End If

    Exit Sub

ErrorHandler:
    Debug.Print "Error in ExecuteValidatedSignal: " & Err.Description
    Call API_ReportFailure(signal("signal_id"), "Exception: " & Err.Description)
    Call LogOrderFailure(signal("signal_id"), signal("ticker"), signal("action"), Err.Description)
End Sub

' ========================================
' RSS注文実行（RssStockOrder_v呼び出し）
' ========================================
Function ExecuteRSSOrder(signal As Dictionary) As String
    '
    ' MarketSpeed II RSS経由で注文実行
    '
    On Error GoTo ErrorHandler

    ' パラメータ構築
    Dim ticker As String
    Dim side As Integer
    Dim quantity As Long

    ticker = signal("ticker")
    side = IIf(signal("action") = "buy", 3, 1)  ' 3=現物買, 1=現物売
    quantity = CLng(signal("quantity"))

    ' 注文ID生成
    Dim orderId As String
    orderId = "ORD_" & Format(Now, "yyyymmddhhnnss") & "_" & Right("000000" & ticker, 6)

    ' RssStockOrder_v呼び出し
    Dim rssResult As Variant
    rssResult = Application.Run("RssStockOrder_v", _
        orderId, _
        ticker, _
        side, _
        0, _
        0, _
        quantity, _
        0, _
        0, _
        1, _
        "", _
        2, _
        0, _
        0, _
        0, _
        0, _
        0, _
        0, _
        0, _
        "")

    ' 結果判定
    If IsError(rssResult) Then
        Debug.Print "RssStockOrder_v returned Error"
        ExecuteRSSOrder = ""
        Exit Function
    End If

    If rssResult = 0 Then
        ' 成功
        ExecuteRSSOrder = orderId
    Else
        ' 失敗
        Debug.Print "RssStockOrder_v failed: " & CStr(rssResult)
        ExecuteRSSOrder = ""
    End If

    Exit Function

ErrorHandler:
    Debug.Print "Error in ExecuteRSSOrder: " & Err.Description
    ExecuteRSSOrder = ""
End Function

' ========================================
' ローカルログ記録（成功）
' ========================================
Sub LogOrderSuccess(signalId As String, ticker As String, action As String, orderId As String)
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("OrderLog")

    Dim nextRow As Long
    nextRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    ws.Cells(nextRow, 1).Value = Now
    ws.Cells(nextRow, 2).Value = signalId
    ws.Cells(nextRow, 3).Value = ticker
    ws.Cells(nextRow, 4).Value = action
    ws.Cells(nextRow, 5).Value = orderId
    ws.Cells(nextRow, 6).Value = "SUCCESS"
End Sub

' ========================================
' ローカルログ記録（失敗）
' ========================================
Sub LogOrderFailure(signalId As String, ticker As String, action As String, reason As String)
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("OrderLog")

    Dim nextRow As Long
    nextRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    ws.Cells(nextRow, 1).Value = Now
    ws.Cells(nextRow, 2).Value = signalId
    ws.Cells(nextRow, 3).Value = ticker
    ws.Cells(nextRow, 4).Value = action
    ws.Cells(nextRow, 5).Value = ""
    ws.Cells(nextRow, 6).Value = "FAILED"
    ws.Cells(nextRow, 7).Value = reason
End Sub
