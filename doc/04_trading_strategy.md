# 日本株自動売買システム - トレード戦略設計書

## 戦略概要

**戦略名：** 低頻度トレンドフォロー（移動平均線クロス + RSI フィルター）

**戦略タイプ：** デイトレード〜短期スイング（1日〜数日保有）

**想定取引頻度：** 1銘柄あたり週1-3回程度

**想定勝率：** 40-50%（損小利大で期待値プラス）

**リスクリワード：** 1:2 以上（損失1に対して利益2以上を目指す）

---

## 1. 対象銘柄選定基準

### 1.1 高流動性銘柄リスト

以下の条件を満たす銘柄を対象とする：

```yaml
liquidity_criteria:
  # 時価総額
  min_market_cap: 100000000000  # 1000億円以上

  # 出来高
  min_daily_volume: 1000000  # 日次100万株以上

  # 売買代金
  min_daily_turnover: 1000000000  # 日次10億円以上

  # 値幅制限
  avoid_stocks_with_limits: true  # ストップ高/安銘柄は除外

  # ボラティリティ
  min_volatility: 1.5  # 日次変動率1.5%以上
  max_volatility: 5.0  # 日次変動率5.0%以下（過度に高い銘柄は除外）
```

### 1.2 推奨銘柄リスト例

**TOPIX Core30 + 高ボラティリティ個別株**

| 銘柄コード | 銘柄名 | セクター | 特徴 |
|-----------|--------|---------|------|
| 9984 | ソフトバンクグループ | 通信 | 高ボラティリティ、大型株 |
| 6758 | ソニーグループ | 電機 | トレンド継続性高い |
| 7203 | トヨタ自動車 | 自動車 | 安定性高い |
| 8306 | 三菱UFJ | 金融 | 出来高大 |
| 6861 | キーエンス | 電機 | 強いトレンド形成 |
| 9433 | KDDI | 通信 | 安定配当株 |
| 4063 | 信越化学 | 化学 | 世界的企業 |
| 8035 | 東京エレクトロン | 電機 | 半導体関連 |
| 4568 | 第一三共 | 医薬品 | バイオ関連 |
| 6098 | リクルート | サービス | 成長株 |

**除外銘柄：**
- 新興市場（マザーズ、グロース）
- 低流動性銘柄（出来高50万株未満）
- 仕手株・材料株
- IPO後3ヶ月以内の銘柄

---

## 2. エントリー条件（買い）

### 2.1 基本ルール

**トレンド確認 + タイミング指標**の組み合わせ

```
必須条件（AND条件）：
1. トレンド条件：25日移動平均線 > 75日移動平均線（上昇トレンド）
2. クロス条件：5日移動平均線が25日移動平均線を下から上に抜けた（ゴールデンクロス）
3. RSI条件：RSI(14) > 50 かつ RSI(14) < 70（過熱感なし）
4. 出来高条件：当日出来高 > 過去20日平均出来高の1.2倍
5. 時間条件：9:30以降〜14:30まで（寄付直後と引け間際を避ける）
```

### 2.2 TradingView Pine Script 実装例

```pinescript
//@version=5
strategy("Kabuto Low-Frequency Trend Following", overlay=true)

// === パラメータ設定 ===
ema5 = ta.ema(close, 5)
ema25 = ta.ema(close, 25)
ema75 = ta.ema(close, 75)
rsi = ta.rsi(close, 14)
volumeAvg = ta.sma(volume, 20)

// === エントリー条件 ===
// 1. トレンド確認
trendUp = ema25 > ema75

// 2. ゴールデンクロス
goldenCross = ta.crossover(ema5, ema25)

// 3. RSI フィルター
rsiFilter = rsi > 50 and rsi < 70

// 4. 出来高確認
volumeIncrease = volume > volumeAvg * 1.2

// 5. 時間フィルター（日本時間 9:30-14:30）
// TradingView の時間は UTC なので調整が必要
hour = hour(time, "Asia/Tokyo")
minute = minute(time, "Asia/Tokyo")
timeFilter = (hour == 9 and minute >= 30) or (hour >= 10 and hour < 14) or (hour == 14 and minute <= 30)

// === エントリーシグナル ===
longCondition = trendUp and goldenCross and rsiFilter and volumeIncrease and timeFilter

if (longCondition)
    strategy.entry("Long", strategy.long)
    alert('{"ticker":"' + syminfo.ticker + '","action":"buy","quantity":100,"price":"market","alert_id":"' + str.tostring(time) + '","passphrase":"YOUR_SECRET"}', alert.freq_once_per_bar)

// === エグジット条件は後述 ===
```

### 2.3 エントリー時の注文設定

```python
# エントリー注文パラメータ
entry_order = {
    "order_type": "market",  # 成行注文（即座に約定）
    "quantity": 100,         # 100株（最小単元）
    "position_size_pct": 10  # ポートフォリオの10%を1銘柄に割り当て
}

# ポジションサイズ計算例
def calculate_position_size(account_balance: float, entry_price: float) -> int:
    """
    account_balance: 口座残高（例：1,000,000円）
    entry_price: エントリー価格（例：3,000円）
    """
    position_value = account_balance * 0.10  # 10%
    quantity = int(position_value / entry_price)

    # 単元株に調整（100株単位）
    quantity = (quantity // 100) * 100

    # 最大1000株まで
    return min(quantity, 1000)
```

---

## 3. エグジット条件

### 3.1 利確条件（以下のいずれか）

```
利確条件（OR条件）：
1. 目標利益：エントリー価格から +3%（推奨リワード）
2. トレーリングストップ：高値から -1.5%（利益を守る）
3. デッドクロス：5日移動平均線が25日移動平均線を上から下に抜けた
```

### 3.2 損切り条件（以下のいずれか）

```
損切り条件（OR条件）：
1. 固定ストップロス：エントリー価格から -1.5%（必須）
2. 時間ストップ：エントリー後5営業日経過しても利益なし
3. トレンド転換：75日移動平均線を下回る
```

### 3.3 TradingView Pine Script 実装例

```pinescript
//@version=5
strategy("Kabuto Strategy - Exit Logic", overlay=true)

// === エントリー価格の記録 ===
var float entryPrice = na
var int entryBar = na

if (strategy.position_size > 0 and na(entryPrice))
    entryPrice := close
    entryBar := bar_index

// === 利確条件 ===
// 1. 目標利益 +3%
targetProfit = entryPrice * 1.03
takeProfitCondition = close >= targetProfit

// 2. トレーリングストップ（高値から-1.5%）
var float highestPrice = na
if (strategy.position_size > 0)
    highestPrice := na(highestPrice) ? close : math.max(highestPrice, close)
trailingStop = highestPrice * 0.985
trailingStopCondition = close <= trailingStop

// 3. デッドクロス
deadCross = ta.crossunder(ema5, ema25)

// === 損切り条件 ===
// 1. 固定ストップロス -1.5%
stopLoss = entryPrice * 0.985
stopLossCondition = close <= stopLoss

// 2. 時間ストップ（5営業日）
timeStop = bar_index - entryBar >= 5
timeStopCondition = timeStop and close < entryPrice

// 3. トレンド転換（75EMA 下抜け）
trendReversalCondition = close < ema75

// === エグジットシグナル ===
exitCondition = takeProfitCondition or trailingStopCondition or deadCross or
                stopLossCondition or timeStopCondition or trendReversalCondition

if (exitCondition and strategy.position_size > 0)
    strategy.close("Long")

    // エグジット理由を判定
    exitReason = takeProfitCondition ? "take_profit" :
                 trailingStopCondition ? "trailing_stop" :
                 deadCross ? "dead_cross" :
                 stopLossCondition ? "stop_loss" :
                 timeStopCondition ? "time_stop" : "trend_reversal"

    alert('{"ticker":"' + syminfo.ticker + '","action":"sell","quantity":100,"price":"market","exit_reason":"' + exitReason + '","alert_id":"' + str.tostring(time) + '","passphrase":"YOUR_SECRET"}', alert.freq_once_per_bar)

    // リセット
    entryPrice := na
    entryBar := na
    highestPrice := na
```

---

## 4. リスク管理ルール

### 4.1 ポジション管理

```yaml
position_management:
  # 1銘柄あたりの最大ポジション
  max_position_per_stock: 10%  # 口座残高の10%

  # 同時保有銘柄数
  max_concurrent_positions: 5  # 最大5銘柄（分散）

  # 全体リスクエクスポージャー
  max_total_exposure: 50%  # 口座残高の50%まで

  # セクター集中回避
  max_same_sector_positions: 2  # 同一セクターは2銘柄まで
```

### 4.2 日次リスク上限

```python
daily_risk_limits = {
    "max_daily_loss": -30000,      # 1日最大損失 -3万円
    "max_daily_trades": 10,        # 1日最大10回
    "max_loss_per_trade": -15000,  # 1取引最大損失 -1.5万円
    "max_consecutive_losses": 3    # 連続3回損失で当日停止
}

def check_daily_limits(current_pnl: float, trade_count: int, consecutive_losses: int):
    """日次リスク上限チェック"""
    if current_pnl < daily_risk_limits["max_daily_loss"]:
        activate_kill_switch("Daily loss limit exceeded")
        return False

    if trade_count >= daily_risk_limits["max_daily_trades"]:
        logger.warning("Daily trade limit reached")
        return False

    if consecutive_losses >= daily_risk_limits["max_consecutive_losses"]:
        activate_kill_switch("Too many consecutive losses")
        return False

    return True
```

---

## 5. バックテスト基準値

### 5.1 最低限満たすべき性能指標

```yaml
minimum_performance:
  # 収益性
  annual_return: 15%          # 年間リターン15%以上
  sharpe_ratio: 1.2           # シャープレシオ1.2以上
  profit_factor: 1.5          # プロフィットファクター1.5以上

  # リスク
  max_drawdown: -15%          # 最大ドローダウン-15%以内
  win_rate: 40%               # 勝率40%以上

  # 取引頻度
  avg_trades_per_month: 8-15  # 月間8-15回（低頻度）
  avg_holding_period: 2-5日   # 平均保有期間2-5日
```

### 5.2 バックテスト期間

```
推奨期間：最低3年分のデータ
- 上昇相場期間を含む
- 下落相場期間を含む（2020年コロナショック等）
- レンジ相場期間を含む

検証データ：
- 学習期間：2020年1月〜2023年12月（3年）
- テスト期間：2024年1月〜現在（アウトオブサンプル）
```

---

## 6. 戦略のバリエーション

### 6.1 保守的バージョン（初心者向け）

```yaml
conservative_version:
  entry:
    - trend: ema25 > ema75 AND ema75 が上向き（角度確認）
    - cross: ゴールデンクロス
    - rsi: 50 < RSI < 65（より控えめ）
    - volume: 過去平均の1.5倍以上（明確な勢い）

  exit:
    - take_profit: +2%（早めの利確）
    - stop_loss: -1%（厳格な損切り）
    - trailing_stop: 高値から-1%

  risk:
    - position_size: 5%（小さめ）
    - max_positions: 3（集中管理）
```

### 6.2 アグレッシブバージョン（経験者向け）

```yaml
aggressive_version:
  entry:
    - trend: ema25 > ema75（基本トレンド）
    - cross: ゴールデンクロス
    - rsi: 50 < RSI < 75（やや過熱も許容）
    - momentum: ADX > 25（強いトレンド確認）

  exit:
    - take_profit: +5%（大きな利益狙い）
    - stop_loss: -2%（余裕持たせる）
    - trailing_stop: 高値から-2%

  risk:
    - position_size: 15%（大きめ）
    - max_positions: 7（分散）
```

---

## 7. 実装時の注意事項

### 7.1 TradingView 設定

```
チャート設定：
- タイムフレーム：15分足 または 1時間足
- データフィード：リアルタイムデータ必須
- Alert 設定：「Once Per Bar Close」（確定足のみ）
```

### 7.2 スリッページ・手数料の考慮

```python
# バックテスト時に必ず含める
trading_costs = {
    "commission": 0.05,        # 片道0.05%（楽天証券いちにち定額コース想定）
    "slippage": 0.1,           # スリッページ0.1%
    "total_cost_per_trade": 0.3  # 往復で約0.3%
}

# 例：100万円の取引
# 手数料：1,000,000 * 0.0005 * 2 = 1,000円
# スリッページ：1,000,000 * 0.001 * 2 = 2,000円
# 合計コスト：約3,000円
```

### 7.3 市場環境別の運用方針

```yaml
market_conditions:
  strong_uptrend:
    # 強い上昇トレンド
    action: フル稼働（5銘柄同時保有可）
    adjustment: トレーリングストップを緩める（-2%）

  weak_trend:
    # 弱いトレンド・レンジ相場
    action: 慎重運用（2-3銘柄のみ）
    adjustment: 早めの利確（+2%）、厳格な損切り（-1%）

  strong_downtrend:
    # 強い下降トレンド
    action: 取引停止（Kill Switch 発動）
    condition: ema25 < ema75 が5日以上継続
```

---

## 8. 完全なエントリー・エグジットフローチャート

```
┌─────────────────────────────────────┐
│     シグナル監視（TradingView）      │
└──────────────┬──────────────────────┘
               │
               ▼
      【トレンド確認】
      ema25 > ema75?
               │
         Yes   │   No → 待機
               ▼
      【ゴールデンクロス検知】
      ema5 が ema25 を上抜け?
               │
         Yes   │   No → 待機
               ▼
      【RSI フィルター】
      50 < RSI < 70?
               │
         Yes   │   No → 待機
               ▼
      【出来高確認】
      volume > 平均*1.2?
               │
         Yes   │   No → 待機
               ▼
      【時間フィルター】
      9:30-14:30?
               │
         Yes   │   No → 待機
               ▼
      【リスク管理チェック】
      ・ポジション数 < 5
      ・日次損失上限内
      ・同一セクター制限内
               │
         OK    │   NG → 拒否
               ▼
┌──────────────────────────────────────┐
│        エントリー（成行買い）          │
│  - エントリー価格記録                  │
│  - ストップロス設定（-1.5%）           │
│  - 目標利益設定（+3%）                 │
└──────────────┬───────────────────────┘
               │
               ▼
      【ポジション監視】
      毎足チェック
               │
               ▼
      以下のいずれかが成立?
      ┌──────────────────────┐
      │ 1. 利確：+3%到達      │
      │ 2. トレーリング：-1.5%│
      │ 3. デッドクロス       │
      │ 4. 損切り：-1.5%      │
      │ 5. 時間切れ：5日経過  │
      │ 6. トレンド転換       │
      └──────────┬───────────┘
               │ Yes
               ▼
┌──────────────────────────────────────┐
│        エグジット（成行売り）          │
│  - エグジット理由記録                  │
│  - P&L 計算                           │
│  - 統計更新                           │
└──────────────────────────────────────┘
```

---

## 9. 運用開始までのステップ

### Step 1: バックテスト（1-2週間）
```
1. TradingView でストラテジーを実装
2. 過去3年分のデータでバックテスト
3. 最低基準（年間リターン15%、勝率40%等）をクリア確認
4. パラメータの微調整
```

### Step 2: ペーパートレード（2-4週間）
```
1. Alert を設定するが実際の注文は出さない
2. 手動でエントリー/エグジットを記録
3. 実際のスリッページ・約定状況を確認
4. システムの動作確認（Webhook 受信等）
```

### Step 3: 少額実運用（1-2ヶ月）
```
1. 最小単元（100株）で自動売買開始
2. 1銘柄のみで運用
3. 毎日ログを確認、問題点を洗い出し
4. リスク管理が適切に機能しているか検証
```

### Step 4: フル稼働
```
1. 複数銘柄（3-5銘柄）に拡大
2. ポジションサイズを段階的に増加
3. 継続的なパフォーマンス監視
4. 月次レビューで戦略調整
```

---

## 10. 戦略評価指標（毎月レビュー）

```python
# 月次レポート生成
monthly_metrics = {
    "total_trades": 12,           # 取引回数
    "win_rate": 0.50,             # 勝率50%
    "avg_profit": 25000,          # 平均利益
    "avg_loss": -12000,           # 平均損失
    "profit_factor": 2.08,        # PF = 総利益/総損失
    "max_consecutive_wins": 4,
    "max_consecutive_losses": 2,
    "sharpe_ratio": 1.35,
    "max_drawdown": -8.5,         # %
    "roi": 4.2                    # 月間ROI 4.2%
}

# 改善が必要な閾値
review_thresholds = {
    "win_rate < 35%": "エントリー条件を厳格化",
    "profit_factor < 1.3": "損切り・利確の見直し",
    "max_drawdown < -20%": "ポジションサイズ縮小",
    "total_trades < 5": "対象銘柄を増やす",
    "total_trades > 30": "エントリー条件を厳格化（過剰取引）"
}
```

---

*最終更新: 2025-12-27*

**免責事項：** 本戦略は教育目的で提供されています。実際の投資判断は自己責任で行い、過去のパフォーマンスが将来の結果を保証するものではありません。
