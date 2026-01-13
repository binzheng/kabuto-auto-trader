Attribute VB_Name = "Module_Logger_Simple"
'
' Kabuto Auto Trader - Simple Logger Module
' タイムスタンプ付きログ出力
'

Option Explicit

' ========================================
' デバッグログ出力（タイムスタンプ付き）
' ========================================
Sub LogDebug(message As String)
    '
    ' タイムスタンプ付きでデバッグウィンドウに出力
    '
    Dim timestamp As String
    timestamp = Format(Now, "yyyy-mm-dd HH:nn:ss")

    Debug.Print "[" & timestamp & "] " & message
    Call LogToFile(message, "DEBUG")
End Sub

' ========================================
' 情報ログ出力
' ========================================
Sub LogInfo(message As String)
    '
    ' INFO レベルのログ出力
    '
    Dim timestamp As String
    timestamp = Format(Now, "yyyy-mm-dd HH:nn:ss")

    Debug.Print "[" & timestamp & "] [INFO] " & message
End Sub

' ========================================
' 警告ログ出力
' ========================================
Sub LogWarning(message As String)
    '
    ' WARNING レベルのログ出力
    '
    Dim timestamp As String
    timestamp = Format(Now, "yyyy-mm-dd HH:nn:ss")

    Debug.Print "[" & timestamp & "] [WARNING] " & message
End Sub

' ========================================
' エラーログ出力
' ========================================
Sub LogError(message As String)
    '
    ' ERROR レベルのログ出力
    '
    Dim timestamp As String
    timestamp = Format(Now, "yyyy-mm-dd HH:nn:ss")

    Debug.Print "[" & timestamp & "] [ERROR] " & message
End Sub

' ========================================
' 成功ログ出力
' ========================================
Sub LogSuccess(message As String)
    '
    ' SUCCESS レベルのログ出力
    '
    Dim timestamp As String
    timestamp = Format(Now, "yyyy-mm-dd HH:nn:ss")

    Debug.Print "[" & timestamp & "] [SUCCESS] " & message
End Sub

' ========================================
' セクション開始ログ
' ========================================
Sub LogSectionStart(sectionName As String)
    '
    ' セクション開始の区切り線付きログ
    '
    Dim timestamp As String
    timestamp = Format(Now, "yyyy-mm-dd HH:nn:ss")

    Debug.Print "[" & timestamp & "] " & String(50, "=")
    Debug.Print "[" & timestamp & "] " & sectionName
    Debug.Print "[" & timestamp & "] " & String(50, "=")
End Sub

' ========================================
' セクション終了ログ
' ========================================
Sub LogSectionEnd()
    '
    ' セクション終了の区切り線
    '
    Dim timestamp As String
    timestamp = Format(Now, "yyyy-mm-dd HH:nn:ss")

    Debug.Print "[" & timestamp & "] " & String(50, "-")
End Sub

' ========================================
' ファイルログ出力（オプション）
' ========================================
Sub LogToFile(message As String, Optional logLevel As String = "INFO")
    '
    ' ファイルにログを出力（オプション機能）
    '
    On Error Resume Next

    Dim timestamp As String
    timestamp = Format(Now, "yyyy-mm-dd HH:nn:ss")

    Dim logFilePath As String
    logFilePath = ThisWorkbook.Path & "\kabuto_vba_" & Format(Now, "yyyymmdd") & ".log"

    Dim fileNum As Integer
    fileNum = FreeFile

    Open logFilePath For Append As #fileNum
    Print #fileNum, "[" & timestamp & "] [" & logLevel & "] " & message
    Close #fileNum
End Sub
