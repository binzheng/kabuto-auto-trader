Attribute VB_Name = "Module_Main"
'
' Kabuto Auto Trader - Main Module
' メインルーチン、自動実行制御
'

Option Explicit

' グローバル変数
Public nextPollingTime As Date
Public isAutoTradingRunning As Boolean

' ========================================
' 自動売買開始
' ========================================
Sub StartAutoTrading()
    If isAutoTradingRunning Then
        Debug.Print "Auto trading is already running"
        Exit Sub
    End If

    isAutoTradingRunning = True
    Call SetSystemState("system_status", "Running")
    Call SetSystemState("workbook_start_time", Now)

    Debug.Print "========================================="
    Debug.Print "Kabuto Auto Trading Started"
    Debug.Print "Time: " & Now
    Debug.Print "========================================="

    ' ダッシュボードをアクティブ化
    ThisWorkbook.Sheets("Dashboard").Activate

    ' 初回ポーリング実行
    Call PollAndProcessSignals
End Sub

' ========================================
' 自動売買一時停止
' ========================================
Sub PauseAutoTrading()
    isAutoTradingRunning = False
    Call SetSystemState("system_status", "Paused")

    On Error Resume Next
    Application.OnTime nextPollingTime, "PollAndProcessSignals", , False
    On Error GoTo 0

    Debug.Print "Auto trading paused"
    MsgBox "自動売買を一時停止しました", vbInformation, "Kabuto Auto Trader"
End Sub

' ========================================
' 自動売買停止
' ========================================
Sub StopAutoTrading()
    isAutoTradingRunning = False
    Call SetSystemState("system_status", "Stopped")

    On Error Resume Next
    Application.OnTime nextPollingTime, "PollAndProcessSignals", , False
    On Error GoTo 0

    Debug.Print "Auto trading stopped"
    MsgBox "自動売買を停止しました", vbInformation, "Kabuto Auto Trader"
End Sub

' ========================================
' メインポーリングルーチン（5秒毎に実行）
' ========================================
Sub PollAndProcessSignals()
    On Error GoTo ErrorHandler

    ' システム状態チェック
    If Not isAutoTradingRunning Then Exit Sub

    ' 最終更新時刻
    Call SetSystemState("last_update", Now)
    Call UpdateDashboardTime

    ' 市場時間チェック
    If GetConfig("ENABLE_MARKET_HOURS_CHECK") = "TRUE" Then
        If Not IsMarketOpen() Then
            Debug.Print "Market is closed - skipping poll"
            GoTo ScheduleNext
        End If
    End If

    ' API接続チェック
    If Not CheckAPIConnection() Then
        Call SetSystemState("api_connection_status", "Error")
        Call LogError("API_ERROR", "PollAndProcessSignals", "API connection failed", "")
        GoTo ScheduleNext
    Else
        Call SetSystemState("api_connection_status", "OK")
    End If

    ' サーバーからシグナル取得
    Dim signals As Collection
    Set signals = FetchPendingSignals()

    If Not signals Is Nothing Then
        If signals.Count > 0 Then
            Debug.Print "Fetched " & signals.Count & " signals"
            Call SetSystemState("last_signal_time", Now)

            ' 各シグナルをキューに追加
            Dim signal As Object
            For Each signal In signals
                Call AddSignalToQueue(signal)
            Next signal
        End If
    End If

    ' キューからシグナルを処理
    Call ProcessNextSignal

    ' ポジションの現在価格を更新（30秒毎）
    Static lastPriceUpdate As Date
    If DateDiff("s", lastPriceUpdate, Now) >= 30 Or lastPriceUpdate = 0 Then
        Call UpdateCurrentPrices
        lastPriceUpdate = Now
    End If

    ' ダッシュボード更新
    Call UpdateDashboard

    ' ハートビート送信（60秒毎）
    Static lastHeartbeat As Date
    If DateDiff("s", lastHeartbeat, Now) >= 60 Or lastHeartbeat = 0 Then
        Call SendHeartbeat
        lastHeartbeat = Now
    End If

ScheduleNext:
    ' 次回実行スケジュール
    Dim interval As Integer
    interval = CInt(GetConfig("POLLING_INTERVAL_SEC"))
    If interval = 0 Then interval = 5

    nextPollingTime = Now + TimeValue("00:00:" & Format(interval, "00"))
    Call SetSystemState("next_poll_time", nextPollingTime)

    Application.OnTime nextPollingTime, "PollAndProcessSignals"

    Exit Sub

ErrorHandler:
    Debug.Print "Error in PollAndProcessSignals: " & Err.Description
    Call LogError("SYSTEM_ERROR", "PollAndProcessSignals", Err.Description, "", "CRITICAL")

    ' エラーでも継続（10秒後に再試行）
    nextPollingTime = Now + TimeValue("00:00:10")
    Application.OnTime nextPollingTime, "PollAndProcessSignals"
End Sub

' ========================================
' ダッシュボード更新
' ========================================
Sub UpdateDashboard()
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("Dashboard")

    ' 最新シグナル表示を更新
    Call UpdateDashboardSignals

    ' 各種カウント更新はセル数式で自動計算
    ' 手動更新不要

End Sub

Sub UpdateDashboardTime()
    On Error Resume Next
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("Dashboard")

    ' 最終更新時刻を表示（例: B3セル）
    ws.Range("B3").Value = Now
End Sub

Sub UpdateDashboardSignals()
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("Dashboard")

    ' OrderHistoryから最新5件取得して表示（B26:G30）
    Dim wsOrder As Worksheet
    Set wsOrder = ThisWorkbook.Sheets("OrderHistory")

    Dim lastRow As Long
    lastRow = wsOrder.Cells(wsOrder.Rows.Count, 1).End(xlUp).Row

    If lastRow < 2 Then Exit Sub

    ' 最新5件表示
    Dim startRow As Long
    startRow = Application.Max(2, lastRow - 4)

    Dim i As Long
    Dim targetRow As Long
    targetRow = 26

    ' データをクリア
    ws.Range("B26:G30").ClearContents

    ' 最新データから降順で表示
    For i = lastRow To startRow Step -1
        ws.Cells(targetRow, 2).Value = wsOrder.Cells(i, 2).Value  ' 時刻
        ws.Cells(targetRow, 3).Value = wsOrder.Cells(i, 5).Value  ' 銘柄
        ws.Cells(targetRow, 4).Value = wsOrder.Cells(i, 4).Value  ' 動作
        ws.Cells(targetRow, 5).Value = wsOrder.Cells(i, 6).Value  ' 数量
        ws.Cells(targetRow, 6).Value = wsOrder.Cells(i, 11).Value ' 価格
        ws.Cells(targetRow, 7).Value = wsOrder.Cells(i, 10).Value ' 状態
        targetRow = targetRow + 1
    Next i
End Sub

' ========================================
' 再読込（設定リロード）
' ========================================
Sub ReloadConfiguration()
    MsgBox "設定を再読込しました", vbInformation, "Kabuto Auto Trader"
    Debug.Print "Configuration reloaded"
End Sub

' ========================================
' レポート生成
' ========================================
Sub GenerateDailyReport()
    MsgBox "本日のレポートを生成します（未実装）", vbInformation, "Kabuto Auto Trader"
    ' TODO: 日次レポート生成ロジック
End Sub
