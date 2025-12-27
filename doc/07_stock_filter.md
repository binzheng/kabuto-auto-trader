# 日本株自動売買システム - 銘柄二次フィルタ設計

## 概要

本文書では、基本的な銘柄リスト（Stock Universe）から、**現在のトレード戦略に最適な銘柄を動的に選定**するための二次フィルタ条件を定義します。日次・週次で自動更新されるフィルタリングシステムを設計します。

---

## 1. 二次フィルタの目的

### 1.1 基本方針

```
一次フィルタ（Stock Universe）:
  → 固定的な条件（時価総額、流動性等）
  → 月次〜四半期更新
  → 20銘柄程度を選定

二次フィルタ（Stock Filter）:
  → 動的な条件（ATR、トレンド強度、出来高）
  → 日次〜週次更新
  → 5-10銘柄に絞り込み
```

**目的：**
1. **戦略適合性の向上**：現在の市場環境に合った銘柄のみを選択
2. **リスク管理**：極端なボラティリティ・低流動性銘柄を除外
3. **パフォーマンス最適化**：トレンド継続性の高い銘柄に集中

---

## 2. ATRベースフィルタ

### 2.1 ATRの役割

**ATR（Average True Range）の意味：**
- 価格変動の絶対的な大きさを測定
- 高ATR = ボラティリティ高い = リスク・リターン大
- 低ATR = ボラティリティ低い = 動きが小さい

**戦略との関係：**
```
ATRベースSL/TP戦略の場合:
  - ATRが小さすぎる → SL/TPが狭すぎて頻繁に発動
  - ATRが大きすぎる → SL/TPが広すぎてリスク過大
  → 適度なATR範囲の銘柄を選定
```

### 2.2 ATRフィルタ基準

#### 2.2.1 絶対値フィルタ

```python
# config/filter_criteria.yaml
atr_filter:
  period: 14                    # ATR計算期間
  min_atr: 20                   # 最小ATR（円）
  max_atr: 200                  # 最大ATR（円）
  optimal_range: [30, 100]      # 最適範囲（円）

  # 価格帯別の調整
  price_brackets:
    - price_range: [500, 1500]
      min_atr: 10
      max_atr: 50

    - price_range: [1500, 5000]
      min_atr: 30
      max_atr: 150

    - price_range: [5000, 15000]
      min_atr: 100
      max_atr: 500
```

**理由：**
- 株価によってATRの絶対値が異なる
- 低価格株（500円）：ATR 10円でも大きい（2%）
- 高価格株（5000円）：ATR 50円でも小さい（1%）

#### 2.2.2 相対値フィルタ（ATR %）

```python
atr_percentage_filter:
  min_atr_pct: 1.0              # 最小ATR%（対株価）
  max_atr_pct: 4.0              # 最大ATR%
  optimal_range_pct: [1.5, 3.0] # 最適範囲

  # 計算式
  # ATR% = (ATR / 株価) × 100
```

**例：**
```
銘柄A: 株価 3,000円、ATR 60円
  → ATR% = 60 / 3000 × 100 = 2.0% ✅ 適格

銘柄B: 株価 1,000円、ATR 8円
  → ATR% = 8 / 1000 × 100 = 0.8% ❌ 低すぎる

銘柄C: 株価 5,000円、ATR 250円
  → ATR% = 250 / 5000 × 100 = 5.0% ❌ 高すぎる
```

### 2.3 ATR推移フィルタ

```python
atr_trend_filter:
  lookback_period: 20           # 過去20日間のATRを比較

  # ATRが拡大中（ボラティリティ上昇中）
  expanding_threshold: 1.2      # 現在ATR > 平均ATR × 1.2

  # ATRが縮小中（ボラティリティ低下中）
  contracting_threshold: 0.8    # 現在ATR < 平均ATR × 0.8

  preference: "stable"          # "stable" or "expanding" or "contracting"
```

**戦略別の推奨設定：**

| 戦略タイプ | ATR推移の好み | 理由 |
|-----------|--------------|------|
| トレンドフォロー | expanding（拡大中） | ボラティリティ上昇はトレンド発生の兆候 |
| レンジ取引 | contracting（縮小中） | ボラティリティ低下は保合い形成 |
| 安定志向 | stable（安定） | 予測可能性を重視 |

### 2.4 Python実装例

```python
# server/filters/atr_filter.py
import pandas as pd
import numpy as np

class ATRFilter:
    def __init__(self, period: int = 14):
        self.period = period

    def calculate_atr(self, df: pd.DataFrame) -> pd.Series:
        """ATRを計算"""
        high = df['high']
        low = df['low']
        close = df['close']

        tr1 = high - low
        tr2 = abs(high - close.shift())
        tr3 = abs(low - close.shift())

        tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
        atr = tr.rolling(window=self.period).mean()

        return atr

    def calculate_atr_percentage(self, df: pd.DataFrame) -> pd.Series:
        """ATR%を計算"""
        atr = self.calculate_atr(df)
        close = df['close']
        return (atr / close) * 100

    def filter_by_atr(self, ticker: str, df: pd.DataFrame) -> tuple[bool, dict]:
        """ATR基準でフィルタリング"""
        atr = self.calculate_atr(df)
        current_atr = atr.iloc[-1]

        atr_pct = self.calculate_atr_percentage(df)
        current_atr_pct = atr_pct.iloc[-1]

        # 基準値チェック
        min_atr_pct = 1.0
        max_atr_pct = 4.0

        passed = min_atr_pct <= current_atr_pct <= max_atr_pct

        metrics = {
            "atr": round(current_atr, 2),
            "atr_pct": round(current_atr_pct, 2),
            "passed": passed,
            "reason": self._get_reason(current_atr_pct, min_atr_pct, max_atr_pct)
        }

        return passed, metrics

    def _get_reason(self, atr_pct, min_val, max_val) -> str:
        if atr_pct < min_val:
            return f"ATR%低すぎ: {atr_pct:.2f}% < {min_val}%"
        elif atr_pct > max_val:
            return f"ATR%高すぎ: {atr_pct:.2f}% > {max_val}%"
        else:
            return f"ATR%適正: {atr_pct:.2f}%"

# 使用例
atr_filter = ATRFilter(period=14)
df = fetch_ohlcv_data("9984", days=60)
passed, metrics = atr_filter.filter_by_atr("9984", df)

print(f"銘柄: 9984")
print(f"ATR: {metrics['atr']}円")
print(f"ATR%: {metrics['atr_pct']}%")
print(f"判定: {'✅ 合格' if passed else '❌ 不合格'}")
print(f"理由: {metrics['reason']}")
```

---

## 3. トレンド強度フィルタ

### 3.1 トレンド強度の定義

**目的：** 明確なトレンドが存在する銘柄のみを選定し、レンジ相場の銘柄を除外

**測定指標：**
1. **EMA勾配**：移動平均線の傾き
2. **ADX**：トレンドの強さを示す指標
3. **価格位置**：移動平均線からの乖離率

### 3.2 EMA勾配フィルタ

```python
ema_slope_filter:
  ema_periods: [25, 75]         # 使用するEMA期間
  lookback: 10                  # 勾配計算の期間（10日）

  # 上昇トレンドの基準
  uptrend_criteria:
    ema25_slope: "> 0"          # 25EMAが上向き
    ema75_slope: "> 0"          # 75EMAも上向き
    ema25_above_ema75: true     # 25EMA > 75EMA
    min_slope_angle: 5          # 最小傾斜角度（度）

  # 下降トレンド（空売りする場合のみ）
  downtrend_criteria:
    ema25_slope: "< 0"
    ema75_slope: "< 0"
    ema25_below_ema75: true
    min_slope_angle: -5
```

**勾配の計算方法：**

```python
# server/filters/trend_filter.py
import numpy as np

class TrendFilter:
    def calculate_ema_slope(self, ema_values: pd.Series, lookback: int = 10) -> float:
        """EMAの勾配を計算（角度、度数法）"""
        recent_ema = ema_values.iloc[-lookback:].values
        x = np.arange(len(recent_ema))

        # 線形回帰で傾きを計算
        slope, _ = np.polyfit(x, recent_ema, 1)

        # 傾きを角度に変換
        angle = np.arctan(slope) * 180 / np.pi

        return angle

    def filter_by_ema_slope(self, df: pd.DataFrame) -> tuple[bool, dict]:
        """EMA勾配でフィルタリング"""
        ema25 = df['close'].ewm(span=25, adjust=False).mean()
        ema75 = df['close'].ewm(span=75, adjust=False).mean()

        slope_25 = self.calculate_ema_slope(ema25, lookback=10)
        slope_75 = self.calculate_ema_slope(ema75, lookback=10)

        current_ema25 = ema25.iloc[-1]
        current_ema75 = ema75.iloc[-1]

        # 上昇トレンド判定
        is_uptrend = (
            slope_25 > 5 and            # 25EMAの傾きが5度以上
            slope_75 > 0 and            # 75EMAも上向き
            current_ema25 > current_ema75  # ゴールデンクロス状態
        )

        metrics = {
            "ema25_slope": round(slope_25, 2),
            "ema75_slope": round(slope_75, 2),
            "ema25_above_ema75": current_ema25 > current_ema75,
            "is_uptrend": is_uptrend,
            "trend_strength": self._calculate_trend_strength(slope_25, slope_75)
        }

        return is_uptrend, metrics

    def _calculate_trend_strength(self, slope_25: float, slope_75: float) -> str:
        """トレンド強度を分類"""
        avg_slope = (slope_25 + slope_75) / 2

        if avg_slope > 15:
            return "very_strong"
        elif avg_slope > 10:
            return "strong"
        elif avg_slope > 5:
            return "moderate"
        elif avg_slope > 0:
            return "weak"
        else:
            return "no_trend"

# 使用例
trend_filter = TrendFilter()
df = fetch_ohlcv_data("9984", days=100)
passed, metrics = trend_filter.filter_by_ema_slope(df)

print(f"25EMA勾配: {metrics['ema25_slope']}度")
print(f"75EMA勾配: {metrics['ema75_slope']}度")
print(f"トレンド強度: {metrics['trend_strength']}")
print(f"判定: {'✅ 上昇トレンド' if passed else '❌ トレンドなし'}")
```

### 3.3 ADXフィルタ

```python
adx_filter:
  period: 14                    # ADX計算期間
  min_adx: 25                   # 最小ADX値（トレンド有りと判定）
  strong_trend_adx: 40          # 強いトレンドの閾値

  # ADXの傾き
  adx_rising: true              # ADXが上昇中かどうか
  lookback: 5                   # ADX上昇判定の期間
```

**ADXの意味：**
- **ADX < 20**：トレンドなし（レンジ相場）
- **20 ≤ ADX < 25**：弱いトレンド
- **25 ≤ ADX < 40**：明確なトレンド
- **ADX ≥ 40**：非常に強いトレンド

**実装例：**

```python
class ADXFilter:
    def calculate_adx(self, df: pd.DataFrame, period: int = 14) -> pd.Series:
        """ADXを計算"""
        high = df['high']
        low = df['low']
        close = df['close']

        # +DM, -DM の計算
        plus_dm = high.diff()
        minus_dm = -low.diff()

        plus_dm[plus_dm < 0] = 0
        minus_dm[minus_dm < 0] = 0

        # TR（True Range）
        tr1 = high - low
        tr2 = abs(high - close.shift())
        tr3 = abs(low - close.shift())
        tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)

        # +DI, -DI
        plus_di = 100 * (plus_dm.rolling(window=period).mean() /
                         tr.rolling(window=period).mean())
        minus_di = 100 * (minus_dm.rolling(window=period).mean() /
                          tr.rolling(window=period).mean())

        # DX
        dx = 100 * abs(plus_di - minus_di) / (plus_di + minus_di)

        # ADX
        adx = dx.rolling(window=period).mean()

        return adx

    def filter_by_adx(self, df: pd.DataFrame, min_adx: float = 25) -> tuple[bool, dict]:
        """ADXでフィルタリング"""
        adx = self.calculate_adx(df)
        current_adx = adx.iloc[-1]

        # ADXが上昇中か
        adx_rising = adx.iloc[-1] > adx.iloc[-6]

        passed = current_adx >= min_adx

        metrics = {
            "adx": round(current_adx, 2),
            "adx_rising": adx_rising,
            "trend_classification": self._classify_trend(current_adx),
            "passed": passed
        }

        return passed, metrics

    def _classify_trend(self, adx: float) -> str:
        if adx >= 40:
            return "very_strong"
        elif adx >= 25:
            return "strong"
        elif adx >= 20:
            return "weak"
        else:
            return "no_trend"
```

### 3.4 価格位置フィルタ

```python
price_position_filter:
  # 株価が移動平均線の上にあるか
  above_ema25: true
  above_ema75: true

  # 移動平均線からの乖離率
  max_deviation_from_ema25: 10  # 最大+10%まで（過熱を避ける）
  min_deviation_from_ema25: -2  # 最小-2%（押し目を狙う）
```

**実装例：**

```python
class PricePositionFilter:
    def filter_by_price_position(self, df: pd.DataFrame) -> tuple[bool, dict]:
        """価格位置でフィルタリング"""
        close = df['close'].iloc[-1]
        ema25 = df['close'].ewm(span=25, adjust=False).mean().iloc[-1]
        ema75 = df['close'].ewm(span=75, adjust=False).mean().iloc[-1]

        # 乖離率
        deviation_from_ema25 = ((close - ema25) / ema25) * 100

        # 判定
        above_ema25 = close > ema25
        above_ema75 = close > ema75
        not_overheated = -2 <= deviation_from_ema25 <= 10

        passed = above_ema25 and above_ema75 and not_overheated

        metrics = {
            "close": round(close, 2),
            "ema25": round(ema25, 2),
            "ema75": round(ema75, 2),
            "deviation_from_ema25_pct": round(deviation_from_ema25, 2),
            "above_ema25": above_ema25,
            "above_ema75": above_ema75,
            "passed": passed
        }

        return passed, metrics
```

---

## 4. 出来高フィルタ

### 4.1 出来高の役割

**目的：**
- 流動性の一時的な低下を検知
- 出来高急増（ブレイクアウト）を検知
- 安定した流動性を確保

### 4.2 出来高推移フィルタ

```python
volume_filter:
  lookback_period: 20           # 平均出来高の計算期間

  # 相対出来高
  min_relative_volume: 0.8      # 平均の80%以上
  max_relative_volume: 3.0      # 平均の300%以下（異常な急増を除外）

  # 連続低出来高の検知
  consecutive_low_volume_days: 3  # 連続3日低出来高なら除外
  low_volume_threshold: 0.6       # 平均の60%未満を「低出来高」と定義

  # 出来高トレンド
  volume_trend: "stable"        # "increasing", "stable", "decreasing"
```

**実装例：**

```python
class VolumeFilter:
    def calculate_relative_volume(self, df: pd.DataFrame,
                                  period: int = 20) -> pd.Series:
        """相対出来高を計算"""
        volume_avg = df['volume'].rolling(window=period).mean()
        relative_volume = df['volume'] / volume_avg
        return relative_volume

    def filter_by_volume(self, df: pd.DataFrame) -> tuple[bool, dict]:
        """出来高でフィルタリング"""
        volume = df['volume']
        volume_avg_20d = volume.rolling(window=20).mean()

        current_volume = volume.iloc[-1]
        avg_volume = volume_avg_20d.iloc[-1]
        relative_volume = current_volume / avg_volume

        # 連続低出来高の検知
        recent_relative_volume = (volume.iloc[-3:] /
                                 volume_avg_20d.iloc[-3:])
        consecutive_low = (recent_relative_volume < 0.6).all()

        # 出来高トレンド
        volume_trend = self._detect_volume_trend(volume)

        # 判定
        passed = (
            0.8 <= relative_volume <= 3.0 and
            not consecutive_low and
            volume_trend != "sharply_decreasing"
        )

        metrics = {
            "current_volume": int(current_volume),
            "avg_volume_20d": int(avg_volume),
            "relative_volume": round(relative_volume, 2),
            "consecutive_low_volume": consecutive_low,
            "volume_trend": volume_trend,
            "passed": passed
        }

        return passed, metrics

    def _detect_volume_trend(self, volume: pd.Series) -> str:
        """出来高トレンドを検出"""
        recent_10d = volume.iloc[-10:].mean()
        previous_10d = volume.iloc[-20:-10].mean()

        change_pct = ((recent_10d - previous_10d) / previous_10d) * 100

        if change_pct > 20:
            return "sharply_increasing"
        elif change_pct > 5:
            return "increasing"
        elif change_pct < -20:
            return "sharply_decreasing"
        elif change_pct < -5:
            return "decreasing"
        else:
            return "stable"
```

### 4.3 出来高ブレイクアウト検知

```python
volume_breakout_filter:
  # ブレイクアウトの定義
  breakout_multiplier: 2.0      # 平均の2倍以上で「ブレイクアウト」
  consecutive_high_volume: 2    # 連続2日以上の高出来高

  # 戦略による使い分け
  use_breakout: true            # ブレイクアウトを好む（トレンドフォロー向け）
  avoid_breakout: false         # ブレイクアウトを避ける（安定志向）
```

**実装例：**

```python
class VolumeBreakoutFilter:
    def detect_breakout(self, df: pd.DataFrame,
                       multiplier: float = 2.0) -> tuple[bool, dict]:
        """出来高ブレイクアウトを検知"""
        volume = df['volume']
        volume_avg = volume.rolling(window=20).mean()

        recent_relative_volume = volume.iloc[-2:] / volume_avg.iloc[-2:]
        is_breakout = (recent_relative_volume > multiplier).all()

        # 価格も上昇しているか（出来高だけでなく）
        close = df['close']
        price_rising = close.iloc[-1] > close.iloc[-3]

        # 判定
        valid_breakout = is_breakout and price_rising

        metrics = {
            "is_volume_breakout": is_breakout,
            "price_rising": price_rising,
            "valid_breakout": valid_breakout,
            "recent_relative_volume": round(recent_relative_volume.iloc[-1], 2)
        }

        return valid_breakout, metrics
```

---

## 5. 統合フィルタシステム

### 5.1 フィルタの優先順位

```yaml
filter_pipeline:
  # フィルタの実行順序（上から順に）
  - name: "volume_filter"
    weight: 0.3
    required: true              # 必須（不合格なら即除外）

  - name: "atr_filter"
    weight: 0.3
    required: true

  - name: "trend_strength_filter"
    weight: 0.4
    required: false             # 推奨（スコアリングのみ）

  # 総合スコア
  min_total_score: 0.7          # 0.7以上で合格
```

### 5.2 統合実装例

```python
# server/filters/integrated_filter.py
from typing import Dict, List, Tuple
import pandas as pd

class IntegratedStockFilter:
    def __init__(self):
        self.atr_filter = ATRFilter(period=14)
        self.trend_filter = TrendFilter()
        self.adx_filter = ADXFilter()
        self.volume_filter = VolumeFilter()
        self.price_position_filter = PricePositionFilter()

    def evaluate_stock(self, ticker: str, df: pd.DataFrame) -> Dict:
        """銘柄を総合評価"""

        results = {
            "ticker": ticker,
            "timestamp": pd.Timestamp.now(),
            "filters": {},
            "passed": False,
            "score": 0.0,
            "rank": None
        }

        # 1. ATRフィルタ（必須）
        atr_passed, atr_metrics = self.atr_filter.filter_by_atr(ticker, df)
        results["filters"]["atr"] = atr_metrics

        if not atr_passed:
            results["rejection_reason"] = "ATR不適格"
            return results

        # 2. 出来高フィルタ（必須）
        volume_passed, volume_metrics = self.volume_filter.filter_by_volume(df)
        results["filters"]["volume"] = volume_metrics

        if not volume_passed:
            results["rejection_reason"] = "出来高不適格"
            return results

        # 3. トレンド強度フィルタ（スコアリング）
        trend_passed, trend_metrics = self.trend_filter.filter_by_ema_slope(df)
        results["filters"]["trend"] = trend_metrics

        adx_passed, adx_metrics = self.adx_filter.filter_by_adx(df)
        results["filters"]["adx"] = adx_metrics

        price_passed, price_metrics = self.price_position_filter.filter_by_price_position(df)
        results["filters"]["price_position"] = price_metrics

        # 4. スコア計算
        score = self._calculate_score(
            atr_metrics, volume_metrics, trend_metrics,
            adx_metrics, price_metrics
        )
        results["score"] = score
        results["passed"] = score >= 0.7

        # 5. ランク付け
        results["rank"] = self._get_rank(score)

        return results

    def _calculate_score(self, atr_m, volume_m, trend_m, adx_m, price_m) -> float:
        """総合スコアを計算（0-1）"""

        scores = []

        # ATRスコア（適正範囲内なら1.0）
        atr_pct = atr_m["atr_pct"]
        if 1.5 <= atr_pct <= 3.0:
            atr_score = 1.0
        elif 1.0 <= atr_pct <= 4.0:
            atr_score = 0.7
        else:
            atr_score = 0.0
        scores.append(atr_score * 0.3)  # 重み30%

        # 出来高スコア
        rel_volume = volume_m["relative_volume"]
        if 1.0 <= rel_volume <= 1.5:
            volume_score = 1.0
        elif 0.8 <= rel_volume <= 2.0:
            volume_score = 0.8
        else:
            volume_score = 0.5
        scores.append(volume_score * 0.3)  # 重み30%

        # トレンド強度スコア
        trend_strength = trend_m.get("trend_strength", "no_trend")
        trend_score_map = {
            "very_strong": 1.0,
            "strong": 0.9,
            "moderate": 0.7,
            "weak": 0.5,
            "no_trend": 0.0
        }
        trend_score = trend_score_map.get(trend_strength, 0.0)
        scores.append(trend_score * 0.2)  # 重み20%

        # ADXスコア
        adx = adx_m["adx"]
        if adx >= 40:
            adx_score = 1.0
        elif adx >= 25:
            adx_score = 0.8
        elif adx >= 20:
            adx_score = 0.5
        else:
            adx_score = 0.0
        scores.append(adx_score * 0.2)  # 重み20%

        return sum(scores)

    def _get_rank(self, score: float) -> str:
        """スコアをランクに変換"""
        if score >= 0.9:
            return "S"
        elif score >= 0.8:
            return "A"
        elif score >= 0.7:
            return "B"
        elif score >= 0.6:
            return "C"
        else:
            return "D"

    def filter_universe(self, universe: List[str]) -> List[Dict]:
        """銘柄リスト全体をフィルタリング"""

        results = []

        for ticker in universe:
            try:
                # OHLCVデータ取得（過去100日分）
                df = fetch_ohlcv_data(ticker, days=100)

                # 評価実行
                result = self.evaluate_stock(ticker, df)
                results.append(result)

            except Exception as e:
                logger.error(f"銘柄評価エラー {ticker}: {e}")
                continue

        # スコア順にソート
        results.sort(key=lambda x: x["score"], reverse=True)

        return results

# 使用例
filter_system = IntegratedStockFilter()

# 一次フィルタ済み銘柄リスト
universe = ["9984", "6758", "7203", "9433", "8306",
            "6861", "8035", "4063", "6098", "4568"]

# 二次フィルタ実行
filtered_results = filter_system.filter_universe(universe)

# 合格銘柄のみ抽出（スコア0.7以上）
approved_stocks = [r for r in filtered_results if r["passed"]]

print("=== 二次フィルタ結果 ===")
for r in approved_stocks[:5]:  # Top 5
    print(f"{r['ticker']}: スコア {r['score']:.2f} (ランク{r['rank']})")
```

---

## 6. 日次・週次更新スケジュール

### 6.1 更新頻度と実行タイミング

```yaml
update_schedule:
  daily:
    # 毎営業日 16:00（市場終了後）
    time: "16:00 JST"
    tasks:
      - calculate_atr
      - calculate_volume_metrics
      - update_trend_indicators
      - run_filter_pipeline
      - generate_daily_report

  weekly:
    # 毎週月曜日 7:00（市場開始前）
    day: "Monday"
    time: "07:00 JST"
    tasks:
      - review_universe
      - recalculate_all_metrics
      - optimize_filter_parameters
      - generate_weekly_summary

  monthly:
    # 毎月第1営業日
    day: "first_business_day"
    time: "07:00 JST"
    tasks:
      - full_universe_review
      - add_new_stocks
      - remove_delisted_stocks
      - backtest_filter_performance
```

### 6.2 自動実行スクリプト

```python
# server/schedulers/filter_scheduler.py
from apscheduler.schedulers.background import BackgroundScheduler
from datetime import datetime
import pytz

class FilterScheduler:
    def __init__(self):
        self.scheduler = BackgroundScheduler(timezone=pytz.timezone('Asia/Tokyo'))
        self.filter_system = IntegratedStockFilter()

    def start(self):
        """スケジューラーを開始"""

        # 日次更新（毎営業日16:00）
        self.scheduler.add_job(
            self.daily_update,
            trigger='cron',
            hour=16,
            minute=0,
            day_of_week='mon-fri'
        )

        # 週次更新（毎週月曜7:00）
        self.scheduler.add_job(
            self.weekly_update,
            trigger='cron',
            day_of_week='mon',
            hour=7,
            minute=0
        )

        self.scheduler.start()
        logger.info("フィルタスケジューラー起動")

    def daily_update(self):
        """日次更新処理"""
        logger.info("=== 日次フィルタ更新開始 ===")

        # 1. 銘柄リスト取得
        universe = get_stock_universe()

        # 2. フィルタリング実行
        results = self.filter_system.filter_universe(universe)

        # 3. 結果を保存
        self._save_results(results, frequency="daily")

        # 4. 合格銘柄を更新
        approved = [r["ticker"] for r in results if r["passed"]]
        self._update_approved_list(approved)

        # 5. レポート生成
        self._generate_daily_report(results)

        logger.info(f"日次更新完了: {len(approved)}/{len(universe)} 銘柄合格")

    def weekly_update(self):
        """週次更新処理"""
        logger.info("=== 週次フィルタ更新開始 ===")

        # パラメータ最適化
        self._optimize_parameters()

        # パフォーマンスレビュー
        self._review_performance()

        logger.info("週次更新完了")

    def _save_results(self, results: List[Dict], frequency: str):
        """結果をDBに保存"""
        timestamp = datetime.now(pytz.timezone('Asia/Tokyo'))

        for result in results:
            # DB保存処理
            save_filter_result(
                ticker=result["ticker"],
                score=result["score"],
                rank=result["rank"],
                passed=result["passed"],
                filters=result["filters"],
                timestamp=timestamp,
                frequency=frequency
            )

    def _update_approved_list(self, approved: List[str]):
        """承認済み銘柄リストを更新"""
        # Redisに保存（高速アクセス用）
        redis_client.set("approved_stocks", json.dumps(approved))

        # DBにも保存（永続化）
        update_approved_stocks_table(approved)

    def _generate_daily_report(self, results: List[Dict]):
        """日次レポート生成"""
        approved = [r for r in results if r["passed"]]
        rejected = [r for r in results if not r["passed"]]

        report = f"""
        ===日次フィルタレポート===
        日時: {datetime.now()}

        合格銘柄: {len(approved)}
        {chr(10).join([f"  - {r['ticker']}: スコア{r['score']:.2f}" for r in approved[:10]])}

        不合格銘柄: {len(rejected)}
        {chr(10).join([f"  - {r['ticker']}: {r.get('rejection_reason', 'スコア不足')}" for r in rejected[:5]])}
        """

        # Slack通知
        send_slack_notification(report)

        # ファイル保存
        save_report(report, "daily_filter_report.txt")
```

---

## 7. フィルタ結果の可視化

### 7.1 ダッシュボード例

```python
# server/dashboard/filter_dashboard.py
import streamlit as st
import pandas as pd
import plotly.express as px

def render_filter_dashboard():
    st.title("銘柄フィルタダッシュボード")

    # 最新フィルタ結果を取得
    results = load_latest_filter_results()

    # 1. サマリー
    st.header("フィルタサマリー")
    col1, col2, col3 = st.columns(3)

    total = len(results)
    approved = len([r for r in results if r["passed"]])
    avg_score = sum(r["score"] for r in results) / total

    col1.metric("合計銘柄数", total)
    col2.metric("合格銘柄数", approved)
    col3.metric("平均スコア", f"{avg_score:.2f}")

    # 2. 合格銘柄リスト
    st.header("合格銘柄（スコア順）")
    approved_df = pd.DataFrame([
        {
            "銘柄": r["ticker"],
            "スコア": r["score"],
            "ランク": r["rank"],
            "ATR%": r["filters"]["atr"]["atr_pct"],
            "相対出来高": r["filters"]["volume"]["relative_volume"],
            "トレンド強度": r["filters"]["trend"]["trend_strength"]
        }
        for r in results if r["passed"]
    ])
    st.dataframe(approved_df)

    # 3. スコア分布
    st.header("スコア分布")
    scores = [r["score"] for r in results]
    fig = px.histogram(scores, nbins=20, title="銘柄スコア分布")
    st.plotly_chart(fig)

    # 4. フィルタ別合格率
    st.header("フィルタ別合格率")
    filter_pass_rates = calculate_filter_pass_rates(results)
    st.bar_chart(filter_pass_rates)
```

---

## まとめ

### フィルタ基準一覧

| フィルタ | 基準値 | 重み | 必須/推奨 |
|---------|--------|------|----------|
| **ATR%** | 1.0-4.0% | 30% | 必須 |
| **相対出来高** | 0.8-3.0倍 | 30% | 必須 |
| **EMA勾配** | > 5度 | 20% | 推奨 |
| **ADX** | ≥ 25 | 20% | 推奨 |
| **価格位置** | EMA25/75上 | - | 推奨 |

### 更新スケジュール

```
毎営業日 16:00: 全フィルタ実行、承認リスト更新
毎週月曜 07:00: パラメータ最適化、週次レビュー
毎月第1営業日: 銘柄リスト見直し、バックテスト
```

### 実装優先度

1. **ATRフィルタ**（最重要）- リスク管理の核
2. **出来高フィルタ**（重要）- 流動性確保
3. **トレンド強度フィルタ**（推奨）- 戦略適合性
4. **自動更新システム**（重要）- 運用効率化

---

*最終更新: 2025-12-27*
