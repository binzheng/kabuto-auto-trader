# 全自動売買システム 日次運用フロー

**文書番号**: doc/22
**作成日**: 2025-12-27
**対象**: Kabuto Auto Trader 全自動売買システム

---

## 目次

1. [前提条件](#前提条件)
2. [朝の起動手順（8:00-9:30）](#朝の起動手順800-930)
3. [市場中の監視（9:30-15:00）](#市場中の監視930-1500)
4. [夕方の停止手順（15:00-18:00）](#夕方の停止手順1500-1800)
5. [日次レポート確認](#日次レポート確認)
6. [異常時の対応フロー](#異常時の対応フロー)
7. [週次・月次メンテナンス](#週次月次メンテナンス)
8. [トラブルシューティング](#トラブルシューティング)

---

## 前提条件

### システム構成

```
┌─────────────────────┐
│  TradingView        │  クラウド上の戦略
│  (Pine Script)      │  ↓ Webhook
└─────────────────────┘
          ↓
┌─────────────────────┐
│  Relay Server       │  VPS上のFastAPIサーバー
│  (Python/FastAPI)   │  ↓ HTTP API
└─────────────────────┘
          ↓
┌─────────────────────┐
│  Excel VBA Client   │  Windows PC上のExcelマクロ
│  (Excel + VBA)      │  ↓ COM
└─────────────────────┘
          ↓
┌─────────────────────┐
│  MarketSpeed II     │  楽天証券取引ツール
│  (RSS)              │
└─────────────────────┘
```

### 必要な環境

**VPS（Relay Server用）**:
- OS: Ubuntu 22.04 LTS
- Python: 3.11+
- FastAPI, Uvicorn稼働中
- ポート: 8000（外部公開）

**Windows PC（Excel VBA Client用）**:
- OS: Windows 10/11
- Excel: 2016以降（VBA有効）
- MarketSpeed II: インストール済み、RSS有効
- インターネット接続: 安定

**通知環境**:
- Slack Webhook URL設定済み
- SMTP設定済み（Gmail等）

---

## 朝の起動手順（8:00-9:30）

### 8:00 - サーバー起動確認

#### 1. VPS接続・サーバー状態確認

```bash
ssh user@your-vps-server

# サーバープロセス確認
ps aux | grep uvicorn

# ログ確認（最新20行）
tail -n 20 /var/log/kabuto/relay_server.log
```

#### 2. サーバー起動（停止している場合）

```bash
cd /path/to/kabuto/relay_server
source venv/bin/activate

# バックグラウンド起動
nohup uvicorn app.main:app --host 0.0.0.0 --port 8000 >> /var/log/kabuto/relay_server.log 2>&1 &
```

#### 3. サーバーヘルスチェック

```bash
# ヘルスエンドポイント確認
curl http://localhost:8000/health

# 期待結果: {"status": "healthy"}
```

#### 4. Slack通知確認

サーバー起動時に以下の通知が届くことを確認:

```
ℹ️ システム起動
起動時刻: 2025-12-27 08:00:00
```

---

### 8:15 - Windows PC 起動準備

#### 1. MarketSpeed II 起動

```
1. MarketSpeed II を起動
2. ログイン（楽天証券ID/パスワード）
3. RSS が有効になっていることを確認
   - メニュー: ツール > RSS設定 > 「RSS機能を有効にする」チェック
```

#### 2. Excel ブック起動

```
1. Kabuto Auto Trader.xlsm を開く
2. マクロ有効化の警告が出た場合: 「コンテンツの有効化」をクリック
3. Config シートを開く
```

#### 3. 設定確認（Config シート）

| 設定項目 | 確認内容 | 備考 |
|---------|---------|------|
| `API_BASE_URL` | `http://your-vps-ip:8000` | VPSのIPアドレス |
| `CLIENT_ID` | `CLIENT-001`（等） | 一意のクライアントID |
| `SLACK_WEBHOOK_*` | Webhook URL設定済み | 4レベル分 |
| `SMTP_*` | SMTP設定済み | Gmail等 |
| `KILL_SWITCH_ACTIVE` | `FALSE` | 手動Kill Switchが無効 |
| `MAX_DAILY_LOSS` | `-50000` | 日次損失限度（円） |
| `MAX_TRADES_PER_HOUR` | `10` | 1時間当たり最大取引数 |

---

### 8:30 - システム接続テスト

#### 1. API接続テスト

```vba
' Excel VBA の イミディエイトウィンドウ（Ctrl + G）で実行:

? CheckAPIConnection()
' 期待結果: True
```

#### 2. RSS接続テスト

```vba
' イミディエイトウィンドウで実行:

? CheckRSSConnection()
' 期待結果: True
```

#### 3. SystemState シート確認

| 項目 | 期待値 | 備考 |
|------|-------|------|
| `system_status` | `idle` | 起動前はidle |
| `api_connection` | `connected` | API接続OK |
| `rss_connection` | `connected` | RSS接続OK |
| `last_heartbeat` | （最新時刻） | Heartbeat送信済み |
| `kill_switch_active` | `FALSE` | Kill Switch無効 |

---

### 9:00 - 起動前最終チェック

#### チェックリスト

- [ ] VPS Relay Server 起動中（`ps aux | grep uvicorn`）
- [ ] MarketSpeed II ログイン済み、RSS有効
- [ ] Excel VBA API接続OK（`CheckAPIConnection() = True`）
- [ ] Excel VBA RSS接続OK（`CheckRSSConnection() = True`）
- [ ] Slack通知正常（システム起動通知受信済み）
- [ ] Config設定確認済み（Kill Switch無効、リミット設定OK）
- [ ] 前日の未決済ポジションなし（または把握済み）

---

### 9:20 - 自動売買開始

#### 1. Excel VBA 自動売買開始

```
1. Dashboard シートを開く
2. 「自動売買開始」ボタンをクリック
```

または

```vba
' イミディエイトウィンドウで実行:
StartAutoTrading
```

#### 2. 起動確認

**SystemState シート**:
- `system_status`: `idle` → `running`
- `last_poll_time`: （最新時刻に更新中）

**Slack通知**:
```
ℹ️ システムイベント
イベント: 自動売買開始
市場セッション: morning-auction
システム状態: running
```

#### 3. ログ確認（SystemLog シート）

| log_id | level | category | event | system_status |
|--------|-------|----------|-------|---------------|
| SYS-20251227-090000 | INFO | STARTUP | 自動売買開始 | running |

---

## 市場中の監視（9:30-15:00）

### 自動実行される処理

#### ポーリング（5秒間隔）

```
1. PollAndProcessSignals() が自動実行
2. サーバーから pending signals を取得（GET /api/signals/pending）
3. 受信したシグナルを SignalQueue に追加
4. ProcessNextSignal() でキューから1件取り出し
5. SafeExecuteOrder() で6層防御チェック → RSS発注
6. ACK送信（POST /api/signals/{id}/ack）
```

#### Heartbeat（5分間隔）

```
1. SendHeartbeat() が自動実行
2. サーバーに生存確認送信（POST /api/heartbeat）
3. SystemState の last_heartbeat を更新
```

---

### 監視項目

#### 1. Slack/Email通知監視

**INFO（緑）**: 情報通知
```
ℹ️ システムイベント
イベント: シグナル受信
銘柄: 7203 (トヨタ自動車)
```
→ **対応**: 特になし、正常動作

**WARNING（黄）**: 警告
```
⚠️ 発注失敗
Signal ID: SIG-20251227-001
銘柄: 7203
失敗理由: 市場時間外
```
→ **対応**: ErrorLog確認、発注タイミング調整検討

**ERROR（赤）**: エラー
```
🚨 連続発注失敗（3回）
失敗回数: 3回
最終シグナル: SIG-20251227-003
失敗理由: RSS接続エラー
```
→ **対応**: RSS接続確認、MarketSpeed II再起動検討

**CRITICAL（鮮紅）**: 緊急
```
🚨🚨🚨 KILL SWITCH 発動
発動理由: 日次損失が閾値を超過（-52,000円）
本日の取引成績: 損益: -52,000円 | 取引回数: 8回
システム状態: ⛔ 全取引停止
```
→ **対応**: 即座に状況確認、手動介入判断

---

#### 2. Dashboard リアルタイム監視

**推奨**: Dashboard シートを常時表示

| 監視項目 | 正常範囲 | 異常時の対応 |
|---------|---------|------------|
| **システム状態** | `running` | `paused`/`stopped` なら原因調査 |
| **API接続** | `connected` | `disconnected` ならサーバー確認 |
| **RSS接続** | `connected` | `disconnected` なら MarketSpeed II 確認 |
| **本日取引回数** | 0-20回 | 20回超過なら異常頻度の可能性 |
| **本日損益** | -50,000円以上 | -50,000円以下で Kill Switch 発動 |
| **最終ポーリング** | 10秒以内 | 30秒以上更新なしは停止の可能性 |
| **最終Heartbeat** | 6分以内 | 10分以上更新なしは通信障害 |

---

#### 3. ログシート定期確認

**10:30, 12:30, 14:30 の1日3回確認推奨**

**SignalLog シート**:
```
最新10件を確認:
- status が "executed" になっているか
- error_message が空欄か
- ack_sent が TRUE か
```

**ErrorLog シート**:
```
本日のエラー件数を確認:
- 1時間に10件以上のエラーがあれば異常
- 同じエラーが連続していれば根本原因調査
```

**OrderHistory シート**:
```
発注状況を確認:
- status が "filled" または "partial" になっているか
- blocked_reason が多数発生していれば防御機構の誤作動の可能性
```

---

#### 4. Kill Switch 監視

**自動トリガー（CheckAutoKillSwitch() が監視）**:

1. **5連続損失**
   - 直近5取引がすべて損失
   - ExecutionLog の pnl がすべてマイナス

2. **日次損失 -50,000円**
   - 本日の累計損益が -50,000円以下
   - Dashboard の「本日損益」で確認

3. **異常頻度（1時間10回）**
   - 直近1時間の取引が10回以上
   - OrderHistory のタイムスタンプで確認

**Kill Switch 発動時の対応**:
```
1. Slack/Email で CRITICAL 通知受信
2. Dashboard で system_status = "stopped" を確認
3. ErrorLog/AuditLog で発動理由を確認
4. 原因分析（戦略の問題 or システムの問題）
5. 再開判断:
   - 戦略の問題 → TradingView戦略を修正
   - システムの問題 → システム設定を修正
6. 再開（手動）:
   - Config シートで KILL_SWITCH_ACTIVE = FALSE に設定
   - Dashboard で「自動売買開始」ボタンをクリック
```

---

### 正常動作時のログ例

**9:35 - シグナル受信・発注成功**

```
【SignalLog】
log_id: SL-20251227-001
timestamp: 2025-12-27 09:35:10
signal_id: SIG-20251227-001
ticker: 7203
action: buy
quantity: 100
status: executed
ack_sent: TRUE

【OrderHistory】
internal_order_id: ORD-20251227-001
signal_id: SIG-20251227-001
rss_order_id: 12345678
ticker: 7203
side: buy
quantity: 100
status: filled
filled_quantity: 100
filled_price: 2850.0

【ExecutionLog】
execution_id: EXE-20251227-001
signal_id: SIG-20251227-001
ticker: 7203
action: buy
quantity: 100
price: 2850.0
commission: 198
```

**10:15 - 売却・利益確定**

```
【ExecutionLog】
execution_id: EXE-20251227-002
signal_id: SIG-20251227-002
ticker: 7203
action: sell
quantity: 100
price: 2870.0
commission: 198
pnl: 1604  # (2870-2850)*100 - 198*2 = 2000 - 396 = 1604
```

---

## 夕方の停止手順（15:00-18:00）

### 15:05 - 自動売買停止

#### 1. 未決済ポジション確認

**CurrentPositions シート**:
```
- quantity > 0 のポジションがあるか確認
- ある場合: 翌日持ち越しまたは手動決済を判断
```

#### 2. 自動売買停止

```
1. Dashboard シートを開く
2. 「自動売買停止」ボタンをクリック
```

または

```vba
' イミディエイトウィンドウで実行:
StopAutoTrading
```

#### 3. 停止確認

**SystemState シート**:
- `system_status`: `running` → `stopped`

**Slack通知**:
```
🚨 システム停止
停止理由: 手動停止
停止時刻: 2025-12-27 15:05:00
```

---

### 15:10 - 本日の取引レビュー

#### Dashboard 確認

| 項目 | 確認内容 |
|------|---------|
| **本日取引回数** | 正常範囲（0-20回）内か |
| **本日損益** | プラスまたは許容範囲内のマイナスか |
| **勝率** | 50%以上が目安 |
| **最大ドローダウン** | -50,000円以内か |

#### ExecutionLog 集計

```vba
' 本日の取引サマリー取得（手動実装が必要な場合）

Sub DailySummary()
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("ExecutionLog")

    Dim totalTrades As Long
    Dim winTrades As Long
    Dim totalPnL As Double
    Dim today As String
    today = Format(Date, "YYYY-MM-DD")

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, "A").End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        If InStr(ws.Cells(i, 2).Value, today) > 0 Then
            If ws.Cells(i, 9).Value = "sell" Then ' action = sell
                totalTrades = totalTrades + 1
                Dim pnl As Double
                pnl = ws.Cells(i, 20).Value ' pnl列
                totalPnL = totalPnL + pnl
                If pnl > 0 Then winTrades = winTrades + 1
            End If
        End If
    Next i

    Debug.Print "本日取引回数: " & totalTrades
    Debug.Print "勝ちトレード: " & winTrades
    Debug.Print "勝率: " & Format(winTrades / totalTrades, "0.0%")
    Debug.Print "本日損益: " & Format(totalPnL, "#,##0") & "円"
End Sub
```

---

### 15:30 - エラーログ確認

#### ErrorLog シート

```
1. 本日のエラー件数を確認
2. severity = "ERROR" または "CRITICAL" の件数をチェック
3. 同じエラーが頻発していないか確認
4. 必要に応じて原因調査・対策
```

**よくあるエラーと対策**:

| エラー | 原因 | 対策 |
|-------|------|------|
| `RSS connection failed` | MarketSpeed II 接続断 | RSS設定確認、MarketSpeed II再起動 |
| `API timeout` | サーバー応答遅延 | サーバー負荷確認、タイムアウト設定見直し |
| `Duplicate signal` | 重複防止機構作動 | 正常動作、対応不要 |
| `Order blocked: Time check failed` | 時間外発注試行 | TradingView戦略のアラート時間確認 |
| `Order blocked: Risk limit exceeded` | リスク限度超過 | Config の MAX_POSITION_SIZE 見直し |

---

### 16:00 - ログアーカイブ（自動）

**ArchiveOldLogs() が自動実行**（1日1回）:

```
- 90日以上前のログを _Archive シートに移動
- SignalLog → SignalLog_Archive
- OrderHistory → OrderHistory_Archive
- ExecutionLog → ExecutionLog_Archive
- SystemLog → SystemLog_Archive
- AuditLog → AuditLog_Archive
- ErrorLog → ErrorLog_Archive
```

**手動実行**（必要な場合）:

```vba
ArchiveOldLogs
```

---

### 17:00 - サーバーログ確認（任意）

#### VPS接続・ログ確認

```bash
ssh user@your-vps-server

# 本日のサーバーログ確認
tail -n 100 /var/log/kabuto/relay_server.log

# エラーログ抽出
grep "ERROR\|CRITICAL" /var/log/kabuto/relay_server.log | tail -n 20
```

**確認項目**:
- Heartbeat 途絶の警告がないか
- Signal generation エラーがないか
- Database 接続エラーがないか

---

### 17:30 - Excel ブック保存・終了

```
1. Excel ブックを保存（Ctrl + S）
2. バックアップ作成（任意）:
   - ファイル名: Kabuto Auto Trader_YYYYMMDD.xlsm
   - 保存先: バックアップフォルダ
3. Excel を終了
```

---

### 18:00 - MarketSpeed II 終了

```
1. MarketSpeed II を終了
2. Windows PC をシャットダウンまたはスリープ
```

---

## 日次レポート確認

### 取引成績サマリー

**Dashboard シート** または **ExecutionLog シート** から以下を確認:

| 指標 | 計算方法 | 目標値 |
|------|---------|-------|
| **取引回数** | 本日の売却件数 | 3-10回 |
| **勝率** | 勝ちトレード数 / 総トレード数 | 50%以上 |
| **平均利益** | 総損益 / 総トレード数 | +500円以上 |
| **最大利益** | max(pnl) | - |
| **最大損失** | min(pnl) | -5,000円以内 |
| **総損益** | sum(pnl) | プラス |
| **手数料合計** | sum(commission) | - |
| **純損益** | sum(pnl) - sum(commission) | プラス |

---

### リスク指標

| 指標 | 確認内容 | 警告レベル |
|------|---------|----------|
| **最大ドローダウン** | 本日の最大含み損 | -50,000円以上 |
| **Kill Switch 発動** | 本日の発動回数 | 1回以上で要調査 |
| **連続損失** | 最大連続損失回数 | 5回以上で要調査 |
| **発注ブロック回数** | OrderHistory の blocked 件数 | 10回以上で設定見直し |

---

### 日次レポート自動生成（実装例）

```vba
Sub GenerateDailyReport()
    ' 日次レポートを DailyReports シートに記録

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("DailyReports")

    Dim nextRow As Long
    nextRow = ws.Cells(ws.Rows.Count, "A").End(xlUp).Row + 1

    ws.Cells(nextRow, 1).Value = Date ' 日付
    ws.Cells(nextRow, 2).Value = GetDailyTradeCount() ' 取引回数
    ws.Cells(nextRow, 3).Value = GetDailyWinRate() ' 勝率
    ws.Cells(nextRow, 4).Value = GetDailyPnL() ' 総損益
    ws.Cells(nextRow, 5).Value = GetMaxDrawdown() ' 最大DD
    ws.Cells(nextRow, 6).Value = GetKillSwitchCount() ' Kill Switch回数

    Debug.Print "日次レポート生成完了: " & Date
End Sub
```

---

## 異常時の対応フロー

### 1. API接続断

**症状**:
- Dashboard の `api_connection` = `disconnected`
- Slack通知: `🚨 API接続断`

**対応手順**:

```
1. VPS サーバー確認
   ssh user@your-vps-server
   ps aux | grep uvicorn

2. サーバー再起動（停止している場合）
   cd /path/to/kabuto/relay_server
   source venv/bin/activate
   nohup uvicorn app.main:app --host 0.0.0.0 --port 8000 >> /var/log/kabuto/relay_server.log 2>&1 &

3. Excel VBA で再接続確認
   ? CheckAPIConnection()

4. 接続回復しない場合:
   - ファイアウォール設定確認
   - VPSのネットワーク確認
   - Config の API_BASE_URL 確認
```

---

### 2. RSS接続断

**症状**:
- Dashboard の `rss_connection` = `disconnected`
- 発注失敗: `RSS connection failed`

**対応手順**:

```
1. MarketSpeed II 確認
   - MarketSpeed II が起動しているか
   - ログイン済みか
   - RSS が有効になっているか

2. MarketSpeed II 再起動
   - MarketSpeed II を終了
   - 再度起動・ログイン
   - RSS を有効化

3. Excel VBA で再接続確認
   ? CheckRSSConnection()

4. 接続回復しない場合:
   - Windows ファイアウォール確認
   - COM オブジェクト登録確認
   - MarketSpeed II のバージョン確認
```

---

### 3. Kill Switch 誤作動

**症状**:
- Slack通知: `🚨🚨🚨 KILL SWITCH 発動`
- しかし実際には異常なし

**対応手順**:

```
1. AuditLog で発動理由を確認
   operation = "KILL_SWITCH"
   result_detail を確認

2. 発動理由が妥当か判断:

   【理由: 5連続損失】
   - ExecutionLog で直近5件の pnl を確認
   - 本当に5連続損失か検証
   - 妥当なら戦略を見直し

   【理由: 日次損失 -50,000円】
   - Dashboard の「本日損益」を確認
   - 本当に -50,000円以下か検証
   - 妥当なら閾値を見直し（Config の MAX_DAILY_LOSS）

   【理由: 異常頻度】
   - OrderHistory で直近1時間の取引件数を確認
   - 本当に10回以上か検証
   - 妥当なら閾値を見直し（Config の MAX_TRADES_PER_HOUR）

3. 誤作動の場合:
   - Config で閾値を調整
   - CheckAutoKillSwitch() のロジックを見直し

4. 再開:
   - Config で KILL_SWITCH_ACTIVE = FALSE
   - Dashboard で「自動売買開始」をクリック
```

---

### 4. シグナル重複エラー

**症状**:
- ErrorLog: `Duplicate signal: SIG-XXXXXX`
- 発注されない

**対応手順**:

```
1. SignalQueue シート確認
   - 同じ signal_id が複数あるか

2. ExecutionLog シート確認
   - 同じ signal_id が already_executed か

3. 原因特定:
   【正常動作】
   - 重複防止機構が正しく作動
   - TradingView が同じアラートを複数送信
   → 対応不要

   【異常動作】
   - SignalQueue のクリーンアップが動作していない
   - CleanupCompletedSignals() を手動実行

4. TradingView 側の修正（必要な場合）:
   - Pine Script のアラート条件を見直し
   - "Once Per Bar Close" 設定を確認
```

---

### 5. サーバー Heartbeat 途絶

**症状**:
- Slack通知: `🚨 Heartbeat途絶`
- `last_heartbeat` が10分以上更新されない

**対応手順**:

```
1. Excel VBA の動作確認
   - Dashboard の system_status が "running" か確認
   - 停止していれば StartAutoTrading で再開

2. API接続確認
   ? CheckAPIConnection()
   接続OKなら Heartbeat 自動回復

3. サーバー側ログ確認
   ssh user@your-vps-server
   grep "heartbeat" /var/log/kabuto/relay_server.log | tail -n 20

4. Heartbeat エンドポイント確認
   curl -X POST http://localhost:8000/api/heartbeat \
     -H "Content-Type: application/json" \
     -d '{"client_id": "CLIENT-001"}'
```

---

## 週次・月次メンテナンス

### 週次タスク（毎週日曜日）

#### 1. パフォーマンスレビュー

```
- ExecutionLog から週次集計
- 総損益、勝率、最大DD を確認
- 戦略のパフォーマンス評価
```

#### 2. ログアーカイブ確認

```
- _Archive シートのデータ量確認
- 必要に応じてエクスポート（CSV等）
```

#### 3. Excelブックバックアップ

```
- Kabuto Auto Trader_YYYYMMDD.xlsm として保存
- クラウドストレージにアップロード（Google Drive等）
```

#### 4. サーバーログローテーション

```bash
ssh user@your-vps-server

# ログファイルのバックアップ
cp /var/log/kabuto/relay_server.log /var/log/kabuto/relay_server_$(date +%Y%m%d).log

# 古いログ削除（30日以上前）
find /var/log/kabuto/ -name "relay_server_*.log" -mtime +30 -delete
```

---

### 月次タスク（毎月1日）

#### 1. 月次パフォーマンスレポート

```
- 月次の総損益、勝率、取引回数を集計
- 戦略別のパフォーマンス分析
- TradingView 戦略の最適化検討
```

#### 2. システムアップデート

```
【VPS サーバー】
sudo apt update
sudo apt upgrade

【Python パッケージ】
cd /path/to/kabuto/relay_server
source venv/bin/activate
pip list --outdated
pip install --upgrade <package-name>

【Windows PC】
- MarketSpeed II のアップデート確認
- Excel のアップデート確認
```

#### 3. 設定見直し

```
【Config シート】
- MAX_DAILY_LOSS: 月次成績に応じて調整
- MAX_TRADES_PER_HOUR: 取引頻度に応じて調整
- MAX_POSITION_SIZE: 資金量に応じて調整

【TradingView 戦略】
- バックテスト結果に基づくパラメータ調整
- 新戦略の追加検討
```

#### 4. セキュリティチェック

```
- VPS SSH キーの更新
- Slack Webhook URL の有効性確認
- SMTP パスワードの変更検討
```

---

## トラブルシューティング

### よくある問題と解決策

#### Q1. シグナルが来ない

**確認項目**:
```
1. TradingView のアラート設定
   - Webhook URL が正しいか
   - アラート条件が適切か

2. Relay Server の稼働
   - ps aux | grep uvicorn
   - curl http://your-vps-ip:8000/health

3. Excel VBA のポーリング
   - Dashboard の last_poll_time が更新されているか
   - system_status が "running" か
```

---

#### Q2. 発注されない

**確認項目**:
```
1. SignalQueue にシグナルがあるか
   - ある場合: 処理が停止している可能性
   - ない場合: シグナルが届いていない

2. ErrorLog のエラー内容
   - "Order blocked: ..." → 防御機構が作動
   - "RSS connection failed" → RSS接続断

3. OrderHistory の blocked_reason
   - Time check failed → 時間外
   - Risk limit exceeded → リスク限度超過
   - Duplicate order → 重複注文
```

---

#### Q3. 約定しない

**確認項目**:
```
1. OrderHistory の status
   - "submitted" → MarketSpeed II で注文確認
   - "partial" → 一部約定、残りは未約定

2. MarketSpeed II の注文照会
   - 注文が登録されているか
   - 約定待ち or キャンセル済みか

3. 価格設定
   - limit_price が適切か（成行ならN/A）
   - 市場価格と乖離していないか
```

---

#### Q4. Excel が固まる

**対応**:
```
1. タスクマネージャーでプロセス確認
   - Excel の CPU 使用率が100%なら無限ループの可能性

2. VBA デバッグモードで停止
   - Ctrl + Break → デバッグモードに移行
   - どの関数で固まっているか確認

3. Excel 強制終了
   - タスクマネージャー → Excel プロセスを終了
   - 再起動後、autosave ファイルから復元

4. 原因調査
   - ErrorLog で直前のエラーを確認
   - PollAndProcessSignals() の無限ループ確認
```

---

#### Q5. サーバーが応答しない

**対応**:
```
1. VPS 接続確認
   ssh user@your-vps-server
   接続できない場合: VPS プロバイダーのコンソール確認

2. プロセス確認
   ps aux | grep uvicorn
   プロセスがない場合: サーバー再起動

3. ポート確認
   netstat -tulpn | grep 8000
   ポート8000が LISTEN していない場合: サーバー再起動

4. ログ確認
   tail -n 100 /var/log/kabuto/relay_server.log
   エラーがあれば対処
```

---

## 付録: チェックリスト印刷用

### 朝の起動チェックリスト

```
日付: ___________  担当: ___________

[ ] 8:00 VPS サーバー起動確認（ps aux | grep uvicorn）
[ ] 8:00 サーバーログ確認（tail -n 20）
[ ] 8:00 Slack システム起動通知受信
[ ] 8:15 MarketSpeed II 起動・ログイン
[ ] 8:15 MarketSpeed II RSS有効確認
[ ] 8:15 Excel ブック起動（マクロ有効化）
[ ] 8:30 Config シート設定確認（Kill Switch無効等）
[ ] 8:30 API接続テスト（CheckAPIConnection = True）
[ ] 8:30 RSS接続テスト（CheckRSSConnection = True）
[ ] 8:30 SystemState シート確認
[ ] 9:00 前日未決済ポジション確認
[ ] 9:20 自動売買開始（StartAutoTrading）
[ ] 9:20 SystemState が "running" 確認
[ ] 9:20 Slack 起動通知受信

備考:
_______________________________________________________
_______________________________________________________
```

---

### 夕方の停止チェックリスト

```
日付: ___________  担当: ___________

[ ] 15:05 未決済ポジション確認（CurrentPositions）
[ ] 15:05 自動売買停止（StopAutoTrading）
[ ] 15:05 SystemState が "stopped" 確認
[ ] 15:05 Slack 停止通知受信
[ ] 15:10 Dashboard 本日損益確認: _________円
[ ] 15:10 Dashboard 本日取引回数確認: _________回
[ ] 15:10 ExecutionLog 勝率確認: _________%
[ ] 15:30 ErrorLog エラー件数確認: _________件
[ ] 15:30 重大エラー（ERROR/CRITICAL）: _________件
[ ] 17:00 サーバーログ確認（任意）
[ ] 17:30 Excel ブック保存
[ ] 17:30 バックアップ作成（任意）
[ ] 18:00 MarketSpeed II 終了

備考:
_______________________________________________________
_______________________________________________________
```

---

## まとめ

この日次運用フローに従うことで、Kabuto Auto Trader を安全かつ効率的に運用できます。

**重要ポイント**:

1. **朝の起動前チェックは必須**
   - API/RSS接続確認
   - Config設定確認
   - 前日ポジション確認

2. **市場中は Slack/Email 通知を監視**
   - CRITICAL 通知は即座に対応
   - ERROR 通知は原因調査

3. **夕方の停止後はレビュー**
   - 本日の取引成績確認
   - エラーログ確認
   - 翌日への改善検討

4. **異常時は慌てず対応フロー通りに**
   - Kill Switch は安全装置として正常動作
   - ログを確認して根本原因を特定

5. **週次・月次メンテナンスを怠らない**
   - バックアップ
   - パフォーマンスレビュー
   - システムアップデート

---

**次のステップ**:

1. この運用フローを印刷して手元に置く
2. 初日はチェックリストに沿って慎重に実施
3. 1週間運用して問題点を洗い出し
4. 必要に応じてフローをカスタマイズ

**問い合わせ**:
システムに関する質問は doc/01-21 を参照してください。
