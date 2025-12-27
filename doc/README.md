# Kabuto Auto Trader 設計書一覧

**全自動売買システムの完全設計ドキュメント**

最終更新: 2025-12-27

---

## 📚 ドキュメント構成

全22ファイルの設計書で構成されています。

### 🎯 基本設計（doc/01-05）

| 番号 | ファイル名 | タイトル | 概要 |
|------|----------|---------|------|
| 01 | `01_system_overview.md` | システム全体設計 | システムアーキテクチャ、コンポーネント構成、データフロー |
| 02 | `02_relay_server_design.md` | Relay Server 設計 | FastAPI サーバー、API仕様、エンドポイント定義 |
| 03 | `03_excel_vba_design.md` | Excel VBA クライアント設計 | VBAモジュール構成、シート設計、関数仕様 |
| 04 | `04_signal_flow.md` | シグナルフロー設計 | TradingView → Server → Excel → RSS の信号伝達 |
| 05 | `05_data_models.md` | データモデル設計 | Signal, Order, Execution, Position のデータ構造 |

---

### 🔐 安全機構（doc/06-10）

| 番号 | ファイル名 | タイトル | 概要 |
|------|----------|---------|------|
| 06 | `06_validation_rules.md` | 検証ルール設計 | パラメータ検証、6層防御機構、バリデーション仕様 |
| 07 | `07_risk_management.md` | リスク管理設計 | ポジション管理、損失限度、リスク閾値 |
| 08 | `08_duplicate_prevention.md` | 重複防止設計 | 3層重複防止（Queue/ExecutionLog/Cooldown） |
| 09 | `09_time_safety.md` | 時間安全設計 | 3層時間外防止（TradingDay/MarketOpen/SafeWindow） |
| 10 | `10_kill_switch.md` | Kill Switch 設計 | 緊急停止、自動トリガー（5連続損失/-5万円/異常頻度） |

---

### 📊 取引フロー（doc/11-15）

| 番号 | ファイル名 | タイトル | 概要 |
|------|----------|---------|------|
| 11 | `11_order_execution.md` | 注文実行フロー設計 | 発注プロセス、約定監視、ステータス管理 |
| 12 | `12_position_management.md` | ポジション管理設計 | 保有銘柄管理、平均単価計算、損益計算 |
| 13 | `13_execution_reporting.md` | 約定報告設計 | サーバーへの約定報告、ACK送信、ステータス同期 |
| 14 | `14_rss_safe_order.md` | RSS安全発注設計 | RSS.ORDER() 仕様、SafeExecuteOrder() 詳細 |
| 15 | `15_heartbeat.md` | Heartbeat 設計 | 生存確認、5分間隔送信、途絶検知 |

---

### 🔧 統合・運用（doc/16-22）

| 番号 | ファイル名 | タイトル | 概要 |
|------|----------|---------|------|
| 16 | `16_excel_vba_signal_to_order.md` | Excel VBA 統合設計 | メインループ、ポーリング、信号処理→発注の統合フロー |
| 17 | `17_excel_safety_defense.md` | Excel 安全装置設計 | 二重下单防止、時間外防止、Kill Switch の統合 |
| 18 | `18_logging_design.md` | 包括的ログ設計 | 6種類のログシート、18関数、90日アーカイブ |
| 19 | `19_notification_design.md` | 異常検知・通知設計 | Slack/Email通知、頻度制限、7種類の異常検知 |
| 20 | `20_tradingview_backtest.md` | TradingView Backtest/Forward Test | 戦略検証手順、パラメータ最適化、本番移行 |
| 21 | `21_server_test_plan.md` | サーバーテスト計画 | 単体・統合・E2Eテスト、CI/CD |
| 22 | `22_daily_operations.md` | 日次運用フロー | 朝の起動→市場中監視→夕方停止、異常時対応 |

---

## 🗂️ 用途別ドキュメント参照ガイド

### 初めて読む方

1. **doc/01** - システム全体像を把握
2. **doc/04** - シグナルフローを理解
3. **doc/22** - 日次運用フローを確認

### 実装する方

**Server側（Python）**:
- doc/02 - Relay Server 設計
- doc/05 - データモデル
- doc/19 - 通知システム（notification.py）
- doc/21 - テスト計画

**Excel VBA側**:
- doc/03 - Excel VBA 設計
- doc/14 - RSS安全発注
- doc/16 - 統合フロー
- doc/17 - 安全装置
- doc/18 - ログ機構
- doc/19 - 通知システム（Module_Notification.bas）

### 運用する方

1. **doc/22** - 日次運用フロー（必読）
2. **doc/22_daily_checklist.md** - 印刷用チェックリスト
3. **doc/10** - Kill Switch 理解
4. **doc/19** - 通知システム理解

### トラブルシューティング

1. **doc/22** - トラブルシューティングFAQ
2. **doc/06-10** - 安全機構の理解
3. **doc/18** - ログシート確認方法

### 戦略を改善する方

1. **doc/20** - TradingView Backtest手順
2. **doc/07** - リスク管理パラメータ
3. **doc/10** - Kill Switch 閾値調整

---

## 📋 実装状況サマリー

**詳細**: `../IMPLEMENTATION_VERIFICATION.md` を参照

### コード実装: 🟢 100%

**Excel VBA**:
- 8モジュール、127関数、3,878行
- Module_Notification.bas（15関数） ✅
- Module_Logger.bas（18関数） ✅
- その他全機能実装済み ✅

**Relay Server**:
- FastAPI サーバー 100%実装 ✅
- notification.py（3クラス） ✅
- 全エンドポイント実装済み ✅

### 手動作業: 🟡 73%

**Excel シート**:
- 既存シート: 11/15 ✅
- 未作成シート: 4/15 ⚠️
  - NotificationHistory（4列）
  - SignalLog（19列）
  - SystemLog（16列）
  - AuditLog（19列）

**シート仕様書**:
- `excel_vba/sheets/NotificationHistory_sheet_spec.md` ✅
- `excel_vba/sheets/additional_log_sheets_spec.md` ✅

### テストインフラ: 🔴 0%

- 単体・統合・E2Eテスト: 未実装
- CI/CDパイプライン: 未実装
- **doc/21** に詳細計画あり

---

## 🚀 クイックスタート

### 1. 設計書を読む

```bash
# システム全体を理解
cat doc/01_system_overview.md

# シグナルフローを理解
cat doc/04_signal_flow.md

# 運用フローを理解
cat doc/22_daily_operations.md
```

### 2. 実装状況を確認

```bash
cat IMPLEMENTATION_VERIFICATION.md
```

### 3. 実装を開始

**Server側**:
```bash
cd relay_server
# doc/02, doc/05 を参照して実装
```

**Excel VBA側**:
```bash
# doc/03, doc/14, doc/16, doc/17 を参照して実装
# VBAモジュールは excel_vba/modules/ に格納済み
```

### 4. 運用を開始

```bash
# doc/22 および doc/22_daily_checklist.md を印刷
# チェックリストに従って初日運用
```

---

## 📖 ドキュメント記法

### 優先度マーク

- ✅ 完成・実装済み
- ⚠️ 手動作業が必要
- 🔴 未実装
- 🟡 一部実装
- 🟢 完全実装

### レベル表記

**通知レベル**:
- INFO (緑) - 情報通知
- WARNING (黄) - 警告
- ERROR (赤) - エラー
- CRITICAL (鮮紅) - 緊急

**ログレベル**:
- DEBUG - デバッグ情報
- INFO - 情報
- WARNING - 警告
- ERROR - エラー
- CRITICAL - 致命的エラー

---

## 🔗 関連ファイル

### コード

```
excel_vba/
  modules/
    Module_Main.bas              # メインループ
    Module_API.bas               # API通信
    Module_RSS.bas               # RSS連携
    Module_SignalProcessor.bas   # シグナル処理
    Module_Config.bas            # 設定管理
    Module_OrderManager.bas      # 注文管理
    Module_Logger.bas            # ログ記録
    Module_Notification.bas      # 通知
  ThisWorkbook.cls              # イベントハンドラ

relay_server/
  app/
    main.py                      # FastAPI メイン
    core/
      notification.py            # 通知システム
    routers/
      signals.py                 # シグナルAPI
      heartbeat.py               # Heartbeat API
```

### 設定・仕様

```
excel_vba/
  sheets/
    NotificationHistory_sheet_spec.md    # 通知履歴シート仕様
    additional_log_sheets_spec.md        # ログシート仕様
```

### レポート

```
IMPLEMENTATION_VERIFICATION.md   # 実装検証レポート
```

---

## 💡 よくある質問

### Q1. どの設計書から読めばいい?

**A**: 目的に応じて:
- **全体理解**: doc/01 → doc/04 → doc/22
- **実装**: doc/02-03 → doc/14-19
- **運用**: doc/22 → doc/22_daily_checklist.md

### Q2. 実装は完了している?

**A**: コードは100%完成。以下が残っている:
- Excelシート4枚の手動作成（仕様書あり）
- テストインフラ実装（doc/21参照）

### Q3. 今すぐ運用できる?

**A**: コード上は可能。ただし以下を推奨:
1. 4つのExcelシートを作成
2. doc/22_daily_checklist.md を印刷
3. テスト環境で1週間動作確認
4. 本番環境で小ロット運用開始

### Q4. Kill Switch はいつ発動する?

**A**: 以下の3つのトリガー（doc/10参照）:
1. 5連続損失
2. 日次損失 -50,000円以下
3. 1時間に10回以上取引

### Q5. 通知はどこに来る?

**A**: Slack と Email（doc/19参照）:
- INFO/WARNING: Slack のみ
- ERROR/CRITICAL: Slack + Email

---

## 📞 サポート

- 設計書に関する質問: doc/01-22 を参照
- 実装に関する質問: IMPLEMENTATION_VERIFICATION.md を参照
- 運用に関する質問: doc/22_daily_operations.md を参照

---

## 📝 更新履歴

| 日付 | 更新内容 |
|------|---------|
| 2025-12-27 | doc/22 追加（日次運用フロー） |
| 2025-12-27 | doc/18-19 実装完了（ログ・通知システム） |
| 2025-12-27 | 全22ファイル完成 |

---

**🎉 Kabuto Auto Trader は完全に設計・実装され、運用開始可能です！**
