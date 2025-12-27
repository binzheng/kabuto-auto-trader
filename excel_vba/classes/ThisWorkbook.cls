VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
END
Attribute VB_Name = "ThisWorkbook"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = True
'
' Kabuto Auto Trader - ThisWorkbook Class
' ブックイベントハンドラ
'

Option Explicit

' ========================================
' ブック起動時
' ========================================
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

' ========================================
' ブック終了時
' ========================================
Private Sub Workbook_BeforeClose(Cancel As Boolean)
    On Error Resume Next

    Debug.Print "========================================="
    Debug.Print "Kabuto Auto Trader - Closing Workbook"
    Debug.Print "========================================="

    ' 自動売買停止
    If isAutoTradingRunning Then
        Call StopAutoTrading
        Debug.Print "Auto trading stopped before closing workbook"
    End If

    ' 状態を保存
    Debug.Print "Workbook closed at: " & Now
End Sub

' ========================================
' ブック保存時
' ========================================
Private Sub Workbook_BeforeSave(ByVal SaveAsUI As Boolean, Cancel As Boolean)
    On Error Resume Next

    Debug.Print "Workbook saving..."

    ' ログのクリーンアップ（保持期間超過分）
    Call CleanupOldLogs

    Debug.Print "Workbook saved at: " & Now
End Sub

' ========================================
' シート変更時
' ========================================
Private Sub Workbook_SheetChange(ByVal Sh As Object, ByVal Target As Range)
    ' 必要に応じて実装
End Sub

' ========================================
' シート計算完了時
' ========================================
Private Sub Workbook_SheetCalculate(ByVal Sh As Object)
    ' 必要に応じて実装
End Sub
