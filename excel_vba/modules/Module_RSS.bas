Attribute VB_Name = "Module_RSS"
'
' Kabuto Auto Trader - RSS Module (Complete Safety Edition)
' MarketSpeed II RSS連携 + 6層防御機構
'
' 設計: doc/14_rss_order_safety_design.md
'

Option Explicit

' ========================================
' 安全発注実行（メインエントリーポイント）
' ========================================
Function SafeExecuteOrder(signal As Dictionary) As String
    Debug.Print "SafeExecuteOrder"

    '
    ' 安全発注実行（誤発注防止完全版）
    '
    On Error GoTo ErrorHandler

    Dim orderParams As New Dictionary

    ' === Step 1: パラメータ構築 ===
    orderParams("ticker") = signal("ticker")
    orderParams("side") = IIf(signal("action") = "buy", 3, 1)  ' 3=現物買, 1=現物売
    orderParams("quantity") = CLng(signal("quantity"))
    orderParams("priceType") = 0  ' 成行固定
    orderParams("price") = 0      ' 成行なので0
    orderParams("condition") = 0  ' 通常注文

    Debug.Print "=== Safe Order Execution ==="
    Debug.Print "Signal ID: " & signal("signal_id")
    Debug.Print "Ticker: " & orderParams("ticker")
    Debug.Print "Action: " & signal("action")
    Debug.Print "Price: " & signal("action")
    Debug.Print "Quantity: " & orderParams("quantity")

    ' === Step 2: 発注可否判定（5段階チェック） ===
    Dim canExecute As Dictionary
    Set canExecute = CanExecuteOrder(orderParams)

    If Not canExecute("allowed") Then
        Debug.Print "Order BLOCKED: " & canExecute("reason")

        ' ブロック理由をログ記録
        Call LogOrderBlocked(signal("signal_id"), canExecute)

        SafeExecuteOrder = ""
        Exit Function
    End If

    Debug.Print "Order checks passed (5 levels)"

    ' === Step 3: ダブルチェック（異常価格検出） ===
    If Not DoubleCheckOrder(orderParams) Then
        Debug.Print "Double check FAILED"
        Call LogError("ORDER_ERROR", "SafeExecuteOrder", "Double check failed", orderParams("ticker"), "CRITICAL")

        SafeExecuteOrder = ""
        Exit Function
    End If

    Debug.Print "Double check passed"

    ' === Step 4: 監査ログ記録（発注前） ===
    Call LogOrderAttempt(signal("signal_id"), orderParams)

    ' === Step 5: RssStockOrder_v() 実行 ===
    ' 発注ID生成
    Dim orderId As String
    orderId = "ORD_" & Format(Now, "yyyymmddhhnnss") & "_" & Right("000" & signal("signal_id"), 6)

    Dim rssResult As Variant
    rssResult = Application.Run("RssStockOrder_v", _
        orderId, _
        orderParams("ticker"), _
        orderParams("side"), _
        0, _
        0, _
        orderParams("quantity"), _
        orderParams("priceType"), _
        orderParams("price"), _
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

    ' === Step 6: 結果判定 ===
    If IsError(rssResult) Then
        Debug.Print "RssStockOrder_v returned Error"
        Call LogError("RSS_ERROR", "SafeExecuteOrder", "RssStockOrder_v returned error", orderParams("ticker"), "CRITICAL")

        SafeExecuteOrder = ""
        Exit Function
    End If

    Dim resultStr As String
    resultStr = CStr(rssResult)

    ' RssStockOrder_vは成功コードを返す (0=成功)
    If rssResult = 0 Then
        ' 成功
        Debug.Print "Order SUCCESS: " & orderId

        ' 監査ログ記録（成功）
        Call LogOrderSuccess(signal("signal_id"), orderParams, orderId)

        ' カウンター更新
        If orderParams("side") = 3 Then  ' 買い(3=現物買)
            Dim currentCount As Long
            currentCount = CLng(GetSystemState("daily_entry_count"))
            Call SetSystemState("daily_entry_count", currentCount + 1)
        End If

        SafeExecuteOrder = orderId
    Else
        ' RSS側エラー
        Debug.Print "RssStockOrder_v failed: " & resultStr
        Call LogError("RSS_ERROR", "SafeExecuteOrder", resultStr, orderParams("ticker"), "ERROR")

        SafeExecuteOrder = ""
    End If

    Exit Function

ErrorHandler:
    Debug.Print "Exception in SafeExecuteOrder: " & Err.Description
    Call LogError("ORDER_EXCEPTION", "SafeExecuteOrder", Err.Description, orderParams("ticker"), "CRITICAL")

    SafeExecuteOrder = ""
End Function

' ========================================
' レベル2: 発注可否判定（5段階チェック）
' ========================================
Function CanExecuteOrder(orderParams As Dictionary) As Dictionary
    '
    ' 発注可否を多層チェック
    '
    Dim result As New Dictionary
    Set result = New Dictionary
    result("allowed") = False
    result("reason") = ""
    
    Dim checks As Dictionary
    Set checks = New Dictionary
    Set result("checks") = checks

    ' === Level 1: Kill Switch チェック ===
    If Not IsSystemEnabled() Then
        result("reason") = "kill_switch_active"
        result("checks")("kill_switch") = "BLOCKED"
        Set CanExecuteOrder = result
        Exit Function
    End If
    result("checks")("kill_switch") = "OK"

    ' === Level 2: 市場時間チェック ===
    If Not IsSafeTradingWindow() Then
        result("reason") = "outside_trading_hours"
        result("checks")("market_hours") = "BLOCKED"
        Set CanExecuteOrder = result
        Exit Function
    End If
    result("checks")("market_hours") = "OK"

    ' === Level 3: パラメータ検証 ===
    Dim paramValidation As Dictionary
    Set paramValidation = ValidateOrderParameters(orderParams)

    If Not paramValidation("valid") Then
        result("reason") = "parameter_validation_failed"
        result("checks")("parameters") = "BLOCKED"
        Set result("parameter_errors") = paramValidation("errors")
        Set CanExecuteOrder = result
        Exit Function
    End If
    result("checks")("parameters") = "OK"

    ' === Level 4: 日次制限チェック ===
    If Not CheckDailyLimits(orderParams("side")) Then
        result("reason") = "daily_limit_exceeded"
        result("checks")("daily_limits") = "BLOCKED"
        Set CanExecuteOrder = result
        Exit Function
    End If
    result("checks")("daily_limits") = "OK"

    ' === Level 5: リスク制限チェック ===
    If orderParams("side") = 3 Then  ' 買いの場合(3=現物買)
        Dim riskCheck As Dictionary
        Set riskCheck = CheckRiskLimits(orderParams("ticker"), orderParams("quantity"))

        If Not riskCheck("allowed") Then
            result("reason") = riskCheck("reason")
            result("checks")("risk_limits") = "BLOCKED"
            Set CanExecuteOrder = result
            Exit Function
        End If
    End If
    result("checks")("risk_limits") = "OK"

    ' === 全チェック通過 ===
    result("allowed") = True
    result("reason") = "all_checks_passed"
    Set CanExecuteOrder = result
End Function

' ========================================
' レベル3: 統合パラメータ検証
' ========================================
Function ValidateOrderParameters(orderParams As Dictionary) As Dictionary
    '
    ' 全パラメータを統合検証
    '
    Dim result As New Dictionary
    result("valid") = True
    Set result("errors") = New Collection

    ' 1. 銘柄コード検証
    Dim tickerResult As Dictionary
    Set tickerResult = ValidateTicker(orderParams("ticker"))
    If Not tickerResult("valid") Then
        result("valid") = False
        Dim err As Variant
        For Each err In tickerResult("errors")
            result("errors").Add err
        Next err
    End If

    ' 2. 売買区分検証
    Dim sideResult As Dictionary
    Set sideResult = ValidateSide(orderParams("side"), orderParams("ticker"))
    If Not sideResult("valid") Then
        result("valid") = False
        For Each err In sideResult("errors")
            result("errors").Add err
        Next err
    End If

    ' 3. 数量検証
    Dim qtyResult As Dictionary
    Set qtyResult = ValidateQuantity(orderParams("quantity"), orderParams("ticker"), orderParams("side"))
    If Not qtyResult("valid") Then
        result("valid") = False
        For Each err In qtyResult("errors")
            result("errors").Add err
        Next err
    End If

    ' 4. 価格種別検証
    Dim priceTypeResult As Dictionary
    Set priceTypeResult = ValidatePriceType(orderParams("priceType"))
    If Not priceTypeResult("valid") Then
        result("valid") = False
        For Each err In priceTypeResult("errors")
            result("errors").Add err
        Next err
    End If

    ' 5. 価格検証
    Dim priceResult As Dictionary
    Set priceResult = ValidatePrice(orderParams("price"), orderParams("priceType"))
    If Not priceResult("valid") Then
        result("valid") = False
        For Each err In priceResult("errors")
            result("errors").Add err
        Next err
    End If

    ' 6. 執行条件検証
    Dim conditionResult As Dictionary
    Set conditionResult = ValidateCondition(orderParams("condition"))
    If Not conditionResult("valid") Then
        result("valid") = False
        For Each err In conditionResult("errors")
            result("errors").Add err
        Next err
    End If

    Set ValidateOrderParameters = result
End Function

' ========================================
' パラメータ検証: 銘柄コード
' ========================================
Function ValidateTicker(ticker As String) As Dictionary
    Dim result As New Dictionary
    result("valid") = False
    Set result("errors") = New Collection

    ' 1. 必須チェック
    If ticker = "" Then
        result("errors").Add "銘柄コードが空です"
        Set ValidateTicker = result
        Exit Function
    End If

    ' 2. 長さチェック
    If Len(ticker) <> 4 Then
        result("errors").Add "銘柄コードは4桁である必要があります: " & ticker
        Set ValidateTicker = result
        Exit Function
    End If

    ' 3. 数字チェック
    If Not IsNumeric(ticker) Then
        result("errors").Add "銘柄コードは数字のみ: " & ticker
        Set ValidateTicker = result
        Exit Function
    End If

    ' 4. ホワイトリストチェック（推奨銘柄のみ許可）
    Dim allowedTickers As Collection
    Set allowedTickers = GetAllowedTickers()

    Dim found As Boolean
    found = False
    Dim t As Variant
    For Each t In allowedTickers
        If t = ticker Then
            found = True
            Exit For
        End If
    Next t

    If Not found Then
        result("errors").Add "許可されていない銘柄: " & ticker
        Set ValidateTicker = result
        Exit Function
    End If

    ' 5. ブラックリストチェック
    If IsTickerBlacklisted(ticker) Then
        result("errors").Add "ブラックリスト銘柄: " & ticker
        Set ValidateTicker = result
        Exit Function
    End If

    result("valid") = True
    Set ValidateTicker = result
End Function

' ========================================
' パラメータ検証: 売買区分
' ========================================
Function ValidateSide(side As Integer, ticker As String) As Dictionary
    Dim result As New Dictionary
    result("valid") = False
    Set result("errors") = New Collection

    ' 1. 値範囲チェック
    If side <> 3 And side <> 1 Then
        result("errors").Add "売買区分は3（現物買）または1（現物売）のみ: " & side
        Set ValidateSide = result
        Exit Function
    End If

    ' 2. 売りの場合はポジション確認
    If side = 1 Then  ' 売り(1=現物売)
        If Not HasPosition(ticker) Then
            result("errors").Add "ポジションなしで売り注文: " & ticker
            Set ValidateSide = result
            Exit Function
        End If

        ' 売却可能数量チェック
        Dim availableQty As Long
        availableQty = GetAvailableQuantity(ticker)

        If availableQty <= 0 Then
            result("errors").Add "売却可能数量なし: " & ticker
            Set ValidateSide = result
            Exit Function
        End If
    End If

    result("valid") = True
    Set ValidateSide = result
End Function

' ========================================
' パラメータ検証: 数量
' ========================================
Function ValidateQuantity(quantity As Long, ticker As String, side As Integer) As Dictionary
    Dim result As New Dictionary
    result("valid") = False
    Set result("errors") = New Collection

    ' 1. 範囲チェック
    If quantity <= 0 Then
        result("errors").Add "数量は正の値である必要があります: " & quantity
        Set ValidateQuantity = result
        Exit Function
    End If

    ' 2. 単元株チェック（100株単位）
    If quantity Mod 100 <> 0 Then
        result("errors").Add "数量は100株単位である必要があります: " & quantity
        Set ValidateQuantity = result
        Exit Function
    End If

    ' 3. 最小/最大チェック
    Dim minQty As Long: minQty = 100
    Dim maxQty As Long: maxQty = 10000  ' 1注文あたり最大10,000株

    If quantity < minQty Then
        result("errors").Add "数量が最小値未満: " & quantity & " < " & minQty
        Set ValidateQuantity = result
        Exit Function
    End If

    If quantity > maxQty Then
        result("errors").Add "数量が最大値超過: " & quantity & " > " & maxQty
        Set ValidateQuantity = result
        Exit Function
    End If

    ' 4. 売りの場合は保有数量チェック
    If side = 1 Then  ' 売り(1=現物売)
        Dim availableQty As Long
        availableQty = GetAvailableQuantity(ticker)

        If quantity > availableQty Then
            result("errors").Add "売却数量が保有数量超過: " & quantity & " > " & availableQty
            Set ValidateQuantity = result
            Exit Function
        End If
    End If

    ' 5. 金額上限チェック（買いの場合）
    If side = 3 Then  ' 買い(3=現物買)
        Dim currentPrice As Double
        currentPrice = GetCurrentPrice(ticker)

        If currentPrice = 0 Then
            result("errors").Add "現在価格取得失敗: " & ticker
            Set ValidateQuantity = result
            Exit Function
        End If

        Dim orderValue As Double
        orderValue = currentPrice * quantity

        Dim maxOrderValue As Long
        maxOrderValue = CLng(GetConfig("MAX_POSITION_PER_TICKER"))

        If orderValue > maxOrderValue Then
            result("errors").Add "注文金額が上限超過: " & Format(orderValue, "#,##0") & " > " & Format(maxOrderValue, "#,##0")
            Set ValidateQuantity = result
            Exit Function
        End If
    End If

    result("valid") = True
    Set ValidateQuantity = result
End Function

' ========================================
' パラメータ検証: 価格種別
' ========================================
Function ValidatePriceType(priceType As Integer) As Dictionary
    Dim result As New Dictionary
    result("valid") = False
    Set result("errors") = New Collection

    ' 全自動売買では成行（0）のみ許可
    If priceType <> 0 Then
        result("errors").Add "全自動売買では成行注文（0）のみ許可: " & priceType
        Set ValidatePriceType = result
        Exit Function
    End If

    result("valid") = True
    Set ValidatePriceType = result
End Function

' ========================================
' パラメータ検証: 価格
' ========================================
Function ValidatePrice(price As Double, priceType As Integer) As Dictionary
    Dim result As New Dictionary
    result("valid") = False
    Set result("errors") = New Collection

    ' 成行の場合は0
    If priceType = 0 Then
        If price <> 0 Then
            result("errors").Add "成行注文の価格は0である必要があります: " & price
            Set ValidatePrice = result
            Exit Function
        End If
    Else
        ' 指値の場合（全自動では使用しないが念のため）
        If price <= 0 Then
            result("errors").Add "指値価格は正の値である必要があります: " & price
            Set ValidatePrice = result
            Exit Function
        End If
    End If

    result("valid") = True
    Set ValidatePrice = result
End Function

' ========================================
' パラメータ検証: 執行条件
' ========================================
Function ValidateCondition(condition As Integer) As Dictionary
    Dim result As New Dictionary
    result("valid") = False
    Set result("errors") = New Collection

    ' 全自動売買では通常注文（0）のみ許可
    If condition <> 0 Then
        result("errors").Add "全自動売買では通常注文（0）のみ許可: " & condition
        Set ValidateCondition = result
        Exit Function
    End If

    result("valid") = True
    Set ValidateCondition = result
End Function

' ========================================
' リスク制限チェック
' ========================================
Function CheckRiskLimits(ticker As String, quantity As Long) As Dictionary
    Dim result As New Dictionary
    result("allowed") = True
    result("reason") = ""

    Dim currentPrice As Double
    currentPrice = GetCurrentPrice(ticker)

    If currentPrice = 0 Then
        result("allowed") = False
        result("reason") = "price_unavailable"
        Set CheckRiskLimits = result
        Exit Function
    End If

    Dim orderValue As Double
    orderValue = currentPrice * quantity

    ' 1. 総ポジション上限チェック
    Dim totalPositionValue As Double
    totalPositionValue = CDbl(GetSystemState("total_position_value"))

    Dim maxTotalExposure As Long
    maxTotalExposure = CLng(GetConfig("MAX_POSITION_VALUE"))

    If totalPositionValue + orderValue > maxTotalExposure Then
        result("allowed") = False
        result("reason") = "total_exposure_exceeded"
        Set CheckRiskLimits = result
        Exit Function
    End If

    ' 2. 1銘柄あたり上限チェック
    Dim currentTickerValue As Double
    currentTickerValue = GetPositionValue(ticker)

    Dim maxPerTicker As Long
    maxPerTicker = CLng(GetConfig("MAX_POSITION_PER_TICKER"))

    If currentTickerValue + orderValue > maxPerTicker Then
        result("allowed") = False
        result("reason") = "per_ticker_limit_exceeded"
        Set CheckRiskLimits = result
        Exit Function
    End If

    ' 3. 最大ポジション数チェック
    Dim currentPositions As Long
    currentPositions = CountOpenPositions()

    Dim maxPositions As Long
    maxPositions = CLng(GetConfig("MAX_POSITIONS"))

    If currentPositions >= maxPositions And Not HasPosition(ticker) Then
        result("allowed") = False
        result("reason") = "max_positions_exceeded"
        Set CheckRiskLimits = result
        Exit Function
    End If

    Set CheckRiskLimits = result
End Function

' ========================================
' 日次制限チェック
' ========================================
Function CheckDailyLimits(side As Integer) As Boolean
    Dim dailyEntryCount As Long
    dailyEntryCount = CLng(GetSystemState("daily_entry_count"))

    Dim maxDailyEntries As Long
    maxDailyEntries = CLng(GetConfig("MAX_DAILY_ENTRIES"))

    If side = 3 Then  ' 買い(3=現物買)
        If dailyEntryCount >= maxDailyEntries Then
            Debug.Print "Daily entry limit exceeded: " & dailyEntryCount & " >= " & maxDailyEntries
            CheckDailyLimits = False
            Exit Function
        End If
    End If

    CheckDailyLimits = True
End Function

' ========================================
' ダブルチェック（最終確認）
' ========================================
Function DoubleCheckOrder(orderParams As Dictionary) As Boolean
    '
    ' 発注直前の最終確認
    '
    Dim checkLog As String
    checkLog = "=== Double Check ===" & vbCrLf

    ' 1. パラメータ再確認
    checkLog = checkLog & "Ticker: " & orderParams("ticker") & vbCrLf
    checkLog = checkLog & "Side: " & IIf(orderParams("side") = 3, "BUY", "SELL") & vbCrLf
    checkLog = checkLog & "Quantity: " & orderParams("quantity") & vbCrLf
    checkLog = checkLog & "Type: " & IIf(orderParams("priceType") = 0, "MARKET", "LIMIT") & vbCrLf

    ' 2. 現在価格取得
    Dim currentPrice As Double
    currentPrice = GetCurrentPrice(orderParams("ticker"))
    checkLog = checkLog & "Current Price: " & currentPrice & vbCrLf

    If currentPrice = 0 Then
        Debug.Print "Double check failed: Price unavailable"
        DoubleCheckOrder = False
        Exit Function
    End If

    ' 3. 注文金額計算
    Dim orderValue As Double
    orderValue = currentPrice * orderParams("quantity")
    checkLog = checkLog & "Order Value: " & Format(orderValue, "#,##0") & vbCrLf

    ' 4. 異常価格チェック（前日終値から±30%以内）
    Dim refPrice As Double
    refPrice = GetReferencePrice(orderParams("ticker"))  ' 前日終値

    If refPrice > 0 Then
        Dim priceChange As Double
        priceChange = (currentPrice - refPrice) / refPrice

        If Abs(priceChange) > 0.3 Then  ' ±30%超
            checkLog = checkLog & "ALERT: Abnormal price change: " & Format(priceChange * 100, "0.0") & "%" & vbCrLf
            Debug.Print checkLog
            DoubleCheckOrder = False  ' 異常価格で発注しない
            Exit Function
        End If
    End If

    ' 5. 売りの場合はポジション再確認
    If orderParams("side") = 1 Then  ' 売り(1=現物売)
        Dim availableQty As Long
        availableQty = GetAvailableQuantity(orderParams("ticker"))

        If availableQty < orderParams("quantity") Then
            checkLog = checkLog & "ERROR: Insufficient position" & vbCrLf
            Debug.Print checkLog
            DoubleCheckOrder = False
            Exit Function
        End If
    End If

    Debug.Print checkLog
    DoubleCheckOrder = True
End Function

' ========================================
' ヘルパー関数
' ========================================
Function IsSystemEnabled() As Boolean
    ' SystemStateシートのKill Switch状態を確認
    Dim status As String
    status = GetSystemState("system_status")

    IsSystemEnabled = (status = "Running")
End Function

Function GetAllowedTickers() As Collection
    ' 推奨銘柄リスト（TOPIX Core30から選定）
    Dim tickers As New Collection
    tickers.Add "9984"  ' SoftBank Group
    tickers.Add "6758"  ' Sony Group
    tickers.Add "7203"  ' Toyota
    tickers.Add "9433"  ' KDDI
    tickers.Add "8306"  ' Mitsubishi UFJ
    tickers.Add "6861"  ' Keyence
    tickers.Add "8035"  ' Tokyo Electron
    tickers.Add "4063"  ' Shin-Etsu Chemical
    tickers.Add "6098"  ' Recruit
    tickers.Add "4568"  ' Daiichi Sankyo
    Set GetAllowedTickers = tickers
End Function

Function HasPosition(ticker As String) As Boolean
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("PositionManager")

    Dim foundCell As Range
    Set foundCell = ws.Columns(1).Find(ticker, LookIn:=xlValues)

    HasPosition = Not foundCell Is Nothing
End Function

Function GetAvailableQuantity(ticker As String) As Long
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("PositionManager")

    Dim foundCell As Range
    Set foundCell = ws.Columns(1).Find(ticker, LookIn:=xlValues)

    If Not foundCell Is Nothing Then
        GetAvailableQuantity = ws.Cells(foundCell.Row, 3).Value  ' C列: quantity
    Else
        GetAvailableQuantity = 0
    End If
End Function

Function GetPositionValue(ticker As String) As Double
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("PositionManager")

    Dim foundCell As Range
    Set foundCell = ws.Columns(1).Find(ticker, LookIn:=xlValues)

    If Not foundCell Is Nothing Then
        Dim qty As Long
        Dim avgCost As Double
        qty = ws.Cells(foundCell.Row, 3).Value      ' C列: quantity
        avgCost = ws.Cells(foundCell.Row, 4).Value  ' D列: avg_cost
        GetPositionValue = qty * avgCost
    Else
        GetPositionValue = 0
    End If
End Function

Function CountOpenPositions() As Long
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("PositionManager")

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row

    ' ヘッダーを除くデータ行数
    If lastRow >= 2 Then
        CountOpenPositions = lastRow - 1
    Else
        CountOpenPositions = 0
    End If
End Function

' ========================================
' 監査ログ記録
' ========================================
Sub LogOrderAttempt(signalId As String, orderParams As Dictionary)
    '
    ' 発注試行ログ（全ての発注判断を記録）
    '
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("ErrorLog")  ' OrderAuditLogの代わりにErrorLogを使用

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    ws.Cells(lastRow, 1).Value = "ORDER_ATTEMPT_" & Format(Now, "yyyymmddhhnnss")
    ws.Cells(lastRow, 2).Value = Now
    ws.Cells(lastRow, 3).Value = "ORDER"
    ws.Cells(lastRow, 4).Value = "SafeExecuteOrder"
    ws.Cells(lastRow, 5).Value = orderParams("ticker")
    ws.Cells(lastRow, 6).Value = signalId
    ws.Cells(lastRow, 7).Value = "Attempting order: " & IIf(orderParams("side") = 3, "BUY", "SELL") & " " & orderParams("quantity")
End Sub

Sub LogOrderSuccess(signalId As String, orderParams As Dictionary, orderId As String)
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("ErrorLog")

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    ws.Cells(lastRow, 1).Value = "ORDER_SUCCESS_" & Format(Now, "yyyymmddhhnnss")
    ws.Cells(lastRow, 2).Value = Now
    ws.Cells(lastRow, 3).Value = "ORDER"
    ws.Cells(lastRow, 4).Value = "SafeExecuteOrder"
    ws.Cells(lastRow, 5).Value = orderParams("ticker")
    ws.Cells(lastRow, 6).Value = signalId
    ws.Cells(lastRow, 7).Value = "Order success: " & orderId & " | " & IIf(orderParams("side") = 3, "BUY", "SELL") & " " & orderParams("quantity")
    ws.Cells(lastRow, 9).Value = "INFO"
End Sub

Sub LogOrderBlocked(signalId As String, blockResult As Dictionary)
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("ErrorLog")

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    ws.Cells(lastRow, 1).Value = "ORDER_BLOCKED_" & Format(Now, "yyyymmddhhnnss")
    ws.Cells(lastRow, 2).Value = Now
    ws.Cells(lastRow, 3).Value = "ORDER"
    ws.Cells(lastRow, 4).Value = "SafeExecuteOrder"
    ws.Cells(lastRow, 5).Value = ""
    ws.Cells(lastRow, 6).Value = signalId
    ws.Cells(lastRow, 7).Value = "Order blocked: " & blockResult("reason")
    ws.Cells(lastRow, 9).Value = "WARNING"
End Sub

' ========================================
' 緊急停止機構
' ========================================
Sub ActivateKillSwitch(reason As String)
    '
    ' Kill Switch発動（即座に全発注停止）
    '
    Debug.Print "========================================="
    Debug.Print "KILL SWITCH ACTIVATED"
    Debug.Print "Reason: " & reason
    Debug.Print "========================================="

    ' システム停止
    Call SetSystemState("system_status", "Stopped")

    ' 自動売買停止
    Call StopAutoTrading

    ' アラート
    MsgBox "【緊急停止】" & vbCrLf & reason, vbCritical, "Kill Switch Activated"

    ' ログ記録
    Call LogError("KILL_SWITCH", "ActivateKillSwitch", reason, "", "CRITICAL")
End Sub

Sub CheckAutoKillSwitch()
    '
    ' 自動Kill Switchトリガー
    '
    On Error Resume Next

    ' 1. 連続損失チェック
    Dim consecutiveLosses As Long
    consecutiveLosses = CountConsecutiveLosses()

    If consecutiveLosses >= 5 Then
        Call ActivateKillSwitch("5連続損失")
        Exit Sub
    End If

    ' 2. 日次損失チェック
    Dim dailyPnL As Double
    dailyPnL = CalculateDailyPnL()

    If dailyPnL <= -50000 Then  ' -5万円
        Call ActivateKillSwitch("日次損失-5万円超過")
        Exit Sub
    End If

    ' 3. 異常頻度チェック
    Dim hourlyTrades As Long
    hourlyTrades = CountTradesLastHour()

    If hourlyTrades >= 10 Then
        Call ActivateKillSwitch("異常な取引頻度（1時間10回）")
        Exit Sub
    End If
End Sub

Function CountConsecutiveLosses() As Long
    ' ExecutionLogから連続損失をカウント
    On Error Resume Next
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("ExecutionLog")

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row

    Dim consecutiveCount As Long
    consecutiveCount = 0

    Dim i As Long
    For i = lastRow To 2 Step -1
        Dim pnl As Double
        pnl = ws.Cells(i, 10).Value  ' J列: realized_pnl

        If pnl < 0 Then
            consecutiveCount = consecutiveCount + 1
        Else
            Exit For  ' 損失が途切れた
        End If
    Next i

    CountConsecutiveLosses = consecutiveCount
End Function

Function CalculateDailyPnL() As Double
    ' 本日の実現損益を計算
    On Error Resume Next
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("ExecutionLog")

    Dim totalPnL As Double
    totalPnL = 0

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim execDate As Date
        execDate = ws.Cells(i, 2).Value  ' B列: execution_time

        If DateValue(execDate) = Date Then
            totalPnL = totalPnL + ws.Cells(i, 10).Value  ' J列: realized_pnl
        End If
    Next i

    CalculateDailyPnL = totalPnL
End Function

Function CountTradesLastHour() As Long
    ' 直近1時間の取引数
    On Error Resume Next
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("ExecutionLog")

    Dim count As Long
    count = 0

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row

    Dim oneHourAgo As Date
    oneHourAgo = DateAdd("h", -1, Now)

    Dim i As Long
    For i = 2 To lastRow
        Dim execTime As Date
        execTime = ws.Cells(i, 2).Value

        If execTime >= oneHourAgo Then
            count = count + 1
        End If
    Next i

    CountTradesLastHour = count
End Function

' ========================================
' RSS関数呼び出し（既存機能）
' ========================================
Function GetCurrentPrice(ticker As String) As Double
    On Error GoTo ErrorHandler

    Dim result As Variant
    result = Application.Run("RssMarket", ticker, "現在値")

    If IsError(result) Then
        Debug.Print "RssMarket Error for ticker: " & ticker
        GetCurrentPrice = 0
        Exit Function
    End If

    GetCurrentPrice = CDbl(result)
    Exit Function

ErrorHandler:
    Debug.Print "Error getting current price: " & Err.Description
    GetCurrentPrice = 0
End Function

Function GetReferencePrice(ticker As String) As Double
    ' 前日終値を取得（RssMarketまたはキャッシュ）
    On Error Resume Next
    Dim refPrice As Variant
    refPrice = Application.Run("RssMarket", ticker, "前日終値")

    If IsError(refPrice) Or refPrice <= 0 Then
        GetReferencePrice = 0
    Else
        GetReferencePrice = CDbl(refPrice)
    End If
End Function

Function GetTickerName(ticker As String) As String
    On Error GoTo ErrorHandler

    Dim result As Variant
    result = Application.Run("RssMarket", ticker, "銘柄名称")

    If IsError(result) Or result = "" Then
        ' フォールバック: 静的マッピング
        Select Case ticker
            Case "9984": GetTickerName = "SoftBank Group"
            Case "6758": GetTickerName = "Sony Group"
            Case "7203": GetTickerName = "Toyota"
            Case "9433": GetTickerName = "KDDI"
            Case "8306": GetTickerName = "Mitsubishi UFJ"
            Case "6861": GetTickerName = "Keyence"
            Case "8035": GetTickerName = "Tokyo Electron"
            Case "4063": GetTickerName = "Shin-Etsu Chemical"
            Case "6098": GetTickerName = "Recruit"
            Case "4568": GetTickerName = "Daiichi Sankyo"
            Case Else: GetTickerName = ticker
        End Select
    Else
        GetTickerName = CStr(result)
    End If

    Exit Function

ErrorHandler:
    Debug.Print "Error getting ticker name: " & Err.Description
    GetTickerName = ticker
End Function

Function CheckRSSConnection() As Boolean
    On Error GoTo ErrorHandler

    ' テスト用に適当な銘柄コードで価格取得
    Dim testTicker As String
    testTicker = "9984"  ' SoftBank Group

    Dim result As Variant
    result = Application.Run("RssMarket", testTicker, "現在値")

    If IsError(result) Then
        CheckRSSConnection = False
    Else
        CheckRSSConnection = True
    End If

    Exit Function

ErrorHandler:
    Debug.Print "RSS connection check failed: " & Err.Description
    CheckRSSConnection = False
End Function

' ========================================
' 注文状態ポーリング（既存機能）
' ========================================
Sub PollOrderStatus(internalId As String)
    On Error GoTo ErrorHandler

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("OrderHistory")

    ' OrderHistoryから該当行検索
    Dim foundCell As Range
    Set foundCell = ws.Columns(1).Find(internalId, LookIn:=xlValues, LookAt:=xlWhole)

    If foundCell Is Nothing Then Exit Sub

    Dim orderRow As Long
    orderRow = foundCell.Row

    Dim rssOrderId As String
    rssOrderId = ws.Cells(orderRow, 9).Value  ' I列: rss_order_id

    If rssOrderId = "" Then Exit Sub

    ' RssOrderStatus関数で注文状態照会
    Dim result As Variant
    result = Application.Run("RssOrderStatus", rssOrderId)

    If IsError(result) Then
        Debug.Print "RssOrderStatus Error for order: " & internalId
        Exit Sub
    End If

    Dim resultStr As String
    resultStr = CStr(result)

    ' result形式: "約定済み|価格:3001|数量:100|手数料:150"
    If InStr(resultStr, "約定済み") > 0 Then
        ' 約定済み - データ解析
        Dim parts() As String
        parts = Split(resultStr, "|")

        Dim price As Double
        Dim quantity As Long
        Dim commission As Double

        ' データ抽出
        Dim i As Integer
        For i = LBound(parts) To UBound(parts)
            If InStr(parts(i), "価格:") > 0 Then
                price = CDbl(Split(parts(i), ":")(1))
            ElseIf InStr(parts(i), "数量:") > 0 Then
                quantity = CLng(Split(parts(i), ":")(1))
            ElseIf InStr(parts(i), "手数料:") > 0 Then
                commission = CDbl(Split(parts(i), ":")(1))
            End If
        Next i

        ' OrderHistory更新
        Call UpdateOrderStatus(internalId, "filled", price, quantity, commission)

        ' ExecutionLog記録
        Call RecordExecution(internalId)

        Debug.Print "Order filled: " & internalId & " at " & price
    ElseIf InStr(resultStr, "受付済み") > 0 Then
        ' まだ約定していない
        Debug.Print "Order pending: " & internalId
    ElseIf InStr(resultStr, "取消済み") > 0 Or InStr(resultStr, "拒否") > 0 Then
        ' 取消・拒否
        Call UpdateOrderStatus(internalId, "cancelled")
        Debug.Print "Order cancelled/rejected: " & internalId
    End If

    Exit Sub

ErrorHandler:
    Debug.Print "Error polling order status: " & Err.Description
    Call LogError("RSS_ERROR", "PollOrderStatus", Err.Description, internalId, "ERROR")
End Sub

' ========================================
' 後方互換性：ExecuteOrder（非推奨）
' ========================================
Function ExecuteOrder(signal As Object) As String
    '
    ' 後方互換性のため残すが、SafeExecuteOrderを使用すること
    '
    Debug.Print "WARNING: ExecuteOrder is deprecated. Use SafeExecuteOrder instead."

    ' SafeExecuteOrderに転送
    ExecuteOrder = SafeExecuteOrder(signal)
End Function