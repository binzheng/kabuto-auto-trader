# 追加ログシート仕様

## 1. SignalLog シート

### 概要
サーバーから受信した全シグナルを記録

### 列構造

| 列 | 列名 | データ型 | 説明 |
|----|------|---------|------|
| A | log_id | TEXT | ログID（SL-YYYYMMDD-NNN） |
| B | timestamp | DATETIME | 受信日時 |
| C | signal_id | TEXT | シグナルID |
| D | strategy | TEXT | 戦略名 |
| E | ticker | TEXT | 銘柄コード |
| F | ticker_name | TEXT | 銘柄名 |
| G | action | TEXT | 売買区分（buy/sell） |
| H | quantity | INTEGER | 数量 |
| I | price_type | TEXT | 価格タイプ |
| J | limit_price | DECIMAL | 指値価格 |
| K | signal_strength | DECIMAL | シグナル強度 |
| L | checksum | TEXT | チェックサム |
| M | status | TEXT | 処理状態 |
| N | queue_time | DATETIME | キュー投入時刻 |
| O | processing_time | DATETIME | 処理開始時刻 |
| P | completed_time | DATETIME | 完了時刻 |
| Q | error_message | TEXT | エラーメッセージ |
| R | ack_sent | BOOLEAN | ACK送信済み |
| S | notes | TEXT | 備考 |

---

## 2. SystemLog シート

### 概要
システム稼働状況・イベントを記録

### 列構造

| 列 | 列名 | データ型 | 説明 |
|----|------|---------|------|
| A | log_id | TEXT | ログID（SYS-YYYYMMDD-HHNNSS） |
| B | timestamp | DATETIME | 日時 |
| C | level | TEXT | ログレベル（INFO/DEBUG/WARNING） |
| D | category | TEXT | カテゴリ |
| E | event | TEXT | イベント名 |
| F | message | TEXT | メッセージ |
| G | module | TEXT | モジュール名 |
| H | function | TEXT | 関数名 |
| I | details | TEXT | 詳細情報 |
| J | system_status | TEXT | システム状態 |
| K | api_status | TEXT | API接続状態 |
| L | rss_status | TEXT | RSS接続状態 |
| M | market_session | TEXT | 市場セッション |
| N | cpu_usage | DECIMAL | CPU使用率（将来実装） |
| O | memory_usage | DECIMAL | メモリ使用率（将来実装） |
| P | notes | TEXT | 備考 |

---

## 3. AuditLog シート

### 概要
コンプライアンス・監査用の完全な操作履歴

### 列構造

| 列 | 列名 | データ型 | 説明 |
|----|------|---------|------|
| A | audit_id | TEXT | 監査ID（AUD-YYYYMMDD-NNN） |
| B | timestamp | DATETIME | 日時 |
| C | operation | TEXT | 操作種別 |
| D | operator | TEXT | 操作者（AUTO/MANUAL） |
| E | signal_id | TEXT | 信号ID |
| F | internal_order_id | TEXT | 内部注文ID |
| G | ticker | TEXT | 銘柄コード |
| H | action | TEXT | 売買区分 |
| I | quantity | INTEGER | 数量 |
| J | price | DECIMAL | 価格 |
| K | validation_passed | BOOLEAN | 検証通過 |
| L | safety_checks | TEXT | 安全チェック |
| M | risk_checks | TEXT | リスクチェック |
| N | market_session | TEXT | 市場セッション |
| O | system_status | TEXT | システム状態 |
| P | result | TEXT | 実行結果（SUCCESS/FAILED/BLOCKED） |
| Q | result_detail | TEXT | 結果詳細 |
| R | checksum | TEXT | チェックサム |
| S | notes | TEXT | 備考 |

---

## シート作成手順

これらのシートは手動でExcelブックに追加する必要があります：

1. Excelブックを開く
2. 新しいシートを挿入
3. シート名を変更（SignalLog、SystemLog、AuditLog）
4. 1行目にヘッダーを設定（上記列名を参照）
5. 列の書式設定:
   - DATETIME列: `YYYY-MM-DD HH:MM:SS`
   - DECIMAL列: 数値、小数点2桁
   - BOOLEAN列: TRUE/FALSE

## 注意事項

- これらのシートは VBA コードから参照されます
- シート名は正確に一致させてください
- ヘッダー行（1行目）は必須です
- 保存期間: SignalLog/SystemLog は 90日、AuditLog は永久
