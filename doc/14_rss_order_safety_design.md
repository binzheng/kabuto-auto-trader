# 14. MarketSpeed II RSS 安全発注設計

## 目的

MarketSpeed II RSSの下単関数（RSS.ORDER）を使用した全自動発注システムの安全設計。

- **誤発注防止**: 多層検証による完全な誤発注防止
- **パラメータ検証**: 発注前の厳密なパラメータチェック
- **トリガー制御**: 発注タイミングの厳密な制御
- **監査証跡**: 全ての発注判断を記録

---

## 1. RSS.ORDER() 関数仕様

### 1.1 関数シグネチャ

```vba
Function RSS.ORDER( _
    ticker As String, _        ' 銘柄コード（4桁）
    side As Integer, _         ' 売買区分（1=買, 2=売）
    quantity As Long, _        ' 数量（株数）
    priceType As Integer, _    ' 価格種別（0=成行, 1=指値, 2=逆指値）
    price As Double, _         ' 価格（成行の場合は0）
    condition As Integer _     ' 執行条件（0=なし, 1=寄成, 2=引成, 3=不成, 4=IOC）
) As Variant
```

**戻り値**:
- **成功**: `"注文番号:YYYYMMDD-NNNNNNNN"`
- **失敗**: エラーメッセージ文字列 または Error型

---

### 1.2 パラメータ制約

| パラメータ | 型 | 範囲 | 例 | 備考 |
|-----------|-----|------|-----|------|
| ticker | String | 4桁数字 | "9984" | 数字のみ、ゼロ埋め不要 |
| side | Integer | 1 or 2 | 1 | 1=買, 2=売 |
| quantity | Long | 100-100,000,000 | 100 | 単元株（100株単位） |
| priceType | Integer | 0, 1, 2 | 0 | 0=成行推奨 |
| price | Double | 0 or 市場価格±30% | 0 | 成行は0 |
| condition | Integer | 0-4 | 0 | 0=なし（通常） |

---

## 2. パラメータ設計と検証

### 2.1 パラメータ検証ルール

#### A. 銘柄コード検証

```vba
Function ValidateTicker(ticker As String) As Dictionary
    Dim result As New Dictionary
    result("valid") = False
    result("errors") = New Collection

    ' 1. 必須チェック
    If ticker = "" Then
        result("errors").Add "銘柄コードが空です"
        Return result
    End If

    ' 2. 長さチェック
    If Len(ticker) <> 4 Then
        result("errors").Add "銘柄コードは4桁である必要があります: " & ticker
        Return result
    End If

    ' 3. 数字チェック
    If Not IsNumeric(ticker) Then
        result("errors").Add "銘柄コードは数字のみ: " & ticker
        Return result
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
        Return result
    End If

    ' 5. ブラックリストチェック
    If IsTickerBlacklisted(ticker) Then
        result("errors").Add "ブラックリスト銘柄: " & ticker
        Return result
    End If

    result("valid") = True
    Return ValidateTicker = result
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
    Return GetAllowedTickers = tickers
End Function
```

#### B. 売買区分検証

```vba
Function ValidateSide(side As Integer, ticker As String) As Dictionary
    Dim result As New Dictionary
    result("valid") = False
    result("errors") = New Collection

    ' 1. 値範囲チェック
    If side <> 1 And side <> 2 Then
        result("errors").Add "売買区分は1（買）または2（売）のみ: " & side
        Return result
    End If

    ' 2. 売りの場合はポジション確認
    If side = 2 Then  ' 売り
        If Not HasPosition(ticker) Then
            result("errors").Add "ポジションなしで売り注文: " & ticker
            Return result
        End If

        ' 売却可能数量チェック
        Dim availableQty As Long
        availableQty = GetAvailableQuantity(ticker)

        If availableQty <= 0 Then
            result("errors").Add "売却可能数量なし: " & ticker
            Return result
        End If
    End If

    result("valid") = True
    Return ValidateSide = result
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
```

#### C. 数量検証

```vba
Function ValidateQuantity(quantity As Long, ticker As String, side As Integer) As Dictionary
    Dim result As New Dictionary
    result("valid") = False
    result("errors") = New Collection

    ' 1. 範囲チェック
    If quantity <= 0 Then
        result("errors").Add "数量は正の値である必要があります: " & quantity
        Return result
    End If

    ' 2. 単元株チェック（100株単位）
    If quantity Mod 100 <> 0 Then
        result("errors").Add "数量は100株単位である必要があります: " & quantity
        Return result
    End If

    ' 3. 最小/最大チェック
    Dim minQty As Long: minQty = 100
    Dim maxQty As Long: maxQty = 10000  ' 1注文あたり最大10,000株

    If quantity < minQty Then
        result("errors").Add "数量が最小値未満: " & quantity & " < " & minQty
        Return result
    End If

    If quantity > maxQty Then
        result("errors").Add "数量が最大値超過: " & quantity & " > " & maxQty
        Return result
    End If

    ' 4. 売りの場合は保有数量チェック
    If side = 2 Then  ' 売り
        Dim availableQty As Long
        availableQty = GetAvailableQuantity(ticker)

        If quantity > availableQty Then
            result("errors").Add "売却数量が保有数量超過: " & quantity & " > " & availableQty
            Return result
        End If
    End If

    ' 5. 金額上限チェック（買いの場合）
    If side = 1 Then  ' 買い
        Dim currentPrice As Double
        currentPrice = GetCurrentPrice(ticker)

        If currentPrice = 0 Then
            result("errors").Add "現在価格取得失敗: " & ticker
            Return result
        End If

        Dim orderValue As Double
        orderValue = currentPrice * quantity

        Dim maxOrderValue As Long
        maxOrderValue = CLng(GetConfig("MAX_POSITION_PER_TICKER"))

        If orderValue > maxOrderValue Then
            result("errors").Add "注文金額が上限超過: " & Format(orderValue, "#,##0") & " > " & Format(maxOrderValue, "#,##0")
            Return result
        End If
    End If

    result("valid") = True
    Return ValidateQuantity = result
End Function
```

#### D. 価格種別・価格検証

```vba
Function ValidatePriceType(priceType As Integer) As Dictionary
    Dim result As New Dictionary
    result("valid") = False
    result("errors") = New Collection

    ' 全自動売買では成行（0）のみ許可
    If priceType <> 0 Then
        result("errors").Add "全自動売買では成行注文（0）のみ許可: " & priceType
        Return result
    End If

    result("valid") = True
    Return ValidatePriceType = result
End Function

Function ValidatePrice(price As Double, priceType As Integer) As Dictionary
    Dim result As New Dictionary
    result("valid") = False
    result("errors") = New Collection

    ' 成行の場合は0
    If priceType = 0 Then
        If price <> 0 Then
            result("errors").Add "成行注文の価格は0である必要があります: " & price
            Return result
        End If
    Else
        ' 指値の場合（全自動では使用しないが念のため）
        If price <= 0 Then
            result("errors").Add "指値価格は正の値である必要があります: " & price
            Return result
        End If
    End If

    result("valid") = True
    Return ValidatePrice = result
End Function
```

#### E. 執行条件検証

```vba
Function ValidateCondition(condition As Integer) As Dictionary
    Dim result As New Dictionary
    result("valid") = False
    result("errors") = New Collection

    ' 全自動売買では通常注文（0）のみ許可
    If condition <> 0 Then
        result("errors").Add "全自動売買では通常注文（0）のみ許可: " & condition
        Return result
    End If

    result("valid") = True
    Return ValidateCondition = result
End Function
```

---

### 2.2 統合パラメータ検証

```vba
Function ValidateOrderParameters(orderParams As Dictionary) As Dictionary
    '
    ' 全パラメータを統合検証
    '
    Dim result As New Dictionary
    result("valid") = True
    result("errors") = New Collection

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

    Return ValidateOrderParameters = result
End Function
```

---

## 3. トリガー制御設計

### 3.1 発注可否判定（5段階チェック）

```vba
Function CanExecuteOrder(orderParams As Dictionary) As Dictionary
    '
    ' 発注可否を多層チェック
    '
    Dim result As New Dictionary
    result("allowed") = False
    result("reason") = ""
    result("checks") = New Dictionary

    ' === Level 1: Kill Switch チェック ===
    If Not IsSystemEnabled() Then
        result("reason") = "kill_switch_active"
        result("checks")("kill_switch") = "BLOCKED"
        Return CanExecuteOrder = result
    End If
    result("checks")("kill_switch") = "OK"

    ' === Level 2: 市場時間チェック ===
    If Not IsSafeTradingWindow() Then
        result("reason") = "outside_trading_hours"
        result("checks")("market_hours") = "BLOCKED"
        Return CanExecuteOrder = result
    End If
    result("checks")("market_hours") = "OK"

    ' === Level 3: パラメータ検証 ===
    Dim paramValidation As Dictionary
    Set paramValidation = ValidateOrderParameters(orderParams)

    If Not paramValidation("valid") Then
        result("reason") = "parameter_validation_failed"
        result("checks")("parameters") = "BLOCKED"
        result("parameter_errors") = paramValidation("errors")
        Return CanExecuteOrder = result
    End If
    result("checks")("parameters") = "OK"

    ' === Level 4: 日次制限チェック ===
    If Not CheckDailyLimits(orderParams("side")) Then
        result("reason") = "daily_limit_exceeded"
        result("checks")("daily_limits") = "BLOCKED"
        Return CanExecuteOrder = result
    End If
    result("checks")("daily_limits") = "OK"

    ' === Level 5: リスク制限チェック ===
    If orderParams("side") = 1 Then  ' 買いの場合
        Dim riskCheck As Dictionary
        Set riskCheck = CheckRiskLimits(orderParams("ticker"), orderParams("quantity"))

        If Not riskCheck("allowed") Then
            result("reason") = riskCheck("reason")
            result("checks")("risk_limits") = "BLOCKED"
            Return CanExecuteOrder = result
        End If
    End If
    result("checks")("risk_limits") = "OK"

    ' === 全チェック通過 ===
    result("allowed") = True
    result("reason") = "all_checks_passed"
    Return CanExecuteOrder = result
End Function

Function IsSystemEnabled() As Boolean
    ' SystemStateシートのKill Switch状態を確認
    Dim status As String
    status = GetSystemState("system_status")

    IsSystemEnabled = (status = "Running")
End Function

Function CheckDailyLimits(side As Integer) As Boolean
    Dim dailyEntryCount As Long
    dailyEntryCount = CLng(GetSystemState("daily_entry_count"))

    Dim maxDailyEntries As Long
    maxDailyEntries = CLng(GetConfig("MAX_DAILY_ENTRIES"))

    If side = 1 Then  ' 買い
        If dailyEntryCount >= maxDailyEntries Then
            Debug.Print "Daily entry limit exceeded: " & dailyEntryCount & " >= " & maxDailyEntries
            Return False
        End If
    End If

    CheckDailyLimits = True
End Function

Function CheckRiskLimits(ticker As String, quantity As Long) As Dictionary
    Dim result As New Dictionary
    result("allowed") = True
    result("reason") = ""

    Dim currentPrice As Double
    currentPrice = GetCurrentPrice(ticker)

    If currentPrice = 0 Then
        result("allowed") = False
        result("reason") = "price_unavailable"
        Return CheckRiskLimits = result
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
        Return CheckRiskLimits = result
    End If

    ' 2. 1銘柄あたり上限チェック
    Dim currentTickerValue As Double
    currentTickerValue = GetPositionValue(ticker)

    Dim maxPerTicker As Long
    maxPerTicker = CLng(GetConfig("MAX_POSITION_PER_TICKER"))

    If currentTickerValue + orderValue > maxPerTicker Then
        result("allowed") = False
        result("reason") = "per_ticker_limit_exceeded"
        Return CheckRiskLimits = result
    End If

    ' 3. 最大ポジション数チェック
    Dim currentPositions As Long
    currentPositions = CountOpenPositions()

    Dim maxPositions As Long
    maxPositions = CLng(GetConfig("MAX_POSITIONS"))

    If currentPositions >= maxPositions And Not HasPosition(ticker) Then
        result("allowed") = False
        result("reason") = "max_positions_exceeded"
        Return CheckRiskLimits = result
    End If

    Return CheckRiskLimits = result
End Function
```

---

### 3.2 トリガー実行タイミング制御

```vba
Function GetTriggerState() As String
    '
    ' トリガー状態を判定
    '
    ' READY      - 発注可能
    ' BLOCKED    - 発注ブロック中
    ' WAITING    - 待機中
    ' COOLDOWN   - クールダウン中
    '

    ' 1. Kill Switch チェック
    If Not IsSystemEnabled() Then
        Return "BLOCKED"
    End If

    ' 2. 市場時間チェック
    If Not IsMarketOpen() Then
        Return "WAITING"
    End If

    ' 3. 安全取引時間チェック
    If Not IsSafeTradingWindow() Then
        Return "WAITING"
    End If

    ' 4. クールダウンチェック
    Static lastOrderTime As Date
    If lastOrderTime <> 0 Then
        Dim intervalSec As Long
        intervalSec = CLng(GetConfig("ORDER_INTERVAL_SEC"))
        If intervalSec = 0 Then intervalSec = 30  ' デフォルト30秒

        If DateDiff("s", lastOrderTime, Now) < intervalSec Then
            Return "COOLDOWN"
        End If
    End If

    ' 5. 全チェック通過
    Return "READY"
End Function
```

---

## 4. 誤発注防止機構

### 4.1 多層防御（6層）

```
Layer 1: 事前検証     - パラメータ検証、ホワイトリスト
Layer 2: トリガー制御  - 市場時間、Kill Switch
Layer 3: 日次制限     - エントリー数、取引数
Layer 4: リスク制限    - ポジション上限、金額上限
Layer 5: 最終確認     - VBAダブルチェック
Layer 6: 監査ログ     - 全判断を記録
```

#### Layer 5: VBAダブルチェック

```vba
Function DoubleCheckOrder(orderParams As Dictionary) As Boolean
    '
    ' 発注直前の最終確認
    '
    Dim checkLog As String
    checkLog = "=== Double Check ===" & vbCrLf

    ' 1. パラメータ再確認
    checkLog = checkLog & "Ticker: " & orderParams("ticker") & vbCrLf
    checkLog = checkLog & "Side: " & IIf(orderParams("side") = 1, "BUY", "SELL") & vbCrLf
    checkLog = checkLog & "Quantity: " & orderParams("quantity") & vbCrLf
    checkLog = checkLog & "Type: " & IIf(orderParams("priceType") = 0, "MARKET", "LIMIT") & vbCrLf

    ' 2. 現在価格取得
    Dim currentPrice As Double
    currentPrice = GetCurrentPrice(orderParams("ticker"))
    checkLog = checkLog & "Current Price: " & currentPrice & vbCrLf

    If currentPrice = 0 Then
        Debug.Print "Double check failed: Price unavailable"
        Return False
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
            Return False  ' 異常価格で発注しない
        End If
    End If

    ' 5. 売りの場合はポジション再確認
    If orderParams("side") = 2 Then  ' 売り
        Dim availableQty As Long
        availableQty = GetAvailableQuantity(orderParams("ticker"))

        If availableQty < orderParams("quantity") Then
            checkLog = checkLog & "ERROR: Insufficient position" & vbCrLf
            Debug.Print checkLog
            Return False
        End If
    End If

    Debug.Print checkLog
    DoubleCheckOrder = True
End Function

Function GetReferencePrice(ticker As String) As Double
    ' 前日終値を取得（RSS.PREV_CLOSEまたはキャッシュ）
    On Error Resume Next
    Dim refPrice As Variant
    refPrice = Application.Run("RSS.PREV_CLOSE", ticker)

    If IsError(refPrice) Or refPrice <= 0 Then
        GetReferencePrice = 0
    Else
        GetReferencePrice = CDbl(refPrice)
    End If
End Function
```

---

### 4.2 発注実行フロー（完全版）

```vba
Function SafeExecuteOrder(signal As Dictionary) As String
    '
    ' 安全発注実行（誤発注防止完全版）
    '
    On Error GoTo ErrorHandler

    Dim orderParams As New Dictionary

    ' === Step 1: パラメータ構築 ===
    orderParams("ticker") = signal("ticker")
    orderParams("side") = IIf(signal("action") = "buy", 1, 2)
    orderParams("quantity") = CLng(signal("quantity"))
    orderParams("priceType") = 0  ' 成行固定
    orderParams("price") = 0      ' 成行なので0
    orderParams("condition") = 0  ' 通常注文

    Debug.Print "=== Safe Order Execution ==="
    Debug.Print "Signal ID: " & signal("signal_id")
    Debug.Print "Ticker: " & orderParams("ticker")
    Debug.Print "Action: " & signal("action")
    Debug.Print "Quantity: " & orderParams("quantity")

    ' === Step 2: 発注可否判定 ===
    Dim canExecute As Dictionary
    Set canExecute = CanExecuteOrder(orderParams)

    If Not canExecute("allowed") Then
        Debug.Print "Order BLOCKED: " & canExecute("reason")

        ' ブロック理由をログ記録
        Call LogOrderBlocked(signal("signal_id"), canExecute)

        SafeExecuteOrder = ""
        Exit Function
    End If

    Debug.Print "Order checks passed"

    ' === Step 3: ダブルチェック ===
    If Not DoubleCheckOrder(orderParams) Then
        Debug.Print "Double check FAILED"
        Call LogError("ORDER_ERROR", "SafeExecuteOrder", "Double check failed", orderParams("ticker"), "CRITICAL")

        SafeExecuteOrder = ""
        Exit Function
    End If

    Debug.Print "Double check passed"

    ' === Step 4: 監査ログ記録（発注前） ===
    Call LogOrderAttempt(signal("signal_id"), orderParams)

    ' === Step 5: RSS.ORDER() 実行 ===
    Dim rssResult As Variant
    rssResult = Application.Run("RSS.ORDER", _
        orderParams("ticker"), _
        orderParams("side"), _
        orderParams("quantity"), _
        orderParams("priceType"), _
        orderParams("price"), _
        orderParams("condition") _
    )

    ' === Step 6: 結果判定 ===
    If IsError(rssResult) Then
        Debug.Print "RSS.ORDER returned Error"
        Call LogError("RSS_ERROR", "SafeExecuteOrder", "RSS.ORDER returned error", orderParams("ticker"), "CRITICAL")

        SafeExecuteOrder = ""
        Exit Function
    End If

    Dim resultStr As String
    resultStr = CStr(rssResult)

    If InStr(resultStr, "注文番号:") > 0 Then
        ' 成功
        Dim orderId As String
        orderId = Mid(resultStr, InStr(resultStr, ":") + 1)

        Debug.Print "Order SUCCESS: " & orderId

        ' 監査ログ記録（成功）
        Call LogOrderSuccess(signal("signal_id"), orderParams, orderId)

        ' カウンター更新
        If orderParams("side") = 1 Then  ' 買い
            Dim currentCount As Long
            currentCount = CLng(GetSystemState("daily_entry_count"))
            Call SetSystemState("daily_entry_count", currentCount + 1)
        End If

        SafeExecuteOrder = orderId
    Else
        ' RSS側エラー
        Debug.Print "RSS.ORDER failed: " & resultStr
        Call LogError("RSS_ERROR", "SafeExecuteOrder", resultStr, orderParams("ticker"), "ERROR")

        SafeExecuteOrder = ""
    End If

    Exit Function

ErrorHandler:
    Debug.Print "Exception in SafeExecuteOrder: " & Err.Description
    Call LogError("ORDER_EXCEPTION", "SafeExecuteOrder", Err.Description, orderParams("ticker"), "CRITICAL")

    SafeExecuteOrder = ""
End Function
```

---

### 4.3 監査ログ

```vba
Sub LogOrderAttempt(signalId As String, orderParams As Dictionary)
    '
    ' 発注試行ログ（全ての発注判断を記録）
    '
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("OrderAuditLog")  ' 新規シート

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    ws.Cells(lastRow, 1).Value = Now
    ws.Cells(lastRow, 2).Value = signalId
    ws.Cells(lastRow, 3).Value = orderParams("ticker")
    ws.Cells(lastRow, 4).Value = IIf(orderParams("side") = 1, "BUY", "SELL")
    ws.Cells(lastRow, 5).Value = orderParams("quantity")
    ws.Cells(lastRow, 6).Value = "ATTEMPT"
End Sub

Sub LogOrderSuccess(signalId As String, orderParams As Dictionary, orderId As String)
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("OrderAuditLog")

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    ws.Cells(lastRow, 1).Value = Now
    ws.Cells(lastRow, 2).Value = signalId
    ws.Cells(lastRow, 3).Value = orderParams("ticker")
    ws.Cells(lastRow, 4).Value = IIf(orderParams("side") = 1, "BUY", "SELL")
    ws.Cells(lastRow, 5).Value = orderParams("quantity")
    ws.Cells(lastRow, 6).Value = "SUCCESS"
    ws.Cells(lastRow, 7).Value = orderId
End Sub

Sub LogOrderBlocked(signalId As String, blockResult As Dictionary)
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("OrderAuditLog")

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    ws.Cells(lastRow, 1).Value = Now
    ws.Cells(lastRow, 2).Value = signalId
    ws.Cells(lastRow, 6).Value = "BLOCKED"
    ws.Cells(lastRow, 8).Value = blockResult("reason")
End Sub
```

---

## 5. 緊急停止機構

### 5.1 手動Kill Switch

```vba
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
```

### 5.2 自動Kill Switch

```vba
Sub CheckAutoKillSwitch()
    '
    ' 自動Kill Switchトリガー
    '
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
```

---

## 6. まとめ

### 6.1 安全発注チェックリスト

**発注前（必須チェック）**:
- [ ] Kill Switch確認（停止中でないこと）
- [ ] 市場時間確認（取引時間内）
- [ ] 銘柄コード検証（4桁数字、ホワイトリスト）
- [ ] 売買区分検証（1 or 2）
- [ ] 数量検証（100株単位、上下限）
- [ ] 価格種別検証（成行=0のみ）
- [ ] 日次制限確認（エントリー数）
- [ ] リスク制限確認（ポジション上限）
- [ ] ダブルチェック（価格異常なし）
- [ ] 監査ログ記録

**発注後（必須）**:
- [ ] 戻り値検証（エラーでないこと）
- [ ] 注文番号抽出（"注文番号:NNNN"）
- [ ] 成功ログ記録
- [ ] カウンター更新

---

### 6.2 推奨設定値

| 設定項目 | 推奨値 | 理由 |
|---------|--------|------|
| 価格種別 | 成行（0）固定 | 約定確実性、シンプル |
| 執行条件 | 通常（0）固定 | 特殊注文を避ける |
| 単元株 | 100株単位 | 市場ルール準拠 |
| 最小数量 | 100株 | 流動性確保 |
| 最大数量 | 10,000株/注文 | リスク分散 |
| 注文間隔 | 30秒以上 | 過剰発注防止 |
| 異常価格閾値 | ±30% | ストップ高・安回避 |

---

### 6.3 実装優先度

**P0（必須）**:
1. パラメータ検証（全項目）
2. トリガー制御（市場時間、Kill Switch）
3. ダブルチェック
4. 監査ログ

**P1（強く推奨）**:
5. 異常価格チェック
6. 自動Kill Switch
7. ホワイトリスト

**P2（推奨）**:
8. 注文間隔制御
9. 詳細ログ

---

**この設計により、誤発注を完全に防止し、安全な全自動発注が実現できます。**
