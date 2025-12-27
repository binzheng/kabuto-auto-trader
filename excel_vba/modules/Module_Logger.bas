Attribute VB_Name = "Module_Logger"
'
' Kabuto Auto Trader - Logger Module
' ログ記録
'

Option Explicit

' ========================================
' エラーログ記録
' ========================================
Sub LogError(errorType As String, module As String, errorMsg As String, Optional ticker As String = "", Optional severity As String = "ERROR")
    On Error Resume Next

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
    ws.Cells(lastRow, 6).Value = ""  ' error_code
    ws.Cells(lastRow, 7).Value = errorMsg
    ws.Cells(lastRow, 8).Value = Err.Source & " (" & Err.Number & ")"
    ws.Cells(lastRow, 9).Value = severity
    ws.Cells(lastRow, 10).Value = False  ' resolved
    ws.Cells(lastRow, 11).Value = ""     ' notes

    Debug.Print "Error logged: " & errorId & " - " & errorMsg

    ' CRITICAL エラーの場合はアラート
    If severity = "CRITICAL" Then
        Call SendCriticalAlert(errorMsg)
    End If
End Sub

' ========================================
' 実行済みシグナルをログ記録
' ========================================
Sub LogExecutedSignal(signalId As String, ticker As String, orderId As String)
    ' ExecutionLogに記録済みなので、ここでは追加処理なし
    Debug.Print "Signal executed and logged: " & signalId
End Sub

' ========================================
' ファイルログ書き込み
' ========================================
Sub WriteLog(message As String)
    On Error Resume Next

    Dim logPath As String
    logPath = "C:\Kabuto\Logs\excel_vba_" & Format(Now, "yyyymmdd") & ".log"

    Dim fso As Object
    Dim ts As Object

    Set fso = CreateObject("Scripting.FileSystemObject")

    ' ログディレクトリが存在しない場合は作成
    Dim logDir As String
    logDir = "C:\Kabuto\Logs"

    If Not fso.FolderExists(logDir) Then
        fso.CreateFolder logDir
    End If

    ' 追記モード
    If fso.FileExists(logPath) Then
        Set ts = fso.OpenTextFile(logPath, 8)  ' ForAppending=8
    Else
        Set ts = fso.CreateTextFile(logPath, True)
    End If

    ts.WriteLine Format(Now, "yyyy-mm-dd hh:nn:ss") & " | " & message
    ts.Close

    Set ts = Nothing
    Set fso = Nothing
End Sub

' ========================================
' 重大エラー時のアラート送信
' ========================================
Sub SendCriticalAlert(errorMsg As String)
    On Error Resume Next

    ' 方法1: メッセージボックスで通知
    MsgBox "【重大エラー】" & vbCrLf & errorMsg, vbCritical, "Kabuto Auto Trader"

    ' 方法2: システム停止
    Call StopAutoTrading

    ' 方法3: サーバーにアラート送信（TODO）
    ' Call SendAlertToServer(errorMsg)
End Sub

' ========================================
' 古いログのクリーンアップ
' ========================================
Sub CleanupOldLogs()
    On Error Resume Next

    Dim retentionDays As Long
    retentionDays = CLng(GetConfig("LOG_RETENTION_DAYS"))
    If retentionDays = 0 Then retentionDays = 90

    Dim cutoffDate As Date
    cutoffDate = DateAdd("d", -retentionDays, Date)

    ' ErrorLogクリーンアップ
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("ErrorLog")

    Dim i As Long
    For i = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row To 2 Step -1
        Dim logDate As Date
        logDate = ws.Cells(i, 2).Value

        If logDate < cutoffDate Then
            ws.Rows(i).Delete
        End If
    Next i

    ' OrderHistoryクリーンアップ
    Set ws = ThisWorkbook.Sheets("OrderHistory")

    For i = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row To 2 Step -1
        Dim orderDate As Date
        orderDate = ws.Cells(i, 2).Value

        If orderDate < cutoffDate Then
            ws.Rows(i).Delete
        End If
    Next i

    ' ExecutionLogクリーンアップ
    Set ws = ThisWorkbook.Sheets("ExecutionLog")

    For i = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row To 2 Step -1
        Dim execDate As Date
        execDate = ws.Cells(i, 2).Value

        If execDate < cutoffDate Then
            ws.Rows(i).Delete
        End If
    Next i

    Debug.Print "Old logs cleaned up (retention: " & retentionDays & " days)"
End Sub

' ========================================
' SignalLog関連
' ========================================
Function LogSignalReceived(signal As Dictionary) As String
    '
    ' シグナル受信をSignalLogに記録
    '
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("SignalLog")

    Dim nextRow As Long
    nextRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    Dim logId As String
    logId = "SL-" & Format(Date, "YYYYMMDD") & "-" & Format(nextRow - 1, "000")

    ws.Cells(nextRow, 1).Value = logId
    ws.Cells(nextRow, 2).Value = Now
    ws.Cells(nextRow, 3).Value = signal("signal_id")
    ws.Cells(nextRow, 4).Value = signal("strategy")
    ws.Cells(nextRow, 5).Value = signal("ticker")
    ws.Cells(nextRow, 6).Value = GetTickerName(signal("ticker"))
    ws.Cells(nextRow, 7).Value = signal("action")
    ws.Cells(nextRow, 8).Value = signal("quantity")
    ws.Cells(nextRow, 9).Value = signal("price_type")
    ws.Cells(nextRow, 10).Value = signal("limit_price")
    ws.Cells(nextRow, 11).Value = signal("signal_strength")
    ws.Cells(nextRow, 12).Value = signal("checksum")
    ws.Cells(nextRow, 13).Value = "received"
    ws.Cells(nextRow, 18).Value = False

    Debug.Print "SignalLog: " & logId & " - Signal received: " & signal("signal_id")

    LogSignalReceived = logId
End Function

Sub UpdateSignalStatus(signalId As String, status As String, Optional errorMsg As String = "")
    '
    ' シグナル状態を更新
    '
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("SignalLog")

    ' signal_idで該当行を検索
    Dim foundCell As Range
    Set foundCell = ws.Columns(3).Find(signalId, LookIn:=xlValues, LookAt:=xlWhole)

    If Not foundCell Is Nothing Then
        Dim row As Long
        row = foundCell.row

        ws.Cells(row, 13).Value = status

        Select Case status
            Case "queued"
                ws.Cells(row, 14).Value = Now
            Case "processing"
                ws.Cells(row, 15).Value = Now
            Case "executed", "failed"
                ws.Cells(row, 16).Value = Now
                If errorMsg <> "" Then
                    ws.Cells(row, 17).Value = errorMsg
                End If
        End Select

        Debug.Print "SignalLog: Updated " & signalId & " status to " & status
    End If
End Sub

Sub MarkSignalACKSent(signalId As String)
    '
    ' シグナルのACK送信をマーク
    '
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("SignalLog")

    Dim foundCell As Range
    Set foundCell = ws.Columns(3).Find(signalId, LookIn:=xlValues, LookAt:=xlWhole)

    If Not foundCell Is Nothing Then
        ws.Cells(foundCell.row, 18).Value = True
        Debug.Print "SignalLog: ACK sent for " & signalId
    End If
End Sub

' ========================================
' OrderHistory関連
' ========================================
Function LogOrderSubmitted(signal As Dictionary, orderParams As Dictionary, rssOrderId As String) As String
    '
    ' 注文発注をOrderHistoryに記録
    '
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("OrderHistory")

    Dim nextRow As Long
    nextRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    Dim orderId As String
    orderId = "ORD-" & Format(Date, "YYYYMMDD") & "-" & Format(nextRow - 1, "000")

    ws.Cells(nextRow, 1).Value = orderId
    ws.Cells(nextRow, 2).Value = Now
    ws.Cells(nextRow, 3).Value = signal("signal_id")
    ws.Cells(nextRow, 4).Value = orderParams("ticker")
    ws.Cells(nextRow, 5).Value = orderParams("action")
    ws.Cells(nextRow, 6).Value = orderParams("quantity")
    ws.Cells(nextRow, 7).Value = orderParams("price_type")
    ws.Cells(nextRow, 8).Value = orderParams("limit_price")
    ws.Cells(nextRow, 9).Value = rssOrderId
    ws.Cells(nextRow, 10).Value = "submitted"
    ws.Cells(nextRow, 16).Value = orderParams("validation_result")
    ws.Cells(nextRow, 17).Value = orderParams("safety_checks")
    ws.Cells(nextRow, 18).Value = GetMarketSession()
    ws.Cells(nextRow, 19).Value = orderParams("reference_price")
    ws.Cells(nextRow, 20).Value = "auto"

    Debug.Print "OrderHistory: " & orderId & " - Order submitted: " & rssOrderId

    LogOrderSubmitted = orderId
End Function

Sub UpdateOrderExecution(internalOrderId As String, filledQty As Integer, filledPrice As Double, commission As Double)
    '
    ' 注文約定情報を更新
    '
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("OrderHistory")

    Dim foundCell As Range
    Set foundCell = ws.Columns(1).Find(internalOrderId, LookIn:=xlValues, LookAt:=xlWhole)

    If Not foundCell Is Nothing Then
        Dim row As Long
        row = foundCell.row

        Dim orderQty As Integer
        orderQty = ws.Cells(row, 6).Value

        ws.Cells(row, 11).Value = filledQty
        ws.Cells(row, 12).Value = filledPrice
        ws.Cells(row, 13).Value = commission
        ws.Cells(row, 14).Value = Now

        If filledQty >= orderQty Then
            ws.Cells(row, 10).Value = "filled"
            Debug.Print "OrderHistory: " & internalOrderId & " - Fully filled"
        Else
            ws.Cells(row, 10).Value = "partial"
            Debug.Print "OrderHistory: " & internalOrderId & " - Partially filled"
        End If
    End If
End Sub

Sub UpdateOrderStatus(internalOrderId As String, status As String, Optional rejectReason As String = "")
    '
    ' 注文状態を更新
    '
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("OrderHistory")

    Dim foundCell As Range
    Set foundCell = ws.Columns(1).Find(internalOrderId, LookIn:=xlValues, LookAt:=xlWhole)

    If Not foundCell Is Nothing Then
        ws.Cells(foundCell.row, 10).Value = status

        If rejectReason <> "" Then
            ws.Cells(foundCell.row, 15).Value = rejectReason
        End If

        Debug.Print "OrderHistory: " & internalOrderId & " status updated to " & status
    End If
End Sub

' ========================================
' ExecutionLog関連
' ========================================
Sub LogExecution(signal As Dictionary, orderInfo As Dictionary, executionInfo As Dictionary)
    '
    ' 約定をExecutionLogに記録
    '
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("ExecutionLog")

    Dim nextRow As Long
    nextRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    Dim execId As String
    execId = "EXE-" & Format(Date, "YYYYMMDD") & "-" & Format(nextRow - 1, "000")

    Dim amount As Double
    amount = executionInfo("quantity") * executionInfo("price")

    Dim totalAmount As Double
    totalAmount = amount + executionInfo("commission")

    ws.Cells(nextRow, 1).Value = execId
    ws.Cells(nextRow, 2).Value = Now
    ws.Cells(nextRow, 3).Value = Date
    ws.Cells(nextRow, 4).Value = signal("signal_id")
    ws.Cells(nextRow, 5).Value = orderInfo("internal_order_id")
    ws.Cells(nextRow, 6).Value = orderInfo("rss_order_id")
    ws.Cells(nextRow, 7).Value = signal("ticker")
    ws.Cells(nextRow, 8).Value = GetTickerName(signal("ticker"))
    ws.Cells(nextRow, 9).Value = signal("action")
    ws.Cells(nextRow, 10).Value = executionInfo("quantity")
    ws.Cells(nextRow, 11).Value = executionInfo("price")
    ws.Cells(nextRow, 12).Value = amount
    ws.Cells(nextRow, 13).Value = executionInfo("commission")
    ws.Cells(nextRow, 14).Value = totalAmount
    ws.Cells(nextRow, 15).Value = signal("strategy")
    ws.Cells(nextRow, 16).Value = GetMarketSession()

    ' 売却時は損益を計算
    If signal("action") = "sell" Then
        Dim pnl As Double
        pnl = CalculateRealizedPnL(signal("ticker"), executionInfo("quantity"), executionInfo("price"), executionInfo("commission"))
        ws.Cells(nextRow, 17).Value = pnl

        If pnl <> 0 Then
            Dim buyPrice As Double
            buyPrice = GetAverageBuyPrice(signal("ticker"))
            If buyPrice > 0 Then
                ws.Cells(nextRow, 18).Value = (pnl / (buyPrice * executionInfo("quantity"))) * 100
            End If
        End If
    End If

    ws.Cells(nextRow, 19).Value = IIf(signal("action") = "buy", "+" & executionInfo("quantity"), "-" & executionInfo("quantity"))

    Debug.Print "ExecutionLog: " & execId & " - Execution recorded"
End Sub

' ========================================
' SystemLog関連
' ========================================
Sub LogSystemEvent(level As String, category As String, eventName As String, message As String, _
                   Optional moduleName As String = "", Optional functionName As String = "", _
                   Optional details As String = "")
    '
    ' システムイベントをSystemLogに記録
    '
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("SystemLog")

    Dim nextRow As Long
    nextRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    Dim logId As String
    logId = "SYS-" & Format(Now, "YYYYMMDD-HHNNSS")

    ws.Cells(nextRow, 1).Value = logId
    ws.Cells(nextRow, 2).Value = Now
    ws.Cells(nextRow, 3).Value = level
    ws.Cells(nextRow, 4).Value = category
    ws.Cells(nextRow, 5).Value = eventName
    ws.Cells(nextRow, 6).Value = message
    ws.Cells(nextRow, 7).Value = moduleName
    ws.Cells(nextRow, 8).Value = functionName
    ws.Cells(nextRow, 9).Value = details
    ws.Cells(nextRow, 10).Value = GetSystemState("system_status")
    ws.Cells(nextRow, 11).Value = GetSystemState("api_connection_status")
    ws.Cells(nextRow, 12).Value = GetSystemState("rss_connection_status")
    ws.Cells(nextRow, 13).Value = GetMarketSession()

    ' INFOレベル以上はDebug.Printも出力
    If level <> "DEBUG" Then
        Debug.Print "SystemLog: [" & level & "] " & eventName & " - " & message
    End If
End Sub

' ========================================
' AuditLog関連
' ========================================
Sub LogAudit(operation As String, operator As String, result As String, resultDetail As String, _
             Optional signalId As String = "", Optional internalOrderId As String = "", _
             Optional ticker As String = "", Optional action As String = "", _
             Optional quantity As Integer = 0, Optional price As Double = 0, _
             Optional validationPassed As Boolean = True, Optional safetyChecks As String = "", _
             Optional riskChecks As String = "", Optional checksum As String = "")
    '
    ' 監査ログをAuditLogに記録
    '
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("AuditLog")

    Dim nextRow As Long
    nextRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    Dim auditId As String
    auditId = "AUD-" & Format(Date, "YYYYMMDD") & "-" & Format(nextRow - 1, "000")

    ws.Cells(nextRow, 1).Value = auditId
    ws.Cells(nextRow, 2).Value = Now
    ws.Cells(nextRow, 3).Value = operation
    ws.Cells(nextRow, 4).Value = operator
    ws.Cells(nextRow, 5).Value = signalId
    ws.Cells(nextRow, 6).Value = internalOrderId
    ws.Cells(nextRow, 7).Value = ticker
    ws.Cells(nextRow, 8).Value = action
    ws.Cells(nextRow, 9).Value = quantity
    ws.Cells(nextRow, 10).Value = price
    ws.Cells(nextRow, 11).Value = validationPassed
    ws.Cells(nextRow, 12).Value = safetyChecks
    ws.Cells(nextRow, 13).Value = riskChecks
    ws.Cells(nextRow, 14).Value = GetMarketSession()
    ws.Cells(nextRow, 15).Value = GetSystemState("system_status")
    ws.Cells(nextRow, 16).Value = result
    ws.Cells(nextRow, 17).Value = resultDetail
    ws.Cells(nextRow, 18).Value = checksum

    Debug.Print "AuditLog: " & auditId & " - " & operation & " - " & result
End Sub

' ========================================
' ユーティリティ関数
' ========================================
Function FormatTimestamp(dt As Date) As String
    '
    ' タイムスタンプをフォーマット
    '
    FormatTimestamp = Format(dt, "YYYY-MM-DD HH:NN:SS")
End Function

Sub ArchiveOldLogs()
    '
    ' 古いログをアーカイブ
    '
    On Error Resume Next

    Dim logsToArchive As Variant
    logsToArchive = Array("SignalLog", "ErrorLog", "SystemLog")

    Dim i As Integer
    For i = LBound(logsToArchive) To UBound(logsToArchive)
        Dim sheetName As String
        sheetName = logsToArchive(i)

        Call ArchiveLogSheet(sheetName, 90)  ' 90日以前をアーカイブ
    Next i
End Sub

Sub ArchiveLogSheet(sheetName As String, daysToKeep As Integer)
    '
    ' ログシートをアーカイブ
    '
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets(sheetName)

    Dim archiveDate As Date
    archiveDate = DateAdd("d", -daysToKeep, Date)

    ' アーカイブシートを作成（存在しなければ）
    Dim archiveSheetName As String
    archiveSheetName = sheetName & "_Archive"

    Dim archiveWs As Worksheet
    On Error Resume Next
    Set archiveWs = ThisWorkbook.Sheets(archiveSheetName)
    If archiveWs Is Nothing Then
        Set archiveWs = ThisWorkbook.Sheets.Add
        archiveWs.Name = archiveSheetName

        ' ヘッダーをコピー
        ws.Rows(1).Copy archiveWs.Rows(1)
    End If
    On Error GoTo 0

    ' 古いログを移動
    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row

    Dim j As Long
    For j = lastRow To 2 Step -1
        Dim logDate As Date
        logDate = ws.Cells(j, 2).Value  ' B列: timestamp

        If logDate < archiveDate Then
            ' アーカイブシートの最終行を取得
            Dim archiveLastRow As Long
            archiveLastRow = archiveWs.Cells(archiveWs.Rows.Count, 1).End(xlUp).Row + 1

            ' 行をコピー
            ws.Rows(j).Copy archiveWs.Rows(archiveLastRow)

            ' 元の行を削除
            ws.Rows(j).Delete
        End If
    Next j

    Debug.Print "ArchiveLog: " & sheetName & " - Archived logs older than " & daysToKeep & " days"
End Sub

Sub CheckAlertsAndNotify()
    '
    ' アラート条件をチェックして通知
    '
    On Error Resume Next

    ' 1. 過去1時間のエラー件数チェック
    Dim errorCount As Integer
    errorCount = CountErrorsInLastHour()

    If errorCount >= 10 Then
        Call NotifyHighErrorRate(errorCount, "1時間")
    End If

    ' 2. 日次損失チェック
    Dim dailyPnL As Double
    dailyPnL = CalculateDailyPnL()

    If dailyPnL <= -50000 Then
        Dim fields As New Collection
        Dim field As Dictionary

        Set field = New Dictionary
        field("title") = "日次損益"
        field("value") = Format(dailyPnL, "#,##0") & "円"
        field("short") = True
        fields.Add field

        Set field = New Dictionary
        field("title") = "損失限度"
        field("value") = "-50,000円"
        field("short") = True
        fields.Add field

        Call SendSlackNotification("CRITICAL", "日次損失限度到達", fields, True)
        Call ActivateKillSwitch("Daily loss limit exceeded")
    End If

    ' 3. API接続状態チェック
    Dim apiStatus As String
    apiStatus = GetSystemState("api_connection_status")

    If apiStatus = "Disconnected" Then
        Dim apiFields As New Collection
        Dim apiField As Dictionary

        Set apiField = New Dictionary
        apiField("title") = "接続状態"
        apiField("value") = "切断"
        apiField("short") = True
        apiFields.Add apiField

        Call SendSlackNotification("ERROR", "API接続断", apiFields, False)
    End If
End Sub

Function CountErrorsInLastHour() As Integer
    '
    ' 過去1時間のエラー件数を集計
    '
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("ErrorLog")

    Dim oneHourAgo As Date
    oneHourAgo = DateAdd("h", -1, Now)

    Dim errorCount As Integer
    errorCount = 0

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim errorTime As Date
        errorTime = ws.Cells(i, 2).Value

        If errorTime >= oneHourAgo Then
            Dim severity As String
            severity = ws.Cells(i, 9).Value

            If severity = "ERROR" Or severity = "CRITICAL" Then
                errorCount = errorCount + 1
            End If
        End If
    Next i

    CountErrorsInLastHour = errorCount
End Function
