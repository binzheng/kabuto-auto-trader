# 12. Windows Excel向けシグナル出力仕様

## 目的

Windows VM上のExcel VBA（MarketSpeed II RSS連携）が、サーバーから注文シグナルを安全に取得するための出力仕様を定義する。

- **Pull方式**: ExcelがサーバーからシグナルをPull（能動的に取得）
- **再取得安全性**: 同じシグナルを複数回取得しても重複発注しない
- **Excel VBA親和性**: HTTPRequest / FileSystemObject で容易に処理可能
- **状態管理**: シグナルのライフサイクル管理（PENDING → FETCHED → EXECUTED）

---

## 1. 出力方式の比較

### 1.1 方式別評価

| 方式 | メリット | デメリット | 推奨度 |
|------|----------|------------|--------|
| **JSON API (Pull)** | ・RESTful設計<br>・状態管理容易<br>・認証統合可能 | ・Excel VBAでHTTPリクエスト必要<br>・ネットワーク依存 | ★★★★★ |
| **CSV ファイル** | ・Excel親和性最高<br>・VBA実装簡単<br>・ネットワーク不要 | ・同時アクセス制御困難<br>・状態管理が複雑 | ★★★☆☆ |
| **JSON ファイル** | ・構造化データ<br>・拡張性高い | ・VBAでJSON解析必要<br>・ファイルロック問題 | ★★☆☆☆ |

### 1.2 推奨方式

**主方式: JSON API (HTTP Pull)**
- サーバーがRESTful APIを提供
- Excel VBAが `MSXML2.XMLHTTP60` でポーリング（5-10秒間隔）
- シグナル状態をサーバー側で管理

**副方式: CSV ファイル（フォールバック）**
- ネットワーク障害時の代替手段
- 共有フォルダ経由でファイル配信
- アトミック書き込みで整合性担保

---

## 2. JSON API Pull 設計

### 2.1 エンドポイント設計

#### GET `/api/signals/pending`
未取得の注文シグナル一覧を取得

**Request**
```http
GET /api/signals/pending HTTP/1.1
Host: relay-server.local:5000
Authorization: Bearer <api_key>
```

**Response (200 OK)**
```json
{
  "status": "success",
  "timestamp": "2025-12-27T09:35:12+09:00",
  "count": 2,
  "signals": [
    {
      "signal_id": "sig_20251227_093510_9984_buy",
      "action": "buy",
      "ticker": "9984",
      "quantity": 100,
      "price": "market",
      "entry_price": 3000.50,
      "stop_loss": 2940.25,
      "take_profit": 3120.75,
      "atr": 30.12,
      "state": "pending",
      "created_at": "2025-12-27T09:35:10+09:00",
      "expires_at": "2025-12-27T09:50:10+09:00",
      "checksum": "a3f8b9c2e1d4..."
    },
    {
      "signal_id": "sig_20251227_093512_6758_buy",
      "action": "buy",
      "ticker": "6758",
      "quantity": 50,
      "price": "market",
      "entry_price": 12500.00,
      "stop_loss": 12250.00,
      "take_profit": 13000.00,
      "atr": 125.50,
      "state": "pending",
      "created_at": "2025-12-27T09:35:12+09:00",
      "expires_at": "2025-12-27T09:50:12+09:00",
      "checksum": "c7d2e9a1f5b3..."
    }
  ]
}
```

**Response (204 No Content)** - シグナルなし
```http
HTTP/1.1 204 No Content
```

---

#### POST `/api/signals/{signal_id}/ack`
シグナルを取得済み（FETCHED）としてマーク

**Request**
```http
POST /api/signals/sig_20251227_093510_9984_buy/ack HTTP/1.1
Host: relay-server.local:5000
Authorization: Bearer <api_key>
Content-Type: application/json

{
  "client_id": "excel_vm_01",
  "checksum": "a3f8b9c2e1d4..."
}
```

**Response (200 OK)**
```json
{
  "status": "success",
  "signal_id": "sig_20251227_093510_9984_buy",
  "state": "fetched",
  "acknowledged_at": "2025-12-27T09:35:15+09:00"
}
```

**役割**:
- シグナル状態を `pending` → `fetched` に更新
- 次回 `/pending` リクエストで返さない（重複防止）
- checksum検証で改ざん検出

---

#### POST `/api/signals/{signal_id}/executed`
シグナルを執行済み（EXECUTED）としてマーク

**Request**
```http
POST /api/signals/sig_20251227_093510_9984_buy/executed HTTP/1.1
Authorization: Bearer <api_key>
Content-Type: application/json

{
  "client_id": "excel_vm_01",
  "execution_price": 3001.00,
  "execution_quantity": 100,
  "order_id": "20251227-00123456",
  "executed_at": "2025-12-27T09:35:18+09:00"
}
```

**Response (200 OK)**
```json
{
  "status": "success",
  "signal_id": "sig_20251227_093510_9984_buy",
  "state": "executed",
  "execution_logged": true
}
```

---

#### GET `/api/signals/{signal_id}`
特定シグナルの詳細取得（再取得用）

**Use Case**:
- Excel VBAがクラッシュして復旧した場合
- 執行確認のための再取得

**Response (200 OK)**
```json
{
  "status": "success",
  "signal": {
    "signal_id": "sig_20251227_093510_9984_buy",
    "action": "buy",
    "ticker": "9984",
    "quantity": 100,
    "price": "market",
    "state": "fetched",
    "fetched_by": "excel_vm_01",
    "fetched_at": "2025-12-27T09:35:15+09:00",
    "created_at": "2025-12-27T09:35:10+09:00"
  }
}
```

---

### 2.2 シグナル状態遷移

```
┌─────────┐
│ PENDING │  ← サーバーがTradingView Webhookから作成
└────┬────┘
     │ GET /api/signals/pending (Excel VBA)
     ▼
┌─────────┐
│ FETCHED │  ← POST /api/signals/{id}/ack
└────┬────┘
     │ Excel VBAがRSS.ORDER()実行
     ▼
┌──────────┐
│ EXECUTED │  ← POST /api/signals/{id}/executed
└────┬─────┘
     │ 15分後に自動削除 or アーカイブ
     ▼
┌──────────┐
│ ARCHIVED │
└──────────┘
```

**状態別保持時間**:
- `PENDING`: 15分（`expires_at`経過で自動削除）
- `FETCHED`: 30分（Excel VBAが執行完了報告するまで）
- `EXECUTED`: 24時間（ログ確認用）
- `ARCHIVED`: 90日（監査証跡）

---

### 2.3 整合性保証メカニズム

#### A. Checksum検証

**生成方法（サーバー側）**:
```python
import hashlib
import json

def generate_signal_checksum(signal: dict) -> str:
    """シグナルの改ざん検出用チェックサム生成"""
    # 重要フィールドのみを使用（state/timestampは除外）
    core_fields = {
        "signal_id": signal["signal_id"],
        "action": signal["action"],
        "ticker": signal["ticker"],
        "quantity": signal["quantity"],
        "entry_price": signal["entry_price"],
        "stop_loss": signal["stop_loss"],
        "take_profit": signal["take_profit"]
    }

    # 辞書順ソート → JSON文字列化 → SHA256
    canonical = json.dumps(core_fields, sort_keys=True, separators=(',', ':'))
    return hashlib.sha256(canonical.encode('utf-8')).hexdigest()[:16]
```

**検証（Excel VBA側）**:
```vba
' チェックサム一致確認（簡易版 - サーバー側で主検証）
Function VerifyChecksum(signalId As String, receivedChecksum As String) As Boolean
    ' Excel VBAでは再計算せず、サーバーの /ack エンドポイントで検証
    ' サーバーが200 OKを返せば正常と判断
    VerifyChecksum = True
End Function
```

**検証タイミング**:
- `/ack` リクエスト時にサーバー側で検証
- チェックサム不一致 → `400 Bad Request` 返却

---

#### B. べき等性保証

**同じシグナルを複数回取得しても安全**:

1. **GET `/pending` の冪等性**
   - `PENDING` 状態のシグナルのみ返却
   - 一度 `FETCHED` になったら返さない

2. **POST `/ack` の冪等性**
   - 同じ `signal_id` に対する複数回の `/ack` → 2回目以降は `200 OK` + 同じレスポンス
   - 状態は `FETCHED` のまま（重複更新なし）

3. **POST `/executed` の冪等性**
   - 同じ `signal_id` に対する複数回の `/executed` → 2回目以降は `409 Conflict`
   - 理由: 同じシグナルで2回発注してはいけない

---

#### C. Expiration（有効期限）

**シグナルの自動失効**:
```json
{
  "signal_id": "sig_20251227_093510_9984_buy",
  "created_at": "2025-12-27T09:35:10+09:00",
  "expires_at": "2025-12-27T09:50:10+09:00",  // 15分後
  "state": "pending"
}
```

**失効処理**:
```python
def cleanup_expired_signals():
    """有効期限切れシグナルの自動削除"""
    now = datetime.now(timezone.utc)

    expired_signals = db.query(Signal).filter(
        Signal.state == "pending",
        Signal.expires_at < now
    ).all()

    for signal in expired_signals:
        signal.state = "expired"
        signal.deleted_at = now
        logger.warning(f"Signal expired: {signal.signal_id}")

    db.commit()

# Schedulerで1分毎に実行
schedule.every(1).minutes.do(cleanup_expired_signals)
```

**理由**:
- 古いシグナルを無限に保持しない
- 取引時間外のシグナルを自動削除
- Excel VBAが長時間停止していた場合の保護

---

## 3. CSV ファイル Pull 設計（フォールバック）

### 3.1 ファイル形式

**ファイルパス**:
```
\\relay-server\kabuto\signals\pending\signal_20251227_093510.csv
\\relay-server\kabuto\signals\executed\signal_20251227_093510.csv
```

**CSV フォーマット**:
```csv
signal_id,action,ticker,quantity,price,entry_price,stop_loss,take_profit,atr,created_at,checksum
sig_20251227_093510_9984_buy,buy,9984,100,market,3000.50,2940.25,3120.75,30.12,2025-12-27T09:35:10+09:00,a3f8b9c2e1d4
```

**ヘッダー行**: 必須（Excel VBAで列名参照）

---

### 3.2 アトミック書き込み

**問題**: CSVファイル書き込み中にExcelが読み込むと不整合

**解決策: Atomic File Write**
```python
import os
import tempfile
import shutil

def write_signal_csv_atomic(signals: list, output_path: str):
    """
    一時ファイルに書き込み → 完了後にリネーム（アトミック操作）
    """
    # 1. 一時ファイルに書き込み
    temp_fd, temp_path = tempfile.mkstemp(
        suffix='.csv',
        dir=os.path.dirname(output_path)
    )

    try:
        with os.fdopen(temp_fd, 'w', newline='', encoding='utf-8-sig') as f:
            writer = csv.DictWriter(f, fieldnames=[...])
            writer.writeheader()
            writer.writerows(signals)

        # 2. アトミックリネーム（Windows: replace=True）
        shutil.move(temp_path, output_path)

    except Exception as e:
        os.remove(temp_path)  # 失敗時はクリーンアップ
        raise
```

**Windows SMBでの注意**:
- `shutil.move()` はWindows SMB共有でもアトミック
- Excel VBAは常に完全なファイルを読み込める

---

### 3.3 ファイルベース状態管理

**ディレクトリ構造**:
```
\\relay-server\kabuto\signals\
├── pending\          ← Excel VBAが監視
│   ├── signal_20251227_093510.csv
│   └── signal_20251227_093512.csv
├── fetched\          ← Excel VBAが移動
│   └── signal_20251227_093510.csv
└── executed\         ← Excel VBAが最終移動
    └── signal_20251227_093510.csv
```

**状態遷移 = ファイル移動**:
1. サーバーが `pending\` にファイル作成
2. Excel VBAが読み込み → `fetched\` に移動
3. RSS.ORDER()実行 → `executed\` に移動

**Excel VBA例**:
```vba
Sub MoveSignalFile(fileName As String, fromFolder As String, toFolder As String)
    Dim fso As Object
    Set fso = CreateObject("Scripting.FileSystemObject")

    Dim sourcePath As String
    Dim destPath As String

    sourcePath = fromFolder & "\" & fileName
    destPath = toFolder & "\" & fileName

    If fso.FileExists(sourcePath) Then
        fso.MoveFile sourcePath, destPath
    End If

    Set fso = Nothing
End Sub
```

---

### 3.4 CSV ロック制御

**読み取り専用オープン**（Excel VBA側）:
```vba
Function ReadSignalCSV(filePath As String) As Variant
    Dim fso As Object
    Dim ts As Object
    Dim content As String

    Set fso = CreateObject("Scripting.FileSystemObject")

    ' 読み取り専用でオープン（書き込みロックしない）
    Set ts = fso.OpenTextFile(filePath, 1, False, -1)  ' ForReading=1
    content = ts.ReadAll
    ts.Close

    ' CSV解析処理...
    ReadSignalCSV = ParseCSV(content)

    Set ts = Nothing
    Set fso = Nothing
End Function
```

**ポイント**:
- `ForReading=1` で読み取り専用
- サーバー側のアトミック書き込みと組み合わせて安全

---

## 4. Excel VBA 実装例

### 4.1 JSON API Pull（推奨）

#### VBA: シグナル取得 + RSS発注

```vba
Option Explicit

' ----- 定数 -----
Const API_BASE_URL As String = "http://relay-server.local:5000/api"
Const API_KEY As String = "your-api-key-here"
Const CLIENT_ID As String = "excel_vm_01"

' ----- メインルーチン（Timerで5秒毎に実行） -----
Sub PollAndExecuteSignals()
    On Error GoTo ErrorHandler

    ' 1. 未取得シグナルをAPI取得
    Dim signals As Collection
    Set signals = FetchPendingSignals()

    If signals.Count = 0 Then
        Debug.Print "No pending signals"
        Exit Sub
    End If

    ' 2. 各シグナルを処理
    Dim signal As Object
    For Each signal In signals
        ' 2-1. シグナル取得確認（ACK）
        If AcknowledgeSignal(signal("signal_id"), signal("checksum")) Then

            ' 2-2. MarketSpeed II RSSで発注
            Dim orderId As String
            orderId = ExecuteOrder(signal)

            If orderId <> "" Then
                ' 2-3. 執行完了報告
                Call ReportExecution(signal("signal_id"), orderId, signal("entry_price"), signal("quantity"))
                Debug.Print "Executed: " & signal("ticker") & " Order=" & orderId
            Else
                Debug.Print "Order failed: " & signal("ticker")
            End If
        End If
    Next signal

    Exit Sub

ErrorHandler:
    Debug.Print "Error in PollAndExecuteSignals: " & Err.Description
End Sub

' ----- API関数群 -----

Function FetchPendingSignals() As Collection
    '
    ' GET /api/signals/pending
    '
    Dim http As Object
    Set http = CreateObject("MSXML2.XMLHTTP.6.0")

    Dim url As String
    url = API_BASE_URL & "/signals/pending"

    http.Open "GET", url, False
    http.setRequestHeader "Authorization", "Bearer " & API_KEY
    http.setRequestHeader "Content-Type", "application/json"
    http.send

    Set FetchPendingSignals = New Collection

    If http.Status = 204 Then
        ' No Content - シグナルなし
        Exit Function
    ElseIf http.Status = 200 Then
        ' JSON解析（JsonConverterライブラリ使用を推奨）
        Dim response As Object
        Set response = JsonConverter.ParseJson(http.responseText)

        Dim signalObj As Variant
        For Each signalObj In response("signals")
            FetchPendingSignals.Add signalObj
        Next signalObj
    Else
        Debug.Print "API Error: " & http.Status & " - " & http.responseText
    End If

    Set http = Nothing
End Function

Function AcknowledgeSignal(signalId As String, checksum As String) As Boolean
    '
    ' POST /api/signals/{signal_id}/ack
    '
    Dim http As Object
    Set http = CreateObject("MSXML2.XMLHTTP.6.0")

    Dim url As String
    url = API_BASE_URL & "/signals/" & signalId & "/ack"

    Dim payload As String
    payload = "{""client_id"":""" & CLIENT_ID & """,""checksum"":""" & checksum & """}"

    http.Open "POST", url, False
    http.setRequestHeader "Authorization", "Bearer " & API_KEY
    http.setRequestHeader "Content-Type", "application/json"
    http.send payload

    If http.Status = 200 Then
        AcknowledgeSignal = True
    Else
        Debug.Print "ACK failed: " & http.Status
        AcknowledgeSignal = False
    End If

    Set http = Nothing
End Function

Function ExecuteOrder(signal As Object) As String
    '
    ' MarketSpeed II RSS発注
    '
    On Error GoTo OrderError

    Dim ticker As String
    Dim quantity As Long
    Dim action As String

    ticker = signal("ticker")
    quantity = CLng(signal("quantity"))
    action = signal("action")

    ' RSS.ORDER関数呼び出し
    Dim orderType As Integer
    orderType = IIf(action = "buy", 1, 2)  ' 1=買い, 2=売り

    Dim result As Variant
    result = Application.Run("RSS.ORDER", _
        ticker, _           ' 銘柄コード
        orderType, _        ' 売買区分
        quantity, _         ' 数量
        0, _                ' 成行（0=成行, 1=指値）
        0, _                ' 価格（成行なので0）
        0 _                 ' 執行条件
    )

    ' result形式: "注文番号:20251227-00123456"
    If InStr(result, "注文番号:") > 0 Then
        ExecuteOrder = Mid(result, InStr(result, ":") + 1)
    Else
        ExecuteOrder = ""
    End If

    Exit Function

OrderError:
    Debug.Print "RSS.ORDER Error: " & Err.Description
    ExecuteOrder = ""
End Function

Sub ReportExecution(signalId As String, orderId As String, price As Double, quantity As Long)
    '
    ' POST /api/signals/{signal_id}/executed
    '
    Dim http As Object
    Set http = CreateObject("MSXML2.XMLHTTP.6.0")

    Dim url As String
    url = API_BASE_URL & "/signals/" & signalId & "/executed"

    Dim payload As String
    payload = "{" & _
        """client_id"":""" & CLIENT_ID & """," & _
        """order_id"":""" & orderId & """," & _
        """execution_price"":" & price & "," & _
        """execution_quantity"":" & quantity & "," & _
        """executed_at"":""" & Format(Now, "yyyy-mm-ddThh:nn:ss+09:00") & """" & _
        "}"

    http.Open "POST", url, False
    http.setRequestHeader "Authorization", "Bearer " & API_KEY
    http.setRequestHeader "Content-Type", "application/json"
    http.send payload

    If http.Status <> 200 Then
        Debug.Print "Execution report failed: " & http.Status
    End If

    Set http = Nothing
End Sub
```

**依存ライブラリ**:
- **JsonConverter** (VBA-JSON): https://github.com/VBA-tools/VBA-JSON
  - Excel VBAでJSON解析に必須

---

### 4.2 CSV ファイル Pull（フォールバック）

```vba
Option Explicit

Const PENDING_FOLDER As String = "\\relay-server\kabuto\signals\pending\"
Const FETCHED_FOLDER As String = "\\relay-server\kabuto\signals\fetched\"
Const EXECUTED_FOLDER As String = "\\relay-server\kabuto\signals\executed\"

Sub PollCSVSignals()
    On Error GoTo ErrorHandler

    Dim fso As Object
    Set fso = CreateObject("Scripting.FileSystemObject")

    Dim folder As Object
    Set folder = fso.GetFolder(PENDING_FOLDER)

    Dim file As Object
    For Each file In folder.Files
        If LCase(fso.GetExtensionName(file.Name)) = "csv" Then

            ' CSVファイル読み込み
            Dim signals As Variant
            signals = ReadCSVFile(file.Path)

            If Not IsEmpty(signals) Then
                ' シグナル処理
                Dim i As Long
                For i = LBound(signals, 1) + 1 To UBound(signals, 1)  ' ヘッダースキップ
                    Dim ticker As String
                    Dim action As String
                    Dim quantity As Long

                    ticker = signals(i, 3)      ' ticker列
                    action = signals(i, 2)      ' action列
                    quantity = CLng(signals(i, 4))

                    ' RSS発注
                    Dim orderId As String
                    orderId = ExecuteOrderCSV(action, ticker, quantity)

                    If orderId <> "" Then
                        Debug.Print "Executed: " & ticker & " Order=" & orderId
                    End If
                Next i

                ' ファイルをfetchedフォルダに移動
                fso.MoveFile file.Path, FETCHED_FOLDER & file.Name

                ' 執行完了後にexecutedフォルダに移動
                fso.MoveFile FETCHED_FOLDER & file.Name, EXECUTED_FOLDER & file.Name
            End If
        End If
    Next file

    Set folder = Nothing
    Set fso = Nothing
    Exit Sub

ErrorHandler:
    Debug.Print "Error: " & Err.Description
End Sub

Function ReadCSVFile(filePath As String) As Variant
    Dim fso As Object
    Dim ts As Object

    Set fso = CreateObject("Scripting.FileSystemObject")
    Set ts = fso.OpenTextFile(filePath, 1, False, -1)  ' ForReading, Unicode

    Dim lines() As String
    Dim content As String
    content = ts.ReadAll
    ts.Close

    lines = Split(content, vbCrLf)

    ' 簡易CSV解析（本番ではCSVパーサー使用推奨）
    Dim rows As Long
    Dim cols As Long
    rows = UBound(lines) + 1
    cols = UBound(Split(lines(0), ",")) + 1

    Dim data() As Variant
    ReDim data(0 To rows - 1, 1 To cols)

    Dim i As Long, j As Long
    For i = 0 To rows - 1
        Dim cells() As String
        cells = Split(lines(i), ",")
        For j = 0 To UBound(cells)
            data(i, j + 1) = cells(j)
        Next j
    Next i

    ReadCSVFile = data

    Set ts = Nothing
    Set fso = Nothing
End Function

Function ExecuteOrderCSV(action As String, ticker As String, quantity As Long) As String
    ' RSS.ORDER呼び出し（JSON版と同じ）
    ' ... (省略)
End Function
```

---

## 5. 再取得時の整合性保証

### 5.1 再取得シナリオ

| シナリオ | Excel VBAの状態 | サーバー対応 |
|----------|----------------|------------|
| **通常ポーリング** | 5秒毎にGET /pending | `PENDING`シグナルのみ返却 |
| **Excel再起動** | 前回の続きから再開 | `FETCHED`シグナルは返さない（重複防止） |
| **ネットワーク断** | `/ack`送信失敗 | 次回GET時に再度`PENDING`として返却 |
| **RSS発注失敗** | `/executed`送信しない | サーバーは`FETCHED`のまま保持（手動確認） |

---

### 5.2 重複発注防止メカニズム

#### A. サーバー側: 状態管理

```python
class SignalState(Enum):
    PENDING = "pending"       # 未取得
    FETCHED = "fetched"       # Excel VBAが取得済み
    EXECUTED = "executed"     # RSS発注済み
    FAILED = "failed"         # 発注失敗
    EXPIRED = "expired"       # 有効期限切れ

class Signal(Base):
    __tablename__ = "signals"

    signal_id = Column(String, primary_key=True)
    state = Column(Enum(SignalState), default=SignalState.PENDING)
    fetched_by = Column(String, nullable=True)   # "excel_vm_01"
    fetched_at = Column(DateTime, nullable=True)
    executed_at = Column(DateTime, nullable=True)
    execution_price = Column(Float, nullable=True)
    order_id = Column(String, nullable=True)

    # タイムスタンプ
    created_at = Column(DateTime, default=datetime.utcnow)
    expires_at = Column(DateTime)  # created_at + 15分

def get_pending_signals():
    """未取得シグナルのみ返却"""
    return db.query(Signal).filter(
        Signal.state == SignalState.PENDING,
        Signal.expires_at > datetime.utcnow()
    ).all()
```

#### B. Excel VBA側: ローカル履歴管理

**発注済みシグナルをExcelシートに記録**:

| signal_id | ticker | action | order_id | executed_at | status |
|-----------|--------|--------|----------|-------------|--------|
| sig_20251227_093510_9984_buy | 9984 | buy | 20251227-00123456 | 2025-12-27 09:35:18 | EXECUTED |

```vba
Sub LogExecutedSignal(signalId As String, ticker As String, orderId As String)
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("ExecutionLog")

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1

    ws.Cells(lastRow, 1).Value = signalId
    ws.Cells(lastRow, 2).Value = ticker
    ws.Cells(lastRow, 3).Value = orderId
    ws.Cells(lastRow, 4).Value = Now
    ws.Cells(lastRow, 5).Value = "EXECUTED"
End Sub

Function IsAlreadyExecuted(signalId As String) As Boolean
    ' ローカルログをチェック
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("ExecutionLog")

    Dim foundCell As Range
    Set foundCell = ws.Columns(1).Find(signalId, LookIn:=xlValues, LookAt:=xlWhole)

    IsAlreadyExecuted = Not foundCell Is Nothing
End Function
```

**再起動時のチェック**:
```vba
Sub PollAndExecuteSignals()
    ' ...
    For Each signal In signals
        ' ローカルログで重複チェック
        If Not IsAlreadyExecuted(signal("signal_id")) Then
            ' 発注処理...
        Else
            Debug.Print "Skipped (already executed): " & signal("signal_id")
        End If
    Next signal
End Sub
```

---

### 5.3 ネットワーク障害時の挙動

#### シナリオ: `/ack` 送信失敗

```
[Excel VBA]
1. GET /pending  → 200 OK (signal_A 取得)
2. POST /ack     → タイムアウト（ネットワーク断）
3. RSS.ORDER()   → 成功（発注済み）
4. POST /executed → タイムアウト

[サーバー]
- signal_A は PENDING のまま（/ack が届いていない）

[次回ポーリング時]
5. GET /pending  → 200 OK (signal_A を再度返却)

[対策]
Excel VBAのローカルログで「すでに発注済み」を検出
→ スキップ + サーバーに /executed を再送
```

**Excel VBA修正版**:
```vba
For Each signal In signals
    If IsAlreadyExecuted(signal("signal_id")) Then
        ' 既に発注済みだがサーバーに報告できていない場合
        ' → /executed を再送
        Call RetryReportExecution(signal("signal_id"))
        Debug.Print "Retried execution report: " & signal("signal_id")
    Else
        ' 通常の発注処理...
    End If
Next signal
```

---

## 6. タイマー起動設定

### 6.1 Excel VBA自動実行

**Application.OnTime を使用**:
```vba
Option Explicit

Dim nextRunTime As Date

Sub StartAutoPolling()
    '
    ' Excelブック起動時に自動実行開始
    '
    nextRunTime = Now + TimeValue("00:00:05")  ' 5秒後
    Application.OnTime nextRunTime, "PollAndExecuteSignals"

    Debug.Print "Auto polling started"
End Sub

Sub StopAutoPolling()
    '
    ' 自動実行停止
    '
    On Error Resume Next
    Application.OnTime nextRunTime, "PollAndExecuteSignals", , False
    Debug.Print "Auto polling stopped"
End Sub

Sub PollAndExecuteSignals()
    On Error GoTo ErrorHandler

    ' シグナル取得 + 発注処理
    ' ... (前述のコード)

    ' 次回実行をスケジュール（5秒後）
    nextRunTime = Now + TimeValue("00:00:05")
    Application.OnTime nextRunTime, "PollAndExecuteSignals"

    Exit Sub

ErrorHandler:
    Debug.Print "Error: " & Err.Description
    ' エラーでも次回実行を継続
    nextRunTime = Now + TimeValue("00:00:10")  ' エラー時は10秒後
    Application.OnTime nextRunTime, "PollAndExecuteSignals"
End Sub
```

**Workbook_Open イベントで自動起動**:
```vba
Private Sub Workbook_Open()
    ' Excelブック起動時に自動ポーリング開始
    Call StartAutoPolling
End Sub

Private Sub Workbook_BeforeClose(Cancel As Boolean)
    ' Excelブック終了時に停止
    Call StopAutoPolling
End Sub
```

---

### 6.2 取引時間外の制御

**市場時間外はポーリング停止**:
```vba
Function IsMarketOpen() As Boolean
    '
    ' 日本市場の取引時間判定
    ' 9:00-11:30, 12:30-15:00（平日のみ）
    '
    Dim currentTime As Date
    currentTime = Now

    ' 週末チェック
    If Weekday(currentTime) = vbSaturday Or Weekday(currentTime) = vbSunday Then
        IsMarketOpen = False
        Exit Function
    End If

    Dim currentHour As Integer
    Dim currentMinute As Integer
    currentHour = Hour(currentTime)
    currentMinute = Minute(currentTime)

    ' 前場: 9:00-11:30
    If currentHour = 9 Or (currentHour = 10) Or (currentHour = 11 And currentMinute <= 30) Then
        IsMarketOpen = True
        Exit Function
    End If

    ' 後場: 12:30-15:00
    If (currentHour = 12 And currentMinute >= 30) Or currentHour = 13 Or currentHour = 14 Then
        IsMarketOpen = True
        Exit Function
    End If

    IsMarketOpen = False
End Function

Sub PollAndExecuteSignals()
    ' 市場時間外はスキップ
    If Not IsMarketOpen() Then
        Debug.Print "Market closed - skipping poll"
        GoTo ScheduleNext
    End If

    ' シグナル取得処理...

ScheduleNext:
    ' 次回実行スケジュール
    nextRunTime = Now + TimeValue("00:00:05")
    Application.OnTime nextRunTime, "PollAndExecuteSignals"
End Sub
```

---

## 7. エラーハンドリング

### 7.1 API エラー対応

**HTTPステータスコード別処理**:
```vba
Function FetchPendingSignals() As Collection
    ' ...
    http.send

    Select Case http.Status
        Case 200
            ' 正常（シグナルあり）
            Set FetchPendingSignals = ParseSignals(http.responseText)

        Case 204
            ' No Content（シグナルなし）
            Set FetchPendingSignals = New Collection

        Case 401
            ' 認証エラー
            MsgBox "API認証エラー: API_KEYを確認してください", vbCritical
            Call StopAutoPolling  ' 自動ポーリング停止

        Case 503
            ' Kill Switch発動
            MsgBox "サーバーがKill Switchモードです", vbExclamation
            Call StopAutoPolling

        Case Else
            ' その他のエラー
            Debug.Print "API Error: " & http.Status & " - " & http.responseText
            ' ポーリングは継続（一時的なエラーの可能性）
    End Select
End Function
```

---

### 7.2 RSS発注エラー対応

**MarketSpeed II エラー処理**:
```vba
Function ExecuteOrder(signal As Object) As String
    On Error GoTo OrderError

    Dim result As Variant
    result = Application.Run("RSS.ORDER", ...)

    ' resultの形式チェック
    If IsError(result) Then
        GoTo OrderError
    End If

    If InStr(result, "エラー") > 0 Or InStr(result, "失敗") > 0 Then
        ' RSS側のエラー
        Debug.Print "RSS Error: " & result

        ' サーバーに失敗報告
        Call ReportOrderFailure(signal("signal_id"), CStr(result))

        ExecuteOrder = ""
    Else
        ' 成功
        ExecuteOrder = ExtractOrderId(result)
    End If

    Exit Function

OrderError:
    Debug.Print "Order Exception: " & Err.Description
    Call ReportOrderFailure(signal("signal_id"), Err.Description)
    ExecuteOrder = ""
End Function

Sub ReportOrderFailure(signalId As String, errorMessage As String)
    ' POST /api/signals/{signal_id}/failed
    Dim http As Object
    Set http = CreateObject("MSXML2.XMLHTTP.6.0")

    Dim url As String
    url = API_BASE_URL & "/signals/" & signalId & "/failed"

    Dim payload As String
    payload = "{""client_id"":""" & CLIENT_ID & """,""error"":""" & errorMessage & """}"

    http.Open "POST", url, False
    http.setRequestHeader "Authorization", "Bearer " & API_KEY
    http.setRequestHeader "Content-Type", "application/json"
    http.send payload

    Set http = Nothing
End Sub
```

**サーバー側: 失敗シグナルの処理**
```python
@app.post("/api/signals/{signal_id}/failed")
def mark_signal_failed(signal_id: str, request: FailureReport):
    signal = db.query(Signal).filter(Signal.signal_id == signal_id).first()

    if not signal:
        raise HTTPException(status_code=404)

    signal.state = SignalState.FAILED
    signal.error_message = request.error
    signal.failed_at = datetime.utcnow()

    db.commit()

    # アラート送信（Slack/Email）
    send_alert(f"Signal execution failed: {signal_id} - {request.error}")

    return {"status": "failure_recorded"}
```

---

## 8. セキュリティ考慮事項

### 8.1 API Key管理

**環境変数またはExcel非表示シート**:
```vba
Function GetAPIKey() As String
    '
    ' 方法1: 非表示シートから読み込み
    '
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("Config")  ' Very Hidden推奨
    GetAPIKey = ws.Range("A1").Value

    '
    ' 方法2: Windowsレジストリから読み込み（より安全）
    '
    ' Dim wsh As Object
    ' Set wsh = CreateObject("WScript.Shell")
    ' GetAPIKey = wsh.RegRead("HKCU\Software\Kabuto\APIKey")
End Function
```

**シートを非表示化**（VBE操作）:
```vba
Sub HideConfigSheet()
    ThisWorkbook.Sheets("Config").Visible = xlSheetVeryHidden
End Sub
```

---

### 8.2 HTTPS通信（本番環境）

**開発環境**: `http://relay-server.local:5000`
**本番環境**: `https://relay-server.local:5000` （自己署名証明書または Let's Encrypt）

**VBAでHTTPS証明書検証スキップ**（開発用のみ）:
```vba
' MSXML2.ServerXMLHTTP.6.0 を使用
Dim http As Object
Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")

' 証明書検証を無効化（自己署名証明書用）
http.setOption 2, 13056  ' SXH_SERVER_CERT_IGNORE_ALL_SERVER_ERRORS

http.Open "GET", "https://relay-server.local:5000/api/signals/pending", False
http.send
```

**本番では証明書検証を有効化**

---

### 8.3 ログ記録

**Excel VBA側のログ**:
```vba
Sub WriteLog(message As String)
    Dim logPath As String
    logPath = "C:\Kabuto\Logs\excel_vba_" & Format(Now, "yyyymmdd") & ".log"

    Dim fso As Object
    Dim ts As Object

    Set fso = CreateObject("Scripting.FileSystemObject")

    ' 追記モード
    If fso.FileExists(logPath) Then
        Set ts = fso.OpenTextFile(logPath, 8)  ' ForAppending=8
    Else
        Set ts = fso.CreateTextFile(logPath, True)
    End If

    ts.WriteLine Format(Now, "yyyy-mm-dd hh:nn:ss") & " | " & message
    ts.Close

    Set ts = Nothing
    Set fso = Nothing
End Sub

' 使用例
Sub PollAndExecuteSignals()
    WriteLog "Polling started"

    Dim signals As Collection
    Set signals = FetchPendingSignals()

    WriteLog "Fetched " & signals.Count & " signals"

    ' ...
End Sub
```

---

## 9. パフォーマンス最適化

### 9.1 ポーリング間隔調整

**市場状況に応じた動的調整**:
```vba
Function GetPollingInterval() As String
    '
    ' 取引時間帯: 5秒
    ' 昼休み: 30秒
    ' 市場終了後: 60秒
    '
    Dim currentHour As Integer
    currentHour = Hour(Now)

    If currentHour >= 9 And currentHour < 12 Then
        GetPollingInterval = "00:00:05"  ' 前場: 5秒
    ElseIf currentHour >= 12 And currentHour < 15 Then
        If Minute(Now) < 30 Then
            GetPollingInterval = "00:00:30"  ' 昼休み: 30秒
        Else
            GetPollingInterval = "00:00:05"  ' 後場: 5秒
        End If
    Else
        GetPollingInterval = "00:01:00"  ' 時間外: 60秒
    End If
End Function

Sub PollAndExecuteSignals()
    ' ...

    ' 動的間隔で次回実行
    nextRunTime = Now + TimeValue(GetPollingInterval())
    Application.OnTime nextRunTime, "PollAndExecuteSignals"
End Sub
```

---

### 9.2 バッチ処理

**複数シグナルの一括発注**:
```vba
Sub BatchExecuteOrders(signals As Collection)
    '
    ' MarketSpeed II のバッチ発注機能を利用
    ' （対応している場合）
    '
    Dim orderArray() As Variant
    ReDim orderArray(1 To signals.Count, 1 To 5)

    Dim i As Long
    i = 1

    Dim signal As Object
    For Each signal In signals
        orderArray(i, 1) = signal("ticker")
        orderArray(i, 2) = IIf(signal("action") = "buy", 1, 2)
        orderArray(i, 3) = signal("quantity")
        orderArray(i, 4) = 0  ' 成行
        orderArray(i, 5) = 0  ' 価格
        i = i + 1
    Next signal

    ' バッチ発注（RSSが対応している場合のみ）
    Dim results As Variant
    results = Application.Run("RSS.BATCH_ORDER", orderArray)

    ' 結果処理...
End Sub
```

---

## 10. まとめ

### 10.1 推奨構成

| 項目 | 推奨方式 | 理由 |
|------|----------|------|
| **主方式** | JSON API Pull | 状態管理容易、セキュリティ高、拡張性高 |
| **副方式** | CSV ファイル | ネットワーク障害時のフォールバック |
| **ポーリング間隔** | 5秒（取引時間）<br>60秒（時間外） | リアルタイム性とサーバー負荷のバランス |
| **認証** | Bearer Token (API Key) | VBAで実装容易、セキュア |
| **状態管理** | サーバー側DB + Excel VBAローカルログ | 2重管理で重複発注防止 |
| **エラー処理** | リトライ + 失敗報告API | 障害時の追跡性担保 |

---

### 10.2 チェックリスト

**サーバー側実装**:
- [ ] GET `/api/signals/pending` エンドポイント
- [ ] POST `/api/signals/{id}/ack` エンドポイント
- [ ] POST `/api/signals/{id}/executed` エンドポイント
- [ ] POST `/api/signals/{id}/failed` エンドポイント
- [ ] シグナル有効期限管理（15分）
- [ ] Checksum生成・検証
- [ ] CSV ファイル出力（フォールバック用）

**Excel VBA実装**:
- [ ] JSON API Poll機能
- [ ] JsonConverterライブラリ導入
- [ ] RSS.ORDER() 呼び出し
- [ ] ローカル実行ログ管理
- [ ] Application.OnTime 自動ポーリング
- [ ] エラーハンドリング
- [ ] 市場時間判定
- [ ] API Key管理（非表示シート or レジストリ）

**テスト項目**:
- [ ] 正常系: シグナル取得 → 発注 → 執行報告
- [ ] 異常系: ネットワーク断 → 再接続 → 重複防止
- [ ] 異常系: RSS発注失敗 → 失敗報告
- [ ] 異常系: Excel再起動 → ローカルログから復旧
- [ ] 負荷テスト: 5秒間隔で24時間ポーリング

---

### 10.3 次のステップ

1. **サーバー実装** (`doc/08_webhook_api_design.md` を拡張)
   - `/api/signals/*` エンドポイント追加
   - Signal モデル + 状態管理ロジック

2. **Excel VBA実装**
   - `kabuto_signal_client.xlsm` 作成
   - JSON API Poll関数群実装
   - MarketSpeed II RSS連携テスト

3. **統合テスト**
   - TradingView → サーバー → Excel → RSS の全体フロー
   - 障害シナリオテスト

4. **監視・アラート**
   - Excel VBA稼働監視（ハートビート）
   - シグナル取得失敗アラート

---

## 付録A: API仕様書（OpenAPI形式）

```yaml
openapi: 3.0.0
info:
  title: Kabuto Signal API for Excel
  version: 1.0.0

paths:
  /api/signals/pending:
    get:
      summary: 未取得シグナル一覧取得
      security:
        - BearerAuth: []
      responses:
        '200':
          description: シグナルあり
          content:
            application/json:
              schema:
                type: object
                properties:
                  status:
                    type: string
                    example: success
                  count:
                    type: integer
                  signals:
                    type: array
                    items:
                      $ref: '#/components/schemas/Signal'
        '204':
          description: シグナルなし

  /api/signals/{signal_id}/ack:
    post:
      summary: シグナル取得確認
      parameters:
        - name: signal_id
          in: path
          required: true
          schema:
            type: string
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                client_id:
                  type: string
                checksum:
                  type: string
      responses:
        '200':
          description: 確認成功

  /api/signals/{signal_id}/executed:
    post:
      summary: 執行完了報告
      parameters:
        - name: signal_id
          in: path
          required: true
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                order_id:
                  type: string
                execution_price:
                  type: number
                execution_quantity:
                  type: integer
      responses:
        '200':
          description: 報告成功

components:
  schemas:
    Signal:
      type: object
      properties:
        signal_id:
          type: string
        action:
          type: string
          enum: [buy, sell]
        ticker:
          type: string
        quantity:
          type: integer
        entry_price:
          type: number
        stop_loss:
          type: number
        take_profit:
          type: number
        state:
          type: string
          enum: [pending, fetched, executed]
        checksum:
          type: string

  securitySchemes:
    BearerAuth:
      type: http
      scheme: bearer
```

---

**このドキュメントで定義した出力仕様により、Excel VBAが安全かつ確実にサーバーからシグナルを取得し、MarketSpeed II RSSで発注できる基盤が整います。**
