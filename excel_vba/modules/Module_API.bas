Attribute VB_Name = "Module_API"
'
' Kabuto Auto Trader - API Module
' サーバーAPI通信
'

Option Explicit

' ========================================
' 未処理シグナル取得
' GET /api/signals/pending
' ========================================
Function FetchPendingSignals() As Collection
    On Error GoTo ErrorHandler

    Dim http As Object
    Set http = CreateObject("MSXML2.XMLHTTP.6.0")

    Dim url As String
    url = GetConfig("API_BASE_URL") & "/signals/pending"

    http.Open "GET", url, False
    http.setRequestHeader "Authorization", "Bearer " & GetConfig("API_KEY")
    http.setRequestHeader "Content-Type", "application/json"
    http.send

    Set FetchPendingSignals = New Collection

    If http.Status = 204 Then
        ' No Content - シグナルなし
        Debug.Print "No pending signals"
        Exit Function
    ElseIf http.Status = 200 Then
        ' JSON解析（JsonConverterライブラリ使用）
        Dim response As Object
        Set response = JsonConverter.ParseJson(http.responseText)

        If response("count") > 0 Then
            Dim signalObj As Variant
            For Each signalObj In response("signals")
                FetchPendingSignals.Add signalObj
            Next signalObj

            Debug.Print "Fetched " & response("count") & " signals from server"
        End If
    Else
        Debug.Print "API Error: " & http.Status & " - " & http.responseText
        Call LogError("API_ERROR", "FetchPendingSignals", "HTTP " & http.Status, "", "ERROR")
    End If

    Exit Function

ErrorHandler:
    Debug.Print "Error in FetchPendingSignals: " & Err.Description
    Call LogError("API_ERROR", "FetchPendingSignals", Err.Description, "", "ERROR")
    Set FetchPendingSignals = New Collection
End Function

' ========================================
' シグナル取得確認
' POST /api/signals/{signal_id}/ack
' ========================================
Function AcknowledgeSignal(signalId As String, checksum As String) As Boolean
    On Error GoTo ErrorHandler

    Dim http As Object
    Set http = CreateObject("MSXML2.XMLHTTP.6.0")

    Dim url As String
    url = GetConfig("API_BASE_URL") & "/signals/" & signalId & "/ack"

    Dim payload As String
    payload = "{""client_id"":""" & GetConfig("CLIENT_ID") & """,""checksum"":""" & checksum & """}"

    http.Open "POST", url, False
    http.setRequestHeader "Authorization", "Bearer " & GetConfig("API_KEY")
    http.setRequestHeader "Content-Type", "application/json"
    http.send payload

    If http.Status = 200 Then
        AcknowledgeSignal = True
        Debug.Print "Signal acknowledged: " & signalId
    Else
        Debug.Print "ACK failed: " & http.Status & " - " & http.responseText
        Call LogError("API_ERROR", "AcknowledgeSignal", "HTTP " & http.Status, signalId, "WARNING")
        AcknowledgeSignal = False
    End If

    Exit Function

ErrorHandler:
    Debug.Print "Error in AcknowledgeSignal: " & Err.Description
    Call LogError("API_ERROR", "AcknowledgeSignal", Err.Description, signalId, "ERROR")
    AcknowledgeSignal = False
End Function

' ========================================
' 執行完了報告
' POST /api/signals/{signal_id}/executed
' ========================================
Sub ReportExecution(signalId As String, orderId As String, price As Double, quantity As Long)
    On Error GoTo ErrorHandler

    Dim http As Object
    Set http = CreateObject("MSXML2.XMLHTTP.6.0")

    Dim url As String
    url = GetConfig("API_BASE_URL") & "/signals/" & signalId & "/executed"

    Dim payload As String
    payload = "{" & _
        """client_id"":""" & GetConfig("CLIENT_ID") & """," & _
        """order_id"":""" & orderId & """," & _
        """execution_price"":" & price & "," & _
        """execution_quantity"":" & quantity & "," & _
        """executed_at"":""" & Format(Now, "yyyy-mm-ddThh:nn:ss+09:00") & """" & _
        "}"

    http.Open "POST", url, False
    http.setRequestHeader "Authorization", "Bearer " & GetConfig("API_KEY")
    http.setRequestHeader "Content-Type", "application/json"
    http.send payload

    If http.Status = 200 Then
        Debug.Print "Execution reported: " & signalId
    Else
        Debug.Print "Execution report failed: " & http.Status & " - " & http.responseText
        Call LogError("API_ERROR", "ReportExecution", "HTTP " & http.Status, signalId, "WARNING")
    End If

    Exit Sub

ErrorHandler:
    Debug.Print "Error in ReportExecution: " & Err.Description
    Call LogError("API_ERROR", "ReportExecution", Err.Description, signalId, "ERROR")
End Sub

' ========================================
' 執行失敗報告
' POST /api/signals/{signal_id}/failed
' ========================================
Sub ReportFailure(signalId As String, errorMessage As String)
    On Error GoTo ErrorHandler

    Dim http As Object
    Set http = CreateObject("MSXML2.XMLHTTP.6.0")

    Dim url As String
    url = GetConfig("API_BASE_URL") & "/signals/" & signalId & "/failed"

    Dim payload As String
    payload = "{" & _
        """client_id"":""" & GetConfig("CLIENT_ID") & """," & _
        """error"":""" & Replace(errorMessage, """", "\""") & """" & _
        "}"

    http.Open "POST", url, False
    http.setRequestHeader "Authorization", "Bearer " & GetConfig("API_KEY")
    http.setRequestHeader "Content-Type", "application/json"
    http.send payload

    If http.Status = 200 Then
        Debug.Print "Failure reported: " & signalId
    Else
        Debug.Print "Failure report failed: " & http.Status
    End If

    Exit Sub

ErrorHandler:
    Debug.Print "Error in ReportFailure: " & Err.Description
End Sub

' ========================================
' ハートビート送信
' POST /api/heartbeat
' ========================================
Sub SendHeartbeat()
    On Error GoTo ErrorHandler

    Dim http As Object
    Set http = CreateObject("MSXML2.XMLHTTP.6.0")

    Dim url As String
    url = GetConfig("API_BASE_URL") & "/../heartbeat"  ' /api/heartbeat ではなく /heartbeat

    Dim payload As String
    payload = "{" & _
        """client_id"":""" & GetConfig("CLIENT_ID") & """," & _
        """timestamp"":""" & Format(Now, "yyyy-mm-ddThh:nn:ss+09:00") & """" & _
        "}"

    http.Open "POST", url, False
    http.setRequestHeader "Authorization", "Bearer " & GetConfig("API_KEY")
    http.setRequestHeader "Content-Type", "application/json"
    http.send payload

    If http.Status = 200 Then
        Debug.Print "Heartbeat sent successfully"
    Else
        Debug.Print "Heartbeat failed: " & http.Status
    End If

    Exit Sub

ErrorHandler:
    Debug.Print "Error in SendHeartbeat: " & Err.Description
    ' ハートビートエラーはログに記録しない（頻繁すぎるため）
End Sub

' ========================================
' API接続チェック
' GET /health
' ========================================
Function CheckAPIConnection() As Boolean
    On Error GoTo ErrorHandler

    Dim http As Object
    Set http = CreateObject("MSXML2.XMLHTTP.6.0")

    Dim url As String
    url = Replace(GetConfig("API_BASE_URL"), "/api", "") & "/health"

    http.Open "GET", url, False
    http.setRequestHeader "Content-Type", "application/json"

    ' タイムアウト設定（5秒）
    http.send

    If http.Status = 200 Then
        CheckAPIConnection = True
    Else
        CheckAPIConnection = False
    End If

    Exit Function

ErrorHandler:
    Debug.Print "Error in CheckAPIConnection: " & Err.Description
    CheckAPIConnection = False
End Function
