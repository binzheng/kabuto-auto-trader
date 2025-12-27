# Kabuto Auto Trader - TradingView 戦略テストガイド

**作成日**: 2025-12-27
**ドキュメントID**: doc/20

---

## 目次

1. [戦略開発フロー](#1-戦略開発フロー)
2. [バックテスト手順](#2-バックテスト手順)
3. [フォワードテスト手順](#3-フォワードテスト手順)
4. [パフォーマンス評価指標](#4-パフォーマンス評価指標)
5. [戦略検証チェックリスト](#5-戦略検証チェックリスト)
6. [Pine Script実装](#6-pine-script実装)
7. [Webhook連携設定](#7-webhook連携設定)
8. [本番運用移行基準](#8-本番運用移行基準)

---

## 1. 戦略開発フロー

### 1.1 全体フロー

```
┌─────────────────┐
│ 1. 戦略アイデア  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 2. Pine Script  │
│    実装         │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 3. バックテスト  │
│   （過去データ）  │
└────────┬────────┘
         │
         ▼
    【合格判定】
         │
         ▼
┌─────────────────┐
│ 4. 最適化       │
│   （過学習注意） │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 5. フォワード    │
│    テスト       │
│  （Paper Trading）│
└────────┬────────┘
         │
         ▼
    【合格判定】
         │
         ▼
┌─────────────────┐
│ 6. 本番運用     │
│  （少額スタート） │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 7. モニタリング  │
│    & 改善       │
└─────────────────┘
```

### 1.2 各フェーズの目的

| フェーズ | 目的 | 期間 | 成功基準 |
|---------|------|------|---------|
| **戦略アイデア** | 仮説構築 | 1-3日 | ロジックが明確 |
| **Pine Script実装** | コード化 | 1-2日 | エラーなく動作 |
| **バックテスト** | 過去データ検証 | 2-5日 | 統計的有意性 |
| **最適化** | パラメータ調整 | 1-3日 | 過学習回避 |
| **フォワードテスト** | 未来データ検証 | 30-90日 | バックテストと同等 |
| **本番運用** | 実資金運用 | 継続 | 安定した収益 |

---

## 2. バックテスト手順

### 2.1 事前準備

#### ステップ1: 戦略コンセプト定義

**記録事項**:
- 戦略名
- 投資対象（日本株、ETF、指数）
- 時間軸（1分足、5分足、日足など）
- エントリー条件
- エグジット条件
- リスク管理ルール

**テンプレート**:

```
【戦略名】
momentum_breakout

【投資対象】
日経225構成銘柄

【時間軸】
5分足

【エントリー条件】
1. 20期間移動平均線を上抜け
2. 出来高が平均の1.5倍以上
3. RSIが50以上

【エグジット条件】
1. 利確: +2%
2. 損切: -1%
3. 時間切れ: 当日引け

【リスク管理】
- 1取引あたり資金の2%まで
- 同時保有: 最大3銘柄
```

#### ステップ2: Pine Script実装

**基本構造**:

```pine
//@version=5
strategy("Momentum Breakout Strategy",
         overlay=true,
         initial_capital=1000000,
         currency=currency.JPY,
         default_qty_type=strategy.percent_of_equity,
         default_qty_value=33,
         commission_type=strategy.commission.percent,
         commission_value=0.1)

// ============================================
// パラメータ設定
// ============================================
ma_length = input.int(20, "MA Length", minval=1)
volume_multiplier = input.float(1.5, "Volume Multiplier", minval=1.0)
rsi_length = input.int(14, "RSI Length", minval=1)
rsi_threshold = input.int(50, "RSI Threshold", minval=0, maxval=100)

profit_target = input.float(2.0, "Profit Target %", minval=0.1)
stop_loss = input.float(1.0, "Stop Loss %", minval=0.1)

// ============================================
// インジケーター計算
// ============================================
ma = ta.sma(close, ma_length)
volume_avg = ta.sma(volume, 20)
rsi = ta.rsi(close, rsi_length)

// ============================================
// エントリー条件
// ============================================
long_condition = ta.crossover(close, ma) and
                 volume > volume_avg * volume_multiplier and
                 rsi > rsi_threshold

// ============================================
// エグジット条件
// ============================================
profit_price = strategy.position_avg_price * (1 + profit_target / 100)
stop_price = strategy.position_avg_price * (1 - stop_loss / 100)

// ============================================
// 戦略実行
// ============================================
if (long_condition)
    strategy.entry("Long", strategy.long)

if (strategy.position_size > 0)
    strategy.exit("Exit", "Long",
                  limit=profit_price,
                  stop=stop_price)

// ============================================
// 可視化
// ============================================
plot(ma, "MA", color=color.blue, linewidth=2)
bgcolor(long_condition ? color.new(color.green, 90) : na)
```

### 2.2 バックテスト実行

#### ステップ3: テスト期間設定

**推奨期間**:

| 時間軸 | 最小期間 | 推奨期間 | サンプル数 |
|--------|---------|---------|-----------|
| **1分足** | 1ヶ月 | 3ヶ月 | 1000+ |
| **5分足** | 3ヶ月 | 6ヶ月 | 500+ |
| **15分足** | 6ヶ月 | 1年 | 300+ |
| **1時間足** | 1年 | 3年 | 200+ |
| **日足** | 3年 | 10年 | 100+ |

**期間分割**:
- **学習期間**: 全体の70%（パラメータ最適化用）
- **検証期間**: 全体の30%（過学習チェック用）

**例**:
```
全期間: 2020-01-01 ～ 2025-01-27（5年）

学習期間: 2020-01-01 ～ 2023-07-01（3.5年）
検証期間: 2023-07-01 ～ 2025-01-27（1.5年）
```

#### ステップ4: 初期資金・手数料設定

**TradingView設定**:

```pine
strategy("My Strategy",
    // 初期資金
    initial_capital=1000000,        // 100万円

    // 通貨
    currency=currency.JPY,

    // ポジションサイズ
    default_qty_type=strategy.percent_of_equity,
    default_qty_value=33,           // 資金の33%

    // 手数料
    commission_type=strategy.commission.percent,
    commission_value=0.1,           // 0.1%

    // スリッページ
    slippage=5                      // 5ティック
)
```

**日本株の一般的な手数料**:

| 証券会社 | 手数料率 | 最低手数料 | 最高手数料 |
|---------|---------|-----------|-----------|
| 楽天証券 | 0.055% | 55円 | 1,070円 |
| SBI証券 | 0.055% | 55円 | 1,070円 |
| マネックス証券 | 0.055% | 55円 | 1,070円 |

**設定推奨値**:
- 手数料: 0.1%（往復0.2%）
- スリッページ: 5-10ティック

#### ステップ5: バックテスト実行

**TradingView操作**:
1. Pine Editorで戦略コードを入力
2. 「Add to Chart」をクリック
3. チャート下部の「Strategy Tester」タブを開く
4. 結果を確認

### 2.3 結果分析

#### ステップ6: 基本統計確認

**Strategy Testerで確認する項目**:

| 項目 | 英語名 | 合格基準 |
|------|--------|---------|
| **純利益** | Net Profit | プラス |
| **総取引数** | Total Trades | 100回以上 |
| **勝率** | Percent Profitable | 50%以上 |
| **プロフィットファクター** | Profit Factor | 1.5以上 |
| **最大ドローダウン** | Max Drawdown | -20%以下 |
| **シャープレシオ** | Sharpe Ratio | 1.0以上 |
| **平均利益/平均損失** | Avg Win / Avg Loss | 1.5以上 |

**例**:
```
Net Profit:        +150,000円
Total Trades:      150回
Percent Profitable: 55%
Profit Factor:     1.8
Max Drawdown:      -12%
Sharpe Ratio:      1.2
Avg Win / Avg Loss: 1.6
```

#### ステップ7: 詳細分析

**エクイティカーブ確認**:
- 右肩上がりか
- ドローダウン期間は短いか
- 最近のパフォーマンスは維持されているか

**取引分布確認**:
- 大きな利益・損失が1回だけではないか
- 取引が時期に偏っていないか
- 連敗・連勝が極端ではないか

**月次リターン確認**:
- 安定してプラスか
- マイナス月は何%か
- 最悪月はどのくらいか

### 2.4 バックテスト記録

**記録テンプレート**:

```markdown
# バックテストレポート

## 戦略情報
- 戦略名: momentum_breakout
- バージョン: v1.0
- テスト日: 2025-01-27

## テスト設定
- 期間: 2020-01-01 ～ 2025-01-27（5年）
- 銘柄: 日経225構成銘柄
- 時間軸: 5分足
- 初期資金: 1,000,000円
- 手数料: 0.1%

## 結果サマリー
- Net Profit: +150,000円 (+15%)
- Total Trades: 150回
- Win Rate: 55%
- Profit Factor: 1.8
- Max Drawdown: -12%
- Sharpe Ratio: 1.2

## 詳細分析
### 月次リターン
| 月 | リターン | 取引回数 |
|----|---------|---------|
| 2024-01 | +2.5% | 12 |
| 2024-02 | +1.8% | 10 |
| 2024-03 | -0.5% | 8 |
...

### 判定
✅ 合格 - フォワードテストへ進む

## 改善点
- RSI閾値を50→55に調整してテスト
- 出来高条件を1.5倍→2.0倍に厳格化
```

---

## 3. フォワードテスト手順

### 3.1 フォワードテストとは

**定義**:
バックテストで合格した戦略を、**未来のデータ**（リアルタイムまたはPaper Trading）で検証すること。

**目的**:
- 過学習（overfitting）の検出
- 実市場での動作確認
- バックテストとの乖離検証

**期間**:
- 最低: 30日
- 推奨: 60-90日
- 理想: 3ヶ月以上

### 3.2 フォワードテスト実行方法

#### 方法1: TradingView Paper Trading

**手順**:
1. TradingViewのチャートで戦略を稼働
2. 「Strategy Tester」→「Paper Trading」をクリック
3. 自動でシグナルが生成される
4. 毎日結果を記録

**メリット**:
- 完全自動
- リアルタイム検証
- 無料

**デメリット**:
- TradingView画面を開いておく必要がある
- 日本株の対応銘柄が限定的

#### 方法2: Webhook → Relay Server → Paper Trading

**手順**:
1. Pine ScriptにWebhook送信コードを追加
2. Relay Serverでシグナルを受信
3. Excel VBAでPaper Trading記録
4. 実際の発注はせず、ログだけ記録

**メリット**:
- 本番システムと同じフロー
- 日本株に対応
- 詳細なログ記録

**デメリット**:
- システム構築が必要

#### 方法3: 少額実トレード

**手順**:
1. 本番システムで稼働
2. 最小ロット（100株など）で実際に売買
3. 結果を記録

**メリット**:
- 最も正確な検証
- スリッページ・手数料も実測

**デメリット**:
- 実資金が必要
- 損失リスクあり

### 3.3 フォワードテスト記録

**日次記録テンプレート**:

| 日付 | シグナル数 | 約定数 | 利益 | 損失 | 純利益 | 累積損益 | 備考 |
|------|----------|--------|------|------|--------|---------|------|
| 2025-01-27 | 3 | 2 | +3,000 | -1,000 | +2,000 | +2,000 | 9:30 買い, 14:00 売り |
| 2025-01-28 | 2 | 2 | +2,500 | 0 | +2,500 | +4,500 | |
| 2025-01-29 | 1 | 1 | 0 | -500 | -500 | +4,000 | 損切り |

**週次レビューテンプレート**:

```markdown
# フォワードテスト週次レビュー

## 週: 2025-01-27 ～ 2025-01-31

### サマリー
- シグナル数: 12回
- 約定数: 10回
- 勝率: 60%
- 純利益: +8,500円
- 最大ドローダウン: -2,000円

### バックテストとの比較
| 指標 | バックテスト | フォワード | 差分 |
|------|-------------|-----------|------|
| 勝率 | 55% | 60% | +5% |
| 平均利益 | +1,500円 | +1,200円 | -300円 |
| 平均損失 | -900円 | -1,000円 | -100円 |

### 気づき
- スリッページが想定より大きい（50円/取引）
- 成行注文のタイミングで不利な価格
- 板が薄い銘柄は避けるべき

### 改善案
- 指値注文への変更を検討
- 出来高フィルターを強化
```

### 3.4 フォワードテスト合格基準

**必須条件**:
1. ✅ 純利益がプラス
2. ✅ 勝率がバックテストの±10%以内
3. ✅ プロフィットファクターが1.2以上
4. ✅ 最大ドローダウンがバックテストの1.5倍以内
5. ✅ 連続負け数が5回以内

**例**:

| 指標 | バックテスト | フォワード | 合格判定 |
|------|-------------|-----------|---------|
| 勝率 | 55% | 52% | ✅ (-3%, 許容範囲) |
| PF | 1.8 | 1.5 | ✅ (>1.2) |
| 最大DD | -12% | -15% | ✅ (1.25倍, 許容範囲) |
| 連敗 | 4回 | 5回 | ✅ (≤5回) |

**判定**: 合格 → 本番運用へ

---

## 4. パフォーマンス評価指標

### 4.1 基本指標

| 指標 | 計算式 | 説明 | 合格基準 |
|------|--------|------|---------|
| **純利益** | 総利益 - 総損失 - 手数料 | 戦略の収益性 | プラス |
| **総取引数** | エントリー回数 | 統計的信頼性 | 100回以上 |
| **勝率** | 勝ち取引 / 総取引 × 100 | 勝つ確率 | 50%以上 |
| **プロフィットファクター** | 総利益 / 総損失 | 利益効率 | 1.5以上 |

### 4.2 リスク指標

| 指標 | 計算式 | 説明 | 合格基準 |
|------|--------|------|---------|
| **最大ドローダウン** | 最大下落率 | 最悪期の損失 | -20%以下 |
| **平均ドローダウン** | 平均下落率 | 通常期の損失 | -10%以下 |
| **最大連敗数** | 最長負け連続 | メンタル耐性 | 5回以下 |
| **ドローダウン期間** | 最長回復期間 | 資金拘束期間 | 30日以下 |

### 4.3 リスク調整後リターン

| 指標 | 計算式 | 説明 | 合格基準 |
|------|--------|------|---------|
| **シャープレシオ** | (平均リターン - 無リスク金利) / リターンの標準偏差 | リスク1単位あたりリターン | 1.0以上 |
| **ソルティノレシオ** | (平均リターン - 無リスク金利) / 下方リスク | 下落リスクあたりリターン | 1.5以上 |
| **カルマーレシオ** | 年間リターン / 最大ドローダウン | ドローダウンあたりリターン | 1.0以上 |

**計算例（シャープレシオ）**:

```
平均月次リターン: 2%
無リスク金利: 0.1% (年0.1% ÷ 12)
リターンの標準偏差: 3%

シャープレシオ = (2% - 0.1%) / 3% = 0.63

※ 年率換算: 0.63 × √12 = 2.18
```

### 4.4 取引効率指標

| 指標 | 計算式 | 説明 | 合格基準 |
|------|--------|------|---------|
| **平均利益/平均損失** | 平均勝ち金額 / 平均負け金額 | リスクリワード比 | 1.5以上 |
| **期待値** | (勝率 × 平均利益) - (敗率 × 平均損失) | 1取引あたり期待利益 | プラス |
| **最大利益/最大損失** | 最大勝ち / 最大負け | 極端な取引の有無 | 3.0以下 |
| **保有時間** | 平均ポジション保有時間 | 資金効率 | - |

**期待値計算例**:

```
勝率: 55%
平均利益: 1,500円
平均損失: 1,000円

期待値 = (0.55 × 1,500) - (0.45 × 1,000)
       = 825 - 450
       = +375円/取引
```

---

## 5. 戦略検証チェックリスト

### 5.1 バックテスト前チェックリスト

- [ ] 戦略コンセプトが明確に文書化されている
- [ ] エントリー・エグジット条件が具体的
- [ ] リスク管理ルールが定義されている
- [ ] Pine Scriptがエラーなく動作する
- [ ] 手数料・スリッページが設定されている
- [ ] テスト期間が十分（最低1年以上）
- [ ] 初期資金が適切（実運用と同じ）

### 5.2 バックテスト後チェックリスト

- [ ] 純利益がプラス
- [ ] 総取引数が100回以上
- [ ] 勝率が50%以上
- [ ] プロフィットファクターが1.5以上
- [ ] 最大ドローダウンが-20%以下
- [ ] シャープレシオが1.0以上
- [ ] エクイティカーブが右肩上がり
- [ ] 大きな利益が1回だけではない
- [ ] 取引が時期に偏っていない
- [ ] 学習期間と検証期間で同等のパフォーマンス

### 5.3 過学習（Overfitting）チェックリスト

- [ ] パラメータ数が少ない（5個以下）
- [ ] パラメータ変更で結果が大きく変わらない
- [ ] 複雑な条件を避けている
- [ ] 学習期間と検証期間で結果が同等
- [ ] ウォークフォワード分析を実施
- [ ] アウトオブサンプルテストで合格

**過学習の兆候**:
- ❌ パラメータが10個以上
- ❌ 小数点以下2桁のパラメータ（例: 1.73）
- ❌ 学習期間は好成績だが検証期間は不調
- ❌ パラメータを少し変えると成績が激変
- ❌ 複雑な if-then-else の連鎖

### 5.4 フォワードテスト前チェックリスト

- [ ] バックテストで合格している
- [ ] 過学習チェックをクリアしている
- [ ] 戦略の最終版が確定している
- [ ] フォワードテスト記録シートを準備
- [ ] Paper Tradingまたは少額実トレードの準備完了
- [ ] 毎日記録する時間を確保

### 5.5 本番運用前チェックリスト

- [ ] フォワードテストで合格している
- [ ] 少なくとも30日間のフォワードテスト実績
- [ ] バックテストとフォワードで乖離が小さい
- [ ] リスク許容度を確認（最大損失額）
- [ ] 緊急停止手順を確認
- [ ] Kill Switch設定を確認
- [ ] 通知設定（Slack/Mail）を確認
- [ ] 初回は最小ロットで開始

---

## 6. Pine Script実装

### 6.1 基本テンプレート

```pine
//@version=5
strategy("My Strategy Template",
         overlay=true,
         initial_capital=1000000,
         currency=currency.JPY,
         default_qty_type=strategy.percent_of_equity,
         default_qty_value=33,
         commission_type=strategy.commission.percent,
         commission_value=0.1,
         slippage=5)

// ============================================
// パラメータ設定（最適化用）
// ============================================
// トレンド系
ma_fast = input.int(10, "Fast MA", minval=1, maxval=200)
ma_slow = input.int(20, "Slow MA", minval=1, maxval=200)

// オシレーター系
rsi_length = input.int(14, "RSI Length", minval=1, maxval=50)
rsi_oversold = input.int(30, "RSI Oversold", minval=0, maxval=50)
rsi_overbought = input.int(70, "RSI Overbought", minval=50, maxval=100)

// リスク管理
profit_target = input.float(2.0, "Profit Target %", minval=0.1, step=0.1)
stop_loss = input.float(1.0, "Stop Loss %", minval=0.1, step=0.1)
trailing_stop = input.float(0.5, "Trailing Stop %", minval=0.1, step=0.1)

// フィルター
volume_multiplier = input.float(1.5, "Volume Filter", minval=1.0, step=0.1)
use_time_filter = input.bool(true, "Use Time Filter")

// ============================================
// インジケーター計算
// ============================================
ma_fast_value = ta.sma(close, ma_fast)
ma_slow_value = ta.sma(close, ma_slow)
rsi = ta.rsi(close, rsi_length)
volume_avg = ta.sma(volume, 20)

// ============================================
// 時間フィルター（日本市場）
// ============================================
session_morning = "0930-1130"
session_afternoon = "1230-1500"

in_morning_session = time(timeframe.period, session_morning)
in_afternoon_session = time(timeframe.period, session_afternoon)
in_trading_hours = in_morning_session or in_afternoon_session

// ============================================
// エントリー条件
// ============================================
// ロング条件
long_trend = ta.crossover(ma_fast_value, ma_slow_value)
long_momentum = rsi > 50
long_volume = volume > volume_avg * volume_multiplier
long_time = use_time_filter ? in_trading_hours : true

long_condition = long_trend and long_momentum and long_volume and long_time

// ショート条件（日本株では通常使わない）
short_trend = ta.crossunder(ma_fast_value, ma_slow_value)
short_momentum = rsi < 50
short_volume = volume > volume_avg * volume_multiplier
short_time = use_time_filter ? in_trading_hours : true

short_condition = short_trend and short_momentum and short_volume and short_time

// ============================================
// エグジット条件
// ============================================
if (strategy.position_size > 0)
    profit_price = strategy.position_avg_price * (1 + profit_target / 100)
    stop_price = strategy.position_avg_price * (1 - stop_loss / 100)
    trailing_price = close * (1 - trailing_stop / 100)

    strategy.exit("Exit Long", "Long",
                  limit=profit_price,
                  stop=stop_price,
                  trail_price=trailing_price,
                  trail_offset=trailing_stop)

// ============================================
// 戦略実行
// ============================================
if (long_condition)
    strategy.entry("Long", strategy.long)

// if (short_condition)
//     strategy.entry("Short", strategy.short)

// ============================================
// 可視化
// ============================================
plot(ma_fast_value, "Fast MA", color=color.blue, linewidth=1)
plot(ma_slow_value, "Slow MA", color=color.red, linewidth=2)

bgcolor(long_condition ? color.new(color.green, 90) : na)
bgcolor(short_condition ? color.new(color.red, 90) : na)

// エントリーマーカー
plotshape(long_condition, "Long Signal", shape.triangleup,
          location.belowbar, color.green, size=size.small)
```

### 6.2 Webhook送信対応

```pine
//@version=5
strategy("Momentum Breakout with Webhook",
         overlay=true,
         initial_capital=1000000,
         currency=currency.JPY)

// ... (パラメータ・インジケーター計算は省略)

// ============================================
// Webhook送信
// ============================================
webhook_url = "https://your-relay-server.com/api/webhook/tradingview"

// エントリー時のWebhookペイロード
long_entry_message = '{"strategy":"momentum_breakout","action":"buy","ticker":"{{ticker}}","price":{{close}},"time":"{{timenow}}"}'

// エグジット時のWebhookペイロード
long_exit_message = '{"strategy":"momentum_breakout","action":"sell","ticker":"{{ticker}}","price":{{close}},"time":"{{timenow}}"}'

// ============================================
// 戦略実行（Webhook付き）
// ============================================
if (long_condition)
    strategy.entry("Long", strategy.long, alert_message=long_entry_message)

if (strategy.position_size > 0)
    profit_price = strategy.position_avg_price * (1 + profit_target / 100)
    stop_price = strategy.position_avg_price * (1 - stop_loss / 100)

    strategy.exit("Exit Long", "Long",
                  limit=profit_price,
                  stop=stop_price,
                  alert_message=long_exit_message)
```

### 6.3 パフォーマンス記録用コード

```pine
//@version=5
strategy("Strategy with Performance Tracking",
         overlay=true,
         initial_capital=1000000)

// ... (戦略ロジックは省略)

// ============================================
// パフォーマンス統計をテーブル表示
// ============================================
var table perf_table = table.new(position.top_right, 2, 8,
                                   bgcolor=color.new(color.black, 80),
                                   border_width=1)

if (barstate.islast)
    // ヘッダー
    table.cell(perf_table, 0, 0, "指標", text_color=color.white, text_size=size.small)
    table.cell(perf_table, 1, 0, "値", text_color=color.white, text_size=size.small)

    // データ
    table.cell(perf_table, 0, 1, "Net Profit", text_color=color.white, text_size=size.small)
    table.cell(perf_table, 1, 1, str.tostring(strategy.netprofit, "#,###"),
               text_color=strategy.netprofit > 0 ? color.green : color.red,
               text_size=size.small)

    table.cell(perf_table, 0, 2, "Win Rate", text_color=color.white, text_size=size.small)
    win_rate = strategy.wintrades / strategy.closedtrades * 100
    table.cell(perf_table, 1, 2, str.tostring(win_rate, "#.##") + "%",
               text_color=color.white, text_size=size.small)

    table.cell(perf_table, 0, 3, "Profit Factor", text_color=color.white, text_size=size.small)
    pf = strategy.grossprofit / strategy.grossloss
    table.cell(perf_table, 1, 3, str.tostring(pf, "#.##"),
               text_color=color.white, text_size=size.small)

    table.cell(perf_table, 0, 4, "Total Trades", text_color=color.white, text_size=size.small)
    table.cell(perf_table, 1, 4, str.tostring(strategy.closedtrades),
               text_color=color.white, text_size=size.small)

    table.cell(perf_table, 0, 5, "Max DD", text_color=color.white, text_size=size.small)
    table.cell(perf_table, 1, 5, str.tostring(strategy.max_drawdown, "#,###"),
               text_color=color.red, text_size=size.small)
```

---

## 7. Webhook連携設定

### 7.1 TradingView Alert設定

**手順**:
1. チャート右上の「⏰（アラート）」アイコンをクリック
2. 「条件」で戦略を選択
3. 「Webhook URL」に Relay Server のURLを入力
4. 「メッセージ」にJSONペイロードを入力
5. 「作成」をクリック

**Webhook URL例**:
```
https://your-relay-server.com/api/webhook/tradingview
```

**メッセージ（JSON）**:
```json
{
  "strategy": "momentum_breakout",
  "action": "{{strategy.order.action}}",
  "ticker": "{{ticker}}",
  "price": {{close}},
  "quantity": 100,
  "timestamp": "{{timenow}}"
}
```

### 7.2 Relay Server側の受信処理

**relay_server/app/api/webhook.py**:

```python
from fastapi import APIRouter, Request
from datetime import datetime
import logging

router = APIRouter()
logger = logging.getLogger(__name__)

@router.post("/webhook/tradingview")
async def receive_tradingview_webhook(request: Request):
    """
    TradingViewからのWebhookを受信
    """
    try:
        payload = await request.json()

        logger.info(f"TradingView webhook received: {payload}")

        # ペイロード検証
        required_fields = ['strategy', 'action', 'ticker', 'price']
        if not all(field in payload for field in required_fields):
            return {"status": "error", "message": "Missing required fields"}

        # シグナル生成
        signal = {
            "signal_id": generate_signal_id(),
            "strategy": payload['strategy'],
            "ticker": payload['ticker'],
            "action": payload['action'].lower(),  # buy / sell
            "quantity": payload.get('quantity', 100),
            "price_type": "market",
            "limit_price": None,
            "signal_strength": 0.8,
            "timestamp": datetime.now().isoformat(),
            "source": "tradingview"
        }

        # シグナルキューに追加
        await signal_queue.add(signal)

        logger.info(f"Signal created from TradingView: {signal['signal_id']}")

        return {
            "status": "success",
            "signal_id": signal['signal_id'],
            "message": "Signal received and queued"
        }

    except Exception as e:
        logger.error(f"TradingView webhook error: {e}")
        return {"status": "error", "message": str(e)}

def generate_signal_id() -> str:
    """シグナルIDを生成"""
    import time
    return f"SIG-{datetime.now().strftime('%Y%m%d')}-{int(time.time() * 1000)}"
```

---

## 8. 本番運用移行基準

### 8.1 移行判定チェックリスト

**必須条件（全て✅が必要）**:

#### バックテスト
- [ ] Net Profit > 0
- [ ] Total Trades ≥ 100
- [ ] Win Rate ≥ 50%
- [ ] Profit Factor ≥ 1.5
- [ ] Max Drawdown ≤ -20%
- [ ] Sharpe Ratio ≥ 1.0
- [ ] 学習期間と検証期間で同等のパフォーマンス

#### フォワードテスト
- [ ] 期間 ≥ 30日
- [ ] Net Profit > 0
- [ ] 勝率がバックテストの±10%以内
- [ ] Profit Factor ≥ 1.2
- [ ] Max Drawdown ≤ バックテストの1.5倍
- [ ] 連続負け ≤ 5回

#### システム
- [ ] Relay Server稼働中
- [ ] Excel VBA動作確認済み
- [ ] MarketSpeed II RSS接続確認済み
- [ ] Kill Switch動作確認済み
- [ ] Slack/Mail通知動作確認済み
- [ ] ログ記録動作確認済み

#### リスク管理
- [ ] 1取引あたり最大損失額を設定
- [ ] 日次損失限度を設定
- [ ] 同時保有銘柄数を制限
- [ ] 最大ドローダウン許容値を設定

### 8.2 段階的ロールアウト

**フェーズ1: 最小ロット（1-2週間）**
- 取引数量: 100株（最小単位）
- 最大ポジション: 1銘柄
- 目的: システム動作確認

**フェーズ2: 少額運用（2-4週間）**
- 取引数量: 200-300株
- 最大ポジション: 2-3銘柄
- 目的: パフォーマンス確認

**フェーズ3: 通常運用（継続）**
- 取引数量: 設計通り
- 最大ポジション: 設計通り
- 目的: 本番運用

### 8.3 モニタリング計画

**日次チェック**:
- [ ] 取引履歴確認
- [ ] エラーログ確認
- [ ] 損益確認
- [ ] システム状態確認

**週次チェック**:
- [ ] 週次パフォーマンスレビュー
- [ ] バックテスト・フォワードテストとの比較
- [ ] リスク指標確認
- [ ] 戦略パラメータ見直し

**月次チェック**:
- [ ] 月次パフォーマンスレビュー
- [ ] 戦略有効性評価
- [ ] リスク許容度見直し
- [ ] 改善案検討

### 8.4 運用停止基準

**即座に停止**:
- 🚨 Kill Switchが発動した
- 🚨 日次損失が-5万円を超えた
- 🚨 システムエラーが頻発（1時間10回以上）
- 🚨 API/RSS接続が長時間断絶

**1週間以内に停止を検討**:
- ⚠️ 5営業日連続で損失
- ⚠️ 週次損失が-3万円を超えた
- ⚠️ 勝率が30%を下回った
- ⚠️ 最大ドローダウンが-25%を超えた

**1ヶ月以内に停止を検討**:
- ⚠️ 月次損失が-5万円を超えた
- ⚠️ フォワードテストとの乖離が大きい
- ⚠️ シャープレシオが0.5を下回った

---

## まとめ

### 推奨フロー

```
1. 戦略アイデア（1-3日）
   ↓
2. Pine Script実装（1-2日）
   ↓
3. バックテスト（2-5日）
   - 5年以上のデータ
   - 100回以上の取引
   - 合格基準クリア
   ↓
4. 過学習チェック
   - 学習期間 vs 検証期間
   - パラメータ感度分析
   ↓
5. フォワードテスト（30-90日）
   - Paper Trading
   - 毎日記録
   - バックテストとの比較
   ↓
6. 本番運用（段階的）
   - フェーズ1: 最小ロット（1-2週）
   - フェーズ2: 少額運用（2-4週）
   - フェーズ3: 通常運用（継続）
   ↓
7. モニタリング & 改善
   - 日次・週次・月次レビュー
   - 運用停止基準の監視
```

### 重要なポイント

- ✅ **十分な取引回数**: 統計的信頼性のため100回以上
- ✅ **過学習回避**: パラメータは少なく、シンプルに
- ✅ **フォワードテスト必須**: 最低30日、推奨60-90日
- ✅ **段階的ロールアウト**: 最小ロットから開始
- ✅ **継続的モニタリング**: 日次・週次・月次レビュー
- ✅ **明確な停止基準**: Kill Switchと運用停止基準

---

**ガイド完成日**: 2025-12-27
