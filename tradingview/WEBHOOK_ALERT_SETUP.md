# Webhook Test アラート設定ガイド

## TradingViewでのアラート作成手順

### 1. アラート作成

1. **チャートに webhook_test.pine を追加**
   - Pine エディタで `webhook_test.pine` を開く
   - 「保存」→「チャートに追加」

2. **アラート作成**
   - チャート右上の「⏰」アラートボタンをクリック

### 2. アラート設定

#### 条件タブ

- **条件**: `Webhook Test` を選択
- **オプション**:
  - ✅ `Once Per Bar Close` にチェック
  - ❌ その他のオプションはチェックしない

#### 通知タブ

- **Webhook URL**:
  ```
  https://YOUR-NGROK-URL/webhook/test
  ```

  例: `https://1234-56-78-90-12.ngrok-free.app/webhook/test`

#### メッセージ

**重要**: 以下のJSONを `webhook_test_alert_message.json` からコピーして、**そのまま**ペーストしてください。

ファイル: `/kabuto/tradingview/webhook_test_alert_message.json`

```json
{"action": "buy","ticker": "{{ticker}}","quantity": 100,"price": "market","entry_price": {{plot_0}},"stop_loss": {{plot_1}},"take_profit": {{plot_2}},"atr": {{plot_3}},"rr_ratio": {{plot_4}},"rsi": {{plot_5}},"timestamp": "{{time}}","passphrase": "JhZd2DaPMxzL69zq_yOllQaMfaOfu-vSPtvtHnQSweY"}
```

**注意**:
- 前後にスペースを入れない
- 改行を入れない
- そのまま1行でペースト

#### アラート名（任意）

```
Kabuto Webhook Test
```

### 3. 作成をクリック

## プレースホルダーの説明

| プレースホルダー | 説明 | Pine Script変数 |
|----------------|------|-----------------|
| `{{ticker}}` | 銘柄コード | testTicker |
| `{{plot_0}}` | エントリー価格 | testEntryPrice |
| `{{plot_1}}` | ストップロス | testStopLoss |
| `{{plot_2}}` | テイクプロフィット | testTakeProfit |
| `{{plot_3}}` | ATR | testAtr |
| `{{plot_4}}` | リスクリワード比 | testRrRatio |
| `{{plot_5}}` | RSI | testRsi |
| `{{time}}` | タイムスタンプ | time |

**注意**: `{{plot_N}}` は、Pine Scriptで定義された変数の順序に対応します。変数の順序を変更した場合、プレースホルダーも更新する必要があります。

## 動作確認

### 成功時の動作

1. **Pine エディタのログ**:
   ```
   ============================================================
   🔔 Webhook送信 #1
   📍 銘柄: 9984 @ ¥4490.00
   ⏰ 送信時刻: 2025-12-29 14:30:00
   📊 データ: SL=4265.50 | TP=4939.00 | RR=2.00
   ============================================================
   ```

2. **TradingViewのアラートパネル**:
   - アラートが記録される
   - タイムスタンプが表示される

3. **Relay Serverのログ**:
   ```
   INFO: Test webhook received: buy 9984
   POST /webhook/test - 200 OK - 15.2ms
   ```

4. **ngrok Web Interface** (`http://127.0.0.1:4040`):
   - リクエスト詳細を確認
   - ステータス: 200 OK
   - Request Body: 正しいJSONフォーマット

### トラブルシューティング

#### エラー: 2重送信

**症状**: 1つのアラートで2つのメッセージが送信される

**原因**:
1. Pine Scriptで `alert()` 関数を使用している
2. TradingViewのアラート設定で「注文約定時」にチェックが入っている

**解決**:
- Pine Scriptから `alert()` を削除済み（現在のバージョンで対応済み）
- アラート設定で「Once Per Bar Close」のみにチェック

#### エラー: Webhook URLが間違っている

**症状**: Relay Serverに届かない

**確認事項**:
1. ngrokが起動しているか
2. ngrokのForwarding URLが正しいか（定期的に変わる）
3. TradingViewのアラート設定で正しいURLが入力されているか
4. URLの末尾が `/webhook/test` になっているか

#### エラー: メッセージが正しくない

**症状**: Relay Serverで `Invalid passphrase` エラー

**確認事項**:
1. `webhook_test_alert_message.json` の内容をそのままコピーしたか
2. パスフレーズが Relay Server の `config.yaml` と一致しているか
3. 余計なスペースや改行が含まれていないか

## パスフレーズの変更

`webhook_test_alert_message.json` のパスフレーズを変更する場合：

1. **Relay Server側**: `relay_server/config.yaml` の `security.webhook_secret` を変更
2. **TradingView側**: `webhook_test_alert_message.json` の `passphrase` 値を変更
3. **Pine Script側**: `webhook_test.pine` の `webhookPassphrase` を変更（表示用）

**重要**: 3つすべてを同じ値に設定してください。

## 本番運用への移行

疎通テストが成功したら：

1. **本番用ストラテジーに切り替え**:
   - `webhook_test.pine` → `kabuto_strategy_v1.pine`

2. **エンドポイント変更**:
   - Webhook URL: `/webhook/test` → `/webhook`

3. **メッセージテンプレート更新**:
   - 本番用のアラートメッセージを作成
   - 実際の取引ロジックに合わせて変数を調整

---

**作成日**: 2025-12-29
**バージョン**: 1.0
