Attribute VB_Name = "Module_Main_Simple"
'
' Kabuto Auto Trader - Simplified Main Module
' シンプルなポ???リングループ（注??実行に特化??
'
' 変更点:
' - 5段階セーフティチェ??クは削除???Relay Serverで実行済み???
' - シグナル処??はRelay Serverで完??
' - Excel側はRSS注??実行???み
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
' メインループ開始（非同期???
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

    ' ス?ータスダ?シュ???ドを初期?
    Call InitializeStatusDashboard
    Call UpdateStatusDashboard

    ' 最??????リングをスケジュール?即座に実???
    Call ScheduleNextPoll

    Exit Sub

ErrorHandler:
    Call LogError("Error in StartPolling: " & Err.Description)
    IsRunning = False
    Call UpdateStatusDisplay("エラー", RGB(255, 182, 193))
End Sub

' ========================================
' ???リング停止
' ========================================
Sub StopPolling()
    On Error Resume Next

    IsRunning = False
    Call LogInfo("Stopping polling...")

    ' スケジュールされた次??????リングをキャンセル
    If NextScheduledTime <> 0 Then
        Application.OnTime NextScheduledTime, "ScheduledPoll", , False
        NextScheduledTime = 0
    End If

    ' ス?ータスダ?シュ???ドを更新
    Call UpdateStatusDashboard

    Call LogSectionEnd
End Sub

' ========================================
' 次????リングをスケジュール
' ========================================
Private Sub ScheduleNextPoll()
    On Error Resume Next

    If Not IsRunning Then Exit Sub

    ' 5秒後にScheduledPollを???
    NextScheduledTime = Now + TimeValue("00:00:05")
    Application.OnTime NextScheduledTime, "ScheduledPoll"
End Sub

' ========================================
' スケジュールされ????リング???
' ========================================
Sub ScheduledPoll()
    On Error GoTo ErrorHandler

    ' 停止フラグが立って?たら???
    If Not IsRunning Then
        Call LogInfo("Polling stopped by flag")
        Exit Sub
    End If

    ' ス?ータスダ?シュ???ドを更新?時刻更新??
    Call UpdateStatusDashboard

    ' シグナルを取得して???
    Call PollAndExecuteSignals

    ' 次??????リングをスケジュール
    Call ScheduleNextPoll

    Exit Sub

ErrorHandler:
    Call LogError("Error in ScheduledPoll: " & Err.Description)
    ' エラーが発生しても継続す?
    Call ScheduleNextPoll
End Sub

' ========================================
' シグナル取得と???
' ========================================
Sub PollAndExecuteSignals()
    On Error Resume Next

    ' Relay Serverから検証済みシグナルを取?
    Dim signals As Collection
    Set signals = API_GetPendingSignals()

    If signals Is Nothing Then
        Exit Sub
    End If

    If signals.Count = 0 Then
        Exit Sub
    End If

    Call LogInfo("Received " & signals.Count & " validated signal(s) from Relay Server")

    ' ?シグナル????
    Dim i As Integer
    For i = 1 To signals.Count
        Dim signal As Object
        Set signal = signals(i)

        ' カウンターを更新
        SignalCount = SignalCount + 1
        LastSignalTime = Now

        ' ACK送信
        Call API_AcknowledgeSignal(signal("signal_id"), signal("checksum"))

        ' 注?実???Relay Serverで検証済み??
        Call ExecuteValidatedSignal(signal)
    Next i
End Sub

' ========================================
' 検証済みシグナルの???
' ========================================
Sub ExecuteValidatedSignal(signal As Object)
    '
    ' Relay Serverで5段階セーフティ検証済みのシグナルを???
    ' Excel側では追?の検証な?
    '
    On Error GoTo ErrorHandler

    Call LogSectionStart("Executing Validated Signal")
    Call LogInfo("Signal ID: " & signal("signal_id"))
    Call LogInfo("Ticker: " & signal("ticker"))
    Call LogInfo("Action: " & signal("action"))
    Call LogInfo("Quantity: " & signal("quantity"))

    Dim logPrice As Variant
    Dim logReverseConditionPrice As Variant
    Dim logReversePrice As Variant
    Dim logQuantity As Variant

    On Error Resume Next
    logPrice = signal("entry_price")
    logReverseConditionPrice = signal("stop_loss")
    logReversePrice = signal("stop_loss")
    logQuantity = signal("quantity")
    On Error GoTo ErrorHandler

    ' RSS注????
    Dim orderId As String
    orderId = ExecuteRSSOrder(signal)

    If orderId <> "" Then
        ' 成功 - Relay Serverに報?
        Call LogSuccess("Order executed successfully: " & orderId)
        SuccessCount = SuccessCount + 1

        ' 実行価格を取???entry_priceを使用??
        Dim executionPrice As Double
        executionPrice = CDbl(signal("entry_price"))

        Call API_ReportExecution( _
            signal("signal_id"), _
            orderId, _
            executionPrice, _
            CLng(signal("quantity")) _
        )

        ' ローカルログ記録
        Call LogOrderSuccess(signal("signal_id"), signal("ticker"), signal("action"), orderId, logPrice, logReverseConditionPrice, logReversePrice, logQuantity)
    Else
        ' 失? - Relay Serverに報?
        Call LogError("Order execution failed")
        FailureCount = FailureCount + 1

        Call API_ReportFailure(signal("signal_id"), "RSS execution failed")

        ' ローカルログ記録
        Call LogOrderFailure(signal("signal_id"), signal("ticker"), signal("action"), "RSS execution failed", logPrice, logReverseConditionPrice, logReversePrice, logQuantity)
    End If

    Exit Sub

ErrorHandler:
    Call LogError("Error in ExecuteValidatedSignal: " & Err.Description)
    Call API_ReportFailure(signal("signal_id"), "Exception: " & Err.Description)
    Call LogOrderFailure(signal("signal_id"), signal("ticker"), signal("action"), Err.Description, logPrice, logReverseConditionPrice, logReversePrice, logQuantity)
End Sub

' ========================================
' RSS注?実???RssStockOrder_v呼び出???
' ========================================
Function ExecuteRSSOrder(signal As Object) As String
    '
    ' MarketSpeed II RSS経由で注????
    '
    On Error GoTo ErrorHandler

    ' パラメータ???
    Dim ticker As String
    Dim side As Integer
    Dim quantity As Long

    Call LogDebug("Parsing ticker...")
    ticker = CStr(signal("ticker"))
    Call LogDebug("Ticker: " & ticker)

    ' action???示?に????として???
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

    ' 注文ID????
    Dim orderId As String
    orderId = "ORD_" & Format(Now, "yyyymmddhhnnss") & "_" & Right("000000" & ticker, 6)
    Call LogDebug("Order ID: " & orderId)

    ' RssStockOrder_v呼び出?
    Call LogDebug("Calling RssStockOrder_v...")
    Call LogDebug("Parameters: orderId=" & orderId & ", ticker=" & ticker & ", side=" & side & ", quantity=" & quantity)

    ' ?ストモード確?
    Dim testMode As String
    testMode = GetConfig("TEST_MODE")

    Dim rssResult As Variant

    If UCase(testMode) = "TRUE" Then
        ' ?ストモー?: モ?ク???
        Call LogInfo("TEST MODE: Simulating RssStockOrder_v call")
        rssResult = 0  ' 成功を返す
    Else
        ' 本番モー?: 実際のRSS呼び出?
        ' tickerをLong型に変換?日本の証券コー???数値??

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

        orderType = "1"

        Dim sorType As String

        sorType = "0"


        ' 価格タイプ???判定??"market" なら???行、それ以外?????値???
        Dim priceType As String
        Dim priceStr As String
        priceStr = LCase(CStr(signal("price")))

        If priceStr = "market" Then
            priceType = "1"  ' ??値
        Else
            priceType = "0"  ' 成??
        End If
        Call LogDebug("Price Type: " & priceType & " (" & priceStr & ")")

        Dim orderPrice As Double
        If priceType = "0" Then
            ' 成行???場合???価格??0に設??
            orderPrice = 0
        Else
            ' ??値の場合???entry_priceを使用
            orderPrice = CDbl(signal("entry_price"))
        End If
        Call LogDebug("Order Price: " & orderPrice)



        ' 実行条件をConfigシートから取得（デフォル??: "1" = 無条件???
        Dim execCondition As String
        execCondition = GetConfig("EXEC_CONDITION")
        If execCondition = "" Then
            execCondition = "1"  ' ??フォル??: 無条件
        End If
        Call LogDebug("Exec Condition: " & execCondition)

        Dim orderExpiry As String
        orderExpiry = ""

        ' 口座区??をConfigシートから取得（デフォル??: "2" = 特定口座???
        Dim accountType As String
        accountType = GetConfig("ACCOUNT_TYPE")
        If accountType = "" Then
            accountType = "2"  ' ??フォル??: 特定口座
        End If
        Call LogDebug("Account Type: " & accountType)



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
        setExecutionCondition = ""
        setOrderExpiry = ""

        If stopLoss > 0 Then
            reverseConditionPrice = stopLoss
            If side = 3 Then
                reverseConditionType = "2"
            Else
                reverseConditionType = "1"
            End If
            reversePriceType = "0"
            reversePrice = ""
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
            
        Dim excelFormulaCall As String
        excelFormulaCall = "=RssStockOrder_v(" & _
            CStr(orderIdNum) & ", " & _
            """" & ticker & """, " & _
            """" & sideCode & """, " & _
            """" & orderType & """, " & _
            """" & sorType & """, " & _
            CStr(quantity) & ", " & _
            """" & priceType & """, " & _
            CStr(orderPrice) & ", " & _
            """" & execCondition & """, " & _
            """" & orderExpiry & """, " & _
            """" & accountType & """, " & _
            IIf(reverseConditionPrice = "", "", CStr(reverseConditionPrice)) & ", " & _
            """" & reverseConditionType & """, " & _
            """" & reversePriceType & """, " & _
            IIf(reversePrice = "", "", CStr(reversePrice)) & ", " & _
            """" & setOrderType & """, " & _
            IIf(setOrderPrice = "", "", CStr(setOrderPrice)) & ", " & _
            """" & setExecutionCondition & """, " & _
            """" & setOrderExpiry & """)"
        Call LogDebug(excelFormulaCall)
        
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

    ' 結果判?
    Call LogDebug("RssStockOrder_v completed, checking result...")

    If IsError(rssResult) Then
        Call LogError("RssStockOrder_v returned Error")
        ExecuteRSSOrder = ""
        Exit Function
    End If

    Call LogDebug("Result value: " & CStr(rssResult))

    If rssResult = 0 Then
        ' 成功
        Call LogSuccess("RssStockOrder_v succeeded")
        If takeProfit > 0 Then
            Call LogInfo("Waiting 5 seconds before take-profit order...")
            Application.Wait Now + TimeValue("00:00:05")

            Dim profitOrderIdNum As Long
            profitOrderIdNum = CLng(DateDiff("s", DateSerial(2020, 1, 1), Now))

            Dim profitSideCode As String
            If side = 3 Then
                profitSideCode = "1"
            Else
                profitSideCode = "3"
            End If

            Dim profitOrderType As String
            profitOrderType = "0"

            Dim profitPriceType As String
            profitPriceType = "0"

            Dim profitOrderPrice As Double
            profitOrderPrice = takeProfit

            Dim profitReverseConditionPrice As Variant
            Dim profitReverseConditionType As Variant
            Dim profitReversePriceType As Variant
            Dim profitReversePrice As Variant

            Dim profitSetOrderType As String
            Dim profitSetOrderPrice As Variant
            Dim profitSetExecutionCondition As String
            Dim profitSetOrderExpiry As String

            profitReverseConditionPrice = ""
            profitReverseConditionType = ""
            profitReversePriceType = ""
            profitReversePrice = ""
            profitSetOrderType = "0"
            profitSetOrderPrice = ""
            profitsetExecutionCondition = ""
            profitSetOrderExpiry = ""

            Call LogDebug("RssStockOrder_v take-profit params: " & _
                "orderIdNum=" & CStr(profitOrderIdNum) & _
                ", ticker=" & CStr(ticker) & _
                ", side=" & CStr(profitSideCode) & _
                ", orderType=" & CStr(profitOrderType) & _
                ", sorType=" & CStr(sorType) & _
                ", quantity=" & CStr(quantity) & _
                ", priceType=" & CStr(profitPriceType) & _
                ", price=" & CStr(profitOrderPrice) & _
                ", execCondition=" & CStr(execCondition) & _
                ", orderExpiry=" & CStr(orderExpiry) & _
                ", accountType=" & CStr(accountType))

            Dim profitResult As Variant
            profitResult = Application.Run("RssStockOrder_v", _
                profitOrderIdNum, _
                ticker, _
                profitSideCode, _
                profitOrderType, _
                sorType, _
                quantity, _
                profitPriceType, _
                profitOrderPrice, _
                execCondition, _
                orderExpiry, _
                accountType, _
                profitReverseConditionPrice, _
                profitReverseConditionType, _
                profitReversePriceType, _
                profitReversePrice, _
                profitSetOrderType, _
                profitSetOrderPrice, _
                profitSetExecutionCondition, _
                profitSetOrderExpiry)

            If IsError(profitResult) Then
                Call LogError("RssStockOrder_v take-profit returned Error")
            ElseIf profitResult = 0 Then
                Call LogSuccess("RssStockOrder_v take-profit succeeded")
            Else
                Call LogError("RssStockOrder_v take-profit failed with code: " & CStr(profitResult))
            End If
        End If
        ExecuteRSSOrder = orderId
    Else
        ' 失?
        Call LogError("RssStockOrder_v failed with code: " & CStr(rssResult))
        ExecuteRSSOrder = ""
    End If

    Exit Function

ErrorHandler:
    Call LogError("Error in ExecuteRSSOrder: " & Err.Description & " (Number: " & Err.Number & ")")
    ExecuteRSSOrder = ""
End Function

' ========================================
' ローカルログ記録??????
' ========================================
Sub LogOrderSuccess(signalId As String, ticker As String, action As String, orderId As String, price As Variant, reverseConditionPrice As Variant, reversePrice As Variant, quantity As Variant)
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
    ws.Cells(nextRow, 7).Value = ""
    ws.Cells(nextRow, 8).Value = price
    ws.Cells(nextRow, 9).Value = reverseConditionPrice
    ws.Cells(nextRow, 10).Value = reversePrice
    ws.Cells(nextRow, 11).Value = quantity
End Sub

' ========================================
' ローカルログ記録?失???
' ========================================
Sub LogOrderFailure(signalId As String, ticker As String, action As String, reason As String, price As Variant, reverseConditionPrice As Variant, reversePrice As Variant, quantity As Variant)
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
    ws.Cells(nextRow, 8).Value = price
    ws.Cells(nextRow, 9).Value = reverseConditionPrice
    ws.Cells(nextRow, 10).Value = reversePrice
    ws.Cells(nextRow, 11).Value = quantity
End Sub

' ========================================
' ス?ータスダ?シュ?????????
' ========================================
Sub InitializeStatusDashboard()
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("Dashboard")

    ' ヘッダー設?
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

    ' ???調整
    ws.Columns("A:A").ColumnWidth = 15
    ws.Columns("B:B").ColumnWidth = 25
End Sub

' ========================================
' ス?ータスダ?シュ???ド更新
' ========================================
Sub UpdateStatusDashboard()
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("Dashboard")

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
        elapsed = (Now - StartTime) * 24 * 60 ' ????
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
