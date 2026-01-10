Attribute VB_Name = "Module_API_Simple"
'
' Kabuto Auto Trader - Simplified API Module
' Relay ServerとのAPI通信（最小限）
'
' エンドポイント:
' - GET /api/signals/pending (検証済みシグナル取得)
' - POST /api/signals/{signal_id}/ack (取得確認)
' - POST /api/signals/{signal_id}/executed (実行報告)
' - POST /api/signals/{signal_id}/failed (失敗報告)
'

Option Explicit

' ========================================
' 設定
' ========================================
Private Const API_BASE_URL As String = "http://localhost:5000"
Private Const API_KEY As String = "your_api_key_here"
Private Const CLIENT_ID As String = "excel_vba_01"

' ========================================
' 検証済みシグナル取得
' ========================================
Function API_GetPendingSignals() As Collection
    '
    ' Relay Serverから検証済みシグナルを取得
    '
    ' 重要: このエンドポイントから返されるシグナルは
    ' Relay Serverで5段階セーフティ検証済み
    '
    On Error GoTo ErrorHandler

    Dim http As Object
    Set http = CreateObject("MSXML2.XMLHTTP")

    Dim url As String
    url = API_BASE_URL & "/api/signals/pending"

    http.Open "GET", url, False
    http.setRequestHeader "Authorization", "Bearer " & API_KEY
    http.setRequestHeader "Content-Type", "application/json"
    http.Send

    ' 204 No Content = シグナルなし
    If http.Status = 204 Then
        Set API_GetPendingSignals = Nothing
        Exit Function
    End If

    ' 200 OK = シグナルあり
    If http.Status = 200 Then
        Dim response As Dictionary
        Set response = JsonConverter.ParseJson(http.responseText)

        If response("count") > 0 Then
            Set API_GetPendingSignals = response("signals")
        Else
            Set API_GetPendingSignals = Nothing
        End If
    Else
        Debug.Print "API Error: GET /signals/pending returned " & http.Status
        Set API_GetPendingSignals = Nothing
    End If

    Exit Function

ErrorHandler:
    Debug.Print "Error in API_GetPendingSignals: " & Err.Description
    Set API_GetPendingSignals = Nothing
End Function

' ========================================
' シグナル取得確認（ACK）
' ========================================
Sub API_AcknowledgeSignal(signalId As String, checksum As String)
    '
    ' シグナル取得を確認
    '
    On Error Resume Next

    Dim http As Object
    Set http = CreateObject("MSXML2.XMLHTTP")

    Dim url As String
    url = API_BASE_URL & "/api/signals/" & signalId & "/ack"

    ' リクエストボディ構築
    Dim body As String
    body = "{""client_id"": """ & CLIENT_ID & """, ""checksum"": """ & checksum & """}"

    http.Open "POST", url, False
    http.setRequestHeader "Authorization", "Bearer " & API_KEY
    http.setRequestHeader "Content-Type", "application/json"
    http.Send body

    If http.Status = 200 Then
        Call LogDebug("ACK sent for signal: " & signalId)
    Else
        Call LogError("ACK failed for signal " & signalId & ": HTTP " & http.Status)
    End If
End Sub

' ========================================
' 実行報告
' ========================================
Sub API_ReportExecution(signalId As String, orderId As String, executionPrice As Double, executionQuantity As Long)
    '
    ' 注文実行成功を報告
    '
    On Error Resume Next

    Dim http As Object
    Set http = CreateObject("MSXML2.XMLHTTP")

    Dim url As String
    url = API_BASE_URL & "/api/signals/" & signalId & "/executed"

    ' リクエストボディ構築
    Dim body As String
    body = "{" & _
           """order_id"": """ & orderId & """," & _
           """execution_price"": " & executionPrice & "," & _
           """execution_quantity"": " & executionQuantity & "," & _
           """executed_at"": """ & Format(Now, "yyyy-mm-ddTHH:nn:ss") & """" & _
           "}"

    http.Open "POST", url, False
    http.setRequestHeader "Authorization", "Bearer " & API_KEY
    http.setRequestHeader "Content-Type", "application/json"
    http.Send body

    If http.Status = 200 Then
        Call LogDebug("Execution reported for signal: " & signalId)
    Else
        Call LogError("Execution report failed for signal " & signalId & ": HTTP " & http.Status)
    End If
End Sub

' ========================================
' 失敗報告
' ========================================
Sub API_ReportFailure(signalId As String, errorMessage As String)
    '
    ' 注文実行失敗を報告
    '
    On Error Resume Next

    Dim http As Object
    Set http = CreateObject("MSXML2.XMLHTTP")

    Dim url As String
    url = API_BASE_URL & "/api/signals/" & signalId & "/failed"

    ' エスケープ処理
    Dim escapedError As String
    escapedError = Replace(errorMessage, """", "\""")
    escapedError = Replace(escapedError, vbCrLf, "\n")

    ' リクエストボディ構築
    Dim body As String
    body = "{""error"": """ & escapedError & """}"

    http.Open "POST", url, False
    http.setRequestHeader "Authorization", "Bearer " & API_KEY
    http.setRequestHeader "Content-Type", "application/json"
    http.Send body

    If http.Status = 200 Then
        Call LogDebug("Failure reported for signal: " & signalId)
    Else
        Call LogError("Failure report failed for signal " & signalId & ": HTTP " & http.Status)
    End If
End Sub

' ========================================
' API接続テスト
' ========================================
Function API_TestConnection() As Boolean
    '
    ' Relay Serverへの接続テスト
    '
    On Error GoTo ErrorHandler

    Dim http As Object
    Set http = CreateObject("MSXML2.XMLHTTP")

    Dim url As String
    url = API_BASE_URL & "/ping"

    http.Open "GET", url, False
    http.Send

    If http.Status = 200 Then
        Call LogSuccess("API Connection OK")
        API_TestConnection = True
    Else
        Call LogError("API Connection Failed: HTTP " & http.Status)
        API_TestConnection = False
    End If

    Exit Function

ErrorHandler:
    Call LogError("Error in API_TestConnection: " & Err.Description)
    API_TestConnection = False
End Function
