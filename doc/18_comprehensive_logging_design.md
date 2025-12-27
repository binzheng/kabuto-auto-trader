# Kabuto Auto Trader - 包括的ログ設計

**作成日**: 2025-12-27
**ドキュメントID**: doc/18

---

## 目次

1. [ログの目的と要件](#1-ログの目的と要件)
2. [Excel側ログ設計](#2-excel側ログ設計)
3. [Server側ログ設計](#3-server側ログ設計)
4. [ログレベル定義](#4-ログレベル定義)
5. [ログフォーマット](#5-ログフォーマット)
6. [ログローテーション](#6-ログローテーション)
7. [ログ分析・監視](#7-ログ分析監視)
8. [実装仕様](#8-実装仕様)

---

## 1. ログの目的と要件

### 1.1 ログの目的

| 目的 | 説明 |
|------|------|
| **監査証跡** | 全ての取引・操作の記録を保持 |
| **トラブルシューティング** | 障害発生時の原因調査 |
| **パフォーマンス分析** | システムの性能評価・改善 |
| **コンプライアンス** | 金融規制への対応 |
| **リスク管理** | 異常検知・アラート |
| **運用監視** | システム稼働状況の可視化 |

### 1.2 ログ要件

#### 必須要件

- ✅ **完全性**: 全ての重要イベントを記録
- ✅ **正確性**: タイムスタンプは秒単位で正確
- ✅ **追跡可能性**: Signal ID で全ライフサイクルを追跡
- ✅ **改ざん防止**: ログは追記のみ（削除・編集不可）
- ✅ **長期保存**: 最低1年間保存

#### 性能要件

- ⚡ **非同期**: ログ記録がメイン処理をブロックしない
- ⚡ **高速**: 1ログ記録は10ms以内
- ⚡ **低負荷**: CPU使用率への影響は5%以内

---

## 2. Excel側ログ設計

### 2.1 ログシート一覧

| シート名 | 目的 | 保存期間 | 重要度 |
|---------|------|---------|--------|
| **SignalLog** | 信号受信履歴 | 90日 | 高 |
| **OrderHistory** | 注文履歴 | 永久 | 最高 |
| **ExecutionLog** | 約定履歴 | 永久 | 最高 |
| **ErrorLog** | エラー履歴 | 90日 | 高 |
| **SystemLog** | システムログ | 30日 | 中 |
| **AuditLog** | 監査ログ | 永久 | 最高 |

---

### 2.2 SignalLog（信号受信履歴）

**目的**: サーバーから受信した全ての信号を記録

**シート構造**:

| 列 | 列名 | データ型 | 説明 | 例 |
|----|------|---------|------|-----|
| A | log_id | TEXT | ログID（自動採番） | SL-20250127-001 |
| B | timestamp | DATETIME | 受信日時（秒精度） | 2025-01-27 09:05:23 |
| C | signal_id | TEXT | 信号ID | SIG-20250127-ABC123 |
| D | strategy | TEXT | 戦略名 | momentum_breakout |
| E | ticker | TEXT | 銘柄コード | 7203 |
| F | ticker_name | TEXT | 銘柄名 | トヨタ自動車 |
| G | action | TEXT | 売買区分 | buy / sell |
| H | quantity | INTEGER | 数量 | 100 |
| I | price_type | TEXT | 価格タイプ | market / limit |
| J | limit_price | DECIMAL | 指値価格 | 2500.0 |
| K | signal_strength | DECIMAL | 信号強度 | 0.85 |
| L | checksum | TEXT | チェックサム | abc123... |
| M | status | TEXT | 処理状態 | received / queued / processing / executed / failed |
| N | queue_time | DATETIME | キュー投入時刻 | 2025-01-27 09:05:24 |
| O | processing_time | DATETIME | 処理開始時刻 | 2025-01-27 09:05:25 |
| P | completed_time | DATETIME | 完了時刻 | 2025-01-27 09:05:30 |
| Q | error_message | TEXT | エラーメッセージ | - |
| R | ack_sent | BOOLEAN | ACK送信済み | TRUE / FALSE |
| S | notes | TEXT | 備考 | - |

**ログ記録タイミング**:
1. 信号受信時（status: received）
2. キュー投入時（status: queued）
3. 処理開始時（status: processing）
4. 処理完了時（status: executed / failed）

**サンプルVBAコード**:

```vba
Sub LogSignalReceived(signal As Dictionary)
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("SignalLog")

    Dim nextRow As Long
    nextRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    Dim logId As String
    logId = "SL-" & Format(Date, "YYYYMMDD") & "-" & Format(nextRow - 1, "000")

    ws.Cells(nextRow, 1).Value = logId
    ws.Cells(nextRow, 2).Value = Now
    ws.Cells(nextRow, 3).Value = signal("signal_id")
    ws.Cells(nextRow, 4).Value = signal("strategy")
    ws.Cells(nextRow, 5).Value = signal("ticker")
    ws.Cells(nextRow, 6).Value = GetTickerName(signal("ticker"))
    ws.Cells(nextRow, 7).Value = signal("action")
    ws.Cells(nextRow, 8).Value = signal("quantity")
    ws.Cells(nextRow, 9).Value = signal("price_type")
    ws.Cells(nextRow, 10).Value = signal("limit_price")
    ws.Cells(nextRow, 11).Value = signal("signal_strength")
    ws.Cells(nextRow, 12).Value = signal("checksum")
    ws.Cells(nextRow, 13).Value = "received"
    ws.Cells(nextRow, 18).Value = False

    Debug.Print "SignalLog: " & logId & " - Signal received: " & signal("signal_id")
End Sub

Sub UpdateSignalStatus(signalId As String, status As String, Optional errorMsg As String = "")
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("SignalLog")

    ' signal_idで該当行を検索
    Dim foundCell As Range
    Set foundCell = ws.Columns(3).Find(signalId, LookIn:=xlValues, LookAt:=xlWhole)

    If Not foundCell Is Nothing Then
        Dim row As Long
        row = foundCell.Row

        ws.Cells(row, 13).Value = status

        Select Case status
            Case "queued"
                ws.Cells(row, 14).Value = Now
            Case "processing"
                ws.Cells(row, 15).Value = Now
            Case "executed", "failed"
                ws.Cells(row, 16).Value = Now
                If errorMsg <> "" Then
                    ws.Cells(row, 17).Value = errorMsg
                End If
        End Select

        Debug.Print "SignalLog: Updated " & signalId & " status to " & status
    End If
End Sub
```

---

### 2.3 OrderHistory（注文履歴）

**目的**: MarketSpeed II RSSに発注した全注文を記録

**シート構造**:

| 列 | 列名 | データ型 | 説明 | 例 |
|----|------|---------|------|-----|
| A | internal_order_id | TEXT | 内部注文ID | ORD-20250127-001 |
| B | order_time | DATETIME | 発注日時 | 2025-01-27 09:05:30 |
| C | signal_id | TEXT | 元信号ID | SIG-20250127-ABC123 |
| D | ticker | TEXT | 銘柄コード | 7203 |
| E | action | TEXT | 売買区分 | buy / sell |
| F | quantity | INTEGER | 注文数量 | 100 |
| G | price_type | TEXT | 価格タイプ | market / limit |
| H | limit_price | DECIMAL | 指値価格 | 2500.0 |
| I | rss_order_id | TEXT | RSS注文ID | RSS-12345 |
| J | order_status | TEXT | 注文状態 | submitted / partial / filled / canceled / rejected |
| K | filled_quantity | INTEGER | 約定数量 | 100 |
| L | filled_price | DECIMAL | 約定価格 | 2498.0 |
| M | commission | DECIMAL | 手数料 | 99.0 |
| N | filled_time | DATETIME | 約定日時 | 2025-01-27 09:05:35 |
| O | reject_reason | TEXT | 拒否理由 | - |
| P | validation_result | TEXT | 検証結果 | PASS |
| Q | safety_checks | TEXT | 安全チェック結果 | 6-layer: PASS |
| R | market_session | TEXT | 市場セッション | morning-trading |
| S | reference_price | DECIMAL | 基準価格 | 2500.0 |
| T | order_source | TEXT | 発注元 | auto / manual |
| U | notes | TEXT | 備考 | - |

**ログ記録タイミング**:
1. 注文発注時（order_status: submitted）
2. 部分約定時（order_status: partial）
3. 全約定時（order_status: filled）
4. キャンセル時（order_status: canceled）
5. 拒否時（order_status: rejected）

**サンプルVBAコード**:

```vba
Sub LogOrderSubmitted(signal As Dictionary, orderParams As Dictionary, rssOrderId As String)
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("OrderHistory")

    Dim nextRow As Long
    nextRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    Dim orderId As String
    orderId = "ORD-" & Format(Date, "YYYYMMDD") & "-" & Format(nextRow - 1, "000")

    ws.Cells(nextRow, 1).Value = orderId
    ws.Cells(nextRow, 2).Value = Now
    ws.Cells(nextRow, 3).Value = signal("signal_id")
    ws.Cells(nextRow, 4).Value = orderParams("ticker")
    ws.Cells(nextRow, 5).Value = orderParams("action")
    ws.Cells(nextRow, 6).Value = orderParams("quantity")
    ws.Cells(nextRow, 7).Value = orderParams("price_type")
    ws.Cells(nextRow, 8).Value = orderParams("limit_price")
    ws.Cells(nextRow, 9).Value = rssOrderId
    ws.Cells(nextRow, 10).Value = "submitted"
    ws.Cells(nextRow, 16).Value = orderParams("validation_result")
    ws.Cells(nextRow, 17).Value = orderParams("safety_checks")
    ws.Cells(nextRow, 18).Value = GetMarketSession()
    ws.Cells(nextRow, 19).Value = orderParams("reference_price")
    ws.Cells(nextRow, 20).Value = "auto"

    Debug.Print "OrderHistory: " & orderId & " - Order submitted: " & rssOrderId

    ' 内部注文IDを返す（後続処理で使用）
    LogOrderSubmitted = orderId
End Sub

Sub UpdateOrderExecution(internalOrderId As String, filledQty As Integer, filledPrice As Double, commission As Double)
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("OrderHistory")

    ' internal_order_idで該当行を検索
    Dim foundCell As Range
    Set foundCell = ws.Columns(1).Find(internalOrderId, LookIn:=xlValues, LookAt:=xlWhole)

    If Not foundCell Is Nothing Then
        Dim row As Long
        row = foundCell.Row

        Dim orderQty As Integer
        orderQty = ws.Cells(row, 6).Value

        ws.Cells(row, 11).Value = filledQty
        ws.Cells(row, 12).Value = filledPrice
        ws.Cells(row, 13).Value = commission
        ws.Cells(row, 14).Value = Now

        If filledQty >= orderQty Then
            ws.Cells(row, 10).Value = "filled"
            Debug.Print "OrderHistory: " & internalOrderId & " - Fully filled"
        Else
            ws.Cells(row, 10).Value = "partial"
            Debug.Print "OrderHistory: " & internalOrderId & " - Partially filled"
        End If
    End If
End Sub
```

---

### 2.4 ExecutionLog（約定履歴）

**目的**: 実際に約定した取引を記録（会計・税務用）

**シート構造**:

| 列 | 列名 | データ型 | 説明 | 例 |
|----|------|---------|------|-----|
| A | execution_id | TEXT | 約定ID | EXE-20250127-001 |
| B | execution_time | DATETIME | 約定日時 | 2025-01-27 09:05:35 |
| C | trade_date | DATE | 取引日 | 2025-01-27 |
| D | signal_id | TEXT | 元信号ID | SIG-20250127-ABC123 |
| E | internal_order_id | TEXT | 内部注文ID | ORD-20250127-001 |
| F | rss_order_id | TEXT | RSS注文ID | RSS-12345 |
| G | ticker | TEXT | 銘柄コード | 7203 |
| H | ticker_name | TEXT | 銘柄名 | トヨタ自動車 |
| I | action | TEXT | 売買区分 | buy / sell |
| J | quantity | INTEGER | 数量 | 100 |
| K | price | DECIMAL | 約定価格 | 2498.0 |
| L | amount | DECIMAL | 約定金額 | 249,800 |
| M | commission | DECIMAL | 手数料 | 99.0 |
| N | total_amount | DECIMAL | 総額（手数料込み） | 249,899 |
| O | strategy | TEXT | 戦略名 | momentum_breakout |
| P | market_session | TEXT | 市場セッション | morning-trading |
| Q | pnl | DECIMAL | 損益（売却時のみ） | +5,000 |
| R | pnl_rate | DECIMAL | 損益率（売却時のみ） | +2.0% |
| S | position_update | TEXT | ポジション更新 | +100 / -100 |
| T | notes | TEXT | 備考 | - |

**ログ記録タイミング**:
- 注文が約定した時点

**サンプルVBAコード**:

```vba
Sub LogExecution(signal As Dictionary, orderInfo As Dictionary, executionInfo As Dictionary)
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("ExecutionLog")

    Dim nextRow As Long
    nextRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    Dim execId As String
    execId = "EXE-" & Format(Date, "YYYYMMDD") & "-" & Format(nextRow - 1, "000")

    Dim amount As Double
    amount = executionInfo("quantity") * executionInfo("price")

    Dim totalAmount As Double
    totalAmount = amount + executionInfo("commission")

    ws.Cells(nextRow, 1).Value = execId
    ws.Cells(nextRow, 2).Value = Now
    ws.Cells(nextRow, 3).Value = Date
    ws.Cells(nextRow, 4).Value = signal("signal_id")
    ws.Cells(nextRow, 5).Value = orderInfo("internal_order_id")
    ws.Cells(nextRow, 6).Value = orderInfo("rss_order_id")
    ws.Cells(nextRow, 7).Value = signal("ticker")
    ws.Cells(nextRow, 8).Value = GetTickerName(signal("ticker"))
    ws.Cells(nextRow, 9).Value = signal("action")
    ws.Cells(nextRow, 10).Value = executionInfo("quantity")
    ws.Cells(nextRow, 11).Value = executionInfo("price")
    ws.Cells(nextRow, 12).Value = amount
    ws.Cells(nextRow, 13).Value = executionInfo("commission")
    ws.Cells(nextRow, 14).Value = totalAmount
    ws.Cells(nextRow, 15).Value = signal("strategy")
    ws.Cells(nextRow, 16).Value = GetMarketSession()

    ' 売却時は損益を計算
    If signal("action") = "sell" Then
        Dim pnl As Double
        pnl = CalculateRealizedPnL(signal("ticker"), executionInfo("quantity"), executionInfo("price"), executionInfo("commission"))
        ws.Cells(nextRow, 17).Value = pnl

        If pnl <> 0 Then
            Dim buyPrice As Double
            buyPrice = GetAverageBuyPrice(signal("ticker"))
            ws.Cells(nextRow, 18).Value = (pnl / (buyPrice * executionInfo("quantity"))) * 100
        End If
    End If

    ws.Cells(nextRow, 19).Value = IIf(signal("action") = "buy", "+" & executionInfo("quantity"), "-" & executionInfo("quantity"))

    Debug.Print "ExecutionLog: " & execId & " - Execution recorded"
End Sub
```

---

### 2.5 ErrorLog（エラー履歴）

**目的**: 全てのエラー・警告を記録

**シート構造**:

| 列 | 列名 | データ型 | 説明 | 例 |
|----|------|---------|------|-----|
| A | error_id | TEXT | エラーID | ERR-20250127-001 |
| B | timestamp | DATETIME | 発生日時 | 2025-01-27 09:05:30 |
| C | severity | TEXT | 深刻度 | CRITICAL / ERROR / WARNING |
| D | category | TEXT | カテゴリ | ORDER / API / RSS / VALIDATION / SYSTEM |
| E | module | TEXT | モジュール名 | Module_RSS |
| F | function | TEXT | 関数名 | SafeExecuteOrder |
| G | error_code | TEXT | エラーコード | RSS_ERR_001 |
| H | error_message | TEXT | エラーメッセージ | RSS connection failed |
| I | error_detail | TEXT | 詳細情報 | Connection timeout after 30s |
| J | signal_id | TEXT | 関連信号ID | SIG-20250127-ABC123 |
| K | ticker | TEXT | 関連銘柄 | 7203 |
| L | action_taken | TEXT | 対処内容 | Order blocked |
| M | kill_switch_triggered | BOOLEAN | Kill Switch発動 | FALSE |
| N | retry_count | INTEGER | リトライ回数 | 0 |
| O | stack_trace | TEXT | スタックトレース | - |
| P | resolved | BOOLEAN | 解決済み | FALSE |
| Q | resolved_time | DATETIME | 解決日時 | - |
| R | notes | TEXT | 備考 | - |

**ログ記録タイミング**:
- エラー・警告発生時（即座）

**サンプルVBAコード**:

```vba
Sub LogError(severity As String, category As String, moduleName As String, functionName As String, _
             errorCode As String, errorMessage As String, Optional errorDetail As String = "", _
             Optional signalId As String = "", Optional ticker As String = "", _
             Optional actionTaken As String = "", Optional killSwitchTriggered As Boolean = False)
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("ErrorLog")

    Dim nextRow As Long
    nextRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    Dim errorId As String
    errorId = "ERR-" & Format(Date, "YYYYMMDD") & "-" & Format(nextRow - 1, "000")

    ws.Cells(nextRow, 1).Value = errorId
    ws.Cells(nextRow, 2).Value = Now
    ws.Cells(nextRow, 3).Value = severity
    ws.Cells(nextRow, 4).Value = category
    ws.Cells(nextRow, 5).Value = moduleName
    ws.Cells(nextRow, 6).Value = functionName
    ws.Cells(nextRow, 7).Value = errorCode
    ws.Cells(nextRow, 8).Value = errorMessage
    ws.Cells(nextRow, 9).Value = errorDetail
    ws.Cells(nextRow, 10).Value = signalId
    ws.Cells(nextRow, 11).Value = ticker
    ws.Cells(nextRow, 12).Value = actionTaken
    ws.Cells(nextRow, 13).Value = killSwitchTriggered
    ws.Cells(nextRow, 14).Value = 0
    ws.Cells(nextRow, 16).Value = False

    ' 重大エラーの場合はDebug.Printも出力
    If severity = "CRITICAL" Or severity = "ERROR" Then
        Debug.Print "ErrorLog: [" & severity & "] " & errorCode & " - " & errorMessage
    End If

    ' Kill Switch発動時は特別処理
    If killSwitchTriggered Then
        Debug.Print "!!! KILL SWITCH TRIGGERED !!!"
        Call ActivateKillSwitch(errorMessage)
    End If
End Sub

' エラーカテゴリの定数
Public Const ERR_CAT_ORDER As String = "ORDER"
Public Const ERR_CAT_API As String = "API"
Public Const ERR_CAT_RSS As String = "RSS"
Public Const ERR_CAT_VALIDATION As String = "VALIDATION"
Public Const ERR_CAT_SYSTEM As String = "SYSTEM"

' 深刻度の定数
Public Const SEV_CRITICAL As String = "CRITICAL"
Public Const SEV_ERROR As String = "ERROR"
Public Const SEV_WARNING As String = "WARNING"
```

---

### 2.6 SystemLog（システムログ）

**目的**: システム稼働状況・イベントを記録

**シート構造**:

| 列 | 列名 | データ型 | 説明 | 例 |
|----|------|---------|------|-----|
| A | log_id | TEXT | ログID | SYS-20250127-001 |
| B | timestamp | DATETIME | 日時 | 2025-01-27 09:00:00 |
| C | level | TEXT | ログレベル | INFO / DEBUG / WARNING |
| D | category | TEXT | カテゴリ | STARTUP / SHUTDOWN / HEARTBEAT / POLLING |
| E | event | TEXT | イベント名 | System started |
| F | message | TEXT | メッセージ | Auto trading system started |
| G | module | TEXT | モジュール名 | Module_Main |
| H | function | TEXT | 関数名 | StartAutoTrading |
| I | details | TEXT | 詳細情報 | Poll interval: 5s |
| J | system_status | TEXT | システム状態 | Running / Paused / Stopped |
| K | api_status | TEXT | API接続状態 | Connected / Disconnected |
| L | rss_status | TEXT | RSS接続状態 | Connected / Disconnected |
| M | market_session | TEXT | 市場セッション | morning-trading |
| N | cpu_usage | DECIMAL | CPU使用率 | 15.5% |
| O | memory_usage | DECIMAL | メモリ使用率 | 320MB |
| P | notes | TEXT | 備考 | - |

**ログ記録タイミング**:
- システム起動時
- システム停止時
- Heartbeat送信時（5分毎）
- ポーリング実行時（5秒毎 - DEBUGレベル）
- 設定変更時

**サンプルVBAコード**:

```vba
Sub LogSystemEvent(level As String, category As String, eventName As String, message As String, _
                   Optional moduleName As String = "", Optional functionName As String = "", _
                   Optional details As String = "")
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("SystemLog")

    Dim nextRow As Long
    nextRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    Dim logId As String
    logId = "SYS-" & Format(Now, "YYYYMMDD-HHNNSS")

    ws.Cells(nextRow, 1).Value = logId
    ws.Cells(nextRow, 2).Value = Now
    ws.Cells(nextRow, 3).Value = level
    ws.Cells(nextRow, 4).Value = category
    ws.Cells(nextRow, 5).Value = eventName
    ws.Cells(nextRow, 6).Value = message
    ws.Cells(nextRow, 7).Value = moduleName
    ws.Cells(nextRow, 8).Value = functionName
    ws.Cells(nextRow, 9).Value = details
    ws.Cells(nextRow, 10).Value = GetSystemState("system_status")
    ws.Cells(nextRow, 11).Value = GetSystemState("api_connection_status")
    ws.Cells(nextRow, 12).Value = GetSystemState("rss_connection_status")
    ws.Cells(nextRow, 13).Value = GetMarketSession()

    ' INFOレベル以上はDebug.Printも出力
    If level <> "DEBUG" Then
        Debug.Print "SystemLog: [" & level & "] " & eventName & " - " & message
    End If
End Sub

' システムログカテゴリの定数
Public Const SYS_CAT_STARTUP As String = "STARTUP"
Public Const SYS_CAT_SHUTDOWN As String = "SHUTDOWN"
Public Const SYS_CAT_HEARTBEAT As String = "HEARTBEAT"
Public Const SYS_CAT_POLLING As String = "POLLING"
Public Const SYS_CAT_CONFIG As String = "CONFIG"
```

---

### 2.7 AuditLog（監査ログ）

**目的**: コンプライアンス・監査用の完全な操作履歴

**シート構造**:

| 列 | 列名 | データ型 | 説明 | 例 |
|----|------|---------|------|-----|
| A | audit_id | TEXT | 監査ID | AUD-20250127-001 |
| B | timestamp | DATETIME | 日時 | 2025-01-27 09:05:30 |
| C | operation | TEXT | 操作種別 | ORDER_SUBMIT / ORDER_CANCEL / SYSTEM_START / KILL_SWITCH |
| D | operator | TEXT | 操作者 | AUTO / MANUAL |
| E | signal_id | TEXT | 信号ID | SIG-20250127-ABC123 |
| F | internal_order_id | TEXT | 内部注文ID | ORD-20250127-001 |
| G | ticker | TEXT | 銘柄コード | 7203 |
| H | action | TEXT | 売買区分 | buy / sell |
| I | quantity | INTEGER | 数量 | 100 |
| J | price | DECIMAL | 価格 | 2498.0 |
| K | validation_passed | BOOLEAN | 検証通過 | TRUE / FALSE |
| L | safety_checks | TEXT | 安全チェック | 6-layer: PASS |
| M | risk_checks | TEXT | リスクチェック | Daily limit: OK |
| N | market_session | TEXT | 市場セッション | morning-trading |
| O | system_status | TEXT | システム状態 | Running |
| P | result | TEXT | 実行結果 | SUCCESS / FAILED / BLOCKED |
| Q | result_detail | TEXT | 結果詳細 | Order submitted to RSS |
| R | checksum | TEXT | チェックサム | abc123... |
| S | notes | TEXT | 備考 | - |

**ログ記録タイミング**:
- 注文発注時（自動・手動問わず）
- 注文キャンセル時
- システム起動/停止時
- Kill Switch発動時
- 設定変更時

**サンプルVBAコード**:

```vba
Sub LogAudit(operation As String, operator As String, result As String, resultDetail As String, _
             Optional signalId As String = "", Optional internalOrderId As String = "", _
             Optional ticker As String = "", Optional action As String = "", _
             Optional quantity As Integer = 0, Optional price As Double = 0, _
             Optional validationPassed As Boolean = True, Optional safetyChecks As String = "", _
             Optional riskChecks As String = "", Optional checksum As String = "")
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("AuditLog")

    Dim nextRow As Long
    nextRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    Dim auditId As String
    auditId = "AUD-" & Format(Date, "YYYYMMDD") & "-" & Format(nextRow - 1, "000")

    ws.Cells(nextRow, 1).Value = auditId
    ws.Cells(nextRow, 2).Value = Now
    ws.Cells(nextRow, 3).Value = operation
    ws.Cells(nextRow, 4).Value = operator
    ws.Cells(nextRow, 5).Value = signalId
    ws.Cells(nextRow, 6).Value = internalOrderId
    ws.Cells(nextRow, 7).Value = ticker
    ws.Cells(nextRow, 8).Value = action
    ws.Cells(nextRow, 9).Value = quantity
    ws.Cells(nextRow, 10).Value = price
    ws.Cells(nextRow, 11).Value = validationPassed
    ws.Cells(nextRow, 12).Value = safetyChecks
    ws.Cells(nextRow, 13).Value = riskChecks
    ws.Cells(nextRow, 14).Value = GetMarketSession()
    ws.Cells(nextRow, 15).Value = GetSystemState("system_status")
    ws.Cells(nextRow, 16).Value = result
    ws.Cells(nextRow, 17).Value = resultDetail
    ws.Cells(nextRow, 18).Value = checksum

    Debug.Print "AuditLog: " & auditId & " - " & operation & " - " & result
End Sub

' 監査操作種別の定数
Public Const AUD_OP_ORDER_SUBMIT As String = "ORDER_SUBMIT"
Public Const AUD_OP_ORDER_CANCEL As String = "ORDER_CANCEL"
Public Const AUD_OP_SYSTEM_START As String = "SYSTEM_START"
Public Const AUD_OP_SYSTEM_STOP As String = "SYSTEM_STOP"
Public Const AUD_OP_KILL_SWITCH As String = "KILL_SWITCH"
Public Const AUD_OP_CONFIG_CHANGE As String = "CONFIG_CHANGE"
```

---

## 3. Server側ログ設計

### 3.1 ログファイル一覧

| ファイル名 | 目的 | ローテーション | 保存期間 |
|----------|------|---------------|---------|
| **app.log** | アプリケーションログ | 日次 | 90日 |
| **signal.log** | 信号生成ログ | 日次 | 90日 |
| **api.log** | API通信ログ | 日次 | 30日 |
| **error.log** | エラーログ | 日次 | 90日 |
| **access.log** | アクセスログ | 日次 | 30日 |
| **audit.log** | 監査ログ | 日次 | 永久 |

### 3.2 ログフォーマット（JSON形式）

**標準フォーマット**:

```json
{
  "timestamp": "2025-01-27T09:05:30.123456+09:00",
  "level": "INFO",
  "logger": "signal_generator",
  "module": "momentum_breakout",
  "function": "generate_signal",
  "message": "Signal generated for 7203",
  "context": {
    "signal_id": "SIG-20250127-ABC123",
    "ticker": "7203",
    "action": "buy",
    "quantity": 100,
    "signal_strength": 0.85
  },
  "trace_id": "trace-123456",
  "environment": "production"
}
```

---

### 3.3 app.log（アプリケーションログ）

**目的**: FastAPIアプリケーションの全般的なログ

**ログレベル別記録内容**:

| レベル | 記録内容 | 例 |
|--------|---------|-----|
| **DEBUG** | 詳細なデバッグ情報 | Function entry/exit, variable values |
| **INFO** | 通常の動作情報 | Signal generated, Order submitted |
| **WARNING** | 警告情報 | Retry attempted, Configuration deprecated |
| **ERROR** | エラー情報 | API call failed, Database error |
| **CRITICAL** | 致命的エラー | System down, Data corruption |

**Python実装例**:

```python
import logging
import json
from datetime import datetime
from typing import Any, Dict

class JSONFormatter(logging.Formatter):
    """JSON形式でログを出力するフォーマッター"""

    def format(self, record: logging.LogRecord) -> str:
        log_data = {
            "timestamp": datetime.now().isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "module": record.module,
            "function": record.funcName,
            "line": record.lineno,
            "message": record.getMessage(),
        }

        # contextがあれば追加
        if hasattr(record, 'context'):
            log_data['context'] = record.context

        # trace_idがあれば追加
        if hasattr(record, 'trace_id'):
            log_data['trace_id'] = record.trace_id

        # 例外情報があれば追加
        if record.exc_info:
            log_data['exception'] = self.formatException(record.exc_info)

        return json.dumps(log_data, ensure_ascii=False)

# ロガーの設定
def setup_logger(name: str) -> logging.Logger:
    logger = logging.getLogger(name)
    logger.setLevel(logging.DEBUG)

    # ファイルハンドラー
    handler = logging.handlers.TimedRotatingFileHandler(
        filename='logs/app.log',
        when='midnight',
        interval=1,
        backupCount=90,
        encoding='utf-8'
    )
    handler.setFormatter(JSONFormatter())
    logger.addHandler(handler)

    # コンソールハンドラー（開発時のみ）
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(JSONFormatter())
    logger.addHandler(console_handler)

    return logger

# 使用例
logger = setup_logger('app')

logger.info(
    "Signal generated",
    extra={
        'context': {
            'signal_id': 'SIG-20250127-ABC123',
            'ticker': '7203',
            'action': 'buy'
        },
        'trace_id': 'trace-123456'
    }
)
```

---

### 3.4 signal.log（信号生成ログ）

**目的**: 信号生成プロセスの詳細を記録

**記録内容**:

```json
{
  "timestamp": "2025-01-27T09:05:30.123456+09:00",
  "level": "INFO",
  "logger": "signal_generator",
  "event": "signal_generated",
  "signal": {
    "signal_id": "SIG-20250127-ABC123",
    "strategy": "momentum_breakout",
    "ticker": "7203",
    "ticker_name": "トヨタ自動車",
    "action": "buy",
    "quantity": 100,
    "price_type": "market",
    "limit_price": null,
    "signal_strength": 0.85,
    "checksum": "abc123..."
  },
  "market_data": {
    "current_price": 2500.0,
    "volume": 1000000,
    "volatility": 0.15,
    "momentum": 0.85
  },
  "conditions": {
    "price_breakout": true,
    "volume_surge": true,
    "trend_confirmed": true
  },
  "trace_id": "trace-123456"
}
```

**Python実装例**:

```python
def log_signal_generated(signal: Dict[str, Any], market_data: Dict[str, Any], conditions: Dict[str, Any]):
    logger = logging.getLogger('signal_generator')

    logger.info(
        f"Signal generated: {signal['signal_id']}",
        extra={
            'context': {
                'event': 'signal_generated',
                'signal': signal,
                'market_data': market_data,
                'conditions': conditions
            },
            'trace_id': signal['signal_id']
        }
    )

def log_signal_sent(signal_id: str, recipients: List[str]):
    logger = logging.getLogger('signal_generator')

    logger.info(
        f"Signal sent: {signal_id}",
        extra={
            'context': {
                'event': 'signal_sent',
                'signal_id': signal_id,
                'recipients': recipients,
                'sent_at': datetime.now().isoformat()
            },
            'trace_id': signal_id
        }
    )

def log_signal_acknowledged(signal_id: str, client_id: str, checksum: str):
    logger = logging.getLogger('signal_generator')

    logger.info(
        f"Signal acknowledged: {signal_id}",
        extra={
            'context': {
                'event': 'signal_acknowledged',
                'signal_id': signal_id,
                'client_id': client_id,
                'checksum': checksum,
                'ack_at': datetime.now().isoformat()
            },
            'trace_id': signal_id
        }
    )
```

---

### 3.5 api.log（API通信ログ）

**目的**: FastAPI エンドポイントへのリクエスト・レスポンスを記録

**記録内容**:

```json
{
  "timestamp": "2025-01-27T09:05:30.123456+09:00",
  "level": "INFO",
  "logger": "api",
  "event": "api_request",
  "request": {
    "method": "POST",
    "path": "/api/signals/SIG-20250127-ABC123/ack",
    "client_ip": "192.168.1.100",
    "user_agent": "Excel-VBA/1.0",
    "headers": {
      "Content-Type": "application/json",
      "Authorization": "Bearer ..."
    }
  },
  "response": {
    "status_code": 200,
    "processing_time_ms": 15,
    "body_size_bytes": 256
  },
  "trace_id": "trace-123456"
}
```

**FastAPI ミドルウェア実装例**:

```python
from fastapi import FastAPI, Request
from starlette.middleware.base import BaseHTTPMiddleware
import time
import logging

class APILoggingMiddleware(BaseHTTPMiddleware):
    """API通信をログに記録するミドルウェア"""

    async def dispatch(self, request: Request, call_next):
        # リクエスト情報を記録
        start_time = time.time()
        trace_id = request.headers.get('X-Trace-ID', f"trace-{int(time.time() * 1000)}")

        logger = logging.getLogger('api')

        # リクエストログ
        logger.info(
            f"API Request: {request.method} {request.url.path}",
            extra={
                'context': {
                    'event': 'api_request',
                    'request': {
                        'method': request.method,
                        'path': request.url.path,
                        'client_ip': request.client.host,
                        'user_agent': request.headers.get('User-Agent')
                    }
                },
                'trace_id': trace_id
            }
        )

        # リクエスト処理
        response = await call_next(request)

        # レスポンスログ
        processing_time = (time.time() - start_time) * 1000  # ms

        logger.info(
            f"API Response: {response.status_code}",
            extra={
                'context': {
                    'event': 'api_response',
                    'response': {
                        'status_code': response.status_code,
                        'processing_time_ms': round(processing_time, 2)
                    }
                },
                'trace_id': trace_id
            }
        )

        return response

# FastAPIに追加
app = FastAPI()
app.add_middleware(APILoggingMiddleware)
```

---

### 3.6 error.log（エラーログ）

**目的**: 全てのエラー・例外を記録

**記録内容**:

```json
{
  "timestamp": "2025-01-27T09:05:30.123456+09:00",
  "level": "ERROR",
  "logger": "app",
  "module": "signal_generator",
  "function": "generate_signal",
  "message": "Failed to fetch market data",
  "error": {
    "type": "ConnectionError",
    "message": "Connection timeout",
    "traceback": "Traceback (most recent call last):\n  File ..."
  },
  "context": {
    "ticker": "7203",
    "retry_count": 2
  },
  "trace_id": "trace-123456"
}
```

**Python実装例**:

```python
def log_error(logger_name: str, error: Exception, context: Dict[str, Any] = None, trace_id: str = None):
    logger = logging.getLogger(logger_name)

    import traceback

    logger.error(
        f"Error occurred: {str(error)}",
        extra={
            'context': {
                'error': {
                    'type': type(error).__name__,
                    'message': str(error),
                    'traceback': traceback.format_exc()
                },
                **(context or {})
            },
            'trace_id': trace_id or f"trace-{int(time.time() * 1000)}"
        },
        exc_info=True
    )

# 使用例
try:
    result = fetch_market_data(ticker)
except Exception as e:
    log_error(
        'signal_generator',
        e,
        context={'ticker': ticker, 'retry_count': retry_count},
        trace_id='trace-123456'
    )
```

---

### 3.7 audit.log（監査ログ）

**目的**: コンプライアンス・監査用の完全な操作履歴

**記録内容**:

```json
{
  "timestamp": "2025-01-27T09:05:30.123456+09:00",
  "level": "INFO",
  "logger": "audit",
  "event": "signal_generated",
  "operator": "SYSTEM",
  "operation": {
    "type": "SIGNAL_GENERATE",
    "signal_id": "SIG-20250127-ABC123",
    "strategy": "momentum_breakout",
    "ticker": "7203",
    "action": "buy",
    "quantity": 100
  },
  "validation": {
    "passed": true,
    "checks": ["risk_limit", "market_hours", "ticker_valid"]
  },
  "result": {
    "status": "SUCCESS",
    "detail": "Signal generated and sent to clients"
  },
  "checksum": "abc123...",
  "trace_id": "trace-123456"
}
```

**Python実装例**:

```python
def log_audit(event: str, operator: str, operation: Dict[str, Any],
              validation: Dict[str, Any], result: Dict[str, Any],
              checksum: str = None, trace_id: str = None):
    logger = logging.getLogger('audit')

    logger.info(
        f"Audit: {event}",
        extra={
            'context': {
                'event': event,
                'operator': operator,
                'operation': operation,
                'validation': validation,
                'result': result,
                'checksum': checksum
            },
            'trace_id': trace_id or f"trace-{int(time.time() * 1000)}"
        }
    )

# 使用例
log_audit(
    event='signal_generated',
    operator='SYSTEM',
    operation={
        'type': 'SIGNAL_GENERATE',
        'signal_id': 'SIG-20250127-ABC123',
        'strategy': 'momentum_breakout',
        'ticker': '7203',
        'action': 'buy',
        'quantity': 100
    },
    validation={
        'passed': True,
        'checks': ['risk_limit', 'market_hours', 'ticker_valid']
    },
    result={
        'status': 'SUCCESS',
        'detail': 'Signal generated and sent to clients'
    },
    checksum='abc123...',
    trace_id='trace-123456'
)
```

---

## 4. ログレベル定義

### 4.1 ログレベル一覧

| レベル | 用途 | 出力先 | 例 |
|--------|------|--------|-----|
| **DEBUG** | 開発・デバッグ情報 | ファイル | Function entry/exit, Variable values |
| **INFO** | 通常の動作情報 | ファイル + コンソール | Signal generated, Order submitted |
| **WARNING** | 警告情報 | ファイル + コンソール | Retry attempted, Deprecated usage |
| **ERROR** | エラー情報 | ファイル + コンソール + アラート | API call failed, Validation failed |
| **CRITICAL** | 致命的エラー | ファイル + コンソール + アラート + 緊急通知 | System down, Kill switch triggered |

### 4.2 環境別ログレベル設定

| 環境 | ファイル | コンソール |
|------|---------|-----------|
| **開発（Development）** | DEBUG | DEBUG |
| **ステージング（Staging）** | INFO | INFO |
| **本番（Production）** | INFO | WARNING |

---

## 5. ログフォーマット

### 5.1 Excel側ログフォーマット

**タイムスタンプ形式**: `YYYY-MM-DD HH:MM:SS`

**例**: `2025-01-27 09:05:30`

**VBA実装**:

```vba
Function FormatTimestamp(dt As Date) As String
    FormatTimestamp = Format(dt, "YYYY-MM-DD HH:NN:SS")
End Function
```

### 5.2 Server側ログフォーマット

**タイムスタンプ形式**: ISO 8601 with timezone

**例**: `2025-01-27T09:05:30.123456+09:00`

**Python実装**:

```python
from datetime import datetime

def format_timestamp() -> str:
    return datetime.now().isoformat()
```

---

## 6. ログローテーション

### 6.1 Excel側ログローテーション

**方式**: シート内の古いデータを別シートへ移動

**実装**:

```vba
Sub ArchiveOldLogs()
    '
    ' 古いログをアーカイブ
    '
    On Error Resume Next

    Dim logsToArchive As Variant
    logsToArchive = Array("SignalLog", "ErrorLog", "SystemLog")

    Dim i As Integer
    For i = LBound(logsToArchive) To UBound(logsToArchive)
        Dim sheetName As String
        sheetName = logsToArchive(i)

        Call ArchiveLogSheet(sheetName, 90)  ' 90日以前を アーカイブ
    Next i
End Sub

Sub ArchiveLogSheet(sheetName As String, daysToKeep As Integer)
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets(sheetName)

    Dim archiveDate As Date
    archiveDate = DateAdd("d", -daysToKeep, Date)

    ' アーカイブシートを作成（存在しなければ）
    Dim archiveSheetName As String
    archiveSheetName = sheetName & "_Archive"

    Dim archiveWs As Worksheet
    On Error Resume Next
    Set archiveWs = ThisWorkbook.Sheets(archiveSheetName)
    If archiveWs Is Nothing Then
        Set archiveWs = ThisWorkbook.Sheets.Add
        archiveWs.Name = archiveSheetName

        ' ヘッダーをコピー
        ws.Rows(1).Copy archiveWs.Rows(1)
    End If
    On Error GoTo 0

    ' 古いログを移動
    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row

    Dim i As Long
    For i = lastRow To 2 Step -1
        Dim logDate As Date
        logDate = ws.Cells(i, 2).Value  ' B列: timestamp

        If logDate < archiveDate Then
            ' アーカイブシートの最終行を取得
            Dim archiveLastRow As Long
            archiveLastRow = archiveWs.Cells(archiveWs.Rows.Count, 1).End(xlUp).Row + 1

            ' 行をコピー
            ws.Rows(i).Copy archiveWs.Rows(archiveLastRow)

            ' 元の行を削除
            ws.Rows(i).Delete
        End If
    Next i

    Debug.Print "ArchiveLog: " & sheetName & " - Archived logs older than " & daysToKeep & " days"
End Sub
```

**定期実行**: 毎日深夜0時に自動実行

```vba
Sub ScheduleDailyArchive()
    Dim nextRun As Date
    nextRun = DateValue(Date + 1) + TimeValue("00:00:00")

    Application.OnTime nextRun, "ArchiveOldLogs"
End Sub
```

### 6.2 Server側ログローテーション

**方式**: TimedRotatingFileHandler（日次ローテーション）

**Python実装**:

```python
import logging
import logging.handlers

def setup_rotating_logger(name: str, filename: str, days_to_keep: int = 90) -> logging.Logger:
    logger = logging.getLogger(name)
    logger.setLevel(logging.INFO)

    handler = logging.handlers.TimedRotatingFileHandler(
        filename=f'logs/{filename}',
        when='midnight',
        interval=1,
        backupCount=days_to_keep,
        encoding='utf-8'
    )

    handler.setFormatter(JSONFormatter())
    logger.addHandler(handler)

    return logger
```

**ファイル名例**:
- `app.log`（今日）
- `app.log.2025-01-26`（昨日）
- `app.log.2025-01-25`（2日前）
- ...

---

## 7. ログ分析・監視

### 7.1 ログ分析クエリ

**Excel側分析（VBA）**:

```vba
Function CountErrorsByCategory(category As String, startDate As Date, endDate As Date) As Integer
    '
    ' カテゴリ別エラー件数を集計
    '
    On Error Resume Next

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("ErrorLog")

    Dim count As Integer
    count = 0

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim logDate As Date
        Dim logCategory As String

        logDate = ws.Cells(i, 2).Value
        logCategory = ws.Cells(i, 4).Value

        If logCategory = category And logDate >= startDate And logDate <= endDate Then
            count = count + 1
        End If
    Next i

    CountErrorsByCategory = count
End Function

Function GetDailyOrderStats(targetDate As Date) As Dictionary
    '
    ' 日次注文統計を取得
    '
    On Error Resume Next

    Dim stats As New Dictionary
    stats("total_orders") = 0
    stats("buy_orders") = 0
    stats("sell_orders") = 0
    stats("filled_orders") = 0
    stats("rejected_orders") = 0
    stats("total_amount") = 0

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("OrderHistory")

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim orderDate As Date
        orderDate = ws.Cells(i, 2).Value

        If DateValue(orderDate) = DateValue(targetDate) Then
            stats("total_orders") = stats("total_orders") + 1

            Dim action As String
            action = ws.Cells(i, 5).Value
            If action = "buy" Then
                stats("buy_orders") = stats("buy_orders") + 1
            Else
                stats("sell_orders") = stats("sell_orders") + 1
            End If

            Dim orderStatus As String
            orderStatus = ws.Cells(i, 10).Value
            If orderStatus = "filled" Then
                stats("filled_orders") = stats("filled_orders") + 1
                stats("total_amount") = stats("total_amount") + ws.Cells(i, 12).Value * ws.Cells(i, 11).Value
            ElseIf orderStatus = "rejected" Then
                stats("rejected_orders") = stats("rejected_orders") + 1
            End If
        End If
    Next i

    Set GetDailyOrderStats = stats
End Function
```

### 7.2 アラート設定

**Excel側アラート**:

```vba
Sub CheckAlertsAndNotify()
    '
    ' アラート条件をチェックして通知
    '
    On Error Resume Next

    ' 1. 過去1時間のエラー件数チェック
    Dim errorCount As Integer
    errorCount = CountErrorsInLastHour()

    If errorCount >= 10 Then
        Call SendAlert("CRITICAL", "High error rate detected: " & errorCount & " errors in last hour")
    End If

    ' 2. 日次損失チェック
    Dim dailyPnL As Double
    dailyPnL = CalculateDailyPnL()

    If dailyPnL <= -50000 Then
        Call SendAlert("CRITICAL", "Daily loss limit reached: " & Format(dailyPnL, "#,##0") & " yen")
        Call ActivateKillSwitch("Daily loss limit exceeded")
    End If

    ' 3. API接続状態チェック
    Dim apiStatus As String
    apiStatus = GetSystemState("api_connection_status")

    If apiStatus = "Disconnected" Then
        Call SendAlert("ERROR", "API connection lost")
    End If
End Sub

Sub SendAlert(severity As String, message As String)
    '
    ' アラート送信（デバッグ出力 + システムログ）
    '
    Debug.Print "!!! ALERT [" & severity & "] " & message

    Call LogSystemEvent("WARNING", "ALERT", "Alert triggered", message)

    ' TODO: メール通知、Slack通知などを実装
End Sub
```

**Server側アラート（Python）**:

```python
import logging

class AlertHandler(logging.Handler):
    """重大なログをアラート通知するハンドラー"""

    def emit(self, record: logging.LogRecord):
        if record.levelno >= logging.ERROR:
            # アラート送信処理
            self.send_alert(record)

    def send_alert(self, record: logging.LogRecord):
        # TODO: Slack、メールなどで通知
        print(f"!!! ALERT [{record.levelname}] {record.getMessage()}")

# ロガーに追加
logger = logging.getLogger('app')
alert_handler = AlertHandler()
alert_handler.setLevel(logging.ERROR)
logger.addHandler(alert_handler)
```

---

## 8. 実装仕様

### 8.1 Module_Logger.bas の拡張

**現在の実装**:
- LogError()
- LogInfo()
- LogWarning()

**追加実装**:

```vba
' SignalLog関連
Public Function LogSignalReceived(signal As Dictionary) As String
Public Sub UpdateSignalStatus(signalId As String, status As String, Optional errorMsg As String = "")
Public Sub MarkSignalACKSent(signalId As String)

' OrderHistory関連
Public Function LogOrderSubmitted(signal As Dictionary, orderParams As Dictionary, rssOrderId As String) As String
Public Sub UpdateOrderExecution(internalOrderId As String, filledQty As Integer, filledPrice As Double, commission As Double)
Public Sub UpdateOrderStatus(internalOrderId As String, status As String, Optional rejectReason As String = "")

' ExecutionLog関連
Public Sub LogExecution(signal As Dictionary, orderInfo As Dictionary, executionInfo As Dictionary)

' ErrorLog関連
Public Sub LogError(severity As String, category As String, moduleName As String, functionName As String, _
                    errorCode As String, errorMessage As String, Optional errorDetail As String = "", _
                    Optional signalId As String = "", Optional ticker As String = "", _
                    Optional actionTaken As String = "", Optional killSwitchTriggered As Boolean = False)

' SystemLog関連
Public Sub LogSystemEvent(level As String, category As String, eventName As String, message As String, _
                          Optional moduleName As String = "", Optional functionName As String = "", _
                          Optional details As String = "")

' AuditLog関連
Public Sub LogAudit(operation As String, operator As String, result As String, resultDetail As String, _
                    Optional signalId As String = "", Optional internalOrderId As String = "", _
                    Optional ticker As String = "", Optional action As String = "", _
                    Optional quantity As Integer = 0, Optional price As Double = 0, _
                    Optional validationPassed As Boolean = True, Optional safetyChecks As String = "", _
                    Optional riskChecks As String = "", Optional checksum As String = "")

' ユーティリティ
Public Function FormatTimestamp(dt As Date) As String
Public Sub ArchiveOldLogs()
Public Sub CheckAlertsAndNotify()
```

### 8.2 Server側ロギング設定

**relay_server/app/core/logging_config.py**:

```python
import logging
import logging.handlers
from pathlib import Path

def setup_logging(log_dir: str = "logs", environment: str = "production"):
    """ロギングの初期設定"""

    # ログディレクトリ作成
    Path(log_dir).mkdir(parents=True, exist_ok=True)

    # ルートロガー設定
    root_logger = logging.getLogger()
    root_logger.setLevel(logging.DEBUG if environment == "development" else logging.INFO)

    # app.log
    setup_rotating_logger('app', f'{log_dir}/app.log', days_to_keep=90)

    # signal.log
    setup_rotating_logger('signal_generator', f'{log_dir}/signal.log', days_to_keep=90)

    # api.log
    setup_rotating_logger('api', f'{log_dir}/api.log', days_to_keep=30)

    # error.log (ERROR以上のみ)
    setup_error_logger(f'{log_dir}/error.log', days_to_keep=90)

    # audit.log
    setup_rotating_logger('audit', f'{log_dir}/audit.log', days_to_keep=365)

def setup_rotating_logger(name: str, filename: str, days_to_keep: int = 90) -> logging.Logger:
    logger = logging.getLogger(name)

    handler = logging.handlers.TimedRotatingFileHandler(
        filename=filename,
        when='midnight',
        interval=1,
        backupCount=days_to_keep,
        encoding='utf-8'
    )

    handler.setFormatter(JSONFormatter())
    logger.addHandler(handler)

    return logger

def setup_error_logger(filename: str, days_to_keep: int = 90):
    logger = logging.getLogger('error')

    handler = logging.handlers.TimedRotatingFileHandler(
        filename=filename,
        when='midnight',
        interval=1,
        backupCount=days_to_keep,
        encoding='utf-8'
    )

    handler.setFormatter(JSONFormatter())
    handler.setLevel(logging.ERROR)
    logger.addHandler(handler)
```

---

## まとめ

### 実装済み

- ✅ Module_Logger.bas の基本機能
- ✅ ErrorLog シート
- ✅ OrderHistory シート

### 実装必要

1. **Excel側**:
   - SignalLog シートの追加
   - ExecutionLog シートの追加
   - SystemLog シートの追加
   - AuditLog シートの追加
   - Module_Logger.bas の拡張（18関数追加）
   - ログアーカイブ機能
   - アラート機能

2. **Server側**:
   - logging_config.py の実装
   - JSONFormatter の実装
   - APILoggingMiddleware の実装
   - ログローテーション設定
   - アラート通知機能

### ログ設計の特徴

- ✅ **完全な追跡可能性**: Signal ID で全ライフサイクルを追跡
- ✅ **二重記録**: Excel + Server 両側で記録
- ✅ **監査対応**: 永久保存のAuditLog
- ✅ **自動アーカイブ**: 古いログは自動的にアーカイブ
- ✅ **アラート機能**: 異常検知時に自動通知
- ✅ **分析機能**: 日次統計、エラー集計など

---

**設計完了日**: 2025-12-27
