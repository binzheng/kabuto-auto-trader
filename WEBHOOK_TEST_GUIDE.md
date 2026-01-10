# TradingView → Relay Server 疎通テスト完全ガイド

## 概要

このガイドでは、TradingViewからRelay ServerへのWebhook疎通テストを実施します。

**テストの流れ**:
```
TradingView → Webhook → ngrok → Relay Server (別PC)
```

---

## パート1: Relay Server の準備（別PC）

### 1-1. 前提条件の確認

**必要なソフトウェア**:
- Python 3.8以上
- Redis
- ngrok（TradingViewからアクセス可能にするため）

### 1-2. Redis のインストールと起動

#### macOS の場合:
```bash
# Redisインストール
brew install redis

# Redis起動
brew services start redis

# 確認
redis-cli ping
# 「PONG」が返ればOK
```

#### Ubuntu/Debian の場合:
```bash
# Redisインストール
sudo apt update
sudo apt install redis-server

# Redis起動
sudo systemctl start redis-server
sudo systemctl enable redis-server

# 確認
redis-cli ping
```

#### Windows の場合:
1. Redis for Windowsをダウンロード: https://github.com/microsoftarchive/redis/releases
2. インストール後、サービスとして起動
3. コマンドプロンプトで確認: `redis-cli ping`

### 1-3. ngrok のインストールと設定

#### macOS の場合:
```bash
# ngrokインストール
brew install ngrok

# ngrokアカウント登録（無料）
# https://ngrok.com/ でサインアップ

# 認証トークンを設定（ngrokダッシュボードから取得）
ngrok config add-authtoken YOUR_AUTH_TOKEN
```

#### Windows/Linux の場合:
1. https://ngrok.com/download からダウンロード
2. 解凍してPATHに追加
3. `ngrok config add-authtoken YOUR_AUTH_TOKEN`

### 1-4. Relay Server の起動

```bash
# プロジェクトディレクトリに移動
cd /path/to/kabuto/relay_server

# 設定ファイルを確認（必要に応じて編集）
cat config.yaml

# 重要: security.webhook_secret を確認・変更
# この値をTradingViewのWebhookメッセージで使用します

# サーバー起動
chmod +x run.sh
./run.sh
```

**起動成功時のログ**:
```
============================================
Kabuto Relay Server Starting...
============================================
Logging initialized
Database initialized
Configuration loaded from config.yaml
Server: 0.0.0.0:5000
...
Kabuto Relay Server Started Successfully
```

### 1-5. ngrok でトンネルを作成

**新しいターミナルを開いて実行**:
```bash
ngrok http 5000
```

**重要**: 以下の **Forwarding URL** をメモします:
```
Forwarding    https://xxxx-xxx-xxx-xxx.ngrok-free.app -> http://localhost:5000
                                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                                     この URL をコピー
```

例: `https://1234-56-78-90-12.ngrok-free.app`

---

## パート2: TradingView の設定

### 2-1. テスト用ストラテジーを追加

1. **TradingViewを開く**
   - 任意のチャート（例: 東証 9984 ソフトバンク）

2. **Pine エディタを開く**
   - 下部の「Pine エディタ」タブをクリック

3. **webhook_test.pine をコピー**
   - `/kabuto/tradingview/strategies/webhook_test.pine` の内容をコピー
   - Pine エディタに貼り付け

4. **保存してチャートに追加**
   - 「保存」ボタンをクリック
   - 「チャートに追加」ボタンをクリック

### 2-2. ストラテジーの設定

1. **設定画面を開く**
   - チャート上のストラテジー名の横にある⚙️アイコンをクリック

2. **Inputs タブで設定**
   - **テスト銘柄コード**: `9984`（またはテストしたい銘柄）
   - **Webhook パスフレーズ**: `your-webhook-secret-change-this`

     ⚠️ **重要**: この値を Relay Server の `config.yaml` の `security.webhook_secret` と **完全に一致** させる

   - **テスト実行**: ✅ **チェックを外したまま**（後でテスト時にチェック）

3. **OK をクリック**

### 2-3. アラートの作成

1. **アラートボタンをクリック**
   - チャート右上の「⏰ アラート」ボタン

2. **アラート設定**
   - **条件**: `Webhook Test`
   - **オプション**:
     - ✅ `注文約定時`
     - ✅ `Once Per Bar Close`

3. **Webhook URL を設定**
   ```
   https://YOUR-NGROK-URL.ngrok-free.app/webhook/test
   ```

   例: `https://1234-56-78-90-12.ngrok-free.app/webhook/test`

4. **メッセージを設定**
   ```
   {{strategy.order.alert_message}}
   ```

5. **アラート名**（任意）
   ```
   Kabuto Webhook Test
   ```

6. **作成をクリック**

---

## パート3: 疎通テスト実行

### 3-1. テスト前の確認

**Relay Server側（別PC）**:
- ✅ Redisが起動している: `redis-cli ping` → `PONG`
- ✅ Relay Serverが起動している: ログに "Started Successfully" が表示
- ✅ ngrokが起動している: Forwarding URLが表示されている

**TradingView側**:
- ✅ webhook_test.pine がチャートに追加されている
- ✅ Webhook パスフレーズが設定されている
- ✅ アラートが作成されている（Webhook URL付き）

### 3-2. テスト実行

1. **TradingViewのストラテジー設定を開く**
   - ⚙️アイコンをクリック

2. **「テスト実行」にチェックを入れる**
   - チャートの背景が緑色になります
   - 青い三角形のマーク（テストシグナル）が表示されます

3. **チャートが更新されるのを待つ**
   - リアルタイムバーが確定すると、Webhookが送信されます

4. **すぐに「テスト実行」のチェックを外す**
   - 繰り返し送信を防ぐため

### 3-3. 結果の確認

#### Relay Server のログを確認

**成功時のログ例**:
```
INFO: Test webhook received: buy 9984
POST /webhook/test - 200 OK - 15.2ms
```

#### ngrok のダッシュボードで確認

1. **ngrokのターミナルに表示されているURL**（例: `http://127.0.0.1:4040`）にアクセス

2. **リクエスト詳細を確認**:
   - **Status**: `200 OK`
   - **Request Headers**: TradingViewのUser-Agent
   - **Request Body**: JSON形式のシグナルデータ
   - **Response Body**:
     ```json
     {
       "status": "test_success",
       "signal_id": "test_signal_id",
       "message": "Test webhook received successfully (dry run)",
       "timestamp": "2025-12-29T10:00:00.123456"
     }
     ```

#### TradingView のアラートログを確認

1. **アラートパネルを開く**
   - 右側のアラートアイコン

2. **最新のアラートを確認**
   - 送信時刻とステータスを確認

---

## パート4: トラブルシューティング

### エラー1: `401 Unauthorized - Invalid passphrase`

**原因**: Passphraseの不一致

**解決方法**:
1. Relay Server の `config.yaml` を確認:
   ```yaml
   security:
     webhook_secret: "your-webhook-secret-change-this"
   ```

2. TradingView のストラテジー設定で、**Webhook パスフレーズ** が上記と完全に一致しているか確認

3. 両方を新しい値に変更:
   - 例: `"MySecret123!@#"` （推奨: 20文字以上のランダム文字列）

4. Relay Server を再起動

### エラー2: `Connection refused` / `Timeout`

**原因**: ngrokまたはRelay Serverの問題

**解決方法**:
1. **Relay Serverが起動しているか確認**:
   ```bash
   curl http://localhost:5000/ping
   # 期待: {"status": "pong", "timestamp": "..."}
   ```

2. **ngrokが動作しているか確認**:
   - ngrokのターミナルで "Forwarding" が表示されているか
   - ngrok Web UI (`http://127.0.0.1:4040`) にアクセスできるか

3. **TradingViewのWebhook URLが正しいか確認**:
   - ngrokのURLをコピペし直す（スペースや改行が含まれていないか）

### エラー3: `Redis is not running`

**解決方法**:
```bash
# macOS
brew services restart redis

# Ubuntu/Linux
sudo systemctl restart redis-server

# 確認
redis-cli ping
```

### エラー4: Webhookが送信されない

**確認事項**:
1. **アラートが正しく作成されているか**
   - TradingViewのアラートパネルで確認

2. **ストラテジーが実際に注文を実行しているか**
   - チャート下部の「ストラテジーテスター」タブで取引履歴を確認

3. **メッセージフィールドが正しいか**
   - `{{strategy.order.alert_message}}` になっているか（余計なスペースなし）

---

## パート5: 本番エンドポイントへの切り替え

テストが成功したら、本番用エンドポイントに切り替えます。

### 変更点

1. **TradingViewのアラート設定**:
   - Webhook URL: `/webhook/test` → `/webhook`
   ```
   https://YOUR-NGROK-URL.ngrok-free.app/webhook
   ```

2. **本番用ストラテジーに切り替え**:
   - `webhook_test.pine` → `kabuto_strategy_v1.pine`

### 本番運用の注意点

1. **ngrokの制限**:
   - 無料版は8時間でセッションが切れます
   - 本番運用では、固定IP + ドメイン、またはngrok有料版を推奨

2. **セキュリティ**:
   - `webhook_secret` を強力なランダム文字列に変更
   - `config.yaml` の `allowed_ips` を設定（TradingViewのIPレンジ）

3. **モニタリング**:
   - Relay Serverのログを定期的に確認
   - Slackアラートを設定（`config.yaml` の `alerts` セクション）

---

## パート6: 次のステップ

疎通テストが成功したら:

1. ✅ **Excel VBA クライアントの設定**
   - `/excel_vba/` の設定を行う
   - Relay Server からシグナルをポーリング

2. ✅ **MarketSpeed II RSS 連携**
   - VBAからMarketSpeed IIへの注文送信テスト

3. ✅ **実際の取引フロー確認**
   - TradingView → Relay Server → Excel VBA → MarketSpeed II

4. ✅ **リスク管理のテスト**
   - Kill Switch動作確認
   - 日次制限テスト

---

## 参考: テスト用JSONサンプル

手動でWebhookをテストする場合（curlコマンド）:

```bash
curl -X POST https://YOUR-NGROK-URL.ngrok-free.app/webhook/test \
  -H "Content-Type: application/json" \
  -d '{
    "action": "buy",
    "ticker": "9984",
    "quantity": 100,
    "price": "market",
    "entry_price": 1500.0,
    "stop_loss": 1425.0,
    "take_profit": 1650.0,
    "atr": 75.0,
    "rr_ratio": 2.0,
    "rsi": 60.0,
    "timestamp": "2025-12-29T10:00:00",
    "passphrase": "your-webhook-secret-change-this"
  }'
```

**期待される成功レスポンス**:
```json
{
  "status": "test_success",
  "signal_id": "test_signal_id",
  "message": "Test webhook received successfully (dry run)",
  "timestamp": "2025-12-29T10:00:00.123456"
}
```

---

**作成日**: 2025-12-29
**バージョン**: 1.0
**対象**: Kabuto Auto Trader v1.0
