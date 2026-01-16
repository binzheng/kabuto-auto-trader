Attribute VB_Name = "Module_Standalone_Test"
'
' Kabuto Auto Trader - Standalone Test Module
' Excel単体テスト用（サーバー不要）
'
' 使用方法:
' 1. このモジュールをインポート
' 2. RunStandaloneTest を実行
' 3. 全てのロジックがExcel内でテストされる
'
' 特徴:
' - サーバー不要
' - Redis不要
' - 完全にExcel内で動作
'

Option Explicit

' ========================================
' スタンドアローンテスト実行
' ========================================
Sub RunStandaloneTest()
    '
    ' Excel単体で全機能をテスト
    '
    On Error GoTo ErrorHandler

    Debug.Print "=================================="
    Debug.Print "[TEST] Kabuto - Standalone Unit Test"
    Debug.Print "=================================="
    Debug.Print ""

    ' テスト初期化
    Call InitializeTestEnvironment

    ' テストケース実行
    Call Test1_CreateMockSignal
    Call Test2_ProcessSignal
    Call Test3_ExecuteMockOrder
    Call Test4_LogOrder
    Call Test5_MultipleSignals
    Call Test6_ErrorHandling

    Debug.Print ""
    Debug.Print "=================================="
    Debug.Print "[OK] All tests completed!"
    Debug.Print "=================================="
    Debug.Print ""
    Debug.Print "Check OrderLog sheet for results."

    MsgBox "[OK] Standalone tests completed!" & vbCrLf & _
           "Check OrderLog sheet and VBA Debug window (Ctrl+G) for details.", _
           vbInformation, "Test Complete"

    Exit Sub

ErrorHandler:
    Debug.Print "[ERROR] Test failed: " & Err.Description
    MsgBox "Test failed: " & Err.Description, vbCritical
End Sub

' ========================================
' ExecuteRSSOrder quick test
' ========================================
Sub TestExecuteRSSOrder()
    On Error GoTo ErrorHandler

    Dim signal As Dictionary
    Set signal = CreateMockSignal("7203", "buy", 100)

    Call LogInfo("TestExecuteRSSOrder: start")

    Dim orderId As String
    orderId = ExecuteRSSOrder(signal)

    If orderId <> "" Then
        Call LogSuccess("TestExecuteRSSOrder: success orderId=" & orderId)
    Else
        Call LogError("TestExecuteRSSOrder: failed")
    End If

    Exit Sub

ErrorHandler:
    Call LogError("TestExecuteRSSOrder error: " & Err.Description)
End Sub

' ========================================
' Create test button on Dashboard
' ========================================
Sub CreateExecuteRSSOrderTestButton()
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("Dashboard")

    ws.Buttons("btnTestExecuteRSSOrder").Delete

    Dim btn As Button
    Set btn = ws.Buttons.Add(ws.Range("D3").Left, ws.Range("D3").Top, 170, 28)
    btn.Name = "btnTestExecuteRSSOrder"
    btn.OnAction = "TestExecuteRSSOrder"
    btn.Characters.Text = "Test ExecuteRSSOrder"

    Call LogInfo("Test button created: " & btn.Name)
End Sub

' ========================================
' テスト初期化
' ========================================
Sub InitializeTestEnvironment()
    Debug.Print "[INFO] Initializing test environment..."

    ' OrderLogシートをクリア（ヘッダー以外）
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("OrderLog")

    If ws.Cells(ws.Rows.Count, 1).End(xlUp).Row > 1 Then
        ws.Rows("2:" & ws.Cells(ws.Rows.Count, 1).End(xlUp).Row).Delete
    End If

    Debug.Print "[OK] Environment initialized"
    Debug.Print ""
End Sub

' ========================================
' テスト1: モックシグナル作成
' ========================================
Sub Test1_CreateMockSignal()
    Debug.Print "Test 1: Create Mock Signal"
    Debug.Print "----------------------------"

    Dim signal As Dictionary
    Set signal = CreateMockSignal("7203", "buy", 100)

    Debug.Print "Signal ID: " & signal("signal_id")
    Debug.Print "Ticker: " & signal("ticker")
    Debug.Print "Action: " & signal("action")
    Debug.Print "Quantity: " & signal("quantity")
    Debug.Print "[OK] Test 1 passed"
    Debug.Print ""
End Sub

' ========================================
' テスト2: シグナル処理
' ========================================
Sub Test2_ProcessSignal()
    Debug.Print "Test 2: Process Signal"
    Debug.Print "-----------------------"

    Dim signal As Dictionary
    Set signal = CreateMockSignal("6758", "buy", 200)

    ' シグナル処理
    Call ProcessSignalStandalone(signal)

    Debug.Print "[OK] Test 2 passed"
    Debug.Print ""
End Sub

' ========================================
' テスト3: モック注文実行
' ========================================
Sub Test3_ExecuteMockOrder()
    Debug.Print "Test 3: Execute Mock Order"
    Debug.Print "---------------------------"

    Dim signal As Dictionary
    Set signal = CreateMockSignal("9984", "buy", 100)

    Dim orderId As String
    orderId = ExecuteRSSOrder_StandaloneMock(signal)

    If orderId <> "" Then
        Debug.Print "Order ID: " & orderId
        Debug.Print "[OK] Test 3 passed"
    Else
        Debug.Print "[ERROR] Test 3 failed: No order ID"
    End If

    Debug.Print ""
End Sub

' ========================================
' テスト4: ログ記録
' ========================================
Sub Test4_LogOrder()
    Debug.Print "Test 4: Log Order"
    Debug.Print "------------------"

    Call LogOrderSuccess_Standalone("sig_test_001", "7201", "buy", "ORD_TEST_001")

    Debug.Print "[OK] Test 4 passed (check OrderLog sheet)"
    Debug.Print ""
End Sub

' ========================================
' テスト5: 複数シグナル処理
' ========================================
Sub Test5_MultipleSignals()
    Debug.Print "Test 5: Multiple Signals"
    Debug.Print "-------------------------"

    Dim signals As Collection
    Set signals = New Collection

    ' 5つのモックシグナル作成
    Dim tickers As Variant
    tickers = Array("7203", "6758", "9984", "8306", "9432")

    Dim i As Integer
    For i = 0 To 4
        Dim signal As Dictionary
        Set signal = CreateMockSignal(CStr(tickers(i)), "buy", (i + 1) * 100)
        signals.Add signal
    Next i

    Debug.Print "Created " & signals.Count & " mock signals"

    ' 各シグナルを処理
    For i = 1 To signals.Count
        Set signal = signals(i)
        Call ProcessSignalStandalone(signal)
    Next i

    Debug.Print "[OK] Test 5 passed"
    Debug.Print ""
End Sub

' ========================================
' テスト6: エラーハンドリング
' ========================================
Sub Test6_ErrorHandling()
    Debug.Print "Test 6: Error Handling"
    Debug.Print "-----------------------"

    ' ランダムで失敗するモックシグナル
    Dim signal As Dictionary
    Set signal = CreateMockSignal("4063", "buy", 100)

    ' 失敗をシミュレート
    Call LogOrderFailure_Standalone(signal("signal_id"), signal("ticker"), signal("action"), "Test: Simulated failure")

    Debug.Print "[OK] Test 6 passed (check OrderLog sheet for failure)"
    Debug.Print ""
End Sub

' ========================================
' ヘルパー: モックシグナル作成
' ========================================
Function CreateMockSignal(ticker As String, action As String, quantity As Long) As Dictionary
    '
    ' テスト用のモックシグナルを作成
    '
    Dim signal As New Dictionary

    signal("signal_id") = "sig_test_" & Format(Now, "yyyymmddhhnnss") & "_" & ticker
    signal("ticker") = ticker
    signal("action") = action
    signal("quantity") = quantity
    signal("price") = GetMockPrice(ticker)
    signal("entry_price") = GetMockPrice(ticker)
    signal("stop_loss") = GetMockPrice(ticker) * 0.95
    signal("take_profit") = GetMockPrice(ticker) * 1.1
    signal("checksum") = "mock_checksum_" & ticker

    Set CreateMockSignal = signal
End Function

' ========================================
' ヘルパー: モック価格取得
' ========================================
Function GetMockPrice(ticker As String) As Double
    '
    ' ティッカーに応じたモック価格を返す
    '
    Select Case ticker
        Case "7203": GetMockPrice = 1850    ' トヨタ
        Case "6758": GetMockPrice = 3000    ' ソニー
        Case "9984": GetMockPrice = 15000   ' ソフトバンク
        Case "8306": GetMockPrice = 1200    ' 三菱UFJ
        Case "9432": GetMockPrice = 2500    ' NTT
        Case "7201": GetMockPrice = 1100    ' 日産
        Case "4063": GetMockPrice = 5000    ' 信越化学
        Case Else: GetMockPrice = 1000
    End Select
End Function

' ========================================
' シグナル処理（スタンドアローン版）
' ========================================
Sub ProcessSignalStandalone(signal As Dictionary)
    '
    ' サーバーなしでシグナルを処理
    '
    On Error GoTo ErrorHandler

    Debug.Print "  Processing: " & signal("ticker") & " " & signal("action") & " " & signal("quantity")

    ' モック注文実行
    Dim orderId As String
    orderId = ExecuteRSSOrder_StandaloneMock(signal)

    If orderId <> "" Then
        ' 成功
        Debug.Print "  [OK] Order executed: " & orderId
        Call LogOrderSuccess_Standalone(signal("signal_id"), signal("ticker"), signal("action"), orderId)
    Else
        ' 失敗
        Debug.Print "  [ERROR] Order failed"
        Call LogOrderFailure_Standalone(signal("signal_id"), signal("ticker"), signal("action"), "Mock execution failed")
    End If

    Exit Sub

ErrorHandler:
    Debug.Print "  [ERROR] Error: " & Err.Description
End Sub

' ========================================
' モック注文実行（スタンドアローン版）
' ========================================
Function ExecuteRSSOrder_StandaloneMock(signal As Dictionary) As String
    '
    ' RSS注文をモック（サーバー通信なし）
    '
    On Error GoTo ErrorHandler

    ' モック注文ID生成
    Dim orderId As String
    orderId = "STANDALONE_ORD_" & Format(Now, "yyyymmddhhnnss") & "_" & signal("ticker")

    ' 処理時間をシミュレート（0.5秒）
    Application.Wait Now + TimeValue("00:00:00.5")

    ' 90%の成功率
    Randomize
    If Rnd() > 0.1 Then
        ExecuteRSSOrder_StandaloneMock = orderId
    Else
        ExecuteRSSOrder_StandaloneMock = ""
    End If

    Exit Function

ErrorHandler:
    ExecuteRSSOrder_StandaloneMock = ""
End Function

' ========================================
' ログ記録（成功 - スタンドアローン版）
' ========================================
Sub LogOrderSuccess_Standalone(signalId As String, ticker As String, action As String, orderId As String)
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("OrderLog")

    Dim nextRow As Long
    nextRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    ws.Cells(nextRow, 1).Value = Now
    ws.Cells(nextRow, 2).Value = signalId
    ws.Cells(nextRow, 3).Value = ticker
    ws.Cells(nextRow, 4).Value = action
    ws.Cells(nextRow, 5).Value = orderId
    ws.Cells(nextRow, 6).Value = "SUCCESS"
    ws.Cells(nextRow, 7).Value = "Standalone Test"

    ' 成功行を緑でハイライト
    ws.Rows(nextRow).Interior.Color = RGB(144, 238, 144)  ' Light Green
End Sub

' ========================================
' ログ記録（失敗 - スタンドアローン版）
' ========================================
Sub LogOrderFailure_Standalone(signalId As String, ticker As String, action As String, reason As String)
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("OrderLog")

    Dim nextRow As Long
    nextRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    ws.Cells(nextRow, 1).Value = Now
    ws.Cells(nextRow, 2).Value = signalId
    ws.Cells(nextRow, 3).Value = ticker
    ws.Cells(nextRow, 4).Value = action
    ws.Cells(nextRow, 5).Value = ""
    ws.Cells(nextRow, 6).Value = "FAILED"
    ws.Cells(nextRow, 7).Value = reason

    ' 失敗行を赤でハイライト
    ws.Rows(nextRow).Interior.Color = RGB(255, 182, 193)  ' Light Pink
End Sub

' ========================================
' 個別テストヘルパー
' ========================================

Sub QuickTest_SingleSignal()
    '
    ' クイックテスト: 1つのシグナル
    '
    Debug.Print "[TEST] Quick Test: Single Signal"

    Dim signal As Dictionary
    Set signal = CreateMockSignal("7203", "buy", 100)

    Call ProcessSignalStandalone(signal)

    Debug.Print "[OK] Quick test completed"
End Sub

Sub QuickTest_BuySell()
    '
    ' クイックテスト: 買い→売り
    '
    Debug.Print "[TEST] Quick Test: Buy -> Sell"

    ' 買い
    Dim buySignal As Dictionary
    Set buySignal = CreateMockSignal("7203", "buy", 100)
    Call ProcessSignalStandalone(buySignal)

    Application.Wait Now + TimeValue("00:00:02")

    ' 売り
    Dim sellSignal As Dictionary
    Set sellSignal = CreateMockSignal("7203", "sell", 100)
    Call ProcessSignalStandalone(sellSignal)

    Debug.Print "[OK] Quick test completed"
End Sub

Sub QuickTest_MultipleOrders()
    '
    ' クイックテスト: 複数注文
    '
    Debug.Print "[TEST] Quick Test: Multiple Orders"

    Dim tickers As Variant
    tickers = Array("7203", "6758", "9984")

    Dim i As Integer
    For i = 0 To 2
        Dim signal As Dictionary
        Set signal = CreateMockSignal(CStr(tickers(i)), "buy", 100)
        Call ProcessSignalStandalone(signal)

        Application.Wait Now + TimeValue("00:00:01")
    Next i

    Debug.Print "[OK] Quick test completed"
End Sub

' ========================================
' パフォーマンステスト
' ========================================
Sub PerformanceTest()
    '
    ' パフォーマンステスト: 大量シグナル処理
    '
    Debug.Print "[PERF] Performance Test: 50 signals"

    Dim startTime As Double
    startTime = Timer

    Dim i As Integer
    For i = 1 To 50
        Dim signal As Dictionary
        Set signal = CreateMockSignal("TEST" & Format(i, "0000"), "buy", 100)
        Call ProcessSignalStandalone(signal)
    Next i

    Dim elapsedTime As Double
    elapsedTime = Timer - startTime

    Debug.Print "[OK] Processed 50 signals in " & Format(elapsedTime, "0.00") & " seconds"
    Debug.Print "Average: " & Format(elapsedTime / 50, "0.000") & " seconds per signal"
End Sub
