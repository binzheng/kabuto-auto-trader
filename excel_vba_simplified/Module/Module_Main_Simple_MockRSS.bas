Attribute VB_Name = "Module_Main_Simple"
'
' Kabuto Auto Trader - Simplified Main Module (MOCK RSS VERSION)
' テスト用: 実際のRSSを使わずにモック注文実行
'
' 使用方法:
' 1. このファイルを Module_Main_Simple.bas の代わりにインポート
' 2. StartPolling を実行
' 3. テストシグナルを送信
' 4. モック実行が成功することを確認
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
    Call LogSectionStart("Kabuto Auto Trader (Simplified - MOCK MODE) Started")
    Call LogInfo("Excel VBA: Order Execution Only (MOCK RSS)")
    Call LogInfo("All validation done by Relay Server")
    Call LogWarning("RSS orders are MOCKED - no real execution")

    ' ポーリングループ
    Do While IsRunning
        ' 1. Relay Serverから検証済みシグナルを取得
        Call PollAndExecuteSignals

        ' 2. 待機（5秒）
        Application.Wait Now + TimeValue("00:00:05")

        ' 処理を継続
        DoEvents
    Loop

    Call LogSectionEnd
    Call LogInfo("Polling Stopped")
    Exit Sub

ErrorHandler:
    Call LogError("Error in StartPolling: " & Err.Description)
    IsRunning = False
End Sub

' ========================================
' ポーリング停止
' ========================================
Sub StopPolling()
    IsRunning = False
    Call LogInfo("Stopping polling...")
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

    Call LogSectionStart("Executing Validated Signal")
    Call LogDebug("Signal ID: " & signal("signal_id"))
    Call LogDebug("Ticker: " & signal("ticker"))
    Call LogDebug("Action: " & signal("action"))
    Call LogDebug("Quantity: " & signal("quantity"))

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

    ' MOCK RSS注文実行
    Dim orderId As String
    orderId = ExecuteRSSOrder_Mock(signal)

    If orderId <> "" Then
        ' 成功 - Relay Serverに報告
        Call LogSuccess("Order executed successfully: " & orderId)

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
        Call LogOrderSuccess(signal("signal_id"), signal("ticker"), signal("action"), orderId, logPrice, logReverseConditionPrice, logReversePrice, logQuantity)
    Else
        ' 失敗 - Relay Serverに報告
        Call LogError("Order execution failed")
        Call API_ReportFailure(signal("signal_id"), "MOCK RSS execution failed")

        ' ローカルログ記録
        Call LogOrderFailure(signal("signal_id"), signal("ticker"), signal("action"), "MOCK RSS execution failed")
    End If

    Call LogSectionEnd
    Exit Sub

ErrorHandler:
    Call LogError("Error in ExecuteValidatedSignal: " & Err.Description)
    Call API_ReportFailure(signal("signal_id"), "Exception: " & Err.Description)
    Call LogOrderFailure(signal("signal_id"), signal("ticker"), signal("action"), Err.Description, logPrice, logReverseConditionPrice, logReversePrice, logQuantity)
End Sub

' ========================================
' MOCK RSS注文実行
' ========================================
Function ExecuteRSSOrder_Mock(signal As Dictionary) As String
    '
    ' テスト用: 実際のRSSを呼ばずに成功を返す
    '
    ' 本番環境では ExecuteRSSOrder() を使用してください
    '
    On Error GoTo ErrorHandler

    Call LogDebug("=== MOCK: RSS Order Execution ===")
    Call LogWarning("This is a MOCK execution - no real order placed")
    Call LogDebug("Ticker: " & signal("ticker"))
    Call LogDebug("Action: " & signal("action"))
    Call LogDebug("Quantity: " & signal("quantity"))

    ' パラメータ表示
    Dim side As String
    side = IIf(signal("action") = "buy", "現物買(3)", "現物売(1)")
    Call LogDebug("Side: " & side)
    Call LogDebug("Price Type: 成行(0)")

    ' モック注文ID生成
    Dim orderId As String
    orderId = "MOCK_ORD_" & Format(Now, "yyyymmddhhnnss") & "_" & signal("ticker")

    ' 実際のRSS処理をシミュレート（2秒待機）
    Call LogDebug("Processing... (2 seconds)")
    Application.Wait Now + TimeValue("00:00:02")

    ' ランダムで成功/失敗を決定（90%成功率）
    Randomize
    Dim successRate As Double
    successRate = Rnd()

    If successRate > 0.1 Then
        ' 成功（90%）
        Call LogSuccess("MOCK: Order executed successfully")
        ExecuteRSSOrder_Mock = orderId
    Else
        ' 失敗（10%）
        Call LogError("MOCK: Order execution failed (random failure for testing)")
        ExecuteRSSOrder_Mock = ""
    End If

    Exit Function

ErrorHandler:
    Call LogError("Error in ExecuteRSSOrder_Mock: " & Err.Description)
    ExecuteRSSOrder_Mock = ""
End Function

' ========================================
' 【本番用】RSS注文実行（RssStockOrder_v呼び出し）
' ========================================
' 本番環境では ExecuteValidatedSignal() 内で
' ExecuteRSSOrder_Mock() の代わりに ExecuteRSSOrder() を呼び出してください
'
Function ExecuteRSSOrder(signal As Dictionary) As String
    '
    ' MarketSpeed II RSS経由で注文実行（本番用）
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

    Call LogDebug("=== RSS Order Execution ===")
    Call LogDebug("Calling RssStockOrder_v()...")

    ' RssStockOrder_v呼び出し
    Dim rssResult As Variant
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

    ' 結果判定
    If IsError(rssResult) Then
        Call LogError("RssStockOrder_v returned Error")
        ExecuteRSSOrder = ""
        Exit Function
    End If

    If rssResult = 0 Then
        ' 成功
        Call LogSuccess("RssStockOrder_v succeeded")
        ExecuteRSSOrder = orderId
    Else
        ' 失敗
        Call LogError("RssStockOrder_v failed: " & CStr(rssResult))
        ExecuteRSSOrder = ""
    End If

    Exit Function

ErrorHandler:
    Call LogError("Error in ExecuteRSSOrder: " & Err.Description)
    ExecuteRSSOrder = ""
End Function

' ========================================
' ローカルログ記録（成功）
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
    ws.Cells(nextRow, 7).Value = ""

    ' 成功行を緑でハイライト
    ws.Rows(nextRow).Interior.Color = RGB(144, 238, 144)  ' Light Green
End Sub

' ========================================
' ローカルログ記録（失敗）
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

    ' 失敗行を赤でハイライト
    ws.Rows(nextRow).Interior.Color = RGB(255, 182, 193)  ' Light Pink
End Sub

' ========================================
' テストヘルパー
' ========================================
Sub TestSingleFetch()
    '
    ' 1回だけシグナルを取得してテスト
    '
    Call LogSectionStart("Test: Single Fetch")

    ' API接続テスト
    If Not API_TestConnection() Then
        MsgBox "Relay Server接続失敗"
        Exit Sub
    End If

    ' 1回だけポーリング
    Call PollAndExecuteSignals

    Call LogSectionEnd
    Call LogInfo("Test completed")
End Sub
