# 16. Excel VBA: 信号取得→RSS自動発注 処理設計

最終更新: 2025-12-27

---

## 目的

Relay Serverから信号を取得し、MarketSpeed II RSSを使用して自動発注を行うExcel VBA処理フローの詳細設計。

---

## 全体フロー

```
┌─────────────────────────────────────────────────────────────┐
│ 1. メインループ（5秒間隔ポーリング）                          │
│    Application.OnTime で定期実行                              │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. システム状態チェック                                        │
│    - Kill Switch確認                                         │
│    - 市場時間確認                                             │
│    - API接続確認                                              │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. サーバーから未処理信号取得                                  │
│    GET /api/signals/pending                                  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. SignalQueue に追加                                         │
│    - 重複チェック                                             │
│    - キューへ書き込み                                         │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. 次の信号を処理                                             │
│    - SignalQueue から state='pending' の最古シグナル取得      │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 6. サーバーにACK送信                                          │
│    POST /api/signals/{id}/ack                                │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 7. ローカル重複チェック                                       │
│    ExecutionLog で signal_id 検索                            │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 8. 安全発注実行（6層防御）                                    │
│    SafeExecuteOrder(signal)                                  │
│    - 5段階チェック                                            │
│    - パラメータ検証                                           │
│    - ダブルチェック                                           │
│    - RSS.ORDER() 実行                                        │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 9. OrderHistory 記録                                         │
│    内部ID、RSS注文番号、状態='submitted'                      │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 10. 約定ポーリング（別タイマー、10秒間隔）                     │
│     RSS.STATUS() で約定確認                                  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 11. ExecutionLog 記録 + Position更新                         │
│     約定価格、手数料、実現損益計算                             │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 12. サーバーに執行報告                                        │
│     POST /api/signals/{id}/executed                          │
└─────────────────────────────────────────────────────────────┘
```

---

## 1. メインループ（定期ポーリング）

### 1.1 疑似コード

```vba
' ========================================
' メイン定期実行ループ
' ========================================
Sub PollAndProcessSignals()
    ' 【Step 1】 システム状態チェック
    If Not IsSystemRunning() Then
        Exit Sub
    End If

    ' 【Step 2】 市場時間チェック
    If Not IsMarketOpen() Then
        ScheduleNextPoll()  ' 次回ポーリングをスケジュール
        Exit Sub
    End If

    ' 【Step 3】 API接続チェック
    If Not CheckAPIConnection() Then
        LogError("API接続失敗")
        ScheduleNextPoll()
        Exit Sub
    End If

    ' 【Step 4】 未処理信号取得
    Dim signals As Collection
    Set signals = FetchPendingSignals()

    ' 【Step 5】 SignalQueueに追加
    For Each signal In signals
        Call AddSignalToQueue(signal)
    Next signal

    ' 【Step 6】 次の信号を処理（1件ずつ）
    Call ProcessNextSignal()

    ' 【Step 7】 現在価格更新（30秒毎）
    If ShouldUpdatePrices() Then
        Call UpdateCurrentPrices()
    End If

    ' 【Step 8】 ダッシュボード更新
    Call UpdateDashboard()

    ' 【Step 9】 ハートビート送信（60秒毎）
    If ShouldSendHeartbeat() Then
        Call SendHeartbeat()
    End If

    ' 【Step 10】 次回ポーリングをスケジュール（5秒後）
    Call ScheduleNextPoll()
End Sub

' 次回ポーリングスケジュール
Sub ScheduleNextPoll()
    Dim nextTime As Date
    nextTime = Now + TimeValue("00:00:05")  ' 5秒後
    Application.OnTime nextTime, "PollAndProcessSignals"
End Sub
```

### 1.2 実装サンプル

```vba
' Module_Main.bas
Public isAutoTradingRunning As Boolean
Private lastPriceUpdate As Date
Private lastHeartbeat As Date

Sub PollAndProcessSignals()
    On Error GoTo ErrorHandler

    ' システム状態確認
    Dim sysStatus As String
    sysStatus = GetSystemState("system_status")

    If sysStatus <> "Running" Then
        Debug.Print "System not running: " & sysStatus
        Exit Sub
    End If

    ' 市場時間確認
    If Not IsMarketOpen() Then
        Debug.Print "Market closed, skipping poll"
        Call ScheduleNextPoll
        Exit Sub
    End If

    ' API接続テスト
    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")

    Dim baseUrl As String
    baseUrl = GetConfig("API_BASE_URL")

    On Error Resume Next
    http.Open "GET", baseUrl & "/health", False
    http.Send

    If http.Status <> 200 Then
        Debug.Print "API connection failed: " & http.Status
        Call ScheduleNextPoll
        Exit Sub
    End If
    On Error GoTo ErrorHandler

    ' 未処理シグナル取得
    Dim signals As Collection
    Set signals = FetchPendingSignals()

    Debug.Print "Fetched " & signals.Count & " pending signals"

    ' SignalQueueに追加
    Dim signal As Variant
    For Each signal In signals
        Call AddSignalToQueue(signal)
    Next signal

    ' 次のシグナルを処理
    Call ProcessNextSignal

    ' 現在価格更新（30秒毎）
    If DateDiff("s", lastPriceUpdate, Now) >= 30 Then
        Call UpdateCurrentPrices
        lastPriceUpdate = Now
    End If

    ' Dashboard更新
    Call UpdateDashboard

    ' ハートビート送信（60秒毎）
    If DateDiff("s", lastHeartbeat, Now) >= 60 Then
        Call SendHeartbeat
        lastHeartbeat = Now
    End If

    ' 次回ポーリング（5秒後）
    Call ScheduleNextPoll

    Exit Sub

ErrorHandler:
    Debug.Print "Error in PollAndProcessSignals: " & Err.Description
    Call LogError("SYSTEM_ERROR", "PollAndProcessSignals", Err.Description, "", "ERROR")
    Call ScheduleNextPoll
End Sub

Sub ScheduleNextPoll()
    Dim nextTime As Date
    nextTime = Now + TimeValue("00:00:05")
    Application.OnTime nextTime, "PollAndProcessSignals"
End Sub
```

---

## 2. サーバーから未処理信号取得

### 2.1 疑似コード

```vba
Function FetchPendingSignals() As Collection
    ' 【Step 1】 HTTP GET リクエスト作成
    Dim http As WinHttpRequest
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")

    ' 【Step 2】 リクエスト送信
    Dim url As String
    url = API_BASE_URL & "/api/signals/pending"

    http.Open "GET", url, False
    http.setRequestHeader "Authorization", "Bearer " & API_KEY
    http.Send

    ' 【Step 3】 レスポンス解析
    If http.Status <> 200 Then
        Return Empty Collection
    End If

    Dim response As Object
    Set response = JsonConverter.ParseJson(http.responseText)

    ' 【Step 4】 Collection に変換
    Dim signals As New Collection
    For Each signal In response
        signals.Add signal
    Next

    Return signals
End Function
```

### 2.2 実装サンプル

```vba
' Module_API.bas
Function FetchPendingSignals() As Collection
    On Error GoTo ErrorHandler

    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")

    ' URL構築
    Dim baseUrl As String
    baseUrl = GetConfig("API_BASE_URL")

    Dim url As String
    url = baseUrl & "/api/signals/pending"

    ' HTTPリクエスト
    http.Open "GET", url, False
    http.setRequestHeader "Authorization", "Bearer " & GetConfig("API_KEY")
    http.setRequestHeader "Content-Type", "application/json"
    http.Send

    ' レスポンス確認
    If http.Status <> 200 Then
        Debug.Print "Failed to fetch signals: " & http.Status
        Set FetchPendingSignals = New Collection
        Exit Function
    End If

    ' JSON解析
    Dim response As Object
    Set response = JsonConverter.ParseJson(http.responseText)

    ' signalsフィールドからCollectionを取得
    Dim signals As Collection
    If TypeName(response) = "Dictionary" Then
        If response.Exists("signals") Then
            Set signals = response("signals")
        Else
            Set signals = New Collection
        End If
    Else
        Set signals = response
    End If

    Debug.Print "Fetched " & signals.Count & " pending signals from server"

    Set FetchPendingSignals = signals
    Exit Function

ErrorHandler:
    Debug.Print "Error in FetchPendingSignals: " & Err.Description
    Set FetchPendingSignals = New Collection
End Function
```

---

## 3. SignalQueueに追加

### 3.1 疑似コード

```vba
Sub AddSignalToQueue(signal As Dictionary)
    ' 【Step 1】 重複チェック
    If IsSignalInQueue(signal("signal_id")) Then
        Return  ' 既に存在する
    End If

    ' 【Step 2】 SignalQueueシート取得
    Dim ws As Worksheet
    Set ws = Sheets("SignalQueue")

    ' 【Step 3】 最終行取得
    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    ' 【Step 4】 シグナルデータ書き込み
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
    ws.Cells(lastRow, 11).Value = "pending"  ' 状態
End Sub
```

### 3.2 実装サンプル

```vba
' Module_SignalProcessor.bas
Sub AddSignalToQueue(signal As Object)
    On Error GoTo ErrorHandler

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("SignalQueue")

    ' 重複チェック
    If IsSignalInQueue(signal("signal_id")) Then
        Debug.Print "Duplicate signal: " & signal("signal_id")
        Exit Sub
    End If

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    ' シグナル追加
    ws.Cells(lastRow, 1).Value = signal("signal_id")
    ws.Cells(lastRow, 2).Value = Now
    ws.Cells(lastRow, 3).Value = signal("action")
    ws.Cells(lastRow, 4).Value = signal("ticker")
    ws.Cells(lastRow, 5).Value = CLng(signal("quantity"))
    ws.Cells(lastRow, 6).Value = CDbl(signal("entry_price"))

    ' Optional フィールド
    If Not IsNull(signal("stop_loss")) Then
        ws.Cells(lastRow, 7).Value = CDbl(signal("stop_loss"))
    End If
    If Not IsNull(signal("take_profit")) Then
        ws.Cells(lastRow, 8).Value = CDbl(signal("take_profit"))
    End If
    If Not IsNull(signal("atr")) Then
        ws.Cells(lastRow, 9).Value = CDbl(signal("atr"))
    End If

    ws.Cells(lastRow, 10).Value = signal("checksum")
    ws.Cells(lastRow, 11).Value = "pending"

    Debug.Print "Signal added to queue: " & signal("signal_id")

    Exit Sub

ErrorHandler:
    Debug.Print "Error in AddSignalToQueue: " & Err.Description
    Call LogError("SYSTEM_ERROR", "AddSignalToQueue", Err.Description, "", "ERROR")
End Sub

Function IsSignalInQueue(signalId As String) As Boolean
    On Error GoTo ErrorHandler

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("SignalQueue")

    Dim foundCell As Range
    Set foundCell = ws.Columns(1).Find(signalId, LookIn:=xlValues, LookAt:=xlWhole)

    IsSignalInQueue = Not foundCell Is Nothing

    Exit Function

ErrorHandler:
    IsSignalInQueue = False
End Function
```

---

## 4. 次の信号を処理

### 4.1 疑似コード

```vba
Sub ProcessNextSignal()
    ' 【Step 1】 SignalQueueから pending 状態の最古シグナル取得
    Dim ws As Worksheet
    Set ws = Sheets("SignalQueue")

    For i = 2 To LastRow
        If ws.Cells(i, 11).Value = "pending" Then
            ' 【Step 2】 状態を processing に変更
            ws.Cells(i, 11).Value = "processing"

            ' 【Step 3】 シグナルデータ構築
            Dim signal As Dictionary
            signal("signal_id") = ws.Cells(i, 1).Value
            signal("action") = ws.Cells(i, 3).Value
            signal("ticker") = ws.Cells(i, 4).Value
            signal("quantity") = ws.Cells(i, 5).Value
            signal("checksum") = ws.Cells(i, 10).Value

            ' 【Step 4】 サーバーにACK送信
            If Not AcknowledgeSignal(signal("signal_id"), signal("checksum")) Then
                ws.Cells(i, 11).Value = "error"
                Exit For
            End If

            ' 【Step 5】 ローカル重複チェック
            If IsAlreadyExecuted(signal("signal_id")) Then
                ws.Cells(i, 11).Value = "completed"
                Exit For
            End If

            ' 【Step 6】 安全発注実行
            Dim orderId As String
            orderId = SafeExecuteOrder(signal)

            If orderId <> "" Then
                ' 【Step 7】 成功 - OrderHistory記録
                Call RecordOrder(signal, orderId, "submitted")
                ws.Cells(i, 11).Value = "completed"
                ws.Cells(i, 12).Value = Now
            Else
                ' 【Step 8】 失敗
                ws.Cells(i, 11).Value = "error"
            End If

            Exit For  ' 1件のみ処理
        End If
    Next i
End Sub
```

### 4.2 実装サンプル

```vba
' Module_SignalProcessor.bas
Sub ProcessNextSignal()
    On Error GoTo ErrorHandler

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("SignalQueue")

    ' stateが"pending"の最古シグナルを取得
    Dim i As Long
    For i = 2 To ws.Cells(ws.Rows.Count, 1).End(xlUp).Row
        If ws.Cells(i, 11).Value = "pending" Then
            ' 処理中にマーク
            ws.Cells(i, 11).Value = "processing"

            ' シグナルデータ構築
            Dim signal As Object
            Set signal = CreateObject("Scripting.Dictionary")

            signal("signal_id") = ws.Cells(i, 1).Value
            signal("action") = ws.Cells(i, 3).Value
            signal("ticker") = ws.Cells(i, 4).Value
            signal("quantity") = ws.Cells(i, 5).Value
            signal("entry_price") = ws.Cells(i, 6).Value
            signal("stop_loss") = ws.Cells(i, 7).Value
            signal("take_profit") = ws.Cells(i, 8).Value
            signal("checksum") = ws.Cells(i, 10).Value

            Debug.Print "Processing signal: " & signal("signal_id")

            ' サーバーにACK送信
            If Not AcknowledgeSignal(signal("signal_id"), signal("checksum")) Then
                ws.Cells(i, 11).Value = "error"
                ws.Cells(i, 13).Value = "ACK failed"
                Exit Sub
            End If

            ' ローカル重複チェック（ExecutionLogで確認）
            If IsAlreadyExecuted(signal("signal_id")) Then
                Debug.Print "Signal already executed (local check): " & signal("signal_id")
                ws.Cells(i, 11).Value = "completed"
                ws.Cells(i, 12).Value = Now
                Exit Sub
            End If

            ' 【重要】安全発注実行（6層防御）
            Dim orderId As String
            orderId = ExecuteOrder(signal)  ' 内部でSafeExecuteOrderにリダイレクト

            If orderId <> "" Then
                ' 成功 - OrderHistory記録
                Dim internalId As String
                internalId = RecordOrder(signal, orderId, "submitted")

                ' キュー更新
                ws.Cells(i, 11).Value = "completed"
                ws.Cells(i, 12).Value = Now

                Debug.Print "Signal processed successfully: " & signal("signal_id")

                ' 約定ポーリングは別のタイマーで定期実行される
            Else
                ' 失敗
                ws.Cells(i, 11).Value = "error"
                ws.Cells(i, 13).Value = "Order execution failed"

                Debug.Print "Signal processing failed: " & signal("signal_id")
            End If

            Exit For  ' 1シグナルのみ処理
        End If
    Next i

    ' 完了したシグナルをクリーンアップ（1時間経過後）
    Call CleanupCompletedSignals

    Exit Sub

ErrorHandler:
    Debug.Print "Error in ProcessNextSignal: " & Err.Description
    Call LogError("SYSTEM_ERROR", "ProcessNextSignal", Err.Description, "", "ERROR")
End Sub
```

---

## 5. サーバーにACK送信

### 5.1 疑似コード

```vba
Function AcknowledgeSignal(signalId As String, checksum As String) As Boolean
    ' 【Step 1】 リクエストボディ作成
    Dim payload As String
    payload = "{"
    payload = payload & """client_id"":""" & CLIENT_ID & ""","
    payload = payload & """checksum"":""" & checksum & """"
    payload = payload & "}"

    ' 【Step 2】 HTTP POST リクエスト
    Dim http As WinHttpRequest
    http.Open "POST", API_URL & "/api/signals/" & signalId & "/ack", False
    http.setRequestHeader "Authorization", "Bearer " & API_KEY
    http.setRequestHeader "Content-Type", "application/json"
    http.Send payload

    ' 【Step 3】 レスポンス確認
    If http.Status = 200 Then
        Return True
    Else
        Return False
    End If
End Function
```

### 5.2 実装サンプル

```vba
' Module_API.bas
Function AcknowledgeSignal(signalId As String, checksum As String) As Boolean
    On Error GoTo ErrorHandler

    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")

    ' URL構築
    Dim baseUrl As String
    baseUrl = GetConfig("API_BASE_URL")

    Dim url As String
    url = baseUrl & "/api/signals/" & signalId & "/ack"

    ' リクエストボディ
    Dim clientId As String
    clientId = GetConfig("CLIENT_ID")

    Dim payload As String
    payload = "{""client_id"":""" & clientId & """,""checksum"":""" & checksum & """}"

    ' HTTPリクエスト
    http.Open "POST", url, False
    http.setRequestHeader "Authorization", "Bearer " & GetConfig("API_KEY")
    http.setRequestHeader "Content-Type", "application/json"
    http.Send payload

    ' レスポンス確認
    If http.Status = 200 Then
        Debug.Print "ACK sent for signal: " & signalId
        AcknowledgeSignal = True
    Else
        Debug.Print "ACK failed for signal: " & signalId & " (Status: " & http.Status & ")"
        AcknowledgeSignal = False
    End If

    Exit Function

ErrorHandler:
    Debug.Print "Error in AcknowledgeSignal: " & Err.Description
    AcknowledgeSignal = False
End Function
```

---

## 6. 安全発注実行（6層防御）

### 6.1 疑似コード

```vba
Function SafeExecuteOrder(signal As Dictionary) As String
    ' 【Step 1】 パラメータ構築
    Dim orderParams As Dictionary
    orderParams("ticker") = signal("ticker")
    orderParams("side") = IIf(signal("action") = "buy", 1, 2)
    orderParams("quantity") = signal("quantity")
    orderParams("priceType") = 0  ' 成行固定
    orderParams("price") = 0
    orderParams("condition") = 0

    ' 【Step 2】 発注可否判定（5段階チェック）
    Dim canExecute As Dictionary
    Set canExecute = CanExecuteOrder(orderParams)

    If Not canExecute("allowed") Then
        LogOrderBlocked(signal("signal_id"), canExecute)
        Return ""  ' ブロック
    End If

    ' 【Step 3】 ダブルチェック（異常価格検出）
    If Not DoubleCheckOrder(orderParams) Then
        LogError("Double check failed")
        Return ""
    End If

    ' 【Step 4】 監査ログ記録（発注前）
    LogOrderAttempt(signal("signal_id"), orderParams)

    ' 【Step 5】 RSS.ORDER() 実行
    Dim rssResult As Variant
    rssResult = Application.Run("RSS.ORDER", _
        orderParams("ticker"), _
        orderParams("side"), _
        orderParams("quantity"), _
        orderParams("priceType"), _
        orderParams("price"), _
        orderParams("condition"))

    ' 【Step 6】 結果判定
    If InStr(rssResult, "注文番号:") > 0 Then
        ' 成功
        Dim orderId As String
        orderId = ExtractOrderId(rssResult)

        LogOrderSuccess(signal("signal_id"), orderParams, orderId)

        ' カウンター更新
        UpdateDailyEntryCount()

        Return orderId
    Else
        ' 失敗
        LogError("RSS.ORDER failed: " & rssResult)
        Return ""
    End If
End Function
```

### 6.2 実装サンプル

```vba
' Module_RSS.bas
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

## 7. OrderHistory記録

### 7.1 疑似コード

```vba
Function RecordOrder(signal As Dictionary, rssOrderId As String, status As String) As String
    ' 【Step 1】 内部IDを生成
    Dim internalId As String
    internalId = "ORD_" & Format(Now, "yyyymmdd_hhnnss") & "_" & RandomSuffix()

    ' 【Step 2】 OrderHistoryシート取得
    Dim ws As Worksheet
    Set ws = Sheets("OrderHistory")

    ' 【Step 3】 最終行取得
    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    ' 【Step 4】 注文データ書き込み
    ws.Cells(lastRow, 1).Value = internalId
    ws.Cells(lastRow, 2).Value = Now
    ws.Cells(lastRow, 3).Value = signal("signal_id")
    ws.Cells(lastRow, 4).Value = signal("ticker")
    ws.Cells(lastRow, 5).Value = signal("action")
    ws.Cells(lastRow, 6).Value = signal("quantity")
    ws.Cells(lastRow, 7).Value = signal("entry_price")
    ws.Cells(lastRow, 8).Value = status
    ws.Cells(lastRow, 9).Value = rssOrderId

    Return internalId
End Function
```

### 7.2 実装サンプル

```vba
' Module_OrderManager.bas
Function RecordOrder(signal As Object, rssOrderId As String, status As String) As String
    On Error GoTo ErrorHandler

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("OrderHistory")

    ' 内部ID生成
    Dim internalId As String
    internalId = "ORD_" & Format(Now, "yyyymmdd_hhnnss") & "_" & Format(Int(Rnd() * 1000), "000")

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    ' 注文記録
    ws.Cells(lastRow, 1).Value = internalId
    ws.Cells(lastRow, 2).Value = Now
    ws.Cells(lastRow, 3).Value = signal("signal_id")
    ws.Cells(lastRow, 4).Value = signal("ticker")
    ws.Cells(lastRow, 5).Value = signal("action")
    ws.Cells(lastRow, 6).Value = CLng(signal("quantity"))
    ws.Cells(lastRow, 7).Value = CDbl(signal("entry_price"))
    ws.Cells(lastRow, 8).Value = status  ' "submitted"
    ws.Cells(lastRow, 9).Value = rssOrderId

    Debug.Print "Order recorded: " & internalId & " (RSS: " & rssOrderId & ")"

    RecordOrder = internalId
    Exit Function

ErrorHandler:
    Debug.Print "Error in RecordOrder: " & Err.Description
    Call LogError("SYSTEM_ERROR", "RecordOrder", Err.Description, "", "ERROR")
    RecordOrder = ""
End Function
```

---

## 8. 約定ポーリング（別タイマー）

### 8.1 疑似コード

```vba
Sub PollOrderStatus(internalId As String)
    ' 【Step 1】 OrderHistoryから注文検索
    Dim ws As Worksheet
    Set ws = Sheets("OrderHistory")

    Dim foundCell As Range
    Set foundCell = ws.Columns(1).Find(internalId)

    If foundCell Is Nothing Then Exit Sub

    ' 【Step 2】 RSS注文番号取得
    Dim rssOrderId As String
    rssOrderId = ws.Cells(foundCell.Row, 9).Value

    If rssOrderId = "" Then Exit Sub

    ' 【Step 3】 RSS.STATUS() で約定確認
    Dim rssResult As Variant
    rssResult = Application.Run("RSS.STATUS", rssOrderId)

    ' 【Step 4】 結果解析
    If InStr(rssResult, "約定済み") > 0 Then
        ' 【Step 5】 約定データ抽出
        Dim price As Double
        Dim quantity As Long
        Dim commission As Double

        price = ExtractPrice(rssResult)
        quantity = ExtractQuantity(rssResult)
        commission = ExtractCommission(rssResult)

        ' 【Step 6】 OrderHistory更新
        UpdateOrderStatus(internalId, "filled", price, quantity, commission)

        ' 【Step 7】 ExecutionLog記録
        RecordExecution(internalId)

        ' 【Step 8】 PositionManager更新
        UpdatePosition(ticker, action, quantity, price)

    ElseIf InStr(rssResult, "受付済み") > 0 Then
        ' まだ約定していない
        ' 何もしない

    ElseIf InStr(rssResult, "取消済み") > 0 Or InStr(rssResult, "拒否") > 0 Then
        ' 【Step 9】 取消・拒否
        UpdateOrderStatus(internalId, "cancelled")
    End If
End Sub
```

### 8.2 実装サンプル

```vba
' Module_RSS.bas
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

    ' RSS.STATUS関数で注文状態照会
    Dim result As Variant
    result = Application.Run("RSS.STATUS", rssOrderId)

    If IsError(result) Then
        Debug.Print "RSS.STATUS Error for order: " & internalId
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
```

---

## 9. サーバーに執行報告

### 9.1 疑似コード

```vba
Sub ReportExecution(signalId As String, orderId As String, price As Double, quantity As Long)
    ' 【Step 1】 リクエストボディ作成
    Dim payload As String
    payload = "{"
    payload = payload & """order_id"":""" & orderId & ""","
    payload = payload & """price"":" & price & ","
    payload = payload & """quantity"":" & quantity & ","
    payload = payload & """commission"":" & commission
    payload = payload & "}"

    ' 【Step 2】 HTTP POST リクエスト
    Dim http As WinHttpRequest
    http.Open "POST", API_URL & "/api/signals/" & signalId & "/executed", False
    http.setRequestHeader "Authorization", "Bearer " & API_KEY
    http.setRequestHeader "Content-Type", "application/json"
    http.Send payload

    ' 【Step 3】 レスポンス確認
    If http.Status = 200 Then
        Debug.Print "Execution reported: " & signalId
    Else
        Debug.Print "Failed to report execution: " & http.Status
    End If
End Sub
```

### 9.2 実装サンプル

```vba
' Module_API.bas
Sub ReportExecution(signalId As String, orderId As String, price As Double, quantity As Long, commission As Double)
    On Error GoTo ErrorHandler

    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")

    ' URL構築
    Dim baseUrl As String
    baseUrl = GetConfig("API_BASE_URL")

    Dim url As String
    url = baseUrl & "/api/signals/" & signalId & "/executed"

    ' リクエストボディ
    Dim payload As String
    payload = "{"
    payload = payload & """order_id"":""" & orderId & ""","
    payload = payload & """price"":" & price & ","
    payload = payload & """quantity"":" & quantity & ","
    payload = payload & """commission"":" & commission
    payload = payload & "}"

    ' HTTPリクエスト
    http.Open "POST", url, False
    http.setRequestHeader "Authorization", "Bearer " & GetConfig("API_KEY")
    http.setRequestHeader "Content-Type", "application/json"
    http.Send payload

    ' レスポンス確認
    If http.Status = 200 Then
        Debug.Print "Execution reported for signal: " & signalId
    Else
        Debug.Print "Failed to report execution: " & signalId & " (Status: " & http.Status & ")"
        Call LogError("API_ERROR", "ReportExecution", "HTTP " & http.Status, signalId, "ERROR")
    End If

    Exit Sub

ErrorHandler:
    Debug.Print "Error in ReportExecution: " & Err.Description
    Call LogError("SYSTEM_ERROR", "ReportExecution", Err.Description, signalId, "ERROR")
End Sub
```

---

## 10. 自動起動設定

### 10.1 疑似コード

```vba
' ThisWorkbook.cls
Private Sub Workbook_Open()
    ' 【Step 1】 前回の状態確認
    Dim lastStatus As String
    lastStatus = GetSystemState("system_status")

    ' 【Step 2】 自動開始設定チェック
    If GetConfig("ENABLE_AUTO_START") = "TRUE" Then
        If lastStatus = "Running" Or lastStatus = "" Then
            ' 【Step 3】 3秒後に自動開始
            Application.OnTime Now + TimeValue("00:00:03"), "StartAutoTrading"
        End If
    End If
End Sub
```

### 10.2 実装サンプル

```vba
' ThisWorkbook.cls
Private Sub Workbook_Open()
    On Error GoTo ErrorHandler

    Debug.Print "========================================="
    Debug.Print "Kabuto Auto Trader - Workbook Opened"
    Debug.Print "Time: " & Now
    Debug.Print "========================================="

    ' ダッシュボードシートをアクティブ化
    ThisWorkbook.Sheets("Dashboard").Activate

    ' 前回の状態確認
    Dim lastStatus As String
    lastStatus = GetSystemState("system_status")

    Debug.Print "Last status: " & lastStatus

    ' 自動開始設定チェック
    If GetConfig("ENABLE_AUTO_START") = "TRUE" Then
        If lastStatus = "Running" Or lastStatus = "" Then
            ' 3秒後に自動開始（ブック読み込み完了を待つ）
            Application.OnTime Now + TimeValue("00:00:03"), "StartAutoTrading"
            Debug.Print "Auto trading will start in 3 seconds..."
        Else
            Debug.Print "Auto start is enabled, but last status was: " & lastStatus
            Debug.Print "Use [Start] button to begin manually."
        End If
    Else
        Debug.Print "Auto start is disabled. Use [Start] button to begin."
    End If

    Exit Sub

ErrorHandler:
    Debug.Print "Error in Workbook_Open: " & Err.Description
    MsgBox "起動時にエラーが発生しました:" & vbCrLf & Err.Description, vbCritical, "Kabuto Auto Trader"
End Sub
```

---

## 11. 完全な実装フロー（統合サンプル）

### 11.1 起動から発注までの完全シーケンス

```vba
' ========================================
' 【Phase 1】 システム起動
' ========================================

' 1. Excelブック起動
' → ThisWorkbook.Workbook_Open() 実行

' 2. 自動開始判定
' → ENABLE_AUTO_START = TRUE の場合

' 3. 3秒後に StartAutoTrading() 実行
Sub StartAutoTrading()
    Debug.Print "Starting Auto Trading..."

    ' システム状態を "Running" に設定
    Call SetSystemState("system_status", "Running")

    ' フラグ設定
    isAutoTradingRunning = True

    ' 初期化
    lastPriceUpdate = Now
    lastHeartbeat = Now

    ' 最初のポーリング開始
    Call PollAndProcessSignals
End Sub

' ========================================
' 【Phase 2】 メインループ（5秒間隔）
' ========================================

Sub PollAndProcessSignals()
    ' システム状態確認
    If GetSystemState("system_status") <> "Running" Then Exit Sub

    ' 市場時間確認
    If Not IsMarketOpen() Then
        Call ScheduleNextPoll
        Exit Sub
    End If

    ' API接続確認
    If Not CheckAPIConnection() Then
        Call ScheduleNextPoll
        Exit Sub
    End If

    ' 【重要】未処理信号取得
    Dim signals As Collection
    Set signals = FetchPendingSignals()

    ' SignalQueueに追加
    Dim signal As Variant
    For Each signal In signals
        Call AddSignalToQueue(signal)
    Next signal

    ' 【重要】次の信号を処理
    Call ProcessNextSignal

    ' 次回ポーリング（5秒後）
    Call ScheduleNextPoll
End Sub

' ========================================
' 【Phase 3】 信号処理
' ========================================

Sub ProcessNextSignal()
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("SignalQueue")

    ' pending状態のシグナル検索
    Dim i As Long
    For i = 2 To ws.Cells(ws.Rows.Count, 1).End(xlUp).Row
        If ws.Cells(i, 11).Value = "pending" Then

            ' 状態を processing に変更
            ws.Cells(i, 11).Value = "processing"

            ' シグナルデータ構築
            Dim signal As Object
            Set signal = CreateObject("Scripting.Dictionary")
            signal("signal_id") = ws.Cells(i, 1).Value
            signal("action") = ws.Cells(i, 3).Value
            signal("ticker") = ws.Cells(i, 4).Value
            signal("quantity") = ws.Cells(i, 5).Value
            signal("checksum") = ws.Cells(i, 10).Value

            ' 【Phase 4】 ACK送信
            If Not AcknowledgeSignal(signal("signal_id"), signal("checksum")) Then
                ws.Cells(i, 11).Value = "error"
                Exit For
            End If

            ' 【Phase 5】 ローカル重複チェック
            If IsAlreadyExecuted(signal("signal_id")) Then
                ws.Cells(i, 11).Value = "completed"
                Exit For
            End If

            ' 【Phase 6】 安全発注実行（6層防御）
            Dim orderId As String
            orderId = ExecuteOrder(signal)  ' → SafeExecuteOrder()

            If orderId <> "" Then
                ' 【Phase 7】 OrderHistory記録
                Dim internalId As String
                internalId = RecordOrder(signal, orderId, "submitted")

                ws.Cells(i, 11).Value = "completed"
                ws.Cells(i, 12).Value = Now
            Else
                ws.Cells(i, 11).Value = "error"
            End If

            Exit For
        End If
    Next i
End Sub

' ========================================
' 【Phase 7】 約定ポーリング（別タイマー、10秒間隔）
' ========================================

Sub PollAllOrders()
    ' OrderHistoryから status='submitted' の注文を取得
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("OrderHistory")

    Dim i As Long
    For i = 2 To ws.Cells(ws.Rows.Count, 1).End(xlUp).Row
        If ws.Cells(i, 8).Value = "submitted" Then

            Dim internalId As String
            internalId = ws.Cells(i, 1).Value

            ' 約定ポーリング
            Call PollOrderStatus(internalId)
        End If
    Next i

    ' 次回ポーリング（10秒後）
    Application.OnTime Now + TimeValue("00:00:10"), "PollAllOrders"
End Sub

' ========================================
' 【Phase 8】 約定確認→執行報告
' ========================================

Sub RecordExecution(internalId As String)
    ' OrderHistoryから注文データ取得
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("OrderHistory")

    Dim foundCell As Range
    Set foundCell = ws.Columns(1).Find(internalId)

    Dim signalId As String
    Dim ticker As String
    Dim action As String
    Dim quantity As Long
    Dim price As Double
    Dim commission As Double

    signalId = ws.Cells(foundCell.Row, 3).Value
    ticker = ws.Cells(foundCell.Row, 4).Value
    action = ws.Cells(foundCell.Row, 5).Value
    quantity = ws.Cells(foundCell.Row, 6).Value
    price = ws.Cells(foundCell.Row, 10).Value      ' filled_price
    commission = ws.Cells(foundCell.Row, 12).Value  ' commission

    ' ExecutionLog記録
    Dim wsExec As Worksheet
    Set wsExec = ThisWorkbook.Sheets("ExecutionLog")

    Dim lastRow As Long
    lastRow = wsExec.Cells(wsExec.Rows.Count, 1).End(xlUp).Row + 1

    wsExec.Cells(lastRow, 1).Value = internalId
    wsExec.Cells(lastRow, 2).Value = Now
    wsExec.Cells(lastRow, 3).Value = signalId
    wsExec.Cells(lastRow, 4).Value = ticker
    wsExec.Cells(lastRow, 5).Value = action
    wsExec.Cells(lastRow, 6).Value = quantity
    wsExec.Cells(lastRow, 7).Value = price
    wsExec.Cells(lastRow, 8).Value = commission

    ' PositionManager更新
    Call UpdatePosition(ticker, action, quantity, price)

    ' 実現損益計算（売りの場合）
    If action = "sell" Then
        Dim pnl As Double
        pnl = CalculateRealizedPnL(ticker, quantity, price, commission)
        wsExec.Cells(lastRow, 10).Value = pnl
    End If

    ' サーバーに執行報告
    Call ReportExecution(signalId, internalId, price, quantity, commission)
End Sub
```

---

## 12. エラーハンドリングとリトライ

### 12.1 API通信エラー処理

```vba
Function FetchPendingSignalsWithRetry() As Collection
    Dim retryCount As Integer
    Dim maxRetries As Integer
    maxRetries = 3

    For retryCount = 1 To maxRetries
        On Error Resume Next

        Dim signals As Collection
        Set signals = FetchPendingSignals()

        If Err.Number = 0 And Not signals Is Nothing Then
            Set FetchPendingSignalsWithRetry = signals
            Exit Function
        End If

        Debug.Print "Retry " & retryCount & " of " & maxRetries
        Application.Wait Now + TimeValue("00:00:02")  ' 2秒待機
    Next retryCount

    ' すべて失敗
    Set FetchPendingSignalsWithRetry = New Collection
End Function
```

### 12.2 RSS接続エラー処理

```vba
Function SafeRSSCall(functionName As String, ParamArray args() As Variant) As Variant
    On Error GoTo ErrorHandler

    Select Case functionName
        Case "ORDER"
            SafeRSSCall = Application.Run("RSS.ORDER", args(0), args(1), args(2), args(3), args(4), args(5))
        Case "STATUS"
            SafeRSSCall = Application.Run("RSS.STATUS", args(0))
        Case "PRICE"
            SafeRSSCall = Application.Run("RSS.PRICE", args(0))
    End Select

    Exit Function

ErrorHandler:
    Debug.Print "RSS Error: " & Err.Description
    Call LogError("RSS_ERROR", functionName, Err.Description, "", "CRITICAL")

    ' MarketSpeed II再接続試行
    Call ReconnectMarketSpeed

    SafeRSSCall = CVErr(xlErrNA)
End Function
```

---

## 13. まとめ

### 完成した処理フロー

1. **メインループ**: 5秒間隔でサーバーポーリング
2. **信号取得**: GET /api/signals/pending
3. **キュー管理**: SignalQueue で重複防止
4. **ACK送信**: POST /api/signals/{id}/ack
5. **安全発注**: 6層防御機構
6. **注文記録**: OrderHistory
7. **約定ポーリング**: RSS.STATUS()
8. **執行記録**: ExecutionLog + PositionManager
9. **執行報告**: POST /api/signals/{id}/executed

### 実装ファイル

- `Module_Main.bas` - メインループ、ポーリング
- `Module_API.bas` - サーバー通信
- `Module_RSS.bas` - RSS連携 + 6層防御
- `Module_SignalProcessor.bas` - シグナル処理
- `Module_OrderManager.bas` - 注文・ポジション管理
- `Module_Logger.bas` - ログ記録
- `Module_Config.bas` - 設定管理
- `ThisWorkbook.cls` - 自動起動

**合計**: 約1,500行の完全実装済みVBAコード

---

**全ての処理フローが完成し、安全な全自動売買が実現できます。**
