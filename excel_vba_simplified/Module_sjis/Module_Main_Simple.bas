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
Private NextScheduledTime As Date
Private StartTime As Date
Private LastSignalTime As Date
Private SignalCount As Long
Private SuccessCount As Long
Private FailureCount As Long

' ========================================
' メインループ開始（非同期版）
' ========================================
Sub StartPolling()
    On Error GoTo ErrorHandler

    If IsRunning Then
        Call LogWarning("Already running")
        Exit Sub
    End If

    IsRunning = True
    StartTime = Now
    SignalCount = 0
    SuccessCount = 0
    FailureCount = 0
    LastSignalTime = 0

    Call LogSectionStart("Kabuto Auto Trader (Simplified) Started")
    Call LogInfo("Excel VBA: Order Execution Only")
    Call LogInfo("All validation done by Relay Server")
    Call LogInfo("Async mode: Excel remains responsive during execution")

    ' ステータスダッシュボードを初期化
    Call InitializeStatusDashboard
    Call UpdateStatusDashboard

    ' 最初のポーリングをスケジュール（即座に実行）
    Call ScheduleNextPoll

    Exit Sub

ErrorHandler:
    Call LogError("Error in StartPolling: " & Err.Description)
    IsRunning = False
    Call UpdateStatusDisplay("エラー", RGB(255, 182, 193))
End Sub

' ========================================
' ポーリング停止
' ========================================
Sub StopPolling()
    On Error Resume Next

    IsRunning = False
    Call LogInfo("Stopping polling...")

    ' スケジュールされた次回のポーリングをキャンセル
    If NextScheduledTime <> 0 Then
        Application.OnTime NextScheduledTime, "ScheduledPoll", , False
        NextScheduledTime = 0
    End If

    ' ステータスダッシュボードを更新
    Call UpdateStatusDashboard

    Call LogSectionEnd
End Sub

' ========================================
' 次回ポーリングをスケジュール
' ========================================
Private Sub ScheduleNextPoll()
    On Error Resume Next

    If Not IsRunning Then Exit Sub

    ' 5秒後にScheduledPollを実行
    NextScheduledTime = Now + TimeValue("00:00:05")
    Application.OnTime NextScheduledTime, "ScheduledPoll"
End Sub

' ========================================
' スケジュールされたポーリング実行
' ========================================
Sub ScheduledPoll()
    On Error GoTo ErrorHandler

    ' 停止フラグが立っていたら終了
    If Not IsRunning Then
        Call LogInfo("Polling stopped by flag")
        Exit Sub
    End If

    ' ステータスダッシュボードを更新（時刻更新）
    Call UpdateStatusDashboard

    ' シグナルを取得して実行
    Call PollAndExecuteSignals

    ' 次回のポーリングをスケジュール
    Call ScheduleNextPoll

    Exit Sub

ErrorHandler:
    Call LogError("Error in ScheduledPoll: " & Err.Description)
    ' エラーが発生しても継続する
    Call ScheduleNextPoll
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

    Call LogInfo("Received " & signals.Count & " validated signal(s) from Relay Server")

    ' 各シグナルを処理
    Dim i As Integer
    For i = 1 To signals.Count
        Dim signal As Object
        Set signal = signals(i)

        ' カウンターを更新
        SignalCount = SignalCount + 1
        LastSignalTime = Now

        ' ACK送信
        Call API_AcknowledgeSignal(signal("signal_id"), signal("checksum"))

        ' 注文実行（Relay Serverで検証済み）
        Call ExecuteValidatedSignal(signal)
    Next i
End Sub

' ========================================
' 検証済みシグナルの実行
' ========================================
Sub ExecuteValidatedSignal(signal As Object)
    '
    ' Relay Serverで5段階セーフティ検証済みのシグナルを実行
    ' Excel側では追加の検証なし
    '
    On Error GoTo ErrorHandler

    Call LogSectionStart("Executing Validated Signal")
    Call LogInfo("Signal ID: " & signal("signal_id"))
    Call LogInfo("Ticker: " & signal("ticker"))
    Call LogInfo("Action: " & signal("action"))
    Call LogInfo("Quantity: " & signal("quantity"))

    ' RSS注文実行
    Dim orderId As String
    orderId = ExecuteRSSOrder(signal)

    If orderId <> "" Then
        ' 成功 - Relay Serverに報告
        Call LogSuccess("Order executed successfully: " & orderId)
        SuccessCount = SuccessCount + 1

        ' 実行価格を取得（entry_priceを使用）
        Dim executionPrice As Double
        executionPrice = CDbl(signal("entry_price"))

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
        Call LogError("Order execution failed")
        FailureCount = FailureCount + 1

        Call API_ReportFailure(signal("signal_id"), "RSS execution failed")

        ' ローカルログ記録
        Call LogOrderFailure(signal("signal_id"), signal("ticker"), signal("action"), "RSS execution failed")
    End If

    Exit Sub

ErrorHandler:
    Call LogError("Error in ExecuteValidatedSignal: " & Err.Description)
    Call API_ReportFailure(signal("signal_id"), "Exception: " & Err.Description)
    Call LogOrderFailure(signal("signal_id"), signal("ticker"), signal("action"), Err.Description)
End Sub

' ========================================
' RSS注文実行（RssStockOrder_v呼び出し）
' ========================================
Function ExecuteRSSOrder(signal As Object) As String
    '
    ' MarketSpeed II RSS経由で注文実行
    '
    On Error GoTo ErrorHandler

    ' パラメータ構築
    Dim ticker As String
    Dim side As Integer
    Dim quantity As Long

    Call LogDebug("Parsing ticker...")
    ticker = CStr(signal("ticker"))
    Call LogDebug("Ticker: " & ticker)

    ' actionを明示的に文字列として取得
    Call LogDebug("Parsing action...")
    Dim action As String
    action = LCase(CStr(signal("action")))
    Call LogDebug("Action: " & action)

    If action = "buy" Then
        side = 3  ' 現物買
    Else
        side = 1  ' 現物売
    End If
    Call LogDebug("Side: " & side)

    Call LogDebug("Parsing quantity...")
    quantity = CLng(signal("quantity"))
    Call LogDebug("Quantity: " & quantity)

    ' 注文ID生成
    Dim orderId As String
    orderId = "ORD_" & Format(Now, "yyyymmddhhnnss") & "_" & Right("000000" & ticker, 6)
    Call LogDebug("Order ID: " & orderId)

    ' RssStockOrder_v呼び出し
    Call LogDebug("Calling RssStockOrder_v...")
    Call LogDebug("Parameters: orderId=" & orderId & ", ticker=" & ticker & ", side=" & side & ", quantity=" & quantity)

    ' テストモード確認
    Dim testMode As String
    testMode = GetConfig("TEST_MODE")

    Dim rssResult As Variant

    If UCase(testMode) = "TRUE" Then
        ' テストモード: モック実行
        Call LogInfo("TEST MODE: Simulating RssStockOrder_v call")
        rssResult = 0  ' 成功を返す
    Else
        ' 本番モード: 実際のRSS呼び出し
        ' tickerをLong型に変換（日本の証券コードは数値）

        Dim orderIdNum As Long

        orderIdNum = CLng(DateDiff("s", DateSerial(2020, 1, 1), Now))



        Dim sideCode As String

        sideCode = CStr(side)



        Dim orderType As String

        Dim stopLoss As Double
        Dim takeProfit As Double

        stopLoss = 0
        takeProfit = 0

        On Error Resume Next
        stopLoss = CDbl(signal("stop_loss"))
        takeProfit = CDbl(signal("take_profit"))
        On Error GoTo ErrorHandler

        If stopLoss > 0 Or takeProfit > 0 Then
            If stopLoss > 0 And takeProfit > 0 Then
                orderType = "1"
            Else
                Call LogError("ExecuteRSSOrder: stop_loss and take_profit must both be set for set order")
                ExecuteRSSOrder = ""
                Exit Function
            End If
        Else
            orderType = "0"
        End If

        Dim sorType As String

        sorType = "0"


        Dim priceType As String

        priceType = "1"

        Dim orderPrice As Double
        orderPrice = CDbl(signal("entry_price"))



        Dim execCondition As String

        execCondition = "1"



        Dim orderExpiry As String

        orderExpiry = ""



        Dim accountType As String

        accountType = "2"



        Dim reverseConditionPrice As Variant
        Dim reverseConditionType As Variant
        Dim reversePriceType As Variant
        Dim reversePrice As Variant

        Dim setOrderType As String
        Dim setOrderPrice As Variant
        Dim setExecutionCondition As String
        Dim setOrderExpiry As String

        reverseConditionPrice = ""
        reverseConditionType = ""
        reversePriceType = ""
        reversePrice = ""
        setOrderType = "0"
        setOrderPrice = ""
        setExecutionCondition = "0"
        setOrderExpiry = ""

        If orderType = "1" Then
            reverseConditionPrice = stopLoss
            If side = 3 Then
                reverseConditionType = "2"
            Else
                reverseConditionType = "1"
            End If
            reversePriceType = "1"
            reversePrice = stopLoss

            setOrderType = "1"
            setOrderPrice = takeProfit
            setExecutionCondition = execCondition
        End If



        Call LogDebug("RssStockOrder_v params: " & _
            "orderIdNum=" & CStr(orderIdNum) & _
            ", ticker=" & CStr(ticker) & _
            ", side=" & CStr(sideCode) & _
            ", orderType=" & CStr(orderType) & _
            ", sorType=" & CStr(sorType) & _
            ", quantity=" & CStr(quantity) & _
            ", priceType=" & CStr(priceType) & _
            ", price=" & CStr(orderPrice) & _
            ", execCondition=" & CStr(execCondition) & _
            ", orderExpiry=" & CStr(orderExpiry) & _
            ", accountType=" & CStr(accountType) & _
            ", reverseConditionPrice=" & CStr(reverseConditionPrice) & _
            ", reverseConditionType=" & CStr(reverseConditionType) & _
            ", reversePriceType=" & CStr(reversePriceType) & _
            ", reversePrice=" & CStr(reversePrice) & _
            ", setOrderType=" & CStr(setOrderType) & _
            ", setOrderPrice=" & CStr(setOrderPrice) & _
            ", setExecutionCondition=" & CStr(setExecutionCondition) & _
            ", setOrderExpiry=" & CStr(setOrderExpiry))

        rssResult = Application.Run("RssStockOrder_v", _
            orderIdNum, _
            ticker, _
            sideCode, _
            orderType, _
            sorType, _
            quantity, _
            priceType, _
            orderPrice, _
            execCondition, _
            orderExpiry, _
            accountType, _
            reverseConditionPrice, _
            reverseConditionType, _
            reversePriceType, _
            reversePrice, _
            setOrderType, _
            setOrderPrice, _
            setExecutionCondition, _
            setOrderExpiry)

    End If

    ' 結果判定
    Call LogDebug("RssStockOrder_v completed, checking result...")

    If IsError(rssResult) Then
        Call LogError("RssStockOrder_v returned Error")
        ExecuteRSSOrder = ""
        Exit Function
    End If

    Call LogDebug("Result value: " & rssResult)

    If rssResult = 0 Then
        ' 成功
        Call LogSuccess("RssStockOrder_v succeeded")
        ExecuteRSSOrder = orderId
    Else
        ' 失敗
        Call LogError("RssStockOrder_v failed with code: " & CStr(rssResult))
        ExecuteRSSOrder = ""
    End If

    Exit Function

ErrorHandler:
    Call LogError("Error in ExecuteRSSOrder: " & Err.Description & " (Number: " & Err.Number & ")")
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

' ========================================
' ステータスダッシュボード初期化
' ========================================
Sub InitializeStatusDashboard()
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets(1)

    ' ヘッダー設定
    With ws.Range("A1:B1")
        .Merge
        .Value = "Kabuto Auto Trader - Status"
        .Font.Bold = True
        .Font.Size = 16
        .HorizontalAlignment = xlCenter
        .Interior.Color = RGB(70, 130, 180)
        .Font.Color = RGB(255, 255, 255)
    End With

    ' ラベル
    ws.Range("A3").Value = "Status:"
    ws.Range("A4").Value = "Current Time:"
    ws.Range("A5").Value = "Start Time:"
    ws.Range("A6").Value = "Running Time:"
    ws.Range("A7").Value = "Last Signal:"
    ws.Range("A8").Value = "Total Signals:"
    ws.Range("A9").Value = "Success:"
    ws.Range("A10").Value = "Failed:"
    ws.Range("A11").Value = "Success Rate:"

    ' ラベルのスタイル
    With ws.Range("A3:A11")
        .Font.Bold = True
        .HorizontalAlignment = xlRight
    End With

    ' 列幅調整
    ws.Columns("A:A").ColumnWidth = 15
    ws.Columns("B:B").ColumnWidth = 25
End Sub

' ========================================
' ステータスダッシュボード更新
' ========================================
Sub UpdateStatusDashboard()
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets(1)

    ' Status
    If IsRunning Then
        ws.Range("B3").Value = "Running"
        ws.Range("B3").Interior.Color = RGB(144, 238, 144)
        ws.Range("B3").Font.Color = RGB(0, 100, 0)
    Else
        ws.Range("B3").Value = "Stopped"
        ws.Range("B3").Interior.Color = RGB(211, 211, 211)
        ws.Range("B3").Font.Color = RGB(128, 128, 128)
    End If

    With ws.Range("B3")
        .Font.Bold = True
        .Font.Size = 12
        .HorizontalAlignment = xlCenter
    End With

    ' Current Time (実行中のみ更新)
    If IsRunning Then
        ws.Range("B4").Value = Format(Now, "yyyy-mm-dd hh:nn:ss")
    End If

    ' Start Time
    If StartTime > 0 Then
        ws.Range("B5").Value = Format(StartTime, "yyyy-mm-dd hh:nn:ss")
    Else
        ws.Range("B5").Value = "-"
    End If

    ' Running Time
    If IsRunning And StartTime > 0 Then
        Dim elapsed As Double
        elapsed = (Now - StartTime) * 24 * 60 ' 分単位
        Dim hours As Long, minutes As Long
        hours = Int(elapsed / 60)
        minutes = elapsed Mod 60
        ws.Range("B6").Value = hours & "h " & minutes & "m"
    Else
        ws.Range("B6").Value = "-"
    End If

    ' Last Signal
    If LastSignalTime > 0 Then
        ws.Range("B7").Value = Format(LastSignalTime, "yyyy-mm-dd hh:nn:ss")
    Else
        ws.Range("B7").Value = "-"
    End If

    ' Total Signals
    ws.Range("B8").Value = SignalCount

    ' Success
    ws.Range("B9").Value = SuccessCount
    ws.Range("B9").Interior.Color = RGB(198, 239, 206)

    ' Failed
    ws.Range("B10").Value = FailureCount
    If FailureCount > 0 Then
        ws.Range("B10").Interior.Color = RGB(255, 199, 206)
    Else
        ws.Range("B10").Interior.Color = xlNone
    End If

    ' Success Rate
    If SignalCount > 0 Then
        Dim successRate As Double
        successRate = (SuccessCount / SignalCount) * 100
        ws.Range("B11").Value = Format(successRate, "0.0") & "%"

        If successRate >= 90 Then
            ws.Range("B11").Interior.Color = RGB(198, 239, 206)
        ElseIf successRate >= 70 Then
            ws.Range("B11").Interior.Color = RGB(255, 235, 156)
        Else
            ws.Range("B11").Interior.Color = RGB(255, 199, 206)
        End If
    Else
        ws.Range("B11").Value = "-"
        ws.Range("B11").Interior.Color = xlNone
    End If
End Sub

' ========================================
' ???????????????????
' ========================================
Sub UpdateStatusDisplay(statusText As String, backColor As Long)
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("Dashboard")

    With ws.Range("B3")
        .Value = statusText
        .Interior.Color = backColor
        .Font.Color = RGB(128, 0, 0)
        .Font.Bold = True
        .Font.Size = 12
        .HorizontalAlignment = xlCenter
    End With
End Sub
