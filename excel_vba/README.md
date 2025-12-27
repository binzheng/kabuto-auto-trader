# Kabuto Auto Trader - Excel VBA実装

MarketSpeed II RSS連携 全自動売買Excel

---

## 概要

完全無人稼働を前提とした、MarketSpeed II RSSを使用した日本株自動売買システムのExcel VBA実装です。

**主要機能**:
- Relay ServerからシグナルをPull（5秒間隔ポーリング）
- MarketSpeed II RSS経由で自動発注
- ポジション管理・損益計算
- エラーログ・約定履歴記録
- 自動復旧機能

---

## ディレクトリ構造

```
excel_vba/
├── modules/
│   ├── Module_Main.bas              # メインルーチン、自動実行制御
│   ├── Module_API.bas               # サーバーAPI通信
│   ├── Module_RSS.bas               # MarketSpeed II RSS連携
│   ├── Module_SignalProcessor.bas   # シグナル処理ロジック
│   ├── Module_Config.bas            # 設定管理
│   ├── Module_OrderManager.bas      # 注文・ポジション管理
│   └── Module_Logger.bas            # ログ記録
├── classes/
│   └── ThisWorkbook.cls             # ブックイベントハンドラ
├── setup/
├── EXCEL_SETUP_GUIDE.md             # セットアップ手順
└── README.md                        # このファイル
```

**合計**: 8モジュール、約1,500行のVBAコード

---

## 機能一覧

### 1. メインループ（Module_Main）

**自動実行**:
- 5秒間隔でサーバーポーリング
- Application.OnTimeで定期実行
- 市場時間外は自動スキップ

**制御機能**:
```vba
StartAutoTrading()    ' 自動売買開始
PauseAutoTrading()    ' 一時停止
StopAutoTrading()     ' 停止
```

---

### 2. API通信（Module_API）

**エンドポイント**:
- `GET /api/signals/pending` - 未処理シグナル取得
- `POST /api/signals/{id}/ack` - 取得確認
- `POST /api/signals/{id}/executed` - 執行報告
- `POST /api/signals/{id}/failed` - 失敗報告
- `POST /api/heartbeat` - ハートビート送信（60秒毎）

**認証**: Bearer Token（API Key）

---

### 3. RSS連携（Module_RSS）

**MarketSpeed II RSS関数**:
```vba
RSS.ORDER(ticker, side, quantity, priceType, price, condition)
RSS.STATUS(orderId)   ' 約定状態確認
RSS.PRICE(ticker)     ' 現在価格取得
RSS.NAME(ticker)      ' 銘柄名取得
```

**エラーハンドリング**:
- RSS関数エラーをキャッチ
- サーバーに失敗報告
- ErrorLogに記録

---

### 4. シグナル処理（Module_SignalProcessor）

**フロー**:
1. サーバーからシグナル取得
2. SignalQueueに追加
3. 重複チェック（ローカルログ）
4. サーバーにACK送信
5. RSS.ORDER()実行
6. OrderHistory記録
7. 約定ポーリング
8. ExecutionLog + PositionManager更新
9. サーバーに執行報告

---

### 5. ポジション管理（Module_OrderManager）

**機能**:
- 新規ポジション作成
- 平均取得単価計算（追加買い時）
- 一部決済・全決済
- 含み損益計算
- 実現損益計算（FIFO方式）

**約定ポーリング**:
- RSS.STATUS()で定期確認
- 約定済み → ExecutionLog記録

---

### 6. 設定管理（Module_Config）

**Config シート**:
- API_BASE_URL
- API_KEY
- CLIENT_ID
- ポーリング間隔
- ポジション上限
- 日次制限

**市場時間管理**:
```vba
IsMarketOpen()          ' 取引時間内？
IsTradingDay()          ' 営業日？
IsSafeTradingWindow()   ' 安全取引時間？
IsTickerBlacklisted()   ' ブラックリスト？
```

---

### 7. ログ記録（Module_Logger）

**ErrorLog**:
```vba
LogError(errorType, module, message, ticker, severity)
```

**ファイルログ**:
```
C:\Kabuto\Logs\excel_vba_YYYYMMDD.log
```

**クリーンアップ**:
- 90日経過ログを自動削除

---

### 8. 自動復旧（ThisWorkbook）

**Workbook_Open**:
- 前回状態確認
- `ENABLE_AUTO_START = TRUE` で3秒後に自動開始
- Dashboardシートをアクティブ化

**Workbook_BeforeClose**:
- 自動売買停止
- 状態保存

---

## Excelブック構成（11シート）

| # | シート名 | 用途 | 行数目安 |
|---|----------|------|----------|
| 1 | Dashboard | リアルタイム監視 | 30行 |
| 2 | SignalQueue | 未処理シグナルキュー | 可変 |
| 3 | OrderHistory | 発注履歴 | 数千行 |
| 4 | ExecutionLog | 約定履歴 | 数千行 |
| 5 | ErrorLog | エラーログ | 数百行 |
| 6 | PositionManager | ポジション管理 | 5-10行 |
| 7 | Config | システム設定 | 13行 |
| 8 | MarketCalendar | 市場カレンダー | 365行 |
| 9 | BlacklistTickers | ブラックリスト | 可変 |
| 10 | SystemState | システム状態 | 12行 |
| 11 | RSSInterface | RSS関数IF | 6行 |

---

## セットアップ

### 1. JsonConverterライブラリ導入

```
https://github.com/VBA-tools/VBA-JSON
```

`JsonConverter.bas` をダウンロード → VBEにインポート

### 2. VBAモジュールインポート

1. VBE起動（Alt+F11）
2. **ファイル** → **ファイルのインポート**
3. `modules/*.bas` を全てインポート
4. `ThisWorkbook.cls` の内容をコピー

### 3. 参照設定

**ツール** → **参照設定**:
- ✅ Microsoft Scripting Runtime

### 4. Config シート設定

```
API_BASE_URL: http://192.168.1.10:5000/api
API_KEY: your-api-key-here
CLIENT_ID: excel_vm_01
```

### 5. 詳細手順

詳細は **EXCEL_SETUP_GUIDE.md** を参照

---

## 使用方法

### 1. 手動起動

1. Dashboardシートを開く
2. **[▶ 開始]** ボタンをクリック
3. イミディエイトウィンドウで動作確認

### 2. 自動起動

**Config シート**:
```
ENABLE_AUTO_START: TRUE
```

Excelブック起動時に自動的に売買開始（3秒後）

### 3. 停止

- **[⏸ 一時停止]** - 一時停止（再開可能）
- **[⏹ 停止]** - 完全停止

### 4. 監視

**Dashboard シート**:
- システム状態
- 本日の取引状況
- リスク管理指標
- 最新シグナル（5件）

---

## データフロー

```
1. Application.OnTime (5秒毎)
   ↓
2. PollAndProcessSignals()
   ↓
3. FetchPendingSignals() → GET /api/signals/pending
   ↓
4. SignalQueue に追加
   ↓
5. ProcessNextSignal()
   ├─ AcknowledgeSignal() → POST /api/signals/{id}/ack
   ├─ IsAlreadyExecuted() (ローカル重複チェック)
   └─ ExecuteOrder() → RSS.ORDER()
   ↓
6. RecordOrder() → OrderHistory 記録
   ↓
7. PollOrderStatus() → RSS.STATUS() (別タイマー)
   ↓
8. RecordExecution() → ExecutionLog + PositionManager 更新
   ↓
9. ReportExecution() → POST /api/signals/{id}/executed
   ↓
10. UpdateDashboard() → リアルタイム表示
```

---

## テスト

### 1. API接続テスト

**イミディエイトウィンドウ**:
```vba
Debug.Print CheckAPIConnection()  ' True
```

### 2. シグナル取得テスト

```vba
Dim signals As Collection
Set signals = FetchPendingSignals()
Debug.Print signals.Count
```

### 3. RSS接続テスト

```vba
Debug.Print CheckRSSConnection()  ' True
```

### 4. 手動起動テスト

```vba
Call StartAutoTrading
' イミディエイトウィンドウで "Kabuto Auto Trading Started" 確認
```

---

## トラブルシューティング

### Q: JsonConverter でエラー

**A**: 参照設定で **Microsoft Scripting Runtime** にチェック

### Q: RSS.ORDER でエラー

**A**:
1. MarketSpeed II が起動しているか確認
2. RSSアドインが有効か確認
3. 銘柄コードが4桁数字か確認

### Q: API接続エラー

**A**:
1. Relay Serverが起動しているか確認
2. Config シートのURL・API_KEYが正しいか確認
3. ファイアウォール設定を確認

### Q: 自動起動しない

**A**:
1. `ENABLE_AUTO_START` が `TRUE` か確認
2. マクロが有効か確認
3. ThisWorkbook の Workbook_Open が正しいか確認

---

## Windows自動起動設定

### 1. タスクスケジューラ

**トリガー**: ログオン時
**プログラム**: `C:\Program Files\Microsoft Office\root\Office16\EXCEL.EXE`
**引数**: `C:\Kabuto\kabuto_auto_trader.xlsm`

### 2. 自動ログオン

```
Win+R → netplwiz
ユーザー選択 → パスワード不要にチェック
```

### 3. スリープ無効化

**設定** → **電源とスリープ** → **なし**

---

## セキュリティ

- **API Key**: Configシートを非表示（Hidden）
- **パスワード**: VBAプロジェクトにパスワード設定推奨
- **通信**: HTTPS推奨（本番環境）

---

## 依存ライブラリ

- **JsonConverter** (VBA-JSON): JSON解析
  - https://github.com/VBA-tools/VBA-JSON
- **Microsoft Scripting Runtime**: Dictionary, FileSystemObject

---

## ライセンス

Proprietary - 個人使用のみ

---

## 関連ドキュメント

- **設計書**: `../doc/13_excel_workbook_design.md`
- **セットアップガイド**: `EXCEL_SETUP_GUIDE.md`
- **Relay Server**: `../relay_server/README.md`
- **TradingView**: `../tradingview/README.md`

---

## サポート

Issue報告: 内部リポジトリ
