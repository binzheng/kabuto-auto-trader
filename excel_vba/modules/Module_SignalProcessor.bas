Attribute VB_Name = "Module_SignalProcessor"
'
' Kabuto Auto Trader - Signal Processor Module
' シグナル処理ロジック
'

Option Explicit

' ========================================
' シグナルをキューに追加
' ========================================
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

' ========================================
' シグナルがキューに存在するかチェック
' ========================================
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

' ========================================
' 次のシグナルを処理
' ========================================
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

            ' 発注処理
            Dim orderId As String
            orderId = ExecuteOrder(signal)

            If orderId <> "" Then
                ' 成功 - OrderHistory記録
                Dim internalId As String
                internalId = RecordOrder(signal, orderId, "submitted")

                ' キュー更新
                ws.Cells(i, 11).Value = "completed"
                ws.Cells(i, 12).Value = Now

                ' 約定ポーリング開始（別途定期実行）
                ' PollOrderStatus は別のタイマーで定期実行

            Else
                ' 失敗
                ws.Cells(i, 11).Value = "error"
                ws.Cells(i, 13).Value = "Order execution failed"
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

' ========================================
' 完了済みシグナルをクリーンアップ
' ========================================
Sub CleanupCompletedSignals()
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("SignalQueue")

    Dim i As Long
    For i = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row To 2 Step -1
        If ws.Cells(i, 11).Value = "completed" Then
            Dim processedAt As Date
            processedAt = ws.Cells(i, 12).Value

            If DateDiff("h", processedAt, Now) >= 1 Then
                ws.Rows(i).Delete
                Debug.Print "Deleted old signal from queue"
            End If
        End If
    Next i
End Sub

' ========================================
' ローカルログで重複チェック
' ========================================
Function IsAlreadyExecuted(signalId As String) As Boolean
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("ExecutionLog")

    Dim foundCell As Range
    Set foundCell = ws.Columns(3).Find(signalId, LookIn:=xlValues, LookAt:=xlWhole)

    IsAlreadyExecuted = Not foundCell Is Nothing
End Function
