# Kabuto Relay Server

リレーサーバー - 日本株自動売買システムの中核コンポーネント

## 概要

TradingViewからのシグナルを受信し、リスク管理・重複防止・市場時間制御を実施した上で、Excel VBA（MarketSpeed II RSS連携）に配信するサーバーです。

## アーキテクチャ

```
TradingView (Pine Script)
    ↓ Webhook (HTTPS POST)
Relay Server (FastAPI + SQLAlchemy + Redis)
    ↓ Pull API (HTTP GET/POST)
Windows VM (Excel VBA)
    ↓ RSS.ORDER()
MarketSpeed II (楽天証券)
```

## 機能

### 1. Webhook受信 (`/webhook`)
- TradingViewアラートからのシグナル受信
- Passphrase認証
- タイムスタンプ検証

### 2. リスク管理（最後の砦）
- **ポジション制限**: 総額100万円、1銘柄20万円、最大5ポジション
- **日次制限**: 1日5エントリー、合計15トレード
- **連続損失**: 5連敗で自動Kill Switch
- **日次損失**: -5万円で自動Kill Switch

### 3. 重複防止・クールダウン
- **Layer 1 (Redis)**: SHA256ハッシュ + 5分TTLで重複検出
- **Layer 2 (Cooldown)**: 同一銘柄30分、任意銘柄5分のクールダウン
- **Layer 3 (日次制限)**: 1日3エントリー、同一銘柄1回

### 4. 市場時間制御
- **7つのセッション状態**: pre-market, morning-trading, lunch-break, etc.
- **安全取引時間**: 9:30-11:20, 13:00-14:30（開場・引け際を回避）
- **休日管理**: jpholidayライブラリで祝日自動判定

### 5. ブラックリスト管理
- **3種類**: permanent（永久）, temporary（一時）, dynamic（自動追加）
- **自動ブラックリスト**: 3連敗で30日間自動ブラックリスト

### 6. Kill Switch（緊急停止）
- **手動**: Admin APIでパスワード認証
- **自動**: 5連敗、-5万円損失、異常頻度で自動発動

### 7. Excel Pull API
- `GET /api/signals/pending` - 未処理シグナル取得
- `POST /api/signals/{id}/ack` - 取得確認
- `POST /api/signals/{id}/executed` - 執行報告
- `POST /api/signals/{id}/failed` - 失敗報告

## インストール

### 前提条件

- Python 3.10以上
- Redis 6.0以上
- SQLite または PostgreSQL

### 1. 依存関係インストール

```bash
pip install -r requirements.txt
```

### 2. 設定ファイル編集

```bash
cp config.yaml config.yaml.local
# config.yaml.local を編集してシークレットを設定
```

**重要な設定項目**:

```yaml
security:
  webhook_secret: "your-webhook-secret-change-this"  # TradingViewのpassphrase
  api_key: "your-api-key-change-this"                # Excel VBAのAPI Key
  admin_password: "your-admin-password-change-this"  # Admin API用

database:
  url: "sqlite:///./data/kabuto.db"  # または PostgreSQL

redis:
  host: localhost
  port: 6379
```

### 3. データディレクトリ作成

```bash
mkdir -p data/logs
```

### 4. サーバー起動

```bash
# 開発環境
python -m app.main

# 本番環境（uvicorn直接）
uvicorn app.main:app --host 0.0.0.0 --port 5000 --workers 4
```

## API ドキュメント

サーバー起動後、以下のURLでAPI仕様を確認できます:

- Swagger UI: `http://localhost:5000/docs`
- ReDoc: `http://localhost:5000/redoc`

## エンドポイント一覧

### Webhook

- `POST /webhook` - TradingViewシグナル受信
- `POST /webhook/test` - テスト用（ドライラン）

### Signals (Excel Pull API)

- `GET /api/signals/pending` - 未処理シグナル一覧
- `POST /api/signals/{id}/ack` - シグナル取得確認
- `POST /api/signals/{id}/executed` - 執行完了報告
- `POST /api/signals/{id}/failed` - 執行失敗報告
- `GET /api/signals/{id}` - 特定シグナル取得

### Health & Status

- `GET /health` - ヘルスチェック（DB・Redis接続確認）
- `GET /status` - システム状態（本日統計、リスク指標）
- `GET /ping` - 簡易ヘルスチェック

### Admin

- `POST /api/admin/kill-switch` - Kill Switch切り替え
- `GET /api/admin/kill-switch/status` - Kill Switch状態
- `POST /api/heartbeat` - Excel VBAからのハートビート
- `GET /api/admin/heartbeats` - 全クライアント状態

## 使用例

### TradingView Webhookアラート設定

```json
{
  "action": "{{strategy.order.action}}",
  "ticker": "{{ticker}}",
  "quantity": 100,
  "price": "market",
  "entry_price": {{close}},
  "stop_loss": {{strategy.order.stop_loss}},
  "take_profit": {{strategy.order.take_profit}},
  "atr": {{atr}},
  "timestamp": "{{timenow}}",
  "passphrase": "your-webhook-secret-change-this"
}
```

### Excel VBA - シグナル取得

```vba
' GET /api/signals/pending
Dim http As Object
Set http = CreateObject("MSXML2.XMLHTTP.6.0")

http.Open "GET", "http://localhost:5000/api/signals/pending", False
http.setRequestHeader "Authorization", "Bearer your-api-key-change-this"
http.send

If http.Status = 200 Then
    ' JSON解析してシグナル処理
ElseIf http.Status = 204 Then
    ' シグナルなし
End If
```

## ログ

ログファイルは `data/logs/kabuto_YYYY-MM-DD.log` に保存されます（JSON形式）。

- **ローテーション**: 1日毎
- **保持期間**: 90日
- **圧縮**: gzip

## 監視・アラート

### ヘルスチェック

```bash
curl http://localhost:5000/health
```

### システム状態

```bash
curl http://localhost:5000/status
```

### Kill Switch状態

```bash
curl http://localhost:5000/api/admin/kill-switch/status
```

## トラブルシューティング

### Redisに接続できない

```bash
# Redisが起動しているか確認
redis-cli ping

# 起動していない場合
redis-server
```

### データベースエラー

```bash
# SQLiteファイルが破損している場合
rm data/kabuto.db

# サーバー再起動でテーブル再作成
python -m app.main
```

### ポート5000が使用中

```yaml
# config.yaml
server:
  port: 5001  # 別のポートに変更
```

## 開発

### テスト実行

```bash
pytest tests/
```

### コードフォーマット

```bash
black app/
```

### Linting

```bash
flake8 app/
```

## セキュリティ

- **Webhook認証**: Passphrase（共有シークレット）
- **API認証**: Bearer Token（API Key）
- **Admin認証**: パスワード認証
- **IP制限**: config.yamlで許可IPを設定可能

## ライセンス

Proprietary - 個人使用のみ

## サポート

Issue報告: 内部リポジトリ