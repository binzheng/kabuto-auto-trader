Attribute VB_Name = "Module_Config"
'
' Kabuto Auto Trader - Config Module
' 設定管理とユーティリティ関数
'

Option Explicit

' ========================================
' 設定値取得
' Configシートから設定を読み込み
' ========================================
Function GetConfig(key As String) As String
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("Config")

    Dim foundCell As Range
    Set foundCell = ws.Columns(1).Find(key, LookIn:=xlValues, LookAt:=xlWhole)

    If Not foundCell Is Nothing Then
        GetConfig = ws.Cells(foundCell.Row, 2).Value
    Else
        GetConfig = ""
    End If
End Function

' ========================================
' システム状態取得
' SystemStateシートから状態を読み込み
' ========================================
Function GetSystemState(key As String) As Variant
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("SystemState")

    Select Case key
        Case "system_status"
            GetSystemState = ws.Range("B1").Value
        Case "last_update"
            GetSystemState = ws.Range("B2").Value
        Case "next_poll_time"
            GetSystemState = ws.Range("B3").Value
        Case "api_connection_status"
            GetSystemState = ws.Range("B4").Value
        Case "rss_connection_status"
            GetSystemState = ws.Range("B5").Value
        Case "market_session"
            GetSystemState = ws.Range("B6").Value
        Case "daily_entry_count"
            GetSystemState = ws.Range("B7").Value
        Case "daily_trade_count"
            GetSystemState = ws.Range("B8").Value
        Case "daily_error_count"
            GetSystemState = ws.Range("B9").Value
        Case "total_position_value"
            GetSystemState = ws.Range("B10").Value
        Case "last_signal_time"
            GetSystemState = ws.Range("B11").Value
        Case "workbook_start_time"
            GetSystemState = ws.Range("B12").Value
        Case Else
            GetSystemState = ""
    End Select
End Function

' ========================================
' システム状態設定
' SystemStateシートに状態を書き込み
' ========================================
Sub SetSystemState(key As String, value As Variant)
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("SystemState")

    Select Case key
        Case "system_status"
            ws.Range("B1").Value = value
        Case "last_update"
            ws.Range("B2").Value = value
        Case "next_poll_time"
            ws.Range("B3").Value = value
        Case "api_connection_status"
            ws.Range("B4").Value = value
        Case "rss_connection_status"
            ws.Range("B5").Value = value
        Case "market_session"
            ws.Range("B6").Value = value
        Case "daily_entry_count"
            ws.Range("B7").Value = value
        Case "daily_trade_count"
            ws.Range("B8").Value = value
        Case "daily_error_count"
            ws.Range("B9").Value = value
        Case "total_position_value"
            ws.Range("B10").Value = value
        Case "last_signal_time"
            ws.Range("B11").Value = value
        Case "workbook_start_time"
            ws.Range("B12").Value = value
    End Select
End Sub

' ========================================
' 市場営業日チェック
' ========================================
Function IsTradingDay(targetDate As Date) As Boolean
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("MarketCalendar")

    Dim foundCell As Range
    Set foundCell = ws.Columns(1).Find(targetDate, LookIn:=xlValues, LookAt:=xlWhole)

    If Not foundCell Is Nothing Then
        IsTradingDay = ws.Cells(foundCell.Row, 3).Value  ' C列: is_trading_day
    Else
        ' データがない場合は平日を取引日とみなす
        Dim dayOfWeek As Integer
        dayOfWeek = Weekday(targetDate)
        IsTradingDay = (dayOfWeek <> vbSaturday And dayOfWeek <> vbSunday)
    End If
End Function

' ========================================
' 市場オープンチェック
' ========================================
Function IsMarketOpen() As Boolean
    On Error Resume Next

    ' 取引日チェック
    If Not IsTradingDay(Date) Then
        IsMarketOpen = False
        Exit Function
    End If

    Dim currentTime As Date
    currentTime = Time

    ' 前場: 9:00-11:30
    If currentTime >= TimeValue("09:00:00") And currentTime <= TimeValue("11:30:00") Then
        IsMarketOpen = True
        Exit Function
    End If

    ' 後場: 12:30-15:00
    If currentTime >= TimeValue("12:30:00") And currentTime <= TimeValue("15:00:00") Then
        IsMarketOpen = True
        Exit Function
    End If

    IsMarketOpen = False
End Function

' ========================================
' 安全取引時間チェック
' ========================================
Function IsSafeTradingWindow() As Boolean
    On Error Resume Next

    If Not IsTradingDay(Date) Then
        IsSafeTradingWindow = False
        Exit Function
    End If

    Dim currentTime As Date
    currentTime = Time

    ' 前場安全時間: 9:30-11:20
    If currentTime >= TimeValue("09:30:00") And currentTime <= TimeValue("11:20:00") Then
        IsSafeTradingWindow = True
        Exit Function
    End If

    ' 後場安全時間: 13:00-14:30
    If currentTime >= TimeValue("13:00:00") And currentTime <= TimeValue("14:30:00") Then
        IsSafeTradingWindow = True
        Exit Function
    End If

    IsSafeTradingWindow = False
End Function

' ========================================
' ブラックリストチェック
' ========================================
Function IsTickerBlacklisted(ticker As String) As Boolean
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("BlacklistTickers")

    Dim foundCell As Range
    Set foundCell = ws.Columns(1).Find(ticker, LookIn:=xlValues, LookAt:=xlWhole)

    If foundCell Is Nothing Then
        IsTickerBlacklisted = False
        Exit Function
    End If

    ' 有効期限チェック
    Dim expiryDate As Variant
    expiryDate = ws.Cells(foundCell.Row, 5).Value  ' E列: expiry_date

    If IsEmpty(expiryDate) Then
        ' 永久ブラックリスト
        IsTickerBlacklisted = True
    ElseIf expiryDate >= Date Then
        ' 有効期限内
        IsTickerBlacklisted = True
    Else
        ' 有効期限切れ
        IsTickerBlacklisted = False
    End If
End Function

' ========================================
' ブラックリスト追加
' ========================================
Sub AddToBlacklist(ticker As String, reason As String, Optional expiryDays As Integer = 0)
    On Error Resume Next

    ' 重複チェック
    If IsTickerBlacklisted(ticker) Then Exit Sub

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("BlacklistTickers")

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    ws.Cells(lastRow, 1).Value = ticker
    ws.Cells(lastRow, 2).Value = GetTickerName(ticker)
    ws.Cells(lastRow, 3).Value = reason
    ws.Cells(lastRow, 4).Value = Date

    If expiryDays > 0 Then
        ws.Cells(lastRow, 5).Value = DateAdd("d", expiryDays, Date)
    End If

    ws.Cells(lastRow, 6).Value = "auto"

    Debug.Print "Added to blacklist: " & ticker
End Sub

' ========================================
' クールダウン期間チェック
' ========================================
Function IsInCooldownPeriod(ticker As String, action As String) As Boolean
    '
    ' クールダウン期間中かチェック
    ' 買い: 30分、売り: 15分
    '
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("OrderHistory")

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row

    ' 最新の注文を検索（逆順でループ）
    Dim i As Long
    For i = lastRow To 2 Step -1
        Dim orderTicker As String
        Dim orderAction As String
        Dim orderTime As Date

        orderTicker = ws.Cells(i, 4).Value  ' D列: ticker
        orderAction = ws.Cells(i, 5).Value  ' E列: action
        orderTime = ws.Cells(i, 2).Value    ' B列: order_time

        ' 同一銘柄・同一アクションの注文を検索
        If orderTicker = ticker And orderAction = action Then
            ' クールダウン期間を設定
            Dim cooldownMinutes As Long
            If action = "buy" Then
                cooldownMinutes = 30  ' 買い: 30分
            Else
                cooldownMinutes = 15  ' 売り: 15分
            End If

            ' 経過時間を計算
            Dim elapsedMinutes As Long
            elapsedMinutes = DateDiff("n", orderTime, Now)

            If elapsedMinutes < cooldownMinutes Then
                Debug.Print "Cooldown active: " & ticker & " " & action & " (elapsed: " & elapsedMinutes & " min / required: " & cooldownMinutes & " min)"
                IsInCooldownPeriod = True
                Exit Function
            Else
                Debug.Print "Cooldown passed: " & ticker & " " & action & " (elapsed: " & elapsedMinutes & " min)"
                IsInCooldownPeriod = False
                Exit Function
            End If
        End If
    Next i

    ' 該当する注文が見つからない場合はクールダウンなし
    IsInCooldownPeriod = False
End Function

' ========================================
' 市場セッション状態取得
' ========================================
Function GetMarketSession() As String
    '
    ' 現在の市場セッション状態を取得
    '
    ' 戻り値:
    ' "pre-market"       - 8:00-9:00
    ' "morning-auction"  - 9:00-9:30
    ' "morning-trading"  - 9:30-11:30
    ' "lunch-break"      - 11:30-12:30
    ' "afternoon-auction" - 12:30-13:00
    ' "afternoon-trading" - 13:00-15:00
    ' "post-market"      - 15:00-18:00
    ' "closed"           - その他
    '
    On Error Resume Next

    ' 営業日チェック
    If Not IsTradingDay(Date) Then
        GetMarketSession = "closed"
        Exit Function
    End If

    Dim currentTime As Date
    currentTime = Time

    ' セッション判定
    If currentTime < TimeValue("08:00:00") Then
        GetMarketSession = "closed"
    ElseIf currentTime >= TimeValue("08:00:00") And currentTime < TimeValue("09:00:00") Then
        GetMarketSession = "pre-market"
    ElseIf currentTime >= TimeValue("09:00:00") And currentTime < TimeValue("09:30:00") Then
        GetMarketSession = "morning-auction"
    ElseIf currentTime >= TimeValue("09:30:00") And currentTime < TimeValue("11:30:00") Then
        GetMarketSession = "morning-trading"
    ElseIf currentTime >= TimeValue("11:30:00") And currentTime < TimeValue("12:30:00") Then
        GetMarketSession = "lunch-break"
    ElseIf currentTime >= TimeValue("12:30:00") And currentTime < TimeValue("13:00:00") Then
        GetMarketSession = "afternoon-auction"
    ElseIf currentTime >= TimeValue("13:00:00") And currentTime < TimeValue("15:00:00") Then
        GetMarketSession = "afternoon-trading"
    ElseIf currentTime >= TimeValue("15:00:00") And currentTime < TimeValue("18:00:00") Then
        GetMarketSession = "post-market"
    Else
        GetMarketSession = "closed"
    End If
End Function
