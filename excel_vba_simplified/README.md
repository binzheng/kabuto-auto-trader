# Kabuto Auto Trader - Simplified Excel VBA

## 概要

このディレクトリには、**注文実行のみに特化した簡略版Excel VBAモジュール**が含まれています。

従来のExcel VBAは多機能でしたが、以下の機能をRelay Serverに移行しました：
- ✅ 5段階セーフティチェック
- ✅ シグナル検証（ティッカー、数量、売買区分）
- ✅ リスク制限チェック
- ✅ Kill Switch管理
- ✅ クールダウン管理
- ✅ 日次制限チェック
- ✅ 通知機能（Slack/メール）

**Excel VBA側の責任**：
- ✅ Relay Serverから検証済みシグナルを取得
- ✅ MarketSpeed II RSS経由で注文実行
- ✅ 実行結果をRelay Serverに報告

---

## アーキテクチャ比較

### 旧アーキテクチャ（問題点）
```
TradingView
    ↓
[Excel VBA] ← 多機能すぎる
    ├→ シグナル取得
    ├→ 5段階セーフティチェック
    ├→ リスク検証
    ├→ RSS注文実行
    ├→ ポジション管理
    ├→ 通知送信
    └→ ログ記録
```

### 新アーキテクチャ（責任分離）
```
TradingView
    ↓
[Relay Server] ← ビジネスロジック中枢
    ├→ シグナル受信
    ├→ 5段階セーフティ検証
    ├→ リスク制限チェック
    ├→ DB保存（Signal/Position/ExecutionLog）
    ├→ 通知送信（Slack/メール）
    └→ 検証済みシグナル配信
         ↓
    [Excel VBA] ← 注文実行のみ
         ├→ GET /api/signals/pending (5秒ごと)
         ├→ RSS注文実行（RssStockOrder_v）
         └→ POST /api/signals/{id}/executed
```

---

## モジュール構成

### 簡略版モジュール（3個）

| モジュール | 役割 | 行数 |
|-----------|------|------|
| **Module_Main_Simple.bas** | ポーリングループと注文実行 | ~200行 |
| **Module_API_Simple.bas** | API通信（4エンドポイント） | ~150行 |
| **Module_Config_Simple.bas** | 設定管理 | ~50行 |

**合計: 約400行**（従来の約1/5）

### 削除されたモジュール

| モジュール | 理由 |
|-----------|------|
| Module_Main.bas | ポーリングロジックを簡略化 |
| Module_SignalProcessor.bas | Relay Serverでシグナル処理 |
| Module_Notification.bas | Relay Serverで通知送信 |
| Module_RSS.bas（大部分） | 5段階セーフティ削除 |
| Module_OrderManager.bas（大部分） | ポジション管理はRelay Server |
| Module_Logger.bas（大部分） | ロギングはRelay Server |

---

## セットアップ手順

### 1. Relay Serverの設定

`relay_server/config.yaml` を作成：

```yaml
server:
  host: 0.0.0.0
  port: 5000
  debug: false

security:
  webhook_secret: "your_tradingview_secret"
  api_key: "your_api_key_here"
  admin_password: "admin_password"

database:
  url: "sqlite:///./data/kabuto.db"

redis:
  host: localhost
  port: 6379
  db: 0

alerts:
  enabled: true
  slack_webhook_urls:
    INFO: "https://hooks.slack.com/services/YOUR/INFO/WEBHOOK"
    WARNING: "https://hooks.slack.com/services/YOUR/WARNING/WEBHOOK"
    ERROR: "https://hooks.slack.com/services/YOUR/ERROR/WEBHOOK"
    CRITICAL: "https://hooks.slack.com/services/YOUR/CRITICAL/WEBHOOK"
  email_smtp_host: "smtp.gmail.com"
  email_smtp_port: 587
  email_smtp_user: "your_email@gmail.com"
  email_smtp_password: "your_app_password"
  email_from: "kabuto@example.com"
  email_recipients:
    - "trader@example.com"
  frequency_limits:
    WARNING: 30
    ERROR: 15
    INFO: 60

risk_control:
  max_total_exposure: 1000000
  max_position_per_ticker: 200000
  max_open_positions: 5
  max_daily_entries: 5
  max_daily_trades: 15
  max_consecutive_losses: 5
  max_daily_loss: -50000
```

### 2. Relay Serverの起動

```bash
cd relay_server
python app/main.py
```

### 3. Excel VBAのインポート

1. Excelファイルを開く
2. Alt+F11でVBAエディタを開く
3. 以下のモジュールをインポート：
   - `Module_Main_Simple.bas`
   - `Module_API_Simple.bas`
   - `Module_Config_Simple.bas`

### 4. Excelシートの作成

必要なシート：
- **Config**: API設定
  - A列: キー、B列: 値
  - `API_BASE_URL` → `http://localhost:5000`
  - `API_KEY` → `your_api_key_here`
  - `CLIENT_ID` → `excel_vba_01`

- **OrderLog**: 注文ログ
  - A列: Timestamp
  - B列: Signal ID
  - C列: Ticker
  - D列: Action
  - E列: Order ID
  - F列: Status
  - G列: Reason (失敗時)

### 5. 起動

VBAエディタで以下を実行：

```vba
Sub Test()
    ' 接続テスト
    If Not API_TestConnection() Then
        MsgBox "Relay Server接続失敗"
        Exit Sub
    End If

    ' ポーリング開始
    Call StartPolling
End Sub
```

---

## データフロー

### 正常フロー

```
1. TradingView → Relay Server
   POST /webhook
   {
     "action": "buy",
     "ticker": "7203",
     "quantity": 100,
     "passphrase": "secret"
   }

2. Relay Server: 5段階セーフティ検証
   Level 1: Kill Switch ✓
   Level 2: Market Hours ✓
   Level 3: Parameter Validation ✓
   Level 4: Daily Limits ✓
   Level 5: Risk Limits ✓

   → DB保存 (state = PENDING)

3. Excel VBA: ポーリング (5秒ごと)
   GET /api/signals/pending
   ← 検証済みシグナル返却

4. Excel VBA: ACK送信
   POST /api/signals/{signal_id}/ack

5. Excel VBA: RSS注文実行
   RssStockOrder_v() → MarketSpeed II

6. Excel VBA: 実行報告
   POST /api/signals/{signal_id}/executed
   {
     "order_id": "ORD_20260110123045_007203",
     "execution_price": 1850.0,
     "execution_quantity": 100
   }

7. Relay Server:
   - Signal state → EXECUTED
   - ExecutionLog記録
   - Position更新
   - 通知送信（Slack）
```

### エラーハンドリング

```
1. Excel VBA: RSS注文失敗
   RssStockOrder_v() → Error

2. Excel VBA: 失敗報告
   POST /api/signals/{signal_id}/failed
   {
     "error": "RSS connection timeout"
   }

3. Relay Server:
   - Signal state → FAILED
   - エラーログ記録
   - 通知送信（Slack/メール）
   - 連続失敗カウント更新

4. Relay Server: 連続失敗が5回以上
   → Kill Switch自動発動
   → CRITICAL通知（@channel）
```

---

## セーフティシステム

### Relay Server側（5段階）

**Level 1: Kill Switch**
- システム全体の停止スイッチ
- 連続失敗（5回以上）で自動発動
- 日次損失（-5万円以上）で自動発動
- 手動でも発動可能

**Level 2: Market Hours**
- 安全な取引時間帯のみ許可
- 午前: 9:30-11:20
- 午後: 13:00-14:30

**Level 3: Parameter Validation**
- ティッカー: 4桁数字、ブラックリスト確認
- 数量: 100株単位、100-10,000株
- 売買区分: buy/sellのみ
- 価格タイプ: marketのみ
- 売り注文: ポジション確認

**Level 4: Daily Limits**
- 日次エントリー制限（デフォルト: 5回）
- 日次取引制限（デフォルト: 15回）
- 時間当たり取引制限（デフォルト: 5回）

**Level 5: Risk Limits**
- 最大エクスポージャー（デフォルト: 100万円）
- ティッカー当たり最大ポジション（デフォルト: 20万円）
- 最大オープンポジション数（デフォルト: 5銘柄）
- 日次最大損失（デフォルト: -5万円）

### Excel VBA側（なし）

**Excel側では追加の検証を行いません。**
- Relay Serverで検証済みシグナルをそのまま実行
- RSS注文実行のみに専念
- シンプルで高速

---

## 通知システム

### Slack通知

**INFO**（緑）:
- システム起動

**WARNING**（黄）:
- 発注失敗（1回）
- クールダウン中

**ERROR**（赤）:
- 連続発注失敗（3回以上）
- Heartbeat途絶
- エラー頻発

**CRITICAL**（赤+@channel）:
- Kill Switch発動
- システム停止

### メール通知

- ERROR以上の場合にメール送信
- HTML形式で見やすく表示

### 通知頻度制限

- WARNING: 30分に1回
- ERROR: 15分に1回
- INFO: 60分に1回
- CRITICAL: 常に送信（制限なし）

---

## トラブルシューティング

### Relay Serverに接続できない

```vba
' VBAエディタで実行
Debug.Print API_TestConnection()
' → False の場合:
'   - Relay Serverが起動しているか確認
'   - ポート5000が開いているか確認
'   - Config シートのAPI_BASE_URLを確認
```

### シグナルが取得できない

1. Relay Serverのログ確認:
```bash
tail -f relay_server/data/logs/kabuto_*.log
```

2. TradingViewからのWebhook送信確認:
```bash
# Relay Serverのアクセスログ
grep "POST /webhook" relay_server/data/logs/kabuto_*.log
```

3. 検証失敗の確認:
```bash
# 5段階セーフティで拒否されたシグナル
grep "failed validation" relay_server/data/logs/kabuto_*.log
```

### RSS注文が失敗する

1. MarketSpeed IIが起動しているか確認
2. RSS機能が有効か確認
3. ログイン状態を確認
4. Excel VBAのOrderLogシートで失敗理由を確認

---

## まとめ

### メリット

✅ **責任分離**: Excel VBAは注文実行のみ
✅ **保守性向上**: VBAコードが1/5に削減
✅ **テスト容易**: Relay Server側でユニットテスト可能
✅ **スケール可能**: 複数のExcelクライアントからRelay Serverに接続可能
✅ **監査ログ**: 全てのシグナル・実行ログがDBに保存
✅ **通知統合**: Slack/メールでリアルタイム通知

### デメリット

⚠️ **Relay Server依存**: Relay Serverが停止するとExcel VBAは機能しない
⚠️ **ネットワーク遅延**: API経由のため若干の遅延（通常<100ms）

### 推奨構成

- Relay Server: 常時起動（Dockerまたはsystemdで管理）
- Excel VBA: トレーディング時間中のみ起動
- Redis: キャッシュ・クールダウン管理用
- PostgreSQL: 本番環境ではSQLiteの代わりに推奨

---

## ライセンス

Proprietary - All rights reserved
