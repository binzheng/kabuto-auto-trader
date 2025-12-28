"""
Kabuto Auto Trader - テクニカルインジケーター計算ライブラリ
MA, RSI, ATR, ボラティリティ等
"""

import pandas as pd
import numpy as np
from typing import Optional
import logging

logger = logging.getLogger(__name__)


class TechnicalIndicators:
    """テクニカルインジケーター計算クラス"""

    def __init__(self, df: pd.DataFrame):
        """
        Args:
            df: OHLCVデータ
        """
        self.df = df.copy()

    # ========================================
    # 移動平均（Moving Average）
    # ========================================

    def calculate_sma(
        self,
        period: int,
        column: str = 'close'
    ) -> pd.Series:
        """
        単純移動平均（Simple Moving Average）

        Args:
            period: 期間
            column: 対象カラム

        Returns:
            pd.Series: SMA
        """
        return self.df[column].rolling(window=period).mean()

    def calculate_ema(
        self,
        period: int,
        column: str = 'close'
    ) -> pd.Series:
        """
        指数移動平均（Exponential Moving Average）

        Args:
            period: 期間
            column: 対象カラム

        Returns:
            pd.Series: EMA
        """
        return self.df[column].ewm(span=period, adjust=False).mean()

    def add_moving_averages(
        self,
        fast_period: int = 5,
        medium_period: int = 25,
        slow_period: int = 75,
        ma_type: str = 'ema'
    ) -> 'TechnicalIndicators':
        """
        移動平均線を追加

        Args:
            fast_period: 短期MA期間
            medium_period: 中期MA期間
            slow_period: 長期MA期間
            ma_type: MAタイプ（'sma' or 'ema'）

        Returns:
            self: メソッドチェーン用
        """
        if ma_type == 'ema':
            self.df['ema_fast'] = self.calculate_ema(fast_period)
            self.df['ema_medium'] = self.calculate_ema(medium_period)
            self.df['ema_slow'] = self.calculate_ema(slow_period)
        elif ma_type == 'sma':
            self.df['sma_fast'] = self.calculate_sma(fast_period)
            self.df['sma_medium'] = self.calculate_sma(medium_period)
            self.df['sma_slow'] = self.calculate_sma(slow_period)
        else:
            raise ValueError(f"未対応のMAタイプ: {ma_type}")

        logger.info(f"{ma_type.upper()}追加: {fast_period}, {medium_period}, {slow_period}")
        return self

    # ========================================
    # RSI（Relative Strength Index）
    # ========================================

    def calculate_rsi(
        self,
        period: int = 14,
        column: str = 'close'
    ) -> pd.Series:
        """
        RSI（相対力指数）

        Args:
            period: 期間
            column: 対象カラム

        Returns:
            pd.Series: RSI (0-100)
        """
        delta = self.df[column].diff()

        # 上昇分と下落分を分離
        gain = delta.where(delta > 0, 0)
        loss = -delta.where(delta < 0, 0)

        # 指数移動平均で平滑化
        avg_gain = gain.ewm(span=period, adjust=False).mean()
        avg_loss = loss.ewm(span=period, adjust=False).mean()

        # RS = 平均上昇幅 / 平均下落幅
        rs = avg_gain / avg_loss

        # RSI = 100 - (100 / (1 + RS))
        rsi = 100 - (100 / (1 + rs))

        return rsi

    def add_rsi(
        self,
        period: int = 14,
        column: str = 'close'
    ) -> 'TechnicalIndicators':
        """
        RSIを追加

        Args:
            period: 期間
            column: 対象カラム

        Returns:
            self: メソッドチェーン用
        """
        self.df['rsi'] = self.calculate_rsi(period, column)
        logger.info(f"RSI追加: 期間 {period}")
        return self

    # ========================================
    # ATR（Average True Range）
    # ========================================

    def calculate_atr(
        self,
        period: int = 14
    ) -> pd.Series:
        """
        ATR（平均真の範囲）

        Args:
            period: 期間

        Returns:
            pd.Series: ATR
        """
        # True Range = max(high-low, |high-prev_close|, |low-prev_close|)
        high_low = self.df['high'] - self.df['low']
        high_close = np.abs(self.df['high'] - self.df['close'].shift(1))
        low_close = np.abs(self.df['low'] - self.df['close'].shift(1))

        true_range = pd.concat([high_low, high_close, low_close], axis=1).max(axis=1)

        # ATR = True Rangeの移動平均
        atr = true_range.ewm(span=period, adjust=False).mean()

        return atr

    def add_atr(
        self,
        period: int = 14
    ) -> 'TechnicalIndicators':
        """
        ATRを追加

        Args:
            period: 期間

        Returns:
            self: メソッドチェーン用
        """
        self.df['atr'] = self.calculate_atr(period)
        logger.info(f"ATR追加: 期間 {period}")
        return self

    # ========================================
    # 出来高（Volume）
    # ========================================

    def calculate_volume_ma(
        self,
        period: int = 20
    ) -> pd.Series:
        """
        出来高移動平均

        Args:
            period: 期間

        Returns:
            pd.Series: 出来高MA
        """
        return self.df['volume'].rolling(window=period).mean()

    def add_volume_indicators(
        self,
        period: int = 20
    ) -> 'TechnicalIndicators':
        """
        出来高関連インジケーターを追加

        Args:
            period: 期間

        Returns:
            self: メソッドチェーン用
        """
        self.df['volume_ma'] = self.calculate_volume_ma(period)
        self.df['volume_ratio'] = self.df['volume'] / self.df['volume_ma']
        logger.info(f"出来高インジケーター追加: 期間 {period}")
        return self

    # ========================================
    # ボラティリティ（Volatility）
    # ========================================

    def calculate_volatility(
        self,
        period: int = 20,
        column: str = 'close'
    ) -> pd.Series:
        """
        ボラティリティ（標準偏差）

        Args:
            period: 期間
            column: 対象カラム

        Returns:
            pd.Series: ボラティリティ
        """
        returns = self.df[column].pct_change()
        volatility = returns.rolling(window=period).std() * np.sqrt(252)  # 年率換算
        return volatility

    def add_volatility(
        self,
        period: int = 20,
        column: str = 'close'
    ) -> 'TechnicalIndicators':
        """
        ボラティリティを追加

        Args:
            period: 期間
            column: 対象カラム

        Returns:
            self: メソッドチェーン用
        """
        self.df['volatility'] = self.calculate_volatility(period, column)
        logger.info(f"ボラティリティ追加: 期間 {period}")
        return self

    # ========================================
    # ボリンジャーバンド（Bollinger Bands）
    # ========================================

    def calculate_bollinger_bands(
        self,
        period: int = 20,
        num_std: float = 2.0,
        column: str = 'close'
    ) -> tuple:
        """
        ボリンジャーバンド

        Args:
            period: 期間
            num_std: 標準偏差の倍数
            column: 対象カラム

        Returns:
            tuple: (upper_band, middle_band, lower_band)
        """
        middle_band = self.df[column].rolling(window=period).mean()
        std = self.df[column].rolling(window=period).std()

        upper_band = middle_band + (std * num_std)
        lower_band = middle_band - (std * num_std)

        return upper_band, middle_band, lower_band

    def add_bollinger_bands(
        self,
        period: int = 20,
        num_std: float = 2.0,
        column: str = 'close'
    ) -> 'TechnicalIndicators':
        """
        ボリンジャーバンドを追加

        Args:
            period: 期間
            num_std: 標準偏差の倍数
            column: 対象カラム

        Returns:
            self: メソッドチェーン用
        """
        upper, middle, lower = self.calculate_bollinger_bands(period, num_std, column)
        self.df['bb_upper'] = upper
        self.df['bb_middle'] = middle
        self.df['bb_lower'] = lower
        logger.info(f"ボリンジャーバンド追加: 期間 {period}, {num_std}σ")
        return self

    # ========================================
    # MACD（Moving Average Convergence Divergence）
    # ========================================

    def calculate_macd(
        self,
        fast_period: int = 12,
        slow_period: int = 26,
        signal_period: int = 9,
        column: str = 'close'
    ) -> tuple:
        """
        MACD

        Args:
            fast_period: 短期EMA期間
            slow_period: 長期EMA期間
            signal_period: シグナル線期間
            column: 対象カラム

        Returns:
            tuple: (macd, signal, histogram)
        """
        ema_fast = self.df[column].ewm(span=fast_period, adjust=False).mean()
        ema_slow = self.df[column].ewm(span=slow_period, adjust=False).mean()

        macd = ema_fast - ema_slow
        signal = macd.ewm(span=signal_period, adjust=False).mean()
        histogram = macd - signal

        return macd, signal, histogram

    def add_macd(
        self,
        fast_period: int = 12,
        slow_period: int = 26,
        signal_period: int = 9,
        column: str = 'close'
    ) -> 'TechnicalIndicators':
        """
        MACDを追加

        Args:
            fast_period: 短期EMA期間
            slow_period: 長期EMA期間
            signal_period: シグナル線期間
            column: 対象カラム

        Returns:
            self: メソッドチェーン用
        """
        macd, signal, histogram = self.calculate_macd(
            fast_period, slow_period, signal_period, column
        )
        self.df['macd'] = macd
        self.df['macd_signal'] = signal
        self.df['macd_histogram'] = histogram
        logger.info(f"MACD追加: {fast_period}/{slow_period}/{signal_period}")
        return self

    # ========================================
    # ユーティリティ
    # ========================================

    def add_all_kabuto_indicators(
        self,
        ema_fast: int = 5,
        ema_medium: int = 25,
        ema_slow: int = 75,
        rsi_period: int = 14,
        atr_period: int = 14,
        volume_period: int = 20
    ) -> 'TechnicalIndicators':
        """
        Kabuto戦略で使用する全インジケーターを追加

        Args:
            ema_fast: 短期EMA期間
            ema_medium: 中期EMA期間
            ema_slow: 長期EMA期間
            rsi_period: RSI期間
            atr_period: ATR期間
            volume_period: 出来高MA期間

        Returns:
            self: メソッドチェーン用
        """
        self.add_moving_averages(ema_fast, ema_medium, ema_slow, ma_type='ema')
        self.add_rsi(rsi_period)
        self.add_atr(atr_period)
        self.add_volume_indicators(volume_period)
        logger.info("Kabuto戦略インジケーター全追加完了")
        return self

    def get_data(self) -> pd.DataFrame:
        """
        インジケーター付きデータを取得

        Returns:
            pd.DataFrame: インジケーター付きOHLCVデータ
        """
        return self.df.copy()


# ========================================
# 便利関数
# ========================================

def quick_add_indicators(
    df: pd.DataFrame,
    indicators: list = None
) -> pd.DataFrame:
    """
    簡易インジケーター追加

    Args:
        df: OHLCVデータ
        indicators: インジケーターリスト（Noneの場合はKabuto戦略デフォルト）

    Returns:
        pd.DataFrame: インジケーター付きデータ
    """
    ti = TechnicalIndicators(df)

    if indicators is None:
        # Kabuto戦略デフォルト
        ti = ti.add_all_kabuto_indicators()
    else:
        for indicator in indicators:
            if indicator == 'ema':
                ti = ti.add_moving_averages(ma_type='ema')
            elif indicator == 'sma':
                ti = ti.add_moving_averages(ma_type='sma')
            elif indicator == 'rsi':
                ti = ti.add_rsi()
            elif indicator == 'atr':
                ti = ti.add_atr()
            elif indicator == 'volume':
                ti = ti.add_volume_indicators()
            elif indicator == 'volatility':
                ti = ti.add_volatility()
            elif indicator == 'bollinger':
                ti = ti.add_bollinger_bands()
            elif indicator == 'macd':
                ti = ti.add_macd()
            else:
                logger.warning(f"未対応のインジケーター: {indicator}")

    return ti.get_data()


if __name__ == '__main__':
    # テスト実行
    import logging
    logging.basicConfig(level=logging.INFO)

    # サンプルデータ作成
    dates = pd.date_range('2024-01-01', '2024-12-31', freq='D')
    df_test = pd.DataFrame({
        'timestamp': dates,
        'open': np.random.uniform(1000, 1100, len(dates)),
        'high': np.random.uniform(1100, 1200, len(dates)),
        'low': np.random.uniform(900, 1000, len(dates)),
        'close': np.random.uniform(1000, 1100, len(dates)),
        'volume': np.random.randint(100000, 1000000, len(dates))
    })

    print("=== インジケーター追加前 ===")
    print(df_test.head())
    print(f"カラム数: {len(df_test.columns)}")

    # Kabuto戦略インジケーター追加
    ti = TechnicalIndicators(df_test)
    ti = ti.add_all_kabuto_indicators()
    df_with_indicators = ti.get_data()

    print("\n=== インジケーター追加後 ===")
    print(df_with_indicators.head())
    print(f"カラム数: {len(df_with_indicators.columns)}")
    print(f"追加されたカラム: {list(set(df_with_indicators.columns) - set(df_test.columns))}")

    # 個別インジケーターテスト
    print("\n=== RSI (最新10行) ===")
    print(df_with_indicators[['timestamp', 'close', 'rsi']].tail(10))

    print("\n=== EMA (最新10行) ===")
    print(df_with_indicators[['timestamp', 'close', 'ema_fast', 'ema_medium', 'ema_slow']].tail(10))
