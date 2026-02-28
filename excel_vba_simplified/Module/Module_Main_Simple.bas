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
Private ScheduledCloseTime As Date
Private StartTime As Date
Private LastSignalTime As Date
Private SignalCount As Long
Private SuccessCount As Long
Private FailureCount As Long

' --- OCO非同期ポーリング状態 ---
Private PendingOCO As Boolean
Private OCO_OrderIdNum As Long
Private OCO_Ticker As String
Private OCO_SideCode As String
Private OCO_StopLoss As Double
Private OCO_TakeProfit As Double
Private OCO_PollCount As Integer
Private OCO_PollMaxCount As Integer
Private OCO_PollInterval As Integer
Private OCO_NextPollTime As Date

' ========================================
' メインループ開始（非同期実行）
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

    ' 大引前不成チェックをスケジュール（15:15）
    Call ScheduleCloseCheck

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

    ' スケジュールされた次回ポーリングをキャンセル
    If NextScheduledTime <> 0 Then
        Application.OnTime NextScheduledTime, "ScheduledPoll", , False
        NextScheduledTime = 0
    End If

    ' 大引前不成チェックをキャンセル
    Call CancelCloseCheck

    ' OCO非同期監視をキャンセル
    Call CleanupOCOState

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
' 大引前不成チェックをスケジュール（15:15）
' ========================================
Private Sub ScheduleCloseCheck()
    On Error Resume Next

    If Not IsRunning Then Exit Sub

    ' 今日の15:15にスケジュール
    Dim closeCheckTime As Date
    closeCheckTime = Date + TimeValue("15:15:00")

    ' 既に15:15を過ぎている場合はスキップ
    If Now >= closeCheckTime Then
        Call LogInfo("Close check time (15:15) already passed today")
        Exit Sub
    End If

    ScheduledCloseTime = closeCheckTime
    Application.OnTime ScheduledCloseTime, "CheckAndModifyOrdersForClose"
    Call LogInfo("Close check scheduled at " & Format(closeCheckTime, "hh:nn:ss"))
End Sub

' ========================================
' 大引前不成チェックをキャンセル
' ========================================
Private Sub CancelCloseCheck()
    On Error Resume Next

    If ScheduledCloseTime <> 0 Then
        Application.OnTime ScheduledCloseTime, "CheckAndModifyOrdersForClose", , False
        ScheduledCloseTime = 0
    End If
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

    ' ステータスダッシュボードを更新（時刻更新含む）
    Call UpdateStatusDashboard

    ' シグナルを取得して実行
    Call PollAndExecuteSignals

    ' 次回ポーリングをスケジュール
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

    Dim logPrice As Variant
    Dim logReverseConditionPrice As Variant
    Dim logReversePrice As Variant
    Dim logQuantity As Variant
    Dim logSetOrderPrice As Variant

    On Error Resume Next
    logPrice = signal("entry_price")
    logReverseConditionPrice = signal("stop_loss")
    logReversePrice = signal("stop_loss")
    logQuantity = signal("quantity")
    logSetOrderPrice = signal("take_profit")
    On Error GoTo ErrorHandler

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
        Call LogOrderSuccess(signal("signal_id"), signal("ticker"), signal("action"), orderId, logPrice, logReverseConditionPrice, logReversePrice, logQuantity, logSetOrderPrice)
    Else
        ' 失敗 - Relay Serverに報告
        Call LogError("Order execution failed")
        FailureCount = FailureCount + 1

        Call API_ReportFailure(signal("signal_id"), "RSS execution failed")

        ' ローカルログ記録
        Call LogOrderFailure(signal("signal_id"), signal("ticker"), signal("action"), "RSS execution failed", logPrice, logReverseConditionPrice, logReversePrice, logQuantity, logSetOrderPrice)
    End If

    Exit Sub

ErrorHandler:
    Call LogError("Error in ExecuteValidatedSignal: " & Err.Description)
    Call API_ReportFailure(signal("signal_id"), "Exception: " & Err.Description)
    Call LogOrderFailure(signal("signal_id"), signal("ticker"), signal("action"), Err.Description, logPrice, logReverseConditionPrice, logReversePrice, logQuantity, logSetOrderPrice)
End Sub

' ========================================
' RSS注文実行（RssStockOrder_v呼び出し）
' ========================================
Function ExecuteRSSOrder(signal As Object) As String
    '
    ' MarketSpeed II RSS経由で注文実行
    '
    On Error GoTo ErrorHandler

    ' パラメータ取得
    Dim ticker As String
    Dim side As Integer
    Dim quantity As Long

    Call LogDebug("Parsing ticker...")
    ticker = CStr(signal("ticker"))
    Call LogDebug("Ticker: " & ticker)

    ' actionを小文字の文字列として取得
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

    ' テストモード確認
    Dim testMode As String
    testMode = GetConfig("TEST_MODE")

    ' 注文モード（現物/信用）
    Dim orderMode As String
    orderMode = LCase(GetConfig("ORDER_MODE"))
    If orderMode = "" Then orderMode = "spot"  ' デフォルト: 現物

    Dim rssFuncName As String
    If orderMode = "margin" Then
        rssFuncName = "RssMarginOpenOrder_v"
    Else
        rssFuncName = "RssStockOrder_v"
    End If

    Call LogDebug("Calling " & rssFuncName & "...")
    Call LogDebug("Parameters: orderId=" & orderId & ", ticker=" & ticker & ", side=" & side & ", quantity=" & quantity & ", orderMode=" & orderMode)

    Dim rssResult As Variant

    If UCase(testMode) = "TRUE" Then
        ' テストモード: モック実行
        Call LogInfo("TEST MODE: Simulating " & rssFuncName & " call")
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

        orderType = "1"  ' デフォルト: 逆指値付通常注文（現物止損あり想定）

        Dim sorType As String

        sorType = "1"


        ' 価格タイプを判定（"market" ならAPIコード"1"、それ以外は"0"）
        Dim priceType As String
        Dim priceStr As String
        priceStr = LCase(CStr(signal("price")))

        If priceStr = "market" Then
            priceType = "1"  ' market指定
        Else
            priceType = "0"  ' 価格指定
        End If
        Call LogDebug("Price Type: " & priceType & " (" & priceStr & ")")

        Dim orderPrice As Double
        If priceType = "0" Then
            ' priceType=0の場合は価格を0に設定
            orderPrice = 0
        Else
            ' priceType=1の場合はentry_priceを使用
            orderPrice = CDbl(signal("entry_price"))
        End If
        Call LogDebug("Order Price: " & orderPrice)



        ' 実行条件をConfigシートから取得（デフォルト: "1" = 無条件）
        Dim execCondition As String
        execCondition = GetConfig("EXEC_CONDITION")
        If execCondition = "" Then
            execCondition = "1"  ' デフォルト: 無条件
        End If
        Call LogDebug("Exec Condition: " & execCondition)

        Dim orderExpiry As String
        orderExpiry = ""

        ' 口座区分をConfigシートから取得（デフォルト: "2" = 特定口座）
        Dim accountType As String
        accountType = GetConfig("ACCOUNT_TYPE")
        If accountType = "" Then
            accountType = "2"  ' デフォルト: 特定口座
        End If
        Call LogDebug("Account Type: " & accountType)

        ' 信用モードの場合: NISA/旧NISAは使用不可
        If orderMode = "margin" Then
            If accountType = "2" Or accountType = "3" Then
                accountType = "0"  ' 特定口座にフォールバック
                Call LogWarning("Margin order: NISA not available, using 特定口座(0)")
            End If
        End If

        Dim reverseConditionPrice As Variant
        Dim reverseConditionType As Variant
        Dim reversePriceType As Variant
        Dim reversePrice As Variant

        Dim setOrderType As String
        Dim setOrderPriceType As String  ' 信用のみ使用
        Dim setOrderPrice As Variant
        Dim setExecutionCondition As String
        Dim setOrderExpiry As String

        reverseConditionPrice = ""
        reverseConditionType = ""
        reversePriceType = ""
        reversePrice = ""
        setOrderType = ""
        setOrderPriceType = ""
        setOrderPrice = ""
        setExecutionCondition = ""
        setOrderExpiry = ""

        ' 信用取引は通常注文（逆指値不要）
        If orderMode = "margin" Then orderType = "0"

        ' Stop-loss設定（reverse注文）: 現物のみ（信用取引は逆指値不要）
        If stopLoss > 0 And orderMode <> "margin" Then
            reverseConditionPrice = stopLoss
            If side = 3 Then
                ' 買い注文：stop-lossは逆指値下（価格が下がったら成行売り）
                reverseConditionType = "2"
            Else
                ' 売り注文：stop-lossは逆指値上（価格が上がったら成行買い）
                reverseConditionType = "1"
            End If
            reversePriceType = "1"  ' 指値
            reversePrice = reverseConditionPrice
        End If

        ' Take-profit設定（set注文）
        If takeProfit > 0 Then
            setOrderType = "1"  ' セット注文
            setOrderPrice = takeProfit  ' 指値価格
            setExecutionCondition = execCondition  ' ConfigのEXEC_CONDITIONを使用
            setOrderExpiry = ""  ' 当日
            ' セット注文価格区分（信用のみ必要）
            If orderMode = "margin" Then
                setOrderPriceType = "1"  ' 指値
            End If
            Call LogDebug("Take-profit set order: price=" & takeProfit)
        End If

        If orderMode = "margin" Then
            ' --- 信用新規注文 ---
            Dim marginType As String
            marginType = GetConfig("MARGIN_TYPE")
            If marginType = "" Then marginType = "1"  ' デフォルト: 制度信用(6ヶ月)

            ' 一般信用いちにちの場合: セット注文の執行条件は大引不成(6)のみ
            If marginType = "4" And takeProfit > 0 Then
                setExecutionCondition = "6"  ' 大引不成
                Call LogDebug("一般信用いちにち: set order exec condition overridden to 大引不成(6)")
            End If

            Call LogDebug("RssMarginOpenOrder_v params: " & _
                "orderIdNum=" & CStr(orderIdNum) & _
                ", ticker=" & CStr(ticker) & _
                ", side=" & CStr(sideCode) & _
                ", orderType=" & CStr(orderType) & _
                ", sorType=" & CStr(sorType) & _
                ", marginType=" & CStr(marginType) & _
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
                ", setOrderPriceType=" & CStr(setOrderPriceType) & _
                ", setOrderPrice=" & CStr(setOrderPrice) & _
                ", setExecutionCondition=" & CStr(setExecutionCondition) & _
                ", setOrderExpiry=" & CStr(setOrderExpiry))

            Dim excelFormulaCallMargin As String
            excelFormulaCallMargin = "=RssMarginOpenOrder_v(" & _
                CStr(orderIdNum) & ", " & _
                """" & ticker & """, " & _
                """" & sideCode & """, " & _
                """" & orderType & """, " & _
                """" & sorType & """, " & _
                """" & marginType & """, " & _
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
                """" & setOrderPriceType & """, " & _
                IIf(setOrderPrice = "", "", CStr(setOrderPrice)) & ", " & _
                """" & setExecutionCondition & """, " & _
                """" & setOrderExpiry & """)"
            Call LogDebug(excelFormulaCallMargin)

            rssResult = Application.Run("RssMarginOpenOrder_v", _
                orderIdNum, _
                ticker, _
                sideCode, _
                orderType, _
                sorType, _
                marginType, _
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
                setOrderPriceType, _
                setOrderPrice, _
                setExecutionCondition, _
                setOrderExpiry)
        Else
            ' --- 現物注文 ---
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

    End If

' 結果判定
    Call LogDebug(rssFuncName & " completed, checking result...")

    ' 戻り値の詳細チェック
    If IsEmpty(rssResult) Then
        Call LogWarning(rssFuncName & " returned Empty (no return value)")
        ' Emptyの場合は成功と仮定（RSS APIが戻り値を返さない場合がある）
        rssResult = 0
    ElseIf IsNull(rssResult) Then
        Call LogWarning(rssFuncName & " returned Null")
        rssResult = 0
    ElseIf IsError(rssResult) Then
        Call LogError(rssFuncName & " returned Error: " & CStr(CVErr(rssResult)))
        ExecuteRSSOrder = ""
        Exit Function
    ElseIf IsArray(rssResult) Then
        Call LogWarning(rssFuncName & " returned Array (partial success/failure)")
        ' 配列の場合は最初の要素をチェック
        If UBound(rssResult) >= 0 Then
            Call LogDebug("Array result: " & Join(rssResult, ", "))
            rssResult = rssResult(0)
        Else
            rssResult = 0
        End If
    End If

    ' 戻り値の型をログ出力
    Call LogDebug("Result type: " & TypeName(rssResult) & ", Value: " & CStr(rssResult))

    If rssResult = 0 Or rssResult = "" Or rssResult = "0" Then
        ' 成功（0、空文字、"0"を成功とみなす）
        Call LogSuccess(rssFuncName & " succeeded (result: " & CStr(rssResult) & ")")

        ' セット注文でstop-lossとtake-profitが設定されているのでログ出力
        If stopLoss > 0 And takeProfit > 0 Then
            Call LogInfo("Set order placed with stop-loss=" & stopLoss & " and take-profit=" & takeProfit)
        ElseIf stopLoss > 0 Then
            Call LogInfo("Order placed with stop-loss=" & stopLoss)
        ElseIf takeProfit > 0 Then
            Call LogInfo("Order placed with take-profit=" & takeProfit)
        End If

        ' セット注文を逆指値付通常注文に訂正（利益確定+損切りのOCO化）
        ' 非同期で実行（fire-and-forget）：結果はログに出力される
        ' 信用注文の場合はOCO変換不要（セット注文はそのまま利確注文として残す）
        If stopLoss > 0 And takeProfit > 0 And orderMode <> "margin" Then
            If UCase(testMode) <> "TRUE" Then
                Call StartAsyncOCOMonitor(orderIdNum, ticker, sideCode, stopLoss, takeProfit)
            Else
                Call LogInfo("TEST MODE: Would modify set order to OCO (stop-loss=" & stopLoss & ", 成行)")
            End If
        End If

        ExecuteRSSOrder = orderId
    Else
        ' 失敗
        Call LogError(rssFuncName & " failed with result type: " & TypeName(rssResult) & ", value: " & CStr(rssResult))
        ExecuteRSSOrder = ""
    End If

    Exit Function

ErrorHandler:
    Call LogError("Error in ExecuteRSSOrder: " & Err.Description & " (Number: " & Err.Number & ")")
    ExecuteRSSOrder = ""
End Function

' ========================================
' OCO非同期監視開始
' OCO_WAIT_SECONDS秒（デフォルト10秒）待機後、自動的にセット注文をOCO化する
' Application.OnTimeで非同期待機（DDE更新をブロックしない）
' ========================================
Sub StartAsyncOCOMonitor(orderIdNum As Long, ticker As String, _
    sideCode As String, stopLoss As Double, takeProfit As Double)
    On Error GoTo ErrorHandler

    ' 多重起動防止
    If PendingOCO Then
        Call LogWarning("OCO monitor already active. Skipping new OCO for orderIdNum=" & orderIdNum)
        Exit Sub
    End If

    Call LogInfo("=== Starting async OCO monitor ===")
    Call LogDebug("StartAsyncOCOMonitor params: " & _
        "orderIdNum=" & CStr(orderIdNum) & _
        ", ticker=" & ticker & _
        ", sideCode=" & sideCode & _
        ", stopLoss=" & CStr(stopLoss) & _
        ", takeProfit=" & CStr(takeProfit))

    ' OCO状態を保存
    PendingOCO = True
    OCO_OrderIdNum = orderIdNum
    OCO_Ticker = ticker
    OCO_SideCode = sideCode
    OCO_StopLoss = stopLoss
    OCO_TakeProfit = takeProfit
    OCO_PollCount = 0

    ' Configから待機秒数を取得（デフォルト: 10秒）
    Dim cfgWaitSecs As String
    cfgWaitSecs = GetConfig("OCO_WAIT_SECONDS")
    Dim waitSecs As Integer
    If cfgWaitSecs = "" Then
        waitSecs = 10
    Else
        waitSecs = CInt(cfgWaitSecs)
    End If

    Call LogInfo("OCO modification scheduled in " & waitSecs & "s (OCO_WAIT_SECONDS)")

    ' 指定秒数後にOCO変更をスケジュール
    OCO_NextPollTime = Now + TimeSerial(0, 0, waitSecs)
    Application.OnTime OCO_NextPollTime, "CheckOCOStatus"

    Call LogInfo("Async OCO scheduled in " & waitSecs & "s (orderIdNum=" & orderIdNum & ")")
    Exit Sub

ErrorHandler:
    Call LogError("Error in StartAsyncOCOMonitor: " & Err.Description)
    Call CleanupOCOState
End Sub

' ========================================
' OCO変更実行コールバック（Application.OnTimeから呼ばれる）
' OCO_WAIT_SECONDS秒の待機後に自動実行される
' ========================================
Sub CheckOCOStatus()
    On Error GoTo ErrorHandler

    ' ガード: OCO保留中でなければ何もしない
    If Not PendingOCO Then
        Call LogDebug("CheckOCOStatus called but no pending OCO, exiting")
        Exit Sub
    End If

    Call LogInfo("OCO wait completed, executing OCO modification...")
    Call ExecuteOCOModification
    Exit Sub

ErrorHandler:
    Call LogError("Error in CheckOCOStatus: " & Err.Description)
    Call CleanupOCOState
End Sub

' ========================================
' OCO訂正実行（親注文約定後に呼ばれる）
' FindSetOrderNumber + RssModifyOrder_V は同期実行
' ========================================
Private Sub ExecuteOCOModification()
    On Error GoTo ErrorHandler

    ' まずステータス数式セルをクリア（B1を解放）
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("OrderHelper")
    ws.Range("B1").ClearContents

    ' Step 1: セット注文の注文番号を取得
    Call LogInfo("Searching for set order number... (async OCO)")

    Dim setOrderNumber As String
    setOrderNumber = FindSetOrderNumber(OCO_Ticker, OCO_SideCode, OCO_TakeProfit)

    If setOrderNumber = "" Then
        Call LogWarning("Set order number not found. Set order (take-profit only) remains active.")
        Call CleanupOCOState
        Exit Sub
    End If

    Call LogInfo("Found set order: " & setOrderNumber)

    ' Step 2: RssModifyOrder_V でセット注文を訂正
    '   通常注文(0) → 逆指値付通常注文(1)
    '   逆指値条件: 価格がstopLoss以下(買い親)/以上(売り親)になったら成行
    Dim modifyIdNum As Long
    modifyIdNum = CLng(DateDiff("s", DateSerial(2020, 1, 1), Now)) + 1

    ' 逆指値条件区分
    Dim stopConditionType As String
    If OCO_SideCode = "3" Then
        ' 親が買い注文 → セット注文は売り → 価格下落でトリガー
        stopConditionType = "2"  ' 以下
    Else
        ' 親が売り注文 → セット注文は買い → 価格上昇でトリガー
        stopConditionType = "1"  ' 以上
    End If

    Call LogDebug("RssModifyOrder_V params: " & _
        "modifyIdNum=" & modifyIdNum & _
        ", orderNumber=" & setOrderNumber & _
        ", orderType=1 (逆指値付通常)" & _
        ", stopConditionPrice=" & OCO_StopLoss & _
        ", stopConditionType=" & stopConditionType & _
        ", stopPriceType=0 (成行)")

    Dim modifyResult As Variant
    modifyResult = Application.Run("RssModifyOrder_V", _
        modifyIdNum, _
        CLng(setOrderNumber), _
        "1", _
        "", _
        "", _
        "", _
        "", _
        "", _
        OCO_StopLoss, _
        stopConditionType, _
        "0", _
        "", _
        "", _
        "", _
        "", _
        "")

    ' Step 3: 結果判定
    Call LogDebug("RssModifyOrder_V result type: " & TypeName(modifyResult) & _
        ", value: " & CStr(modifyResult))

    If IsError(modifyResult) Then
        Call LogError("RssModifyOrder_V returned error (async OCO)")
        Call LogOrderModifyResult(setOrderNumber, OCO_Ticker, OCO_StopLoss, False, "RSS error")
    ElseIf modifyResult = 0 Or modifyResult = "" Or modifyResult = "0" Then
        Call LogSuccess("Set order modified to OCO: take-profit=" & OCO_TakeProfit & _
            ", stop-loss=" & OCO_StopLoss & " (成行)")
        Call LogOrderModifyResult(setOrderNumber, OCO_Ticker, OCO_StopLoss, True, "")
    Else
        Call LogError("RssModifyOrder_V failed: " & CStr(modifyResult) & " (async OCO)")
        Call LogOrderModifyResult(setOrderNumber, OCO_Ticker, OCO_StopLoss, False, CStr(modifyResult))
    End If

    ' クリーンアップ
    Call CleanupOCOState
    Exit Sub

ErrorHandler:
    Call LogError("Error in ExecuteOCOModification: " & Err.Description)
    Call CleanupOCOState
End Sub

' ========================================
' OCO非同期状態のクリーンアップ
' ========================================
Private Sub CleanupOCOState()
    On Error Resume Next

    ' スケジュール済みポーリングをキャンセル
    If OCO_NextPollTime <> 0 Then
        Application.OnTime OCO_NextPollTime, "CheckOCOStatus", , False
        OCO_NextPollTime = 0
    End If

    ' ステータス数式セルをクリア
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("OrderHelper")
    If Not ws Is Nothing Then
        ws.Range("B1").ClearContents
    End If

    ' 状態リセット
    PendingOCO = False
    OCO_OrderIdNum = 0
    OCO_Ticker = ""
    OCO_SideCode = ""
    OCO_StopLoss = 0
    OCO_TakeProfit = 0
    OCO_PollCount = 0
    OCO_PollMaxCount = 0
    OCO_PollInterval = 0

    Call LogDebug("OCO state cleaned up")
End Sub

' ========================================
' セット注文の注文番号を検索
' RssOrderList を使って対象のセット注文を特定する
' ========================================
Function FindSetOrderNumber(ticker As String, sideCode As String, _
    takeProfit As Double) As String
    On Error GoTo ErrorHandler

    Dim ws As Worksheet

    ' OrderHelperシートを取得または作成
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets("OrderHelper")
    On Error GoTo ErrorHandler

    If ws Is Nothing Then
        Set ws = ThisWorkbook.Sheets.Add( _
            After:=ThisWorkbook.Sheets(ThisWorkbook.Sheets.Count))
        ws.Name = "OrderHelper"
        ws.Visible = xlSheetHidden
    End If

    ' シートをクリア
    ws.Cells.ClearContents

    ' セット注文の売買方向を決定
    Dim sellSide As Integer
    If sideCode = "3" Then
        sellSide = 1  ' 親が買い → セット注文は売り
    Else
        sellSide = 3  ' 親が売り → セット注文は買い
    End If

    ' RssOrderList を配置
    ' パラメータ: header, order_status=1(訂正可能), order_type(現物=1/信用=2),
    '   stock_code, account_type="A"(全て), buy_sell
    Dim orderTypeFilter As Integer
    If LCase(GetConfig("ORDER_MODE")) = "margin" Then
        orderTypeFilter = 2  ' 信用
    Else
        orderTypeFilter = 1  ' 現物
    End If
    ws.Range("A1").Formula = "=RssOrderList(A1,1," & orderTypeFilter & ",""" & ticker & """,""A""," & sellSide & ")"

    ' RSSデータが展開されるまで待機（最大5秒）
    Dim waitLoop As Integer
    For waitLoop = 1 To 5
        Application.Wait Now + TimeValue("00:00:01")
        DoEvents
        If ws.Range("A2").Value <> "" Then Exit For
    Next waitLoop

    ' ヘッダー行からカラムインデックスを取得
    Dim colOrderNum As Integer
    Dim colOrderPrice As Integer
    Dim colOrderType As Integer
    Dim col As Integer
    colOrderNum = 0
    colOrderPrice = 0
    colOrderType = 0

    For col = 1 To 30
        Dim headerVal As String
        headerVal = CStr(ws.Cells(1, col).Value)
        If headerVal = "" Then Exit For
        If InStr(headerVal, "注文番号") > 0 Then colOrderNum = col
        If InStr(headerVal, "注文価格") > 0 Or InStr(headerVal, "価格") > 0 Then colOrderPrice = col
        If InStr(headerVal, "注文区分") > 0 Then colOrderType = col
    Next col

    If colOrderNum = 0 Then
        Call LogWarning("FindSetOrderNumber: 注文番号 column not found in RssOrderList header")
        GoTo Cleanup
    End If

    ' データ行を走査して take_profit 価格に一致する注文を検索
    Dim row As Long
    Dim orderNum As String
    orderNum = ""

    For row = 2 To 100
        If ws.Cells(row, 1).Value = "" Then Exit For

        ' 価格カラムがある場合は価格で照合
        If colOrderPrice > 0 Then
            Dim orderPrice As Double
            On Error Resume Next
            orderPrice = CDbl(ws.Cells(row, colOrderPrice).Value)
            On Error GoTo ErrorHandler

            If orderPrice = takeProfit Then
                orderNum = CStr(ws.Cells(row, colOrderNum).Value)
                Call LogDebug("Found matching set order: number=" & orderNum & _
                    ", price=" & orderPrice)
                Exit For
            End If
        Else
            ' 価格カラムが見つからない場合は最初の注文を使用
            orderNum = CStr(ws.Cells(row, colOrderNum).Value)
            Call LogDebug("Using first order (price column not found): number=" & orderNum)
            Exit For
        End If
    Next row

Cleanup:
    ' 一時データをクリア
    On Error Resume Next
    ws.Cells.ClearContents
    On Error GoTo 0

    FindSetOrderNumber = orderNum
    Exit Function

ErrorHandler:
    Call LogError("Error in FindSetOrderNumber: " & Err.Description)
    On Error Resume Next
    If Not ws Is Nothing Then ws.Cells.ClearContents
    FindSetOrderNumber = ""
End Function

' ========================================
' 注文訂正結果のログ記録
' ========================================
Sub LogOrderModifyResult(orderNumber As String, ticker As String, _
    stopLoss As Double, success As Boolean, errorMsg As String)
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("OrderLog")

    Dim nextRow As Long
    nextRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    ws.Cells(nextRow, 1).Value = Now
    ws.Cells(nextRow, 2).Value = "MODIFY_OCO"
    ws.Cells(nextRow, 3).Value = ticker
    ws.Cells(nextRow, 4).Value = "modify"
    ws.Cells(nextRow, 5).Value = orderNumber
    ws.Cells(nextRow, 6).Value = IIf(success, "SUCCESS", "FAILED")
    ws.Cells(nextRow, 7).Value = IIf(success, "", errorMsg)
    ws.Cells(nextRow, 8).Value = ""
    ws.Cells(nextRow, 9).Value = stopLoss
    ws.Cells(nextRow, 10).Value = ""
    ws.Cells(nextRow, 11).Value = ""
    ws.Cells(nextRow, 12).Value = ""
End Sub

' ========================================
' 未約定注文を不成に変更（毎日15:15に自動実行）
' RssModifyOrder_V で執行条件を "7"(不成) に訂正する
' 注意: 今週中・期間指定の注文は訂正不可のためスキップ
' ========================================
Sub CheckAndModifyOrdersForClose()
    On Error GoTo ErrorHandler

    Call LogSectionStart("Close Check: Modifying active orders to Funari (不成)")

    ' テストモード確認
    Dim testMode As String
    testMode = GetConfig("TEST_MODE")

    Dim ws As Worksheet

    ' OrderHelperシートを取得または作成
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets("OrderHelper")
    On Error GoTo ErrorHandler

    If ws Is Nothing Then
        Set ws = ThisWorkbook.Sheets.Add( _
            After:=ThisWorkbook.Sheets(ThisWorkbook.Sheets.Count))
        ws.Name = "OrderHelper"
        ws.Visible = xlSheetHidden
    End If

    ' シートをクリア
    ws.Cells.ClearContents

    ' RssOrderList を配置
    ' 注文状況=1(訂正取消可能注文), 注文種類=0(全て:現物+信用), 口座区分="A"(全て)
    ws.Range("A1").Formula = "=RssOrderList(A1,1,0,,""A"")"

    ' RSSデータが展開されるまで待機（最大5秒）
    Dim waitLoop As Integer
    For waitLoop = 1 To 5
        Application.Wait Now + TimeValue("00:00:01")
        DoEvents
        If ws.Range("A2").Value <> "" Then Exit For
    Next waitLoop

    ' ヘッダー行からカラムインデックスを動的取得
    Dim colOrderNum As Integer
    Dim colExecCondition As Integer
    Dim colOrderType As Integer
    Dim colTicker As Integer
    Dim col As Integer
    colOrderNum = 0
    colExecCondition = 0
    colOrderType = 0
    colTicker = 0

    For col = 1 To 30
        Dim headerVal As String
        headerVal = CStr(ws.Cells(1, col).Value)
        If headerVal = "" Then Exit For
        If InStr(headerVal, "注文番号") > 0 Then colOrderNum = col
        If InStr(headerVal, "執行条件") > 0 Then colExecCondition = col
        If InStr(headerVal, "注文区分") > 0 Then colOrderType = col
        If colTicker = 0 Then
            If InStr(headerVal, "銘柄コード") > 0 Then colTicker = col
        End If
    Next col

    If colOrderNum = 0 Then
        Call LogInfo("Close check: no active orders found (or header not available)")
        GoTo Cleanup
    End If

    ' データ行を走査して各注文を不成に変更
    Dim row As Long
    Dim modifiedCount As Integer
    Dim skippedCount As Integer
    Dim failedCount As Integer
    modifiedCount = 0
    skippedCount = 0
    failedCount = 0

    For row = 2 To 200
        If ws.Cells(row, 1).Value = "" Then Exit For

        Dim orderNumber As String
        orderNumber = CStr(ws.Cells(row, colOrderNum).Value)

        If orderNumber = "" Or orderNumber = "0" Then GoTo NextOrderRow

        ' 執行条件を確認
        Dim execCond As String
        execCond = ""
        If colExecCondition > 0 Then
            execCond = CStr(ws.Cells(row, colExecCondition).Value)
        End If

        ' 既に不成 or 大引不成 ならスキップ
        If InStr(execCond, "不成") > 0 Then
            Call LogDebug("Order " & orderNumber & ": already 不成, skip")
            skippedCount = skippedCount + 1
            GoTo NextOrderRow
        End If

        ' 今週中 or 期間指定 は訂正不可（RSS仕様制限）
        If InStr(execCond, "今週中") > 0 Or InStr(execCond, "期間指定") > 0 Then
            Call LogWarning("Order " & orderNumber & ": exec=" & execCond & " cannot modify to 不成 (RSS restriction)")
            skippedCount = skippedCount + 1
            GoTo NextOrderRow
        End If

        ' 注文区分を取得してコードに変換
        Dim orderTypeText As String
        Dim orderTypeCode As String
        orderTypeText = ""
        orderTypeCode = "0"  ' デフォルト: 通常注文
        If colOrderType > 0 Then
            orderTypeText = CStr(ws.Cells(row, colOrderType).Value)
            If InStr(orderTypeText, "逆指値付通常") > 0 Then
                orderTypeCode = "1"
            ElseIf InStr(orderTypeText, "逆指値") > 0 Then
                orderTypeCode = "2"
            Else
                orderTypeCode = "0"
            End If
        End If

        ' 銘柄コード
        Dim tickerStr As String
        tickerStr = ""
        If colTicker > 0 Then tickerStr = CStr(ws.Cells(row, colTicker).Value)

        Call LogInfo("Modifying order " & orderNumber & " (ticker=" & tickerStr & _
            ", type=" & orderTypeText & ", exec=" & execCond & ") to 不成")

        If UCase(testMode) = "TRUE" Then
            Call LogInfo("TEST MODE: Would modify order " & orderNumber & " to 不成")
            modifiedCount = modifiedCount + 1
            GoTo NextOrderRow
        End If

        ' RssModifyOrder_V で執行条件を不成に訂正
        Dim modifyIdNum As Long
        modifyIdNum = CLng(DateDiff("s", DateSerial(2020, 1, 1), Now)) + row

        Call LogDebug("RssModifyOrder_V params: " & _
            "modifyIdNum=" & modifyIdNum & _
            ", orderNumber=" & orderNumber & _
            ", orderType=" & orderTypeCode & _
            ", price=" & _
            ", execCondition=7 (不成)" & _
            ", orderExpiry=")

        Dim excelFormulaCallFunari As String
        excelFormulaCallFunari = "=RssModifyOrder_V(" & _
            CStr(modifyIdNum) & ", " & _
            orderNumber & ", " & _
            """" & orderTypeCode & """, " & _
            ", " & _
            ", " & _
            ", " & _
            """7"", " & _
            ", " & _
            ", " & _
            ", " & _
            ", " & _
            ", " & _
            ", " & _
            ", " & _
            ", " & _
            ")"
        Call LogDebug(excelFormulaCallFunari)

        Dim modifyResult As Variant
        modifyResult = Application.Run("RssModifyOrder_V", _
            modifyIdNum, _
            CLng(orderNumber), _
            orderTypeCode, _
            "", _
            "", _
            "", _
            "7", _
            "", _
            "", _
            "", _
            "", _
            "", _
            "", _
            "", _
            "", _
            "")

        ' 結果判定
        If IsError(modifyResult) Then
            Call LogError("Failed to modify order " & orderNumber & " to 不成: RSS error")
            failedCount = failedCount + 1
        ElseIf modifyResult = 0 Or modifyResult = "" Or modifyResult = "0" Then
            Call LogSuccess("Order " & orderNumber & " modified to 不成")
            modifiedCount = modifiedCount + 1
        Else
            Call LogError("Failed to modify order " & orderNumber & ": " & CStr(modifyResult))
            failedCount = failedCount + 1
        End If

        ' 連続API呼び出し防止（1秒待機）
        Application.Wait Now + TimeValue("00:00:01")
        DoEvents

NextOrderRow:
    Next row

    Call LogInfo("Close check complete: " & modifiedCount & " modified, " & _
        skippedCount & " skipped, " & failedCount & " failed")

Cleanup:
    On Error Resume Next
    If Not ws Is Nothing Then ws.Cells.ClearContents
    On Error GoTo 0

    Exit Sub

ErrorHandler:
    Call LogError("Error in CheckAndModifyOrdersForClose: " & Err.Description)
    On Error Resume Next
    If Not ws Is Nothing Then ws.Cells.ClearContents
End Sub

' ========================================
' ローカルログ記録（成功時）
' ========================================
Sub LogOrderSuccess(signalId As String, ticker As String, action As String, orderId As String, price As Variant, reverseConditionPrice As Variant, reversePrice As Variant, quantity As Variant, setOrderPrice As Variant)
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
    ws.Cells(nextRow, 12).Value = setOrderPrice
End Sub

' ========================================
' ローカルログ記録（失敗時）
' ========================================
Sub LogOrderFailure(signalId As String, ticker As String, action As String, reason As String, price As Variant, reverseConditionPrice As Variant, reversePrice As Variant, quantity As Variant, setOrderPrice As Variant)
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
    ws.Cells(nextRow, 12).Value = setOrderPrice
End Sub

' ========================================
' ステータスダッシュボード初期化
' ========================================
Sub InitializeStatusDashboard()
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("Dashboard")

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
        elapsed = (Now - StartTime) * 24 * 60 ' 分換算
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
' ステータス表示を直接更新
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
