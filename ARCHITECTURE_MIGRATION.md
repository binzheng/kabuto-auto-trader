# Kabuto Auto Trader - アーキテクチャ移行ガイド

## 概要

このドキュメントでは、Kabuto Auto Traderのアーキテクチャ変更について説明します。

**変更の目的**:
- Excel VBAの機能を**注文実行のみ**に絞る
- ビジネスロジックをRelay Serverに集約
- 保守性・テスト性・スケーラビリティの向上

---

## アーキテクチャ比較

### 旧アーキテクチャ（問題点）

```
TradingView Webhook
    ↓
┌─────────────────────────────────┐
│ Excel VBA（過剰な責任）         │
│  ├─ シグナル取得                │
│  ├─ 5段階セーフティチェック    │
│  ├─ リスク検証                  │
│  ├─ RSS注文実行                 │
│  ├─ ポジション管理              │
│  ├─ 通知送信（Slack/メール）    │
│  └─ ログ記録                    │
└─────────────────────────────────┘
    ↓
MarketSpeed II (RSS)
```

**問題点**:
- ❌ Excel VBAが多機能すぎる（約2000行）
- ❌ テストが困難（VBAのユニットテストは難しい）
- ❌ 保守が困難（ロジックがVBAに埋め込まれている）
- ❌ スケールしない（1台のExcelでしか動作しない）
- ❌ 監査ログが分散（Excel内とファイル）

### 新アーキテクチャ（責任分離）

```
TradingView Webhook
    ↓
┌─────────────────────────────────────────────┐
│ Relay Server（ビジネスロジック中枢）       │
│  ├─ TradingViewからシグナル受信             │
│  ├─ 5段階セーフティ検証                     │
│  │   Level 1: Kill Switch                    │
│  │   Level 2: Market Hours                   │
│  │   Level 3: Parameter Validation           │
│  │   Level 4: Daily Limits                   │
│  │   Level 5: Risk Limits                    │
│  ├─ クールダウン管理（Redis）               │
│  ├─ ブラックリスト管理                      │
│  ├─ DB保存（Signal/Position/ExecutionLog）  │
│  ├─ 通知送信（Slack/メール）                │
│  └─ 検証済みシグナル配信                    │
└─────────────────────────────────────────────┘
    ↓ API (検証済みシグナルのみ)
┌─────────────────────────────────┐
│ Excel VBA（注文実行のみ）       │
│  ├─ GET /api/signals/pending    │
│  ├─ RSS注文実行                 │
│  └─ POST /api/signals/executed  │
└─────────────────────────────────┘
    ↓
MarketSpeed II (RSS)
```

**メリット**:
- ✅ 責任が明確（Excel = 注文実行、Server = 全ロジック）
- ✅ VBAコードが約1/5に削減（2000行 → 400行）
- ✅ テスト可能（Relay Server側でユニットテスト）
- ✅ 保守容易（Pythonで記述、ロジック変更が容易）
- ✅ スケール可能（複数Excelから同じServerに接続可能）
- ✅ 監査ログ統合（全てDB + Slack通知）

---

## 機能マッピング

### Relay Serverに移行した機能

| 旧（Excel VBA） | 新（Relay Server） | 理由 |
|----------------|-------------------|------|
| Module_Main.bas（ポーリング） | main.py（アプリケーション起動） | サーバー側でシグナル管理 |
| Module_SignalProcessor.bas | webhook.py, signals.py | シグナル処理の集中管理 |
| Module_RSS.bas（5段階セーフティ） | pre_order_validation.py | 検証ロジックの統一 |
| Module_Notification.bas | notification.py | 通知の集中管理 |
| Module_Config.bas（大部分） | config.py, config.yaml | 設定の外部化 |
| Module_Logger.bas（大部分） | logging.py, csv_logger.py | ログの統合 |

### Excel VBA側に残った機能

| モジュール | 機能 | 行数 |
|-----------|------|------|
| Module_Main_Simple.bas | ポーリングループ、注文実行 | ~200行 |
| Module_API_Simple.bas | API通信（4エンドポイント） | ~150行 |
| Module_Config_Simple.bas | 設定読み込み | ~50行 |

**合計: 約400行**（旧: 約2000行）

---

## データフロー詳細

### 1. シグナル受信フロー

```
TradingView Alert
    ↓
POST /webhook
{
  "passphrase": "secret",
  "action": "buy",
  "ticker": "7203",
  "quantity": 100,
  "price": 1850.0,
  "entry_price": 1850.0,
  "stop_loss": 1800.0,
  "take_profit": 1950.0,
  "timestamp": "2026-01-10T09:35:00"
}
    ↓
[Relay Server: webhook.py]
    ├─ パスフレーズ検証
    ├─ 重複排除チェック（Redis）
    ├─ 市場時間チェック
    ├─ クールダウンチェック（Redis）
    ├─ ポジション確認（売りの場合）
    └─ DB保存（state = PENDING）
         signal_id: sig_20260110_093500_7203_buy
```

### 2. 検証フロー（5段階セーフティ）

```
Excel VBA Polling
    ↓
GET /api/signals/pending
Authorization: Bearer <api_key>
    ↓
[Relay Server: signals.py]
    ├─ DB query (state = PENDING, not expired)
    └─ For each signal:
         ↓
    [PreOrderValidationService]
         ├─ Level 1: Kill Switch ✓
         ├─ Level 2: Market Hours ✓
         ├─ Level 3: Parameter Validation ✓
         ├─ Level 4: Daily Limits ✓
         └─ Level 5: Risk Limits ✓
              ↓
         PASS: Return signal to Excel
         FAIL: Mark as REJECTED, log violation
    ↓
Response: 200 OK
{
  "status": "success",
  "count": 1,
  "signals": [
    {
      "signal_id": "sig_20260110_093500_7203_buy",
      "action": "buy",
      "ticker": "7203",
      "quantity": 100,
      "checksum": "a1b2c3d4e5f6g7h8"
    }
  ]
}
```

### 3. 注文実行フロー

```
[Excel VBA]
    ↓
POST /api/signals/{signal_id}/ack
{
  "client_id": "excel_vba_01",
  "checksum": "a1b2c3d4e5f6g7h8"
}
    ↓
[Relay Server]
    └─ Signal state: PENDING → FETCHED
    ↓
[Excel VBA: ExecuteRSSOrder()]
    ↓
RssStockOrder_v(
  order_id="ORD_20260110093510_007203",
  ticker="7203",
  side=3,  # 現物買
  quantity=100,
  price_type=0,  # 成行
  ...
)
    ↓
[MarketSpeed II]
    └─ 注文執行
         ↓
    SUCCESS: order_id="ORD_20260110093510_007203"
    ↓
[Excel VBA]
    ↓
POST /api/signals/{signal_id}/executed
{
  "order_id": "ORD_20260110093510_007203",
  "execution_price": 1850.0,
  "execution_quantity": 100,
  "executed_at": "2026-01-10T09:35:15"
}
    ↓
[Relay Server: signals.py]
    ├─ Signal state: FETCHED → EXECUTED
    ├─ ExecutionLog記録
    ├─ Position更新
    ├─ DailyStats更新
    └─ 通知送信（Slack）
```

### 4. エラーハンドリングフロー

```
[Excel VBA: ExecuteRSSOrder()]
    ↓
RssStockOrder_v() → Error
    ↓
[Excel VBA]
    ↓
POST /api/signals/{signal_id}/failed
{
  "error": "RSS connection timeout"
}
    ↓
[Relay Server: signals.py]
    ├─ Signal state: FETCHED → FAILED
    ├─ error_message記録
    ├─ DailyStats更新（consecutive_losses++）
    └─ 通知送信（Slack/メール）
         ↓
    [RiskControlService]
         └─ 連続失敗 >= 5回?
              YES → Kill Switch自動発動
                   └─ CRITICAL通知（@channel）
```

---

## 5段階セーフティシステム

### Level 1: Kill Switch

**場所**: `relay_server/app/services/kill_switch.py`

**チェック内容**:
- システム全体の停止スイッチが有効か確認
- DB (`SystemConfig` テーブル) で管理

**自動発動条件**:
- 連続失敗が5回以上
- 日次損失が-5万円以上
- 時間当たり取引が10回以上

**手動制御**:
```bash
# 発動
curl -X POST http://localhost:5000/api/admin/kill-switch/activate \
  -H "Content-Type: application/json" \
  -d '{"reason": "Manual stop"}'

# 解除
curl -X POST http://localhost:5000/api/admin/kill-switch/deactivate
```

### Level 2: Market Hours

**場所**: `relay_server/app/services/market_hours.py`

**チェック内容**:
- 現在時刻が安全な取引時間帯か確認
- タイムゾーン: Asia/Tokyo

**安全な取引時間帯**:
- 午前: 9:30-11:20
- 午後: 13:00-14:30

**理由**:
- 寄り付き・引けの急激な値動きを避ける
- 昼休みの流動性不足を避ける

### Level 3: Parameter Validation

**場所**: `relay_server/app/services/pre_order_validation.py`

**チェック内容**:

1. **ティッカーコード**:
   - 4桁の数字か（例: 7203）
   - ブラックリストに含まれていないか

2. **売買区分**:
   - "buy" または "sell" のみ
   - 売り注文の場合、ポジションが存在するか

3. **数量**:
   - 100株単位か
   - 100株以上、10,000株以下
   - 売り注文の場合、保有株数以下か

4. **価格タイプ**:
   - "market"（成行）のみ許可
   - 指値は安全性のため禁止

### Level 4: Daily Limits

**場所**: `relay_server/app/services/pre_order_validation.py`

**チェック内容**:
- 日次エントリー数（デフォルト: 5回）
- 日次取引数（デフォルト: 15回）
- 時間当たり取引数（デフォルト: 5回）

**データソース**: `DailyStats` テーブル

### Level 5: Risk Limits

**場所**: `relay_server/app/services/pre_order_validation.py`

**チェック内容**:

1. **最大エクスポージャー**:
   - 全ポジションの合計金額
   - デフォルト: 100万円

2. **ティッカー当たり最大ポジション**:
   - 単一銘柄の最大金額
   - デフォルト: 20万円

3. **最大オープンポジション数**:
   - 同時保有可能な銘柄数
   - デフォルト: 5銘柄

4. **日次最大損失**:
   - 本日の累積損失
   - デフォルト: -5万円

**データソース**: `Position` テーブル、`DailyStats` テーブル

---

## 通知システム

### Slack通知

**実装**: `relay_server/app/core/notification.py`

**レベル別Webhook URL**:
```yaml
alerts:
  slack_webhook_urls:
    INFO: "https://hooks.slack.com/services/.../INFO"
    WARNING: "https://hooks.slack.com/services/.../WARNING"
    ERROR: "https://hooks.slack.com/services/.../ERROR"
    CRITICAL: "https://hooks.slack.com/services/.../CRITICAL"
```

**通知内容**:

| レベル | 色 | 内容 | 例 |
|--------|---|------|---|
| INFO | 緑 | システム起動 | "システム起動" |
| WARNING | 黄 | 発注失敗（1回） | "発注失敗: 7203 クールダウン中" |
| ERROR | 赤 | 連続発注失敗（3回以上） | "連続発注失敗（5回）" |
| CRITICAL | 赤+@channel | Kill Switch発動 | "🚨🚨🚨 KILL SWITCH 発動" |

### メール通知

**実装**: `relay_server/app/core/notification.py`

**送信条件**: ERROR以上

**フォーマット**: HTML

**内容**:
- エラー種別
- 発生時刻
- 推奨対応
- システムステータス

### 通知頻度制限

**実装**: Redisでタイムスタンプ管理

**制限**:
- INFO: 60分に1回
- WARNING: 30分に1回
- ERROR: 15分に1回
- CRITICAL: 制限なし（常に送信）

**キー**: `notification:last:{level}:{title}`

---

## データベーススキーマ

### Signal テーブル

```python
signal_id: str          # sig_20260110_093500_7203_buy
action: str             # "buy" or "sell"
ticker: str             # "7203"
quantity: int           # 100
price: float            # 1850.0
entry_price: float      # 1850.0
stop_loss: float        # 1800.0
take_profit: float      # 1950.0
state: SignalState      # PENDING/FETCHED/EXECUTED/FAILED/REJECTED
checksum: str           # "a1b2c3d4e5f6g7h8"
created_at: datetime
expires_at: datetime
fetched_by: str         # "excel_vba_01"
fetched_at: datetime
executed_at: datetime
execution_price: float
order_id: str           # "ORD_20260110093510_007203"
error_message: str
```

### ExecutionLog テーブル

```python
execution_id: str       # EXE_20260110_093515_7203
signal_id: str          # sig_20260110_093500_7203_buy
order_id: str           # ORD_20260110093510_007203
action: str             # "buy"
ticker: str             # "7203"
quantity: int           # 100
price: float            # 1850.0
commission: float       # 0
total_amount: float     # 185000.0
position_effect: str    # "open" or "close"
executed_at: datetime
```

### Position テーブル

```python
ticker: str             # "7203"
ticker_name: str        # "トヨタ自動車"
quantity: int           # 100
avg_cost: float         # 1850.0
sector: str             # "自動車"
entry_signal_id: str    # sig_20260110_093500_7203_buy
created_at: datetime
updated_at: datetime
```

### DailyStats テーブル

```python
date: date              # 2026-01-10
entry_count: int        # 3
exit_count: int         # 2
total_trades: int       # 5
total_pnl: float        # 15000.0
consecutive_losses: int # 0
error_count: int        # 0
created_at: datetime
updated_at: datetime
```

---

## セットアップ手順

### 1. 環境準備

```bash
# Python 3.9+
python --version

# Redis
redis-server --version

# PostgreSQL (本番環境推奨)
psql --version
```

### 2. Relay Serverセットアップ

```bash
cd relay_server

# 仮想環境作成
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# 依存パッケージインストール
pip install -r requirements.txt

# 設定ファイルコピー
cp config.yaml.example config.yaml

# config.yamlを編集
vim config.yaml
```

### 3. Redis起動

```bash
# macOS/Linux
redis-server

# Docker
docker run -d -p 6379:6379 redis:latest
```

### 4. Relay Server起動

```bash
cd relay_server
python app/main.py
```

**ログ確認**:
```
=============================================================
Kabuto Relay Server Starting...
=============================================================
Logging initialized
Configuration loaded from config.yaml
Database initialized
Redis initialized: localhost:6379
Notification manager initialized
Server: 0.0.0.0:5000
Database: sqlite:///./data/kabuto.db
Redis: localhost:6379
=============================================================
Kabuto Relay Server Started Successfully
=============================================================
```

### 5. Excel VBAセットアップ

1. `excel_vba_simplified/README.md` を参照
2. 3つのモジュールをインポート
3. Configシートを作成・設定
4. OrderLogシートを作成

### 6. 動作確認

```bash
# API接続テスト
curl http://localhost:5000/ping

# ステータス確認
curl http://localhost:5000/status

# Healthチェック
curl http://localhost:5000/health
```

---

## 移行チェックリスト

### Relay Server側

- [ ] config.yamlを作成・設定
- [ ] Redisを起動
- [ ] Relay Serverを起動
- [ ] `/health` エンドポイントが200 OKを返すか確認
- [ ] Slack通知のテスト
- [ ] メール通知のテスト

### Excel VBA側

- [ ] 簡略版モジュール（3個）をインポート
- [ ] Configシートを作成
- [ ] OrderLogシートを作成
- [ ] API_TestConnection()が成功するか確認
- [ ] ポーリング開始（StartPolling）

### TradingView側

- [ ] Webhook URLを更新（Relay Serverのエンドポイント）
- [ ] Passphraseを設定（config.yamlのwebhook_secretと一致）
- [ ] テストアラートを送信

---

## トラブルシューティング

### Relay Serverが起動しない

**原因**: Redisに接続できない

**解決**:
```bash
# Redis起動確認
redis-cli ping
# → PONG が返ればOK

# Redis起動
redis-server
```

### Excel VBAがシグナルを取得できない

**原因1**: Relay Serverが起動していない

**解決**:
```bash
curl http://localhost:5000/ping
```

**原因2**: API keyが間違っている

**解決**:
- ConfigシートのAPI_KEYとconfig.yamlのapi_keyが一致するか確認

**原因3**: シグナルが5段階セーフティで拒否されている

**解決**:
```bash
# Relay Serverのログ確認
tail -f relay_server/data/logs/kabuto_*.log | grep "failed validation"
```

### 注文が実行されない

**原因**: MarketSpeed IIのRSS機能が無効

**解決**:
- MarketSpeed IIが起動しているか確認
- RSS機能が有効か確認
- ログイン状態を確認

---

## まとめ

### 変更のメリット

| 項目 | 旧 | 新 | 改善 |
|-----|---|---|------|
| VBA行数 | 2000行 | 400行 | 80%削減 |
| 保守性 | 低（VBA） | 高（Python） | ✅ |
| テスト性 | 困難 | 容易（ユニットテスト） | ✅ |
| スケール性 | 1台のみ | 複数Excel可能 | ✅ |
| 監査ログ | 分散 | 統合（DB） | ✅ |
| 通知 | Excel内のみ | Slack/メール | ✅ |

### 次のステップ

1. **本番環境準備**:
   - PostgreSQLデータベースセットアップ
   - Dockerコンテナ化
   - systemdでRelay Server自動起動

2. **監視強化**:
   - Prometheus + Grafanaでメトリクス監視
   - ログ分析（ELK Stack）

3. **機能追加**:
   - Webダッシュボード（Vue.js + FastAPI）
   - バックテスト機能
   - ポートフォリオ最適化

---

**作成日**: 2026-01-10
**バージョン**: 1.0.0
