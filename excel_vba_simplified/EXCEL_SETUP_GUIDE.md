# Excel自動売買システム - セットアップガイド

## 概要

このガイドでは、ExcelでKabuto Auto Traderを設定し、Start/Stopボタンで制御する方法を説明します。

---

## 1. VBAモジュールのインポート

### 必要なモジュール

1. **Module_Main_Simple.bas** - メインロジック
2. **Module_API_Simple.bas** - API通信
3. **Module_Logger_Simple.bas** - ログ出力
4. **Module_Config_Simple.bas** - 設定管理
5. **JsonConverter.bas** - JSON解析（VBA-JSON）

### インポート手順

1. Excelを開く
2. **Alt + F11** でVBAエディタを開く
3. **ファイル** → **ファイルのインポート**
4. 上記5つの.basファイルを順番にインポート

---

## 2. 参照設定

VBAエディタで：

1. **ツール** → **参照設定**
2. 以下にチェック（不要になりました - Late Binding使用）
   - ~~Microsoft Scripting Runtime~~

---

## 3. Excelシートの作成

### Sheet1（メインシート）

このシートにステータスダッシュボードとボタンを配置します。

#### ステータスダッシュボード（自動生成）

Start時に自動的に以下のステータス表示が作成されます：

```
+----------------------------------+
| Kabuto Auto Trader - Status      |
+----------------------------------+
| Status:         | Running        | ← 実行中/停止中
| Current Time:   | 2026-01-12 ... | ← 実行中は自動更新
| Start Time:     | 2026-01-12 ... |
| Running Time:   | 0h 5m          |
| Last Signal:    | 2026-01-12 ... |
| Total Signals:  | 10             |
| Success:        | 8              |
| Failed:         | 2              |
| Success Rate:   | 80.0%          |
+----------------------------------+
```

### Configシート

| A列（キー） | B列（値） |
|------------|----------|
| API_BASE_URL | http://localhost:5000 |
| API_KEY | A83b4aZF_r5iflTLtEbiwC5PuI3gn7pGc_R4h8eW_tQ |
| CLIENT_ID | excel_vba_01 |
| TEST_MODE | TRUE |

**TEST_MODE説明:**
- `TRUE`: MarketSpeed II不要のテストモード（常に成功を返す）
- `FALSE`または空欄: 実際のRssStockOrder_vを呼び出す

### OrderLogシート

| A列 | B列 | C列 | D列 | E列 | F列 | G列 |
|-----|-----|-----|-----|-----|-----|-----|
| Timestamp | Signal ID | Ticker | Action | Order ID | Status | Reason |

---

## 4. Start/Stopボタンの作成

### 手順

#### Startボタン

1. **開発タブ** → **挿入** → **ボタン（フォームコントロール）**
2. Sheet1の適当な位置（例: D3セル）にボタンを配置
3. マクロの登録ダイアログが表示される
4. **StartPolling** を選択 → OK
5. ボタンを右クリック → **テキストの編集** → 「Start」に変更
6. ボタンのスタイルを整える（緑色にするなど）

#### Stopボタン

1. 同様に**ボタン（フォームコントロール）**を挿入
2. Startボタンの隣（例: E3セル）に配置
3. **StopPolling** を選択 → OK
4. テキストを「Stop」に変更
5. ボタンのスタイルを整える（赤色にするなど）

### ボタン配置の推奨レイアウト

```
Sheet1:
+---------------------------------------+
| A                    B                |
|---------------------------------------|
| Kabuto Auto Trader - Status          |
|---------------------------------------|
|                                       |
| Status:              Running    [D3]  | ← Startボタン [E3] ← Stopボタン
| Current Time:        ...              |
| Start Time:          ...              |
| ...                                   |
+---------------------------------------+
```

---

## 5. 動作確認

### テスト手順

1. **Relay Serverを起動**
   ```bash
   cd relay_server
   python -m app.main
   ```

2. **Redisを起動**（別ターミナル）
   ```bash
   redis-server
   ```

3. **Excelで「Start」ボタンをクリック**
   - ステータスが「Running」（緑色）になる
   - Current Timeが5秒ごとに更新される
   - Running Timeがカウントアップされる

4. **テストシグナルを送信**
   ```bash
   curl -X POST http://localhost:5000/webhook \
     -H "Content-Type: application/json" \
     -d '{"action": "buy", "ticker": "7203", "quantity": 100, "price": "market", "entry_price": 1850.0, "timestamp": "1736668800000", "passphrase": "JhZd2DaPMxzL69zq_yOllQaMfaOfu-vSPtvtHnQSweY"}'
   ```

5. **ステータスを確認**
   - Total Signals: 1
   - Success: 1（TEST_MODE=TRUEの場合）
   - Last Signal: 現在時刻
   - OrderLogシートに記録が追加される

6. **「Stop」ボタンをクリック**
   - ステータスが「Stopped」（灰色）になる
   - Current Timeの更新が停止する

7. **イミディエイトウィンドウ（Ctrl+G）でログを確認**
   ```
   [2026-01-12 12:10:00] ==================================================
   [2026-01-12 12:10:00] Kabuto Auto Trader (Simplified) Started
   [2026-01-12 12:10:00] ==================================================
   [2026-01-12 12:10:00] [INFO] Excel VBA: Order Execution Only
   [2026-01-12 12:10:00] [INFO] All validation done by Relay Server
   [2026-01-12 12:10:00] [INFO] Async mode: Excel remains responsive during execution
   ```

---

## 6. 本番運用への移行

### TEST_MODE を無効化

1. **MarketSpeed IIを起動**
2. **RSS機能を有効化**
3. Configシートで `TEST_MODE` を `FALSE` に変更、または削除
4. Excelを保存

### 市場時間を本番設定に戻す

**relay_server/config.yaml:**

```yaml
market_hours:
  timezone: "Asia/Tokyo"
  safe_trading_windows:
    morning:
      start: "09:30"  # 本番: 9:30
      end: "11:20"    # 本番: 11:20
    afternoon:
      start: "13:00"  # 本番: 13:00
      end: "14:30"    # 本番: 14:30
```

### クールダウンを有効化

**relay_server/config.yaml:**

```yaml
cooldown:
  buy_same_ticker: 1800   # 30分
  buy_any_ticker: 300     # 5分
  sell_same_ticker: 900   # 15分
  sell_any_ticker: 0
```

**Relay Serverを再起動**して設定を反映。

---

## 7. トラブルシューティング

### エラー: 「ユーザー定義型は定義されていません」

**原因**: JsonConverterがインポートされていない

**解決**: `JsonConverter.bas` をインポート

### エラー: 「型が一致しません (Error 13)」

**原因**: MarketSpeed IIが起動していない、またはRSS関数が見つからない

**解決**:
- TEST_MODE=TRUEでテスト
- MarketSpeed IIを起動してRSS機能を有効化

### エラー: 「操作は中断されました」

**原因**: APIタイムアウト

**解決**:
- Relay Serverが起動しているか確認
- Module_API_Simple.basが最新版か確認（ServerXMLHTTP.6.0使用）

### ステータスが更新されない

**原因**:
1. Startボタンが押されていない
2. エラーが発生している

**解決**:
1. Stopボタン → Startボタンで再起動
2. Ctrl+Gでイミディエイトウィンドウを開いてエラーログを確認

---

## 8. 機能詳細

### 非同期実行

`Application.OnTime`を使用した非同期スケジューリングにより、**Excelは実行中も操作可能**です。

- ポーリング間隔: 5秒
- ブロッキングなし
- セル編集、シート切り替え、計算などが自由に可能

### ステータスダッシュボード

#### 表示項目

| 項目 | 説明 | 更新頻度 |
|------|------|---------|
| Status | Running/Stopped | ボタン操作時 |
| Current Time | 現在時刻 | 5秒（実行中のみ）|
| Start Time | 開始時刻 | 開始時 |
| Running Time | 稼働時間 | 5秒（実行中のみ）|
| Last Signal | 最終シグナル受信時刻 | シグナル受信時 |
| Total Signals | 総シグナル数 | シグナル受信時 |
| Success | 成功数 | 注文成功時 |
| Failed | 失敗数 | 注文失敗時 |
| Success Rate | 成功率 | 5秒（実行中のみ）|

#### 色分け

- **Status Running**: 緑色背景
- **Status Stopped**: 灰色背景
- **Success Rate >= 90%**: 緑色背景
- **Success Rate 70-89%**: 黄色背景
- **Success Rate < 70%**: 赤色背景

### ログ出力

すべてのログはイミディエイトウィンドウ（Ctrl+G）に出力されます：

- `[INFO]`: 情報メッセージ
- `[SUCCESS]`: 成功メッセージ
- `[WARNING]`: 警告メッセージ
- `[ERROR]`: エラーメッセージ

---

## まとめ

このシステムにより：

✅ **Start/Stopボタンでワンクリック制御**
✅ **リアルタイムステータス表示**（実行中のみ時刻更新）
✅ **非同期実行でExcel操作可能**
✅ **詳細な実行統計（成功率など）**
✅ **TEST_MODEでMarketSpeed II不要のテスト**
✅ **ローカルログ + Relay Server統合**

快適な自動売買をお楽しみください！
