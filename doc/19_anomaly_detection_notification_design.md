# Kabuto Auto Trader - 異常検知・通知設計

**作成日**: 2025-12-27
**ドキュメントID**: doc/19

---

## 目次

1. [異常検知の目的](#1-異常検知の目的)
2. [異常検知条件](#2-異常検知条件)
3. [通知レベル定義](#3-通知レベル定義)
4. [Slack通知設計](#4-slack通知設計)
5. [メール通知設計](#5-メール通知設計)
6. [Excel側実装](#6-excel側実装)
7. [Server側実装](#7-server側実装)
8. [通知テンプレート](#8-通知テンプレート)
9. [設定管理](#9-設定管理)

---

## 1. 異常検知の目的

### 1.1 目的

| 目的 | 説明 |
|------|------|
| **早期発見** | システム異常を即座に検知 |
| **損失防止** | 異常取引による損失を最小化 |
| **稼働率向上** | ダウンタイムを最小化 |
| **運用負荷軽減** | 自動監視により人的監視を削減 |

### 1.2 通知方針

- ⚡ **即時性**: 異常検知から1分以内に通知
- 🎯 **正確性**: 誤検知を最小化（false positive < 5%）
- 📊 **情報充実**: 原因調査に必要な情報を含む
- 🔕 **通知疲れ防止**: 重複通知を抑制

---

## 2. 異常検知条件

### 2.1 発注失敗関連

| 異常種別 | 検知条件 | レベル | 通知先 |
|---------|---------|--------|--------|
| **発注失敗（単発）** | 1回の発注失敗 | WARNING | Slack |
| **発注失敗（連続）** | 3回連続で発注失敗 | ERROR | Slack + Mail |
| **発注拒否率高** | 直近10回中5回以上拒否 | ERROR | Slack + Mail |
| **RSS接続エラー** | RSSへの接続失敗 | CRITICAL | Slack + Mail |
| **検証エラー（連続）** | 3回連続で検証失敗 | WARNING | Slack |

### 2.2 異常回数関連

| 異常種別 | 検知条件 | レベル | 通知先 |
|---------|---------|--------|--------|
| **エラー頻発** | 1時間に10回以上エラー | ERROR | Slack + Mail |
| **API呼び出し失敗** | 5分間に3回以上失敗 | WARNING | Slack |
| **Kill Switch発動** | 自動Kill Switch発動 | CRITICAL | Slack + Mail |
| **5連続損失** | 5取引連続で損失 | ERROR | Slack + Mail |
| **日次損失限度** | 日次損失-5万円到達 | CRITICAL | Slack + Mail |
| **異常取引頻度** | 1時間に10回以上取引 | WARNING | Slack |

### 2.3 システム停止関連

| 異常種別 | 検知条件 | レベル | 通知先 |
|---------|---------|--------|--------|
| **システム停止** | 自動取引システム停止 | ERROR | Slack + Mail |
| **システムクラッシュ** | 予期しない終了 | CRITICAL | Slack + Mail |
| **Heartbeat途絶** | 10分間Heartbeat未受信 | ERROR | Slack + Mail |
| **API接続断** | APIサーバー接続断 | ERROR | Slack |
| **市場時間外起動** | 市場時間外に起動試行 | WARNING | Slack |

---

## 3. 通知レベル定義

### 3.1 通知レベル一覧

| レベル | 重大度 | 対応要否 | 通知先 | 例 |
|--------|--------|---------|--------|-----|
| **INFO** | 情報 | 不要 | Slack（#info） | システム起動、正常取引 |
| **WARNING** | 警告 | 監視 | Slack（#warnings） | 発注失敗（単発）、市場時間外起動 |
| **ERROR** | エラー | 必要 | Slack（#alerts） + Mail | 連続失敗、API接続断 |
| **CRITICAL** | 緊急 | 即座 | Slack（#critical） + Mail + SMS* | Kill Switch、システムクラッシュ |

*SMS通知は将来実装

### 3.2 レベル別通知頻度制限

| レベル | 同一エラーの再通知間隔 |
|--------|---------------------|
| **INFO** | 通知しない |
| **WARNING** | 30分 |
| **ERROR** | 15分 |
| **CRITICAL** | 制限なし（毎回通知） |

---

## 4. Slack通知設計

### 4.1 Slackチャンネル構成

| チャンネル名 | 用途 | 通知レベル |
|------------|------|-----------|
| **#kabuto-info** | 通常動作情報 | INFO |
| **#kabuto-warnings** | 警告情報 | WARNING |
| **#kabuto-alerts** | エラー・アラート | ERROR |
| **#kabuto-critical** | 緊急事態 | CRITICAL |
| **#kabuto-trades** | 取引通知 | INFO |

### 4.2 Slack Webhook URL設定

**設定場所**: Configシート

| 設定キー | 説明 | 例 |
|---------|------|-----|
| slack_webhook_info | INFO用Webhook | https://hooks.slack.com/services/xxx/yyy/zzz |
| slack_webhook_warnings | WARNING用Webhook | https://hooks.slack.com/services/xxx/yyy/zzz |
| slack_webhook_alerts | ERROR用Webhook | https://hooks.slack.com/services/xxx/yyy/zzz |
| slack_webhook_critical | CRITICAL用Webhook | https://hooks.slack.com/services/xxx/yyy/zzz |
| slack_webhook_trades | 取引通知用Webhook | https://hooks.slack.com/services/xxx/yyy/zzz |

### 4.3 Slack通知フォーマット

**WARNING例（発注失敗）**:

```json
{
  "username": "Kabuto Auto Trader",
  "icon_emoji": ":warning:",
  "attachments": [
    {
      "color": "warning",
      "title": "⚠️ 発注失敗",
      "fields": [
        {
          "title": "銘柄",
          "value": "7203 トヨタ自動車",
          "short": true
        },
        {
          "title": "売買区分",
          "value": "買い",
          "short": true
        },
        {
          "title": "数量",
          "value": "100株",
          "short": true
        },
        {
          "title": "失敗理由",
          "value": "RSS接続タイムアウト",
          "short": true
        },
        {
          "title": "Signal ID",
          "value": "SIG-20250127-ABC123",
          "short": false
        },
        {
          "title": "発生時刻",
          "value": "2025-01-27 09:05:30",
          "short": false
        }
      ],
      "footer": "Kabuto Auto Trader",
      "ts": 1706318730
    }
  ]
}
```

**ERROR例（3回連続失敗）**:

```json
{
  "username": "Kabuto Auto Trader",
  "icon_emoji": ":x:",
  "attachments": [
    {
      "color": "danger",
      "title": "🚨 連続発注失敗（3回）",
      "fields": [
        {
          "title": "失敗回数",
          "value": "3回連続",
          "short": true
        },
        {
          "title": "直近の失敗",
          "value": "7203 トヨタ自動車 買い 100株",
          "short": true
        },
        {
          "title": "共通失敗理由",
          "value": "RSS接続タイムアウト",
          "short": false
        },
        {
          "title": "推奨対応",
          "value": "RSSの接続状態を確認してください",
          "short": false
        }
      ],
      "footer": "Kabuto Auto Trader",
      "ts": 1706318730
    }
  ]
}
```

**CRITICAL例（Kill Switch発動）**:

```json
{
  "username": "Kabuto Auto Trader",
  "icon_emoji": ":rotating_light:",
  "text": "@channel",
  "attachments": [
    {
      "color": "#FF0000",
      "title": "🚨🚨🚨 KILL SWITCH 発動 🚨🚨🚨",
      "fields": [
        {
          "title": "発動理由",
          "value": "日次損失限度到達（-50,000円）",
          "short": false
        },
        {
          "title": "本日の取引成績",
          "value": "損益: -52,300円 | 取引回数: 8回 | 勝率: 25%",
          "short": false
        },
        {
          "title": "システム状態",
          "value": "⛔ 全取引停止",
          "short": false
        },
        {
          "title": "必要な対応",
          "value": "1. 原因調査\n2. リスク設定見直し\n3. 手動で再起動",
          "short": false
        },
        {
          "title": "発生時刻",
          "value": "2025-01-27 14:30:15",
          "short": false
        }
      ],
      "footer": "Kabuto Auto Trader - EMERGENCY",
      "ts": 1706338215
    }
  ]
}
```

### 4.4 VBA実装（Slack通知）

**Module_Notification.bas**:

```vba
Attribute VB_Name = "Module_Notification"
'
' Kabuto Auto Trader - Notification Module
' Slack / Mail 通知機能
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
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("NotificationHistory")

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
        row = foundCell.Row
        ws.Cells(row, 3).Value = Now
        ws.Cells(row, 4).Value = ws.Cells(row, 4).Value + 1
    Else
        ' 新規追加
        Dim nextRow As Long
        nextRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

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
Sub NotifyKillSwitchActivated(reason As String, dailyStats As Dictionary)
    On Error Resume Next

    Dim fields As New Collection
    Dim field As Dictionary

    Set field = New Dictionary
    field("title") = "発動理由"
    field("value") = reason
    field("short") = False
    fields.Add field

    Set field = New Dictionary
    field("title") = "本日の取引成績"
    field("value") = "損益: " & Format(dailyStats("pnl"), "#,##0") & "円 | " & _
                     "取引回数: " & dailyStats("trade_count") & "回 | " & _
                     "勝率: " & Format(dailyStats("win_rate") * 100, "0") & "%"
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
End Sub
```

---

## 5. メール通知設計

### 5.1 メール設定

**設定場所**: Configシート

| 設定キー | 説明 | 例 |
|---------|------|-----|
| smtp_server | SMTPサーバー | smtp.gmail.com |
| smtp_port | SMTPポート | 587 |
| smtp_use_tls | TLS使用 | TRUE |
| smtp_username | SMTP認証ユーザー名 | your-email@gmail.com |
| smtp_password | SMTP認証パスワード | your-app-password |
| notification_email_to | 通知先メールアドレス | alert@example.com |
| notification_email_from | 送信元メールアドレス | kabuto@example.com |

### 5.2 メールテンプレート

**件名フォーマット**:
```
[Kabuto] {LEVEL} - {TITLE}
```

**例**:
- `[Kabuto] WARNING - 発注失敗`
- `[Kabuto] ERROR - 連続発注失敗（3回）`
- `[Kabuto] CRITICAL - KILL SWITCH 発動`

**本文フォーマット（HTML）**:

```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background-color: #f44336; color: white; padding: 20px; border-radius: 5px; }
        .header.warning { background-color: #ff9800; }
        .header.error { background-color: #f44336; }
        .header.critical { background-color: #d32f2f; }
        .content { padding: 20px; background-color: #f5f5f5; margin-top: 20px; border-radius: 5px; }
        .field { margin-bottom: 15px; }
        .field-title { font-weight: bold; color: #333; }
        .field-value { color: #666; margin-top: 5px; }
        .footer { margin-top: 20px; padding-top: 20px; border-top: 1px solid #ddd; color: #999; font-size: 12px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header {LEVEL_CLASS}">
            <h1>{ICON} {TITLE}</h1>
        </div>
        <div class="content">
            {FIELDS}
        </div>
        <div class="footer">
            <p>Kabuto Auto Trader</p>
            <p>発生時刻: {TIMESTAMP}</p>
        </div>
    </div>
</body>
</html>
```

### 5.3 VBA実装（メール通知）

```vba
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
        .Configuration.Fields("http://schemas.microsoft.com/cdo/configuration/sendusing") = 2
        .Configuration.Fields("http://schemas.microsoft.com/cdo/configuration/smtpserver") = smtpServer
        .Configuration.Fields("http://schemas.microsoft.com/cdo/configuration/smtpserverport") = smtpPort

        If smtpUseTLS Then
            .Configuration.Fields("http://schemas.microsoft.com/cdo/configuration/smtpusessl") = True
        End If

        If smtpUsername <> "" Then
            .Configuration.Fields("http://schemas.microsoft.com/cdo/configuration/smtpauthenticate") = 1
            .Configuration.Fields("http://schemas.microsoft.com/cdo/configuration/sendusername") = smtpUsername
            .Configuration.Fields("http://schemas.microsoft.com/cdo/configuration/sendpassword") = smtpPassword
        End If

        .Configuration.Fields.Update
        .Send
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
```

---

## 6. Excel側実装

### 6.1 異常検知タイマー

**Module_Main.bas に追加**:

```vba
Public Sub StartAnomalyDetection()
    '
    ' 異常検知タイマー起動（1分間隔）
    '
    On Error Resume Next

    Dim nextRun As Date
    nextRun = Now + TimeValue("00:01:00")  ' 1分後

    Application.OnTime nextRun, "CheckAnomalies"
End Sub

Public Sub CheckAnomalies()
    '
    ' 異常検知チェック
    '
    On Error Resume Next

    ' 1. 連続発注失敗チェック
    Call CheckConsecutiveOrderFailures

    ' 2. エラー頻発チェック
    Call CheckHighErrorRate

    ' 3. API接続状態チェック
    Call CheckAPIConnectionStatus

    ' 4. Heartbeat途絶チェック
    Call CheckHeartbeatTimeout

    ' 次回の異常検知をスケジュール
    Call StartAnomalyDetection
End Sub

Sub CheckConsecutiveOrderFailures()
    '
    ' 連続発注失敗をチェック
    '
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("OrderHistory")

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row

    ' 直近3件の注文をチェック
    Dim consecutiveFailures As Integer
    consecutiveFailures = 0

    Dim i As Long
    For i = lastRow To Application.Max(2, lastRow - 2) Step -1
        Dim orderStatus As String
        orderStatus = ws.Cells(i, 10).Value  ' J列: order_status

        If orderStatus = "rejected" Then
            consecutiveFailures = consecutiveFailures + 1
        Else
            Exit For
        End If
    Next i

    ' 3回連続失敗で通知
    If consecutiveFailures >= 3 Then
        Dim lastSignal As New Dictionary
        lastSignal("ticker") = ws.Cells(lastRow, 4).Value
        lastSignal("action") = ws.Cells(lastRow, 5).Value
        lastSignal("quantity") = ws.Cells(lastRow, 6).Value

        Dim reason As String
        reason = ws.Cells(lastRow, 15).Value  ' O列: reject_reason

        Call NotifyConsecutiveFailures(consecutiveFailures, lastSignal, reason)
    End If
End Sub

Sub CheckHighErrorRate()
    '
    ' エラー頻発をチェック
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
            severity = ws.Cells(i, 3).Value

            If severity = "ERROR" Or severity = "CRITICAL" Then
                errorCount = errorCount + 1
            End If
        End If
    Next i

    ' 10回以上で通知
    If errorCount >= 10 Then
        Call NotifyHighErrorRate(errorCount, "1時間")
    End If
End Sub

Sub CheckAPIConnectionStatus()
    '
    ' API接続状態をチェック
    '
    On Error Resume Next

    Dim apiStatus As String
    apiStatus = GetSystemState("api_connection_status")

    If apiStatus = "Disconnected" Then
        ' API接続断を通知
        Dim fields As New Collection
        Dim field As Dictionary

        Set field = New Dictionary
        field("title") = "接続状態"
        field("value") = "切断"
        field("short") = True
        fields.Add field

        Set field = New Dictionary
        field("title") = "推奨対応"
        field("value") = "ネットワーク接続とサーバー状態を確認してください"
        field("short") = False
        fields.Add field

        Call SendSlackNotification("ERROR", "API接続断", fields, False)
    End If
End Sub

Sub CheckHeartbeatTimeout()
    '
    ' Heartbeat途絶をチェック
    '
    On Error Resume Next

    Dim lastHeartbeat As Date
    lastHeartbeat = GetSystemState("last_heartbeat_time")

    If IsEmpty(lastHeartbeat) Then Exit Sub

    Dim elapsedMinutes As Long
    elapsedMinutes = DateDiff("n", lastHeartbeat, Now)

    ' 10分以上経過で通知
    If elapsedMinutes >= 10 Then
        Dim fields As New Collection
        Dim field As Dictionary

        Set field = New Dictionary
        field("title") = "最終Heartbeat"
        field("value") = Format(lastHeartbeat, "YYYY-MM-DD HH:NN:SS")
        field("short") = True
        fields.Add field

        Set field = New Dictionary
        field("title") = "経過時間"
        field("value") = elapsedMinutes & "分"
        field("short") = True
        fields.Add field

        Set field = New Dictionary
        field("title") = "推奨対応"
        field("value") = "サーバーの稼働状態を確認してください"
        field("short") = False
        fields.Add field

        Call SendSlackNotification("ERROR", "Heartbeat途絶", fields, False)
    End If
End Sub
```

### 6.2 NotificationHistory シート

**シート構造**:

| 列 | 列名 | データ型 | 説明 |
|----|------|---------|------|
| A | level | TEXT | 通知レベル |
| B | title | TEXT | 通知タイトル |
| C | last_notify_time | DATETIME | 前回通知時刻 |
| D | notify_count | INTEGER | 通知回数 |

---

## 7. Server側実装

### 7.1 Slack通知（Python）

**relay_server/app/core/notification.py**:

```python
import requests
import json
from typing import Dict, List, Any, Optional
from datetime import datetime
import logging

logger = logging.getLogger(__name__)

class SlackNotifier:
    """Slack通知クラス"""

    def __init__(self, webhook_urls: Dict[str, str]):
        """
        Args:
            webhook_urls: レベル別のWebhook URL辞書
                例: {'INFO': 'https://...', 'WARNING': 'https://...'}
        """
        self.webhook_urls = webhook_urls

    def send(
        self,
        level: str,
        title: str,
        fields: List[Dict[str, Any]],
        mention_channel: bool = False
    ) -> bool:
        """
        Slack通知を送信

        Args:
            level: 通知レベル（INFO/WARNING/ERROR/CRITICAL）
            title: タイトル
            fields: フィールドのリスト
            mention_channel: @channel メンションするか

        Returns:
            送信成功: True、失敗: False
        """
        webhook_url = self.webhook_urls.get(level)
        if not webhook_url:
            logger.warning(f"Slack webhook URL not configured for level: {level}")
            return False

        payload = self._build_payload(level, title, fields, mention_channel)

        try:
            response = requests.post(
                webhook_url,
                data=json.dumps(payload),
                headers={'Content-Type': 'application/json'},
                timeout=10
            )

            if response.status_code == 200:
                logger.info(f"Slack notification sent: {title}")
                return True
            else:
                logger.error(f"Slack notification failed: HTTP {response.status_code}")
                return False

        except Exception as e:
            logger.error(f"Slack notification error: {e}")
            return False

    def _build_payload(
        self,
        level: str,
        title: str,
        fields: List[Dict[str, Any]],
        mention_channel: bool
    ) -> Dict[str, Any]:
        """Slackペイロードを構築"""

        colors = {
            'INFO': '#36a64f',
            'WARNING': 'warning',
            'ERROR': 'danger',
            'CRITICAL': '#FF0000'
        }

        icons = {
            'INFO': ':information_source:',
            'WARNING': ':warning:',
            'ERROR': ':x:',
            'CRITICAL': ':rotating_light:'
        }

        prefixes = {
            'INFO': 'ℹ️',
            'WARNING': '⚠️',
            'ERROR': '🚨',
            'CRITICAL': '🚨🚨🚨'
        }

        payload = {
            'username': 'Kabuto Auto Trader',
            'icon_emoji': icons.get(level, ':robot:'),
            'attachments': [{
                'color': colors.get(level, '#36a64f'),
                'title': f"{prefixes.get(level, '')} {title}",
                'fields': fields,
                'footer': 'Kabuto Auto Trader',
                'ts': int(datetime.now().timestamp())
            }]
        }

        if mention_channel:
            payload['text'] = '@channel'

        return payload


class EmailNotifier:
    """メール通知クラス"""

    def __init__(self, smtp_config: Dict[str, Any]):
        """
        Args:
            smtp_config: SMTP設定辞書
                例: {
                    'server': 'smtp.gmail.com',
                    'port': 587,
                    'use_tls': True,
                    'username': 'user@example.com',
                    'password': 'password',
                    'from': 'sender@example.com',
                    'to': 'recipient@example.com'
                }
        """
        self.smtp_config = smtp_config

    def send(
        self,
        level: str,
        title: str,
        fields: List[Dict[str, Any]]
    ) -> bool:
        """
        メール通知を送信

        Args:
            level: 通知レベル
            title: タイトル
            fields: フィールドのリスト

        Returns:
            送信成功: True、失敗: False
        """
        import smtplib
        from email.mime.text import MIMEText
        from email.mime.multipart import MIMEMultipart

        try:
            # メール作成
            msg = MIMEMultipart('alternative')
            msg['Subject'] = f"[Kabuto] {level.upper()} - {title}"
            msg['From'] = self.smtp_config['from']
            msg['To'] = self.smtp_config['to']

            # HTML本文
            html_body = self._build_html_body(level, title, fields)
            msg.attach(MIMEText(html_body, 'html'))

            # SMTP送信
            with smtplib.SMTP(
                self.smtp_config['server'],
                self.smtp_config['port']
            ) as server:
                if self.smtp_config.get('use_tls', True):
                    server.starttls()

                if self.smtp_config.get('username'):
                    server.login(
                        self.smtp_config['username'],
                        self.smtp_config['password']
                    )

                server.send_message(msg)

            logger.info(f"Email notification sent: {title}")
            return True

        except Exception as e:
            logger.error(f"Email notification error: {e}")
            return False

    def _build_html_body(
        self,
        level: str,
        title: str,
        fields: List[Dict[str, Any]]
    ) -> str:
        """HTML本文を構築"""

        level_classes = {
            'WARNING': 'warning',
            'ERROR': 'error',
            'CRITICAL': 'critical'
        }

        icons = {
            'WARNING': '⚠️',
            'ERROR': '🚨',
            'CRITICAL': '🚨🚨🚨'
        }

        fields_html = ''
        for field in fields:
            fields_html += f'''
            <div class="field">
                <div class="field-title">{field['title']}</div>
                <div class="field-value">{field['value'].replace(chr(10), '<br>')}</div>
            </div>
            '''

        html = f'''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body {{ font-family: Arial, sans-serif; }}
        .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
        .header {{ background-color: #f44336; color: white; padding: 20px; border-radius: 5px; }}
        .header.warning {{ background-color: #ff9800; }}
        .header.error {{ background-color: #f44336; }}
        .header.critical {{ background-color: #d32f2f; }}
        .content {{ padding: 20px; background-color: #f5f5f5; margin-top: 20px; border-radius: 5px; }}
        .field {{ margin-bottom: 15px; }}
        .field-title {{ font-weight: bold; color: #333; }}
        .field-value {{ color: #666; margin-top: 5px; }}
        .footer {{ margin-top: 20px; padding-top: 20px; border-top: 1px solid #ddd; color: #999; font-size: 12px; }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header {level_classes.get(level, 'error')}">
            <h1>{icons.get(level, '🚨')} {title}</h1>
        </div>
        <div class="content">
            {fields_html}
        </div>
        <div class="footer">
            <p>Kabuto Auto Trader</p>
            <p>発生時刻: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
        </div>
    </div>
</body>
</html>
        '''

        return html


class NotificationManager:
    """通知マネージャー"""

    def __init__(self, slack_notifier: Optional[SlackNotifier] = None,
                 email_notifier: Optional[EmailNotifier] = None):
        self.slack = slack_notifier
        self.email = email_notifier

    def notify(
        self,
        level: str,
        title: str,
        fields: List[Dict[str, Any]],
        mention_channel: bool = False
    ):
        """
        レベルに応じて通知を送信

        Args:
            level: 通知レベル
            title: タイトル
            fields: フィールドのリスト
            mention_channel: @channel メンションするか
        """

        # Slack通知
        if self.slack:
            self.slack.send(level, title, fields, mention_channel)

        # メール通知（ERROR以上）
        if self.email and level in ['ERROR', 'CRITICAL']:
            self.email.send(level, title, fields)

    def notify_signal_generation_failed(self, error: Exception):
        """信号生成失敗を通知"""
        fields = [
            {'title': 'エラー種別', 'value': type(error).__name__, 'short': True},
            {'title': 'エラーメッセージ', 'value': str(error), 'short': True}
        ]
        self.notify('ERROR', '信号生成失敗', fields)

    def notify_system_started(self):
        """システム起動を通知"""
        fields = [
            {'title': '起動時刻', 'value': datetime.now().strftime('%Y-%m-%d %H:%M:%S'), 'short': True}
        ]
        self.notify('INFO', 'システム起動', fields)

    def notify_system_stopped(self, reason: str):
        """システム停止を通知"""
        fields = [
            {'title': '停止理由', 'value': reason, 'short': False},
            {'title': '停止時刻', 'value': datetime.now().strftime('%Y-%m-%d %H:%M:%S'), 'short': True}
        ]
        self.notify('ERROR', 'システム停止', fields)

    def notify_heartbeat_missed(self, client_id: str, last_heartbeat: datetime):
        """Heartbeat途絶を通知"""
        elapsed = (datetime.now() - last_heartbeat).total_seconds() / 60

        fields = [
            {'title': 'クライアントID', 'value': client_id, 'short': True},
            {'title': '最終Heartbeat', 'value': last_heartbeat.strftime('%Y-%m-%d %H:%M:%S'), 'short': True},
            {'title': '経過時間', 'value': f'{int(elapsed)}分', 'short': True}
        ]
        self.notify('ERROR', 'Heartbeat途絶', fields)
```

### 7.2 設定ファイル

**relay_server/.env**:

```bash
# Slack設定
SLACK_WEBHOOK_INFO=https://hooks.slack.com/services/xxx/yyy/zzz
SLACK_WEBHOOK_WARNING=https://hooks.slack.com/services/xxx/yyy/zzz
SLACK_WEBHOOK_ERROR=https://hooks.slack.com/services/xxx/yyy/zzz
SLACK_WEBHOOK_CRITICAL=https://hooks.slack.com/services/xxx/yyy/zzz

# SMTP設定
SMTP_SERVER=smtp.gmail.com
SMTP_PORT=587
SMTP_USE_TLS=true
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password
NOTIFICATION_EMAIL_FROM=kabuto@example.com
NOTIFICATION_EMAIL_TO=alert@example.com
```

### 7.3 使用例

```python
from app.core.notification import SlackNotifier, EmailNotifier, NotificationManager
import os

# 初期化
slack = SlackNotifier({
    'INFO': os.getenv('SLACK_WEBHOOK_INFO'),
    'WARNING': os.getenv('SLACK_WEBHOOK_WARNING'),
    'ERROR': os.getenv('SLACK_WEBHOOK_ERROR'),
    'CRITICAL': os.getenv('SLACK_WEBHOOK_CRITICAL')
})

email = EmailNotifier({
    'server': os.getenv('SMTP_SERVER'),
    'port': int(os.getenv('SMTP_PORT', 587)),
    'use_tls': os.getenv('SMTP_USE_TLS', 'true').lower() == 'true',
    'username': os.getenv('SMTP_USERNAME'),
    'password': os.getenv('SMTP_PASSWORD'),
    'from': os.getenv('NOTIFICATION_EMAIL_FROM'),
    'to': os.getenv('NOTIFICATION_EMAIL_TO')
})

notifier = NotificationManager(slack, email)

# システム起動通知
notifier.notify_system_started()

# エラー通知
try:
    # 何か処理
    pass
except Exception as e:
    notifier.notify_signal_generation_failed(e)
```

---

## 8. 通知テンプレート

### 8.1 発注失敗

**トリガー**: 注文が拒否された時

**レベル**: WARNING

**フィールド**:
- 銘柄
- 売買区分
- 数量
- 失敗理由
- Signal ID
- 発生時刻

### 8.2 連続発注失敗

**トリガー**: 3回連続で注文が拒否された時

**レベル**: ERROR

**フィールド**:
- 失敗回数
- 直近の失敗
- 共通失敗理由
- 推奨対応
- 発生時刻

### 8.3 Kill Switch発動

**トリガー**: Kill Switchが発動した時

**レベル**: CRITICAL

**フィールド**:
- 発動理由
- 本日の取引成績
- システム状態
- 必要な対応
- 発生時刻

### 8.4 システム停止

**トリガー**: システムが停止した時

**レベル**: ERROR

**フィールド**:
- 停止理由
- 停止時刻
- 稼働時間
- 本日の取引回数

### 8.5 エラー頻発

**トリガー**: 1時間に10回以上エラーが発生した時

**レベル**: ERROR

**フィールド**:
- エラー回数
- 閾値
- 推奨対応
- 発生時刻

---

## 9. 設定管理

### 9.1 Excel Configシート

**通知設定項目**:

| 設定キー | 説明 | デフォルト値 |
|---------|------|------------|
| notification_enabled | 通知機能有効化 | TRUE |
| slack_enabled | Slack通知有効化 | TRUE |
| email_enabled | メール通知有効化 | TRUE |
| slack_webhook_info | INFO用Webhook | |
| slack_webhook_warnings | WARNING用Webhook | |
| slack_webhook_alerts | ERROR用Webhook | |
| slack_webhook_critical | CRITICAL用Webhook | |
| smtp_server | SMTPサーバー | smtp.gmail.com |
| smtp_port | SMTPポート | 587 |
| smtp_use_tls | TLS使用 | TRUE |
| smtp_username | SMTP認証ユーザー名 | |
| smtp_password | SMTP認証パスワード | |
| notification_email_to | 通知先メールアドレス | |
| notification_email_from | 送信元メールアドレス | |

### 9.2 通知頻度制限設定

| 設定キー | 説明 | デフォルト値 |
|---------|------|------------|
| notify_interval_warning | WARNING再通知間隔（分） | 30 |
| notify_interval_error | ERROR再通知間隔（分） | 15 |
| notify_interval_critical | CRITICAL再通知間隔（分） | 0（制限なし） |

---

## まとめ

### 実装必要項目

#### Excel側
1. Module_Notification.bas の作成（15関数）
2. NotificationHistory シートの追加
3. Module_Main.bas に異常検知ロジック追加（5関数）
4. Configシートに通知設定追加

#### Server側
1. relay_server/app/core/notification.py の作成
2. .env ファイルに通知設定追加
3. 各エンドポイントに通知ロジック統合

### 通知フロー

```
異常検知
  ↓
レベル判定
  ↓
頻度制限チェック
  ↓
┌─────────┬─────────┐
│  Slack  │  Mail   │
│ 通知送信 │ 通知送信 │
└─────────┴─────────┘
  ↓
通知履歴記録
```

### 主要な異常検知

- ✅ 発注失敗（単発・連続）
- ✅ エラー頻発
- ✅ Kill Switch発動
- ✅ システム停止
- ✅ API接続断
- ✅ Heartbeat途絶

---

**設計完了日**: 2025-12-27
