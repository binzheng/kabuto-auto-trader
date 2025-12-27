# Kabuto Auto Trader

**TradingView連携 日本株全自動売買システム**

[![Python](https://img.shields.io/badge/Python-3.11+-blue.svg)](https://www.python.org/)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.100+-green.svg)](https://fastapi.tiangolo.com/)
[![Excel VBA](https://img.shields.io/badge/Excel%20VBA-2016+-orange.svg)](https://docs.microsoft.com/en-us/office/vba/api/overview/excel)
[![MarketSpeed II](https://img.shields.io/badge/MarketSpeed%20II-RSS-red.svg)](https://marketspeed.jp/)

---

## 📖 概要

Kabuto Auto Traderは、TradingViewのアラートから楽天証券MarketSpeed IIでの自動発注まで、完全自動化された日本株トレーディングシステムです。

### 主な特徴

- ✅ **完全自動化**: TradingView → Relay Server → Excel VBA → MarketSpeed II RSS
- 🛡️ **6層防御機構**: パラメータ検証、リスク管理、二重下单防止、時間外防止
- 🚨 **Kill Switch**: 5連続損失、日次損失-5万円、異常頻度で自動停止
- 📊 **包括的ログ**: 6種類のログシート、90日自動アーカイブ
- 🔔 **Slack/Email通知**: 4レベル（INFO/WARNING/ERROR/CRITICAL）、頻度制限
- 📈 **リアルタイム監視**: Dashboard、約定ポーリング、Heartbeat

---

## 🏗️ システムアーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│                       TradingView                           │
│                    (Pine Script 戦略)                       │
└────────────────────────┬────────────────────────────────────┘
                         │ Webhook (HTTPS)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    Relay Server (VPS)                       │
│  ┌────────────────────────────────────────────────────┐    │
│  │  FastAPI + Uvicorn                                 │    │
│  │  - /api/signals/webhook    (TradingView受信)      │    │
│  │  - /api/signals/pending    (Excel取得)            │    │
│  │  - /api/signals/{id}/ack   (ACK受信)              │    │
│  │  - /api/signals/{id}/executed (約定報告受信)      │    │
│  │  - /api/heartbeat          (生存確認)              │    │
│  └────────────────────────────────────────────────────┘    │
└────────────────────────┬────────────────────────────────────┘
                         │ HTTP API (polling 5秒)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              Excel VBA Client (Windows PC)                  │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Module_Main.bas           (メインループ)          │    │
│  │  Module_API.bas            (API通信)               │    │
│  │  Module_SignalProcessor.bas (信号処理)            │    │
│  │  Module_RSS.bas            (RSS連携・6層防御)      │    │
│  │  Module_OrderManager.bas   (注文・ポジション管理)  │    │
│  │  Module_Logger.bas         (18関数ログ記録)       │    │
│  │  Module_Notification.bas   (Slack/Email通知)      │    │
│  │  Module_Config.bas         (設定・安全装置)        │    │
│  └────────────────────────────────────────────────────┘    │
└────────────────────────┬────────────────────────────────────┘
                         │ COM (RSS)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              MarketSpeed II (楽天証券)                      │
│  - RSS.ORDER() 関数で自動発注                               │
│  - 約定状態のポーリング監視                                  │
└─────────────────────────────────────────────────────────────┘
```

---

## 📊 実装状況

**最終更新**: 2025-12-27

### コード実装: 🟢 100%

| コンポーネント | 状態 | 詳細 |
|--------------|------|------|
| **Relay Server** | ✅ 100% | FastAPI、全エンドポイント、notification.py |
| **Excel VBA** | ✅ 100% | 8モジュール、127関数、3,878行 |
| **設計ドキュメント** | ✅ 100% | 22ファイル完成 |

**Excel VBA モジュール**:
- Module_Main.bas (235行, 9関数)
- Module_API.bas (241行, 6関数)
- Module_RSS.bas (1,132行, 32関数)
- Module_SignalProcessor.bas (194行, 5関数)
- Module_Config.bas (355行, 10関数)
- Module_OrderManager.bas (286行, 6関数)
- Module_Logger.bas (662行, 18関数) ⭐ 拡張完了
- Module_Notification.bas (663行, 15関数) ⭐ 新規追加

**Relay Server**:
- app/main.py - FastAPI メイン
- app/routers/ - API エンドポイント
- app/core/notification.py (354行, 3クラス) ⭐ 新規追加

### 手動作業: 🟡 73%

**Excelシート**:
- ✅ 既存シート: 11/15 (Config, SystemState, SignalQueue, OrderHistory, ExecutionLog, ErrorLog, CurrentPositions, Dashboard, DailyReports, HolidayCalendar, RiskSettings)
- ⚠️ 未作成シート: 4/15
  - NotificationHistory (4列) - 通知頻度制限用
  - SignalLog (19列) - シグナル受信記録
  - SystemLog (16列) - システムイベント記録
  - AuditLog (19列) - 監査用完全履歴

**シート仕様書**:
- ✅ `excel_vba/sheets/NotificationHistory_sheet_spec.md`
- ✅ `excel_vba/sheets/additional_log_sheets_spec.md`

### テストインフラ: 🔴 0%

- ⚠️ 単体・統合・E2Eテスト: 未実装
- ⚠️ CI/CDパイプライン: 未実装
- 📄 doc/21_server_test_plan.md に詳細計画あり

**詳細**: `IMPLEMENTATION_VERIFICATION.md` を参照

---

## 🚀 セットアップ

### 前提条件

**VPS (Relay Server用)**:
- Ubuntu 22.04 LTS
- Python 3.11+
- ポート 8000 を外部公開

**Windows PC (Excel VBA Client用)**:
- Windows 10/11
- Excel 2016以降（VBA有効）
- MarketSpeed II インストール済み、RSS有効
- インターネット接続安定

**通知設定**:
- Slack Webhook URL（4レベル分: INFO, WARNING, ERROR, CRITICAL）
- SMTP設定（Gmail等）

---

### 1. Relay Server セットアップ

```bash
# リポジトリクローン
git clone <repository-url>
cd kabuto/relay_server

# Python仮想環境作成
python3.11 -m venv venv
source venv/bin/activate

# 依存関係インストール
pip install -r requirements.txt

# 環境変数設定
cp .env.example .env
nano .env  # DATABASE_URL, SECRET_KEY 等を設定

# データベースマイグレーション
alembic upgrade head

# サーバー起動
uvicorn app.main:app --host 0.0.0.0 --port 8000

# バックグラウンド起動（本番）
nohup uvicorn app.main:app --host 0.0.0.0 --port 8000 >> /var/log/kabuto/relay_server.log 2>&1 &
```

**ヘルスチェック**:
```bash
curl http://localhost:8000/health
# 期待結果: {"status": "healthy"}
```

---

### 2. Excel VBA Client セットアップ

#### 2.1 Excelブック作成

1. **新規Excelブック作成**:
   - ファイル名: `Kabuto Auto Trader.xlsm` (マクロ有効)

2. **シート作成** (11シート):
   - Config
   - SystemState
   - SignalQueue
   - OrderHistory
   - ExecutionLog
   - ErrorLog
   - CurrentPositions
   - Dashboard
   - DailyReports
   - HolidayCalendar
   - RiskSettings

3. **追加シート作成** (4シート - 手動作業):
   - NotificationHistory (4列) - `excel_vba/sheets/NotificationHistory_sheet_spec.md` 参照
   - SignalLog (19列) - `excel_vba/sheets/additional_log_sheets_spec.md` 参照
   - SystemLog (16列) - `excel_vba/sheets/additional_log_sheets_spec.md` 参照
   - AuditLog (19列) - `excel_vba/sheets/additional_log_sheets_spec.md` 参照

#### 2.2 VBAモジュールインポート

```
1. Excel VBA エディタを開く (Alt + F11)
2. ファイル > ファイルのインポート
3. 以下のファイルを順次インポート:
   - excel_vba/modules/Module_Main.bas
   - excel_vba/modules/Module_API.bas
   - excel_vba/modules/Module_RSS.bas
   - excel_vba/modules/Module_SignalProcessor.bas
   - excel_vba/modules/Module_Config.bas
   - excel_vba/modules/Module_OrderManager.bas
   - excel_vba/modules/Module_Logger.bas
   - excel_vba/modules/Module_Notification.bas
   - excel_vba/ThisWorkbook.cls (クラスモジュール)
```

#### 2.3 Config シート設定

| 設定項目 | 値 | 備考 |
|---------|-----|------|
| `API_BASE_URL` | `http://your-vps-ip:8000` | VPSのIPアドレス |
| `CLIENT_ID` | `CLIENT-001` | 一意のクライアントID |
| `SLACK_WEBHOOK_INFO` | `https://hooks.slack.com/...` | INFO通知用 |
| `SLACK_WEBHOOK_WARNING` | `https://hooks.slack.com/...` | WARNING通知用 |
| `SLACK_WEBHOOK_ERROR` | `https://hooks.slack.com/...` | ERROR通知用 |
| `SLACK_WEBHOOK_CRITICAL` | `https://hooks.slack.com/...` | CRITICAL通知用 |
| `SMTP_SERVER` | `smtp.gmail.com` | SMTPサーバー |
| `SMTP_PORT` | `587` | SMTPポート |
| `SMTP_USERNAME` | `your-email@gmail.com` | SMTPユーザー名 |
| `SMTP_PASSWORD` | `your-app-password` | SMTPパスワード |
| `SMTP_FROM` | `your-email@gmail.com` | 送信元アドレス |
| `SMTP_TO` | `alert@example.com` | 送信先アドレス |
| `KILL_SWITCH_ACTIVE` | `FALSE` | 手動Kill Switch |
| `MAX_DAILY_LOSS` | `-50000` | 日次損失限度（円） |
| `MAX_TRADES_PER_HOUR` | `10` | 1時間最大取引数 |
| `MAX_POSITION_SIZE` | `1000` | 最大ポジション数量 |

---

### 3. TradingView 設定

#### 3.1 戦略作成

Pine Script で戦略を作成（例: doc/20_tradingview_backtest.md 参照）

#### 3.2 アラート設定

```
1. TradingView チャートでアラート作成
2. Webhook URL: http://your-vps-ip:8000/api/signals/webhook
3. Message (JSON形式):

{
  "signal_id": "SIG-{{time}}",
  "timestamp": "{{timenow}}",
  "strategy": "your-strategy-name",
  "ticker": "{{ticker}}",
  "ticker_name": "{{ticker}}",
  "action": "{{strategy.order.action}}",
  "quantity": 100,
  "price_type": "market",
  "limit_price": null,
  "signal_strength": 0.8
}

4. 保存
```

---

## 🎯 使用方法

### 日次運用フロー

**詳細**: `doc/22_daily_operations.md` および `doc/22_daily_checklist.md` を参照

#### 朝の起動（8:00-9:20）

```
8:00  VPS サーバー起動確認
      MarketSpeed II 起動・ログイン
      Excel ブック起動

8:30  API接続テスト: CheckAPIConnection()
      RSS接続テスト: CheckRSSConnection()
      SystemState シート確認

9:00  起動前最終チェック（11項目）

9:20  自動売買開始:
      Dashboard シート > 「自動売買開始」ボタンクリック
```

#### 市場中の監視（9:30-15:00）

- **Slack/Email通知監視**:
  - INFO (緑): 正常動作
  - WARNING (黄): ErrorLog確認
  - ERROR (赤): 原因調査
  - CRITICAL (鮮紅): **即座に対応**

- **Dashboard 定期確認** (10:30, 12:30, 14:30):
  - システム状態: `running`
  - API/RSS接続: `connected`
  - 本日損益: -50,000円以上
  - 本日取引回数: 0-20回

#### 夕方の停止（15:05-17:30）

```
15:05 未決済ポジション確認
      Dashboard > 「自動売買停止」ボタンクリック

15:10 本日の取引レビュー（損益・勝率確認）

15:30 ErrorLog 確認

17:30 Excel ブック保存・バックアップ
```

---

## 🛡️ 安全機構

### 6層防御機構

1. **パラメータ検証**: ticker, side, quantity, price_type, price, condition
2. **市場時間チェック**: 営業日、市場開場時間、安全時間窓
3. **リスク限度チェック**: ポジションサイズ、日次損失、取引頻度
4. **重複防止（3層）**: SignalQueue, ExecutionLog, Cooldown
5. **ダブルチェック**: 発注前の最終確認
6. **監査ログ**: 全操作の完全記録

### Kill Switch（緊急停止）

**自動トリガー**:
- 🔴 5連続損失
- 🔴 日次損失 -50,000円以下
- 🔴 1時間に10回以上取引

**手動トリガー**:
- Config シートで `KILL_SWITCH_ACTIVE = TRUE`

**発動時の対応**:
1. AuditLog で発動理由確認
2. 原因分析（戦略 or システム）
3. 対策実施
4. 再開判断・実施

---

## 📊 ログ・通知

### ログシート（6種類）

| シート名 | 用途 | ログID形式 | 保存期間 |
|---------|------|-----------|---------|
| SignalLog | シグナル受信記録 | SL-YYYYMMDD-NNN | 90日 |
| OrderHistory | 注文履歴 | ORD-YYYYMMDD-NNN | 永久 |
| ExecutionLog | 約定履歴 | EXE-YYYYMMDD-NNN | 永久 |
| SystemLog | システムイベント | SYS-YYYYMMDD-HHNNSS | 90日 |
| AuditLog | 監査用完全履歴 | AUD-YYYYMMDD-NNN | 永久 |
| ErrorLog | エラーログ | ERR-YYYYMMDD-HHNNSS | 90日 |

**自動アーカイブ**: 90日以上のログを `_Archive` シートに移動

### 通知システム

**Slack/Email 通知レベル**:

| レベル | 色 | アイコン | Slack | Email | 頻度制限 |
|-------|-----|---------|-------|-------|---------|
| INFO | 緑 | ℹ️ | ✅ | ❌ | なし |
| WARNING | 黄 | ⚠️ | ✅ | ❌ | 30分 |
| ERROR | 赤 | 🚨 | ✅ | ✅ | 15分 |
| CRITICAL | 鮮紅 | 🚨🚨🚨 | ✅ | ✅ | なし |

**通知イベント**:
- 発注失敗（WARNING）
- 連続発注失敗（ERROR）
- Kill Switch発動（CRITICAL）
- エラー頻発（ERROR）
- API接続断（ERROR）
- システムイベント（INFO/WARNING）

---

## 📁 プロジェクト構成

```
kabuto/
├── README.md                          # このファイル
├── IMPLEMENTATION_VERIFICATION.md     # 実装検証レポート
│
├── doc/                               # 設計ドキュメント（22ファイル）
│   ├── README.md                      # 設計書索引
│   ├── 01_system_overview.md          # システム全体設計
│   ├── 02_relay_server_design.md      # Relay Server 設計
│   ├── 03_excel_vba_design.md         # Excel VBA 設計
│   ├── 04_signal_flow.md              # シグナルフロー
│   ├── 05_data_models.md              # データモデル
│   ├── 06_validation_rules.md         # 検証ルール
│   ├── 07_risk_management.md          # リスク管理
│   ├── 08_duplicate_prevention.md     # 重複防止
│   ├── 09_time_safety.md              # 時間安全
│   ├── 10_kill_switch.md              # Kill Switch
│   ├── 11_order_execution.md          # 注文実行
│   ├── 12_position_management.md      # ポジション管理
│   ├── 13_execution_reporting.md      # 約定報告
│   ├── 14_rss_safe_order.md           # RSS安全発注
│   ├── 15_heartbeat.md                # Heartbeat
│   ├── 16_excel_vba_signal_to_order.md # Excel VBA 統合
│   ├── 17_excel_safety_defense.md     # Excel 安全装置
│   ├── 18_logging_design.md           # ログ設計
│   ├── 19_notification_design.md      # 通知設計
│   ├── 20_tradingview_backtest.md     # TradingView Backtest
│   ├── 21_server_test_plan.md         # サーバーテスト計画
│   ├── 22_daily_operations.md         # 日次運用フロー
│   └── 22_daily_checklist.md          # 印刷用チェックリスト
│
├── relay_server/                      # Relay Server (Python/FastAPI)
│   ├── app/
│   │   ├── main.py                    # FastAPI メイン
│   │   ├── core/
│   │   │   └── notification.py        # 通知システム
│   │   ├── routers/
│   │   │   ├── signals.py             # シグナルAPI
│   │   │   └── heartbeat.py           # Heartbeat API
│   │   └── models/
│   ├── requirements.txt
│   └── .env.example
│
└── excel_vba/                         # Excel VBA Client
    ├── modules/
    │   ├── Module_Main.bas            # メインループ
    │   ├── Module_API.bas             # API通信
    │   ├── Module_RSS.bas             # RSS連携
    │   ├── Module_SignalProcessor.bas # シグナル処理
    │   ├── Module_Config.bas          # 設定管理
    │   ├── Module_OrderManager.bas    # 注文管理
    │   ├── Module_Logger.bas          # ログ記録（18関数）
    │   └── Module_Notification.bas    # 通知（15関数）
    ├── ThisWorkbook.cls               # イベントハンドラ
    └── sheets/
        ├── NotificationHistory_sheet_spec.md
        └── additional_log_sheets_spec.md
```

---

## 🔧 トラブルシューティング

### Q1. シグナルが来ない

**確認項目**:
1. TradingView アラート設定（Webhook URL正しいか）
2. Relay Server 稼働（`ps aux | grep uvicorn`）
3. Excel VBA ポーリング（Dashboard の `last_poll_time` 更新中か）

---

### Q2. 発注されない

**確認項目**:
1. SignalQueue にシグナルがあるか
2. ErrorLog のエラー内容確認
3. OrderHistory の `blocked_reason` 確認

**よくある理由**:
- `Time check failed`: 時間外
- `Risk limit exceeded`: リスク限度超過
- `Duplicate order`: 重複防止機構作動

---

### Q3. API接続断

**対応**:
```bash
# VPS サーバー確認
ssh user@your-vps-server
ps aux | grep uvicorn

# サーバー再起動
cd /path/to/kabuto/relay_server
source venv/bin/activate
nohup uvicorn app.main:app --host 0.0.0.0 --port 8000 >> /var/log/kabuto/relay_server.log 2>&1 &

# Excel VBA で再接続確認
? CheckAPIConnection()
```

---

### Q4. RSS接続断

**対応**:
```
1. MarketSpeed II 起動確認
2. MarketSpeed II 再起動
3. RSS 有効化確認（ツール > RSS設定）
4. Excel VBA で再接続確認: CheckRSSConnection()
```

---

### Q5. Kill Switch 発動

**対応**:
1. AuditLog で発動理由確認（`operation = "KILL_SWITCH"`）
2. 発動理由の妥当性判断
3. 原因分析（戦略の問題 or システムの問題）
4. 対策実施
5. Config で `KILL_SWITCH_ACTIVE = FALSE`
6. Dashboard で「自動売買開始」ボタンクリック

---

## 📚 ドキュメント

### 設計書（全22ファイル）

**索引**: `doc/README.md`

**用途別ガイド**:
- **初めて読む**: doc/01 → doc/04 → doc/22
- **実装する**: doc/02-03 → doc/14-19
- **運用する**: doc/22 → doc/22_daily_checklist.md
- **トラブル対応**: doc/22 (トラブルシューティング)

### 実装検証

- `IMPLEMENTATION_VERIFICATION.md` - 実装状況の詳細レポート

---

## 🎓 開発ガイド

### Relay Server 開発

```bash
cd relay_server

# 開発サーバー起動（ホットリロード）
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# テスト実行（未実装）
pytest

# ログ確認
tail -f /var/log/kabuto/relay_server.log
```

### Excel VBA 開発

```
1. Excel VBA エディタを開く (Alt + F11)
2. モジュールを編集
3. イミディエイトウィンドウ (Ctrl + G) でテスト実行
4. 保存 (Ctrl + S)
```

**VBAデバッグ**:
```vba
' イミディエイトウィンドウで実行

? CheckAPIConnection()        ' API接続テスト
? CheckRSSConnection()         ' RSS接続テスト
? FetchPendingSignals()        ' シグナル取得テスト
PollAndProcessSignals          ' ポーリング1回実行
```

---

## 🔐 セキュリティ

### 推奨事項

1. **API KEY 管理**:
   - `.env` ファイルをGit管理外に
   - `.env.example` をテンプレートとして提供

2. **HTTPS 通信**:
   - TradingView → Relay Server は HTTPS推奨
   - Let's Encrypt で無料SSL証明書取得

3. **Webhook 認証**:
   - TradingView Webhook に秘密トークン追加検討

4. **SSH キー認証**:
   - VPS への SSH 接続はキー認証のみ
   - パスワード認証無効化

5. **定期パスワード変更**:
   - Slack Webhook URL
   - SMTP パスワード
   - SSH キー

---

## 📈 パフォーマンス

### 最適化項目

- **ポーリング間隔**: 5秒（調整可能、Config シート）
- **Heartbeat間隔**: 5分（調整可能）
- **ログアーカイブ**: 90日（調整可能、Module_Logger.bas）

### リソース要件

**VPS**:
- CPU: 1コア以上
- メモリ: 1GB以上
- ディスク: 10GB以上

**Windows PC**:
- CPU: デュアルコア以上
- メモリ: 4GB以上
- Excel: 2016以降
- MarketSpeed II: 最新版

---

## 🤝 コントリビューション

このプロジェクトは個人用トレーディングシステムです。

フォーク・改変は自由ですが、自己責任でご使用ください。

---

## ⚠️ 免責事項

- このシステムは教育目的で開発されています
- 実際の取引で発生した損失について、開発者は一切の責任を負いません
- 運用は自己責任で行ってください
- 戦略のバックテスト・フォワードテストを十分に実施してください
- 少額での運用から開始することを強く推奨します

---

## 📄 ライセンス

このプロジェクトは個人使用を目的としています。

---

## 📞 サポート

- **設計書**: `doc/README.md` - 設計書索引
- **実装状況**: `IMPLEMENTATION_VERIFICATION.md`
- **運用方法**: `doc/22_daily_operations.md`
- **チェックリスト**: `doc/22_daily_checklist.md`

---

## 🎉 クイックスタート

### 最速で動かす（3ステップ）

#### 1. Relay Server 起動

```bash
cd relay_server
python3.11 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

#### 2. Excel VBA セットアップ

```
1. Kabuto Auto Trader.xlsm 作成
2. VBAモジュール8個をインポート
3. Config シートで API_BASE_URL 設定
```

#### 3. 運用開始

```
1. doc/22_daily_checklist.md を印刷
2. チェックリストに従って起動
3. Dashboard > 「自動売買開始」ボタンクリック
```

**詳細手順**: `doc/22_daily_operations.md` を参照

---

**🚀 Kabuto Auto Trader で安全・確実な自動トレーディングを！**

最終更新: 2025-12-27
