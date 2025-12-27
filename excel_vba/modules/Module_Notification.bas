Attribute VB_Name = "Module_Notification"
'
' Kabuto Auto Trader - Notification Module
' 異常検知・通知機能
'

Option Explicit

' ========================================
' Slack通知
' ========================================
Sub SendSlackNotification(level As String, title As String, fields As Collection, Optional mentionChannel As Boolean = False)
    On Error Resume Next

    ' Webhook URL取得
    Dim webhookUrl As String
    Select Case level
        Case "INFO"
            webhookUrl = GetConfig("slack_webhook_info")
        Case "WARNING"
            webhookUrl = GetConfig("slack_webhook_warnings")
        Case "ERROR"
            webhookUrl = GetConfig("slack_webhook_alerts")
        Case "CRITICAL"
            webhookUrl = GetConfig("slack_webhook_critical")
        Case Else
            webhookUrl = GetConfig("slack_webhook_alerts")
    End Select

    If webhookUrl = "" Then
        Debug.Print "Slack: Webhook URL not configured for level " & level
        Exit Sub
    End If

    ' 通知頻度制限チェック
    If Not ShouldSendNotification(level, title) Then
        Debug.Print "Slack: Notification suppressed (frequency limit): " & title
        Exit Sub
    End If

    ' ペイロード作成
    Dim payload As String
    payload = BuildSlackPayload(level, title, fields, mentionChannel)

    ' HTTP POST送信
    Dim http As Object
    Set http = CreateObject("MSXML2.XMLHTTP")

    http.Open "POST", webhookUrl, False
    http.setRequestHeader "Content-Type", "application/json"
    http.send payload

    If http.Status = 200 Then
        Debug.Print "Slack: Notification sent - " & title
        Call RecordNotification(level, title)
    Else
        Debug.Print "Slack: Failed to send - HTTP " & http.Status
        Call LogError("ERROR", "NOTIFICATION", "Module_Notification", "SendSlackNotification", _
                      "SLACK_ERR_001", "Slack notification failed", "HTTP " & http.Status)
    End If
End Sub

Function BuildSlackPayload(level As String, title As String, fields As Collection, mentionChannel As Boolean) As String
    '
    ' Slackペイロード（JSON）を構築
    '
    On Error Resume Next

    Dim color As String
    Dim icon As String
    Dim prefix As String

    Select Case level
        Case "INFO"
            color = "#36a64f"  ' Green
            icon = ":information_source:"
            prefix = "ℹ️"
        Case "WARNING"
            color = "warning"  ' Yellow
            icon = ":warning:"
            prefix = "⚠️"
        Case "ERROR"
            color = "danger"   ' Red
            icon = ":x:"
            prefix = "🚨"
        Case "CRITICAL"
            color = "#FF0000"  ' Bright Red
            icon = ":rotating_light:"
            prefix = "🚨🚨🚨"
    End Select

    ' JSON作成（手動構築）
    Dim json As String
    json = "{"
    json = json & """username"": ""Kabuto Auto Trader"","
    json = json & """icon_emoji"": """ & icon & """"

    If mentionChannel Then
        json = json & ",""text"": ""@channel"""
    End If

    json = json & ",""attachments"": [{"
    json = json & """color"": """ & color & ""","
    json = json & """title"": """ & prefix & " " & title & ""","
    json = json & """fields"": ["

    ' フィールド追加
    Dim i As Integer
    For i = 1 To fields.Count
        Dim field As Dictionary
        Set field = fields(i)

        json = json & "{"
        json = json & """title"": """ & EscapeJSON(field("title")) & ""","
        json = json & """value"": """ & EscapeJSON(field("value")) & ""","
        json = json & """short"": " & LCase(CStr(field("short")))
        json = json & "}"

        If i < fields.Count Then
            json = json & ","
        End If
    Next i

    json = json & "],"
    json = json & """footer"": ""Kabuto Auto Trader"","
    json = json & """ts"": " & CLng((Now - DateSerial(1970, 1, 1)) * 86400)
    json = json & "}]}"

    BuildSlackPayload = json
End Function

Function EscapeJSON(text As String) As String
    '
    ' JSON文字列エスケープ
    '
    Dim result As String
    result = text

    result = Replace(result, "\", "\\")
    result = Replace(result, """", "\""")
    result = Replace(result, vbCrLf, "\n")
    result = Replace(result, vbCr, "\n")
    result = Replace(result, vbLf, "\n")

    EscapeJSON = result
End Function

' ========================================
' メール通知
' ========================================
Sub SendEmailNotification(level As String, title As String, fields As Collection)
    On Error Resume Next

    ' メール設定取得
    Dim smtpServer As String
    Dim smtpPort As Integer
    Dim smtpUseTLS As Boolean
    Dim smtpUsername As String
    Dim smtpPassword As String
    Dim emailTo As String
    Dim emailFrom As String

    smtpServer = GetConfig("smtp_server")
    smtpPort = CInt(GetConfig("smtp_port"))
    smtpUseTLS = CBool(GetConfig("smtp_use_tls"))
    smtpUsername = GetConfig("smtp_username")
    smtpPassword = GetConfig("smtp_password")
    emailTo = GetConfig("notification_email_to")
    emailFrom = GetConfig("notification_email_from")

    If smtpServer = "" Or emailTo = "" Then
        Debug.Print "Email: SMTP not configured"
        Exit Sub
    End If

    ' 件名作成
    Dim subject As String
    subject = "[Kabuto] " & UCase(level) & " - " & title

    ' 本文作成
    Dim body As String
    body = BuildEmailBody(level, title, fields)

    ' CDO.Message使用してメール送信
    Dim msg As Object
    Set msg = CreateObject("CDO.Message")

    With msg
        .From = emailFrom
        .To = emailTo
        .Subject = subject
        .HTMLBody = body

        ' SMTP設定
        .Configuration.fields("http://schemas.microsoft.com/cdo/configuration/sendusing") = 2
        .Configuration.fields("http://schemas.microsoft.com/cdo/configuration/smtpserver") = smtpServer
        .Configuration.fields("http://schemas.microsoft.com/cdo/configuration/smtpserverport") = smtpPort

        If smtpUseTLS Then
            .Configuration.fields("http://schemas.microsoft.com/cdo/configuration/smtpusessl") = True
        End If

        If smtpUsername <> "" Then
            .Configuration.fields("http://schemas.microsoft.com/cdo/configuration/smtpauthenticate") = 1
            .Configuration.fields("http://schemas.microsoft.com/cdo/configuration/sendusername") = smtpUsername
            .Configuration.fields("http://schemas.microsoft.com/cdo/configuration/sendpassword") = smtpPassword
        End If

        .Configuration.fields.Update
        .send
    End With

    Debug.Print "Email: Notification sent - " & title
End Sub

Function BuildEmailBody(level As String, title As String, fields As Collection) As String
    '
    ' メール本文（HTML）を構築
    '
    On Error Resume Next

    Dim levelClass As String
    Dim icon As String

    Select Case level
        Case "WARNING"
            levelClass = "warning"
            icon = "⚠️"
        Case "ERROR"
            levelClass = "error"
            icon = "🚨"
        Case "CRITICAL"
            levelClass = "critical"
            icon = "🚨🚨🚨"
    End Select

    Dim html As String
    html = "<!DOCTYPE html>" & vbCrLf
    html = html & "<html>" & vbCrLf
    html = html & "<head><meta charset=""UTF-8""><style>"
    html = html & "body { font-family: Arial, sans-serif; }"
    html = html & ".container { max-width: 600px; margin: 0 auto; padding: 20px; }"
    html = html & ".header { background-color: #f44336; color: white; padding: 20px; border-radius: 5px; }"
    html = html & ".header.warning { background-color: #ff9800; }"
    html = html & ".header.error { background-color: #f44336; }"
    html = html & ".header.critical { background-color: #d32f2f; }"
    html = html & ".content { padding: 20px; background-color: #f5f5f5; margin-top: 20px; border-radius: 5px; }"
    html = html & ".field { margin-bottom: 15px; }"
    html = html & ".field-title { font-weight: bold; color: #333; }"
    html = html & ".field-value { color: #666; margin-top: 5px; }"
    html = html & ".footer { margin-top: 20px; padding-top: 20px; border-top: 1px solid #ddd; color: #999; font-size: 12px; }"
    html = html & "</style></head>" & vbCrLf
    html = html & "<body>" & vbCrLf
    html = html & "<div class=""container"">" & vbCrLf
    html = html & "<div class=""header " & levelClass & """>" & vbCrLf
    html = html & "<h1>" & icon & " " & title & "</h1>" & vbCrLf
    html = html & "</div>" & vbCrLf
    html = html & "<div class=""content"">" & vbCrLf

    ' フィールド追加
    Dim i As Integer
    For i = 1 To fields.Count
        Dim field As Dictionary
        Set field = fields(i)

        html = html & "<div class=""field"">" & vbCrLf
        html = html & "<div class=""field-title"">" & field("title") & "</div>" & vbCrLf
        html = html & "<div class=""field-value"">" & Replace(field("value"), vbLf, "<br>") & "</div>" & vbCrLf
        html = html & "</div>" & vbCrLf
    Next i

    html = html & "</div>" & vbCrLf
    html = html & "<div class=""footer"">" & vbCrLf
    html = html & "<p>Kabuto Auto Trader</p>" & vbCrLf
    html = html & "<p>発生時刻: " & Format(Now, "YYYY-MM-DD HH:NN:SS") & "</p>" & vbCrLf
    html = html & "</div>" & vbCrLf
    html = html & "</div>" & vbCrLf
    html = html & "</body>" & vbCrLf
    html = html & "</html>"

    BuildEmailBody = html
End Function

' ========================================
' 通知頻度制限
' ========================================
Function ShouldSendNotification(level As String, title As String) As Boolean
    '
    ' 通知頻度制限チェック
    '
    On Error Resume Next

    ' CRITICAL は常に通知
    If level = "CRITICAL" Then
        ShouldSendNotification = True
        Exit Function
    End If

    ' 前回の通知時刻を取得
    Dim lastNotifyTime As Variant
    lastNotifyTime = GetLastNotificationTime(title)

    If IsEmpty(lastNotifyTime) Then
        ' 初回通知
        ShouldSendNotification = True
        Exit Function
    End If

    ' 経過時間を計算
    Dim elapsedMinutes As Long
    elapsedMinutes = DateDiff("n", lastNotifyTime, Now)

    ' レベル別の再通知間隔
    Dim intervalMinutes As Long
    Select Case level
        Case "WARNING"
            intervalMinutes = 30
        Case "ERROR"
            intervalMinutes = 15
        Case Else
            intervalMinutes = 30
    End Select

    If elapsedMinutes >= intervalMinutes Then
        ShouldSendNotification = True
    Else
        ShouldSendNotification = False
    End If
End Function

Function GetLastNotificationTime(title As String) As Variant
    '
    ' 前回の通知時刻を取得
    '
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("NotificationHistory")

    Dim foundCell As Range
    Set foundCell = ws.Columns(2).Find(title, LookIn:=xlValues, LookAt:=xlWhole)

    If Not foundCell Is Nothing Then
        GetLastNotificationTime = ws.Cells(foundCell.Row, 3).Value
    Else
        GetLastNotificationTime = Empty
    End If
End Function

Sub RecordNotification(level As String, title As String)
    '
    ' 通知履歴を記録
    '
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("NotificationHistory")

    ' 既存エントリを検索
    Dim foundCell As Range
    Set foundCell = ws.Columns(2).Find(title, LookIn:=xlValues, LookAt:=xlWhole)

    If Not foundCell Is Nothing Then
        ' 更新
        Dim row As Long
        row = foundCell.row
        ws.Cells(row, 3).Value = Now
        ws.Cells(row, 4).Value = ws.Cells(row, 4).Value + 1
    Else
        ' 新規追加
        Dim nextRow As Long
        nextRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).row + 1

        ws.Cells(nextRow, 1).Value = level
        ws.Cells(nextRow, 2).Value = title
        ws.Cells(nextRow, 3).Value = Now
        ws.Cells(nextRow, 4).Value = 1
    End If
End Sub

' ========================================
' 発注失敗通知
' ========================================
Sub NotifyOrderFailed(signal As Dictionary, reason As String)
    On Error Resume Next

    Dim fields As New Collection
    Dim field As Dictionary

    Set field = New Dictionary
    field("title") = "銘柄"
    field("value") = signal("ticker") & " " & GetTickerName(signal("ticker"))
    field("short") = True
    fields.Add field

    Set field = New Dictionary
    field("title") = "売買区分"
    field("value") = IIf(signal("action") = "buy", "買い", "売り")
    field("short") = True
    fields.Add field

    Set field = New Dictionary
    field("title") = "数量"
    field("value") = signal("quantity") & "株"
    field("short") = True
    fields.Add field

    Set field = New Dictionary
    field("title") = "失敗理由"
    field("value") = reason
    field("short") = True
    fields.Add field

    Set field = New Dictionary
    field("title") = "Signal ID"
    field("value") = signal("signal_id")
    field("short") = False
    fields.Add field

    Set field = New Dictionary
    field("title") = "発生時刻"
    field("value") = Format(Now, "YYYY-MM-DD HH:NN:SS")
    field("short") = False
    fields.Add field

    Call SendSlackNotification("WARNING", "発注失敗", fields, False)
End Sub

' ========================================
' 連続失敗通知
' ========================================
Sub NotifyConsecutiveFailures(failureCount As Integer, lastSignal As Dictionary, reason As String)
    On Error Resume Next

    Dim fields As New Collection
    Dim field As Dictionary

    Set field = New Dictionary
    field("title") = "失敗回数"
    field("value") = failureCount & "回連続"
    field("short") = True
    fields.Add field

    Set field = New Dictionary
    field("title") = "直近の失敗"
    field("value") = lastSignal("ticker") & " " & GetTickerName(lastSignal("ticker")) & " " & _
                     IIf(lastSignal("action") = "buy", "買い", "売り") & " " & lastSignal("quantity") & "株"
    field("short") = True
    fields.Add field

    Set field = New Dictionary
    field("title") = "共通失敗理由"
    field("value") = reason
    field("short") = False
    fields.Add field

    Set field = New Dictionary
    field("title") = "推奨対応"
    field("value") = GetRecommendedAction(reason)
    field("short") = False
    fields.Add field

    Call SendSlackNotification("ERROR", "連続発注失敗（" & failureCount & "回）", fields, False)
    Call SendEmailNotification("ERROR", "連続発注失敗（" & failureCount & "回）", fields)
End Sub

Function GetRecommendedAction(reason As String) As String
    '
    ' エラー原因に応じた推奨対応を返す
    '
    Select Case True
        Case InStr(reason, "RSS") > 0
            GetRecommendedAction = "RSSの接続状態を確認してください"
        Case InStr(reason, "API") > 0
            GetRecommendedAction = "APIサーバーの接続状態を確認してください"
        Case InStr(reason, "検証") > 0
            GetRecommendedAction = "注文パラメータの設定を確認してください"
        Case InStr(reason, "リスク") > 0
            GetRecommendedAction = "リスク設定を見直してください"
        Case Else
            GetRecommendedAction = "システムログを確認してください"
    End Select
End Function

' ========================================
' Kill Switch発動通知
' ========================================
Sub NotifyKillSwitchActivated(reason As String)
    On Error Resume Next

    Dim fields As New Collection
    Dim field As Dictionary

    Set field = New Dictionary
    field("title") = "発動理由"
    field("value") = reason
    field("short") = False
    fields.Add field

    ' 本日の取引成績を計算
    Dim dailyPnL As Double
    Dim tradeCount As Integer
    Dim winCount As Integer

    dailyPnL = CalculateDailyPnL()
    tradeCount = GetSystemState("daily_trade_count")
    ' winCountの計算は省略（実装必要に応じて）

    Set field = New Dictionary
    field("title") = "本日の取引成績"
    field("value") = "損益: " & Format(dailyPnL, "#,##0") & "円 | " & _
                     "取引回数: " & tradeCount & "回"
    field("short") = False
    fields.Add field

    Set field = New Dictionary
    field("title") = "システム状態"
    field("value") = "⛔ 全取引停止"
    field("short") = False
    fields.Add field

    Set field = New Dictionary
    field("title") = "必要な対応"
    field("value") = "1. 原因調査" & vbLf & "2. リスク設定見直し" & vbLf & "3. 手動で再起動"
    field("short") = False
    fields.Add field

    Set field = New Dictionary
    field("title") = "発生時刻"
    field("value") = Format(Now, "YYYY-MM-DD HH:NN:SS")
    field("short") = False
    fields.Add field

    Call SendSlackNotification("CRITICAL", "KILL SWITCH 発動", fields, True)
    Call SendEmailNotification("CRITICAL", "KILL SWITCH 発動", fields)
End Sub

' ========================================
' システム停止通知
' ========================================
Sub NotifySystemStopped(stopReason As String)
    On Error Resume Next

    Dim fields As New Collection
    Dim field As Dictionary

    Set field = New Dictionary
    field("title") = "停止理由"
    field("value") = stopReason
    field("short") = False
    fields.Add field

    Set field = New Dictionary
    field("title") = "停止時刻"
    field("value") = Format(Now, "YYYY-MM-DD HH:NN:SS")
    field("short") = True
    fields.Add field

    Set field = New Dictionary
    field("title") = "稼働時間"
    field("value") = CalculateUptime()
    field("short") = True
    fields.Add field

    Set field = New Dictionary
    field("title") = "本日の取引"
    field("value") = GetSystemState("daily_trade_count") & "回"
    field("short") = True
    fields.Add field

    Call SendSlackNotification("ERROR", "システム停止", fields, False)
    Call SendEmailNotification("ERROR", "システム停止", fields)
End Sub

Function CalculateUptime() As String
    '
    ' 稼働時間を計算
    '
    On Error Resume Next

    Dim startTime As Date
    startTime = GetSystemState("workbook_start_time")

    If IsEmpty(startTime) Then
        CalculateUptime = "不明"
        Exit Function
    End If

    Dim uptimeMinutes As Long
    uptimeMinutes = DateDiff("n", startTime, Now)

    Dim hours As Long
    Dim minutes As Long
    hours = uptimeMinutes \ 60
    minutes = uptimeMinutes Mod 60

    CalculateUptime = hours & "時間" & minutes & "分"
End Function

' ========================================
' エラー頻発通知
' ========================================
Sub NotifyHighErrorRate(errorCount As Integer, timeWindow As String)
    On Error Resume Next

    Dim fields As New Collection
    Dim field As Dictionary

    Set field = New Dictionary
    field("title") = "エラー回数"
    field("value") = errorCount & "回 / " & timeWindow
    field("short") = True
    fields.Add field

    Set field = New Dictionary
    field("title") = "閾値"
    field("value") = "10回 / 1時間"
    field("short") = True
    fields.Add field

    Set field = New Dictionary
    field("title") = "推奨対応"
    field("value") = "ErrorLogを確認し、共通原因を調査してください"
    field("short") = False
    fields.Add field

    Call SendSlackNotification("ERROR", "エラー頻発検知", fields, False)
    Call SendEmailNotification("ERROR", "エラー頻発検知", fields)
End Sub
