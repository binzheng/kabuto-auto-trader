# TradingView Pine Script - 使用方法

## ファイル構成

```
tradingview/
├── README.md                           # このファイル
└── strategies/
    └── kabuto_strategy_v1.pine         # メイン戦略スクリプト
```

---

## セットアップ手順

### 1. TradingView にスクリプトをインポート

1. TradingView にログイン
2. チャートを開く
3. 下部の「Pine エディタ」をクリック
4. `kabuto_strategy_v1.pine` の内容をコピー＆ペースト
5. 「チャートに追加」をクリック

### 2. パラメータ設定

スクリプトを追加後、設定アイコン（⚙️）をクリックして以下を調整：

#### 移動平均線
- 短期EMA期間: `5`（デフォルト）
- 中期EMA期間: `25`（デフォルト）
- 長期EMA期間: `75`（デフォルト）

#### テクニカル指標
- RSI期間: `14`
- RSI下限: `50`
- RSI上限: `70`
- 出来高平均期間: `20`
- 出来高倍率: `1.2`

#### ATR設定
- ATR期間: `14`
- ストップロス倍率: `2.0`（エントリー価格 - ATR×2.0）
- テイクプロフィット倍率: `4.0`（エントリー価格 + ATR×4.0）
- 最低リスクリワード比: `1.5`

#### リスク管理
- 1日最大エントリー数: `3`
- クールダウン時間: `30`分
- 損切り後待機時間: `60`分

#### 時間帯設定（日本時間）
- 前場取引: ✅ 有効
- 前場開始: `930`（9:30）
- 前場終了: `1120`（11:20）
- 後場取引: ✅ 有効
- 後場開始: `1300`（13:00）
- 後場終了: `1430`（14:30）
- 強制決済時刻: `1445`（14:45）

#### Webhook設定
- Webhookパスフレーズ: `YOUR_SECRET_PASSPHRASE`（⚠️ 必ず変更してください）

### 3. Alert（アラート）の設定

#### 3.1 アラート作成

1. チャート右上の「アラート」アイコンをクリック
2. 「条件」を **"Kabuto Strategy v1.0"** に設定
3. 「メッセージ」に以下のプレースホルダーを使用：

```
{{strategy.order.alert_message}}
```

これにより、スクリプトが生成したJSON形式のメッセージがそのまま送信されます。

#### 3.2 Webhook URL設定

「Webhook URL」欄に中継サーバーのエンドポイントを入力：

```
https://your-server.com/webhook
```

#### 3.3 アラート頻度

- **「アラート頻度」** を **"毎回"** に設定
- **「有効期限」** を **"無期限"** に設定（推奨）

---

## JSON メッセージフォーマット

### エントリーシグナル（買い）

```json
{
  "action": "buy",
  "ticker": "9984",
  "quantity": 100,
  "price": "market",
  "entry_price": 3000.50,
  "stop_loss": 2940.25,
  "take_profit": 3120.75,
  "atr": 30.12,
  "rr_ratio": 2.0,
  "rsi": 62.5,
  "timestamp": "1735279200000",
  "passphrase": "YOUR_SECRET_PASSPHRASE"
}
```

### エグジットシグナル（売り）

```json
{
  "action": "sell",
  "ticker": "9984",
  "quantity": 100,
  "price": "market",
  "exit_reason": "take_profit",
  "exit_price": 3120.75,
  "timestamp": "1735365600000",
  "passphrase": "YOUR_SECRET_PASSPHRASE"
}
```

**exit_reason の種類：**
- `"stop_loss"` - 損切り
- `"take_profit"` - 利確
- `"market_close"` - 引け前強制決済

---

## 情報パネルの見方

チャート右上に表示されるパネルの項目：

| 項目 | 説明 | 表示例 |
|------|------|--------|
| 本日エントリー | 当日のエントリー回数 / 上限 | `2/3` |
| クールダウン | ⏸️ = クールダウン中、✅ = 取引可能 | `✅` |
| 時刻（JST） | 日本時間の現在時刻 | `10:30` |
| 取引時間 | ✅ = 取引可能時間帯、⏸️ = 取引時間外 | `✅` |
| ATR(14) | 現在のATR値 | `28.50` |
| RSI(14) | 現在のRSI値 | `62.30` |
| 出来高倍率 | 現在出来高 / 平均出来高 | `1.45x` |
| ポジション | 保有中 / なし | `保有中` |
| 取引可否 | ✅ = 全条件クリア、⏸️ = 何らかの制限 | `✅` |

---

## チャート表示

### 移動平均線
- **オレンジ線**: 短期EMA（5）
- **青線**: 中期EMA（25）
- **紫線**: 長期EMA（75）

### エントリー/エグジット
- **青色水平線**: エントリー価格
- **赤色水平線**: ストップロス
- **緑色水平線**: テイクプロフィット

### 背景色
- **薄緑**: 取引可能時間帯
- **薄赤**: 取引時間外

### マーク
- **緑色の三角形（▲）**: 買いシグナル発生

---

## バックテスト方法

### 1. 期間設定

チャート左上の時間範囲を設定：
- 推奨: 最低3年分（2022年〜現在）

### 2. タイムフレーム

- **推奨**: 15分足 または 1時間足
- デイトレ〜短期スイング向け

### 3. 銘柄選定

高流動性銘柄を推奨：
- ソフトバンクG（9984）
- ソニーG（6758）
- トヨタ自動車（7203）
- 三菱UFJ（8306）
- キーエンス（6861）

### 4. 評価指標

「Strategy Tester」タブで確認：
- **純利益**: プラスであること
- **勝率**: 40%以上が目標
- **プロフィットファクター**: 1.5以上
- **最大ドローダウン**: -15%以内
- **シャープレシオ**: 1.2以上

---

## トラブルシューティング

### Q1. アラートが発火しない

**確認事項：**
1. アラート条件が "Kabuto Strategy v1.0" になっているか
2. アラート頻度が "毎回" になっているか
3. スクリプトが「チャートに追加」されているか
4. 時間帯フィルターが有効になっていて、取引時間外ではないか

### Q2. エントリーシグナルが出ない

**確認事項：**
1. 日次エントリー上限（デフォルト3回）に達していないか
2. クールダウン中（前回エントリーから30分以内）ではないか
3. RSIが50-70の範囲内にあるか
4. 出来高が平均の1.2倍以上あるか
5. 取引可能時間帯（9:30-11:20, 13:00-14:30）にあるか

### Q3. RR比率が低くて約定しない

ATR倍率を調整：
- ストップロス倍率を小さく（例: 2.0 → 1.5）
- テイクプロフィット倍率を大きく（例: 4.0 → 5.0）

### Q4. バックテスト結果が悪い

**調整ポイント：**
1. RSI範囲を狭める（50-70 → 55-65）
2. 出来高倍率を上げる（1.2 → 1.5）
3. 対象銘柄を変更（高ボラティリティ銘柄を選択）
4. タイムフレームを変更（15分足 ↔ 1時間足）

### Q5. スクリプト更新後、複数アラートの設定変更が大変

TradingView上で更新対象が多数ある場合は、ブラウザのDevToolsコンソールで一括更新スクリプトを実行できます。

対象ファイル:
- `tradingview/tools/bulk_update_alerts_console.js`
- `tradingview/tools/bulk_update_alerts_playwright.js`（推奨）

使い方:
1. `jp.tradingview.com` でログインし、アラート一覧を開く
2. ブラウザのDevTools Consoleを開く
3. `bulk_update_alerts_console.js` の内容を貼り付けて実行
4. 動作確認（dry-run）:
   - `bulkUpdateTradingViewAlerts({ dryRun: true })`
5. 実行:
   - `bulkUpdateTradingViewAlerts()`

注意:
- TradingViewのUI変更でボタン文言が変わると動作しない場合があります
- 実行前に少数アラートで必ずテストしてください
- 本番稼働中のアラートに対して実行する場合は、実行時間帯に注意してください

#### Playwright版（推奨）

1. Playwrightをインストール
   - `npm install playwright`
2. 実行（初回はログイン案内後にEnter）
   - `node tradingview/tools/bulk_update_alerts_playwright.js --max-updates=20`
3. 事前確認（クリックなし）
   - `node tradingview/tools/bulk_update_alerts_playwright.js --dry-run --max-updates=20`
4. ブラウザ未インストールエラー時
   - `npx playwright install`
   - もしくはシステムChromeを使う:
   - `node tradingview/tools/bulk_update_alerts_playwright.js --dry-run --max-updates=20 --channel=chrome`

主なオプション:
- `--dry-run` : クリックせず対象検出のみ
- `--max-updates=20` : 最大更新件数
- `--profile=.tv-playwright-profile` : ログインセッション保存先
- `--headless` : ヘッドレス実行（通常は非推奨）
- `--channel=chrome` : Playwright同梱ブラウザではなく、ローカルChromeを使用

#### 有効期限一括変更（`bulk_update_expiry_playwright.js`）

アラートの有効期限を一括で変更します。`--profile` はタイムフレームスクリプトと共通のため、ログイン済みの場合はそのまま使用できます。

1. 実行（有効期限を 2027-01-01 23:59 に設定）
   - `node tradingview/tools/bulk_update_expiry_playwright.js --expiry=2027-01-01 --max-updates=20`
2. 時刻まで指定する場合
   - `node tradingview/tools/bulk_update_expiry_playwright.js --expiry=2027-01-01T23:59 --max-updates=20`
3. 事前確認（クリックなし）
   - `node tradingview/tools/bulk_update_expiry_playwright.js --expiry=2027-01-01 --dry-run --max-updates=20`

主なオプション:
- `--expiry=YYYY-MM-DD[THH:mm]` : 変更後の有効期限（**必須**）。時刻省略時は `23:59` を使用
- `--dry-run` : クリックせず対象検出のみ
- `--max-updates=20` : 最大更新件数
- `--profile=.tv-playwright-profile` : ログインセッション保存先
- `--channel=chrome` : ローカルChromeを使用

#### 条件（ストラテジーバージョン）一括変更（`bulk_update_condition_playwright.js`）

アラートの条件欄に表示されているストラテジーのバージョンを一括変更します（例: `v4.0` → `v7.0`）。
起動URLは Kabuto v7.0 が適用されているチャートをデフォルトとし、ウィンドウは最大化されます。

1. 実行（v4.0 → v7.0）
   - `node tradingview/tools/bulk_update_condition_playwright.js --max-updates=20`
2. 事前確認（クリックなし）
   - `node tradingview/tools/bulk_update_condition_playwright.js --dry-run --max-updates=5`
3. バージョンを明示的に指定する場合
   - `node tradingview/tools/bulk_update_condition_playwright.js --from-version=v4.0 --to-version=v7.0`

主なオプション:
- `--from-version=v4.0` : 変更前のバージョン文字列（デフォルト: `v4.0`）
- `--to-version=v7.0` : 変更後のバージョン文字列（デフォルト: `v7.0`）
- `--dry-run` : クリックせず対象検出のみ
- `--max-updates=20` : 最大更新件数
- `--profile=.tv-playwright-profile` : ログインセッション保存先（他スクリプトと共通）
- `--channel=chrome` : ローカルChromeを使用
- `--url=...` : 起動URL（デフォルト: `https://jp.tradingview.com/chart/2TEyPaCa/?symbol=TSE%3A9984`）

注意:
- チャートに v7.0 のストラテジーが適用されている必要があります
- 起動後、アラートパネル（ベルアイコン）を手動で開いてから Enter を押してください
- `data-qa-id="main-series-select-additional-info"` の値でバージョンを判定します

---

## セキュリティ注意事項

### パスフレーズの管理

⚠️ **重要**: デフォルトの `YOUR_SECRET_PASSPHRASE` は必ず変更してください

**推奨パスフレーズ生成方法：**

```bash
# ランダムな32文字の文字列を生成（macOS/Linux）
openssl rand -base64 32
```

生成された文字列をスクリプトの「Webhookパスフレーズ」に設定し、中継サーバーの `.env` ファイルにも同じ値を設定してください。

```env
# .env
WEBHOOK_SECRET=your-generated-passphrase-here
```

### Alert メッセージの確認

アラート作成後、必ず「テスト」ボタンで以下を確認：
1. JSON形式が正しいか
2. パスフレーズが含まれているか
3. Webhook URLが正しいか

---

## 次のステップ

1. **ペーパートレード**: 1-2週間、実際の注文は出さずにアラートのみ確認
2. **少額実運用**: 100株のみで自動売買を開始
3. **パフォーマンス監視**: 毎日ログを確認し、問題点を洗い出し
4. **段階的拡大**: 問題なければ複数銘柄・ポジションサイズを増加

---

**バージョン**: v1.0
**最終更新**: 2025-12-27
**対応環境**: TradingView Pine Script v5
