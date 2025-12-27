# NotificationHistory シート仕様

## 概要
通知履歴を記録し、通知頻度制限を管理するシート

## シート構造

| 列 | 列名 | データ型 | 説明 | 例 |
|----|------|---------|------|-----|
| A | level | TEXT | 通知レベル | WARNING / ERROR / CRITICAL |
| B | title | TEXT | 通知タイトル | 発注失敗 / Kill Switch発動 |
| C | last_notify_time | DATETIME | 前回通知時刻 | 2025-01-27 09:05:30 |
| D | notify_count | INTEGER | 通知回数 | 5 |

## ヘッダー行（1行目）

```
A1: level
B1: title
C1: last_notify_time
D1: notify_count
```

## サンプルデータ

| level | title | last_notify_time | notify_count |
|-------|-------|-----------------|--------------|
| WARNING | 発注失敗 | 2025-01-27 09:05:30 | 3 |
| ERROR | 連続発注失敗（3回） | 2025-01-27 09:15:45 | 1 |
| CRITICAL | KILL SWITCH 発動 | 2025-01-27 14:30:15 | 1 |
| ERROR | エラー頻発検知 | 2025-01-27 10:20:00 | 2 |
| ERROR | API接続断 | 2025-01-27 11:00:00 | 1 |

## 初期化SQL（参考）

このシートはExcelブック内に手動で作成する必要があります。

## 使用される関数

- `GetLastNotificationTime(title)` - 前回通知時刻を取得
- `RecordNotification(level, title)` - 通知履歴を記録
- `ShouldSendNotification(level, title)` - 通知頻度制限チェック

## 注意事項

- このシートは自動で作成されません
- Excelブックに手動で追加する必要があります
- ヘッダー行（1行目）は必ず設定してください
