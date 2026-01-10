Attribute VB_Name = "Module_Config_Simple"
'
' Kabuto Auto Trader - Simplified Config Module
' 簡略化された設定管理
'
' 必要最小限の設定のみ:
' - API_BASE_URL
' - API_KEY
' - CLIENT_ID
'

Option Explicit

' ========================================
' 設定取得
' ========================================
Function GetConfig(key As String) As String
    '
    ' Configシートから設定値を取得
    '
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
' 設定設定
' ========================================
Sub SetConfig(key As String, value As String)
    '
    ' Configシートに設定値を保存
    '
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("Config")

    Dim foundCell As Range
    Set foundCell = ws.Columns(1).Find(key, LookIn:=xlValues, LookAt:=xlWhole)

    If Not foundCell Is Nothing Then
        ' 更新
        ws.Cells(foundCell.Row, 2).Value = value
    Else
        ' 新規追加
        Dim nextRow As Long
        nextRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1
        ws.Cells(nextRow, 1).Value = key
        ws.Cells(nextRow, 2).Value = value
    End If
End Sub
