"""
Kabuto Auto Trader - データクリーニング & 前処理ライブラリ
OHLCVデータの品質管理と前処理
"""

import pandas as pd
import numpy as np
from typing import Optional, Tuple, List
import logging

logger = logging.getLogger(__name__)


class DataCleaner:
    """データクリーニングクラス"""

    def __init__(self, df: pd.DataFrame):
        """
        Args:
            df: OHLCVデータ
        """
        self.df = df.copy()
        self.original_length = len(df)
        self.cleaning_log = []

    # ========================================
    # 異常値除去
    # ========================================

    def remove_anomalies(self, min_volume: int = 0) -> 'DataCleaner':
        """
        異常行を削除

        Args:
            min_volume: 最小出来高（デフォルト0 = 出来高ゼロを除外）

        Returns:
            self: メソッドチェーン用
        """
        before = len(self.df)

        # 出来高ゼロまたは極端に少ない行を削除
        self.df = self.df[self.df['volume'] > min_volume]

        # OHLCが全て同じ（動きがない）行を削除
        no_movement = (
            (self.df['open'] == self.df['close']) &
            (self.df['high'] == self.df['low']) &
            (self.df['open'] == self.df['high'])
        )
        self.df = self.df[~no_movement]

        # NaN/Inf を含む行を削除
        self.df = self.df.replace([np.inf, -np.inf], np.nan)
        self.df = self.df.dropna()

        after = len(self.df)
        removed = before - after

        if removed > 0:
            self._log(f"異常値除去: {removed}行削除（出来高ゼロ、動きなし、NaN等）")

        return self

    def remove_duplicates(self) -> 'DataCleaner':
        """
        重複行を削除

        Returns:
            self: メソッドチェーン用
        """
        before = len(self.df)
        self.df = self.df.drop_duplicates(subset=['timestamp'], keep='first')
        after = len(self.df)
        removed = before - after

        if removed > 0:
            self._log(f"重複削除: {removed}行削除")

        return self

    def detect_outliers(
        self,
        column: str = 'close',
        method: str = 'iqr',
        threshold: float = 3.0
    ) -> pd.Series:
        """
        外れ値を検出

        Args:
            column: 対象カラム
            method: 検出方法
                - 'iqr': 四分位範囲（デフォルト）
                - 'zscore': Z-score
            threshold: 閾値（IQR: 1.5-3.0, Z-score: 2.0-3.0）

        Returns:
            pd.Series: 外れ値フラグ（True=外れ値）
        """
        if method == 'iqr':
            Q1 = self.df[column].quantile(0.25)
            Q3 = self.df[column].quantile(0.75)
            IQR = Q3 - Q1
            lower_bound = Q1 - threshold * IQR
            upper_bound = Q3 + threshold * IQR
            outliers = (self.df[column] < lower_bound) | (self.df[column] > upper_bound)

        elif method == 'zscore':
            mean = self.df[column].mean()
            std = self.df[column].std()
            z_scores = np.abs((self.df[column] - mean) / std)
            outliers = z_scores > threshold

        else:
            raise ValueError(f"未対応の検出方法: {method}")

        return outliers

    def remove_outliers(
        self,
        column: str = 'close',
        method: str = 'iqr',
        threshold: float = 3.0
    ) -> 'DataCleaner':
        """
        外れ値を削除

        Args:
            column: 対象カラム
            method: 検出方法
            threshold: 閾値

        Returns:
            self: メソッドチェーン用
        """
        before = len(self.df)
        outliers = self.detect_outliers(column, method, threshold)
        self.df = self.df[~outliers]
        after = len(self.df)
        removed = before - after

        if removed > 0:
            self._log(f"外れ値削除 ({column}, {method}): {removed}行削除")

        return self

    # ========================================
    # 欠損値処理
    # ========================================

    def fill_missing_values(
        self,
        method: str = 'ffill',
        limit: Optional[int] = 3
    ) -> 'DataCleaner':
        """
        欠損値を補完

        Args:
            method: 補完方法
                - 'ffill': 前方補完（前の値で埋める）
                - 'bfill': 後方補完（後の値で埋める）
                - 'interpolate': 線形補間
                - 'drop': 削除
            limit: 連続欠損の最大補完数（Noneで無制限）

        Returns:
            self: メソッドチェーン用
        """
        before_nulls = self.df.isnull().sum().sum()

        if method == 'ffill':
            self.df = self.df.fillna(method='ffill', limit=limit)
        elif method == 'bfill':
            self.df = self.df.fillna(method='bfill', limit=limit)
        elif method == 'interpolate':
            self.df = self.df.interpolate(method='linear', limit=limit)
        elif method == 'drop':
            self.df = self.df.dropna()
        else:
            raise ValueError(f"未対応の補完方法: {method}")

        after_nulls = self.df.isnull().sum().sum()
        filled = before_nulls - after_nulls

        if filled > 0:
            self._log(f"欠損値補完 ({method}): {filled}個補完")

        return self

    # ========================================
    # 取引日調整
    # ========================================

    def align_trading_days(
        self,
        trading_calendar: Optional[pd.DatetimeIndex] = None
    ) -> 'DataCleaner':
        """
        取引日に合わせてデータを調整

        Args:
            trading_calendar: 取引日カレンダー（Noneの場合は平日のみ）

        Returns:
            self: メソッドチェーン用
        """
        if trading_calendar is None:
            # 土日を除外
            self.df = self.df[self.df['timestamp'].dt.dayofweek < 5]
            self._log("取引日調整: 土日を除外")
        else:
            # 指定された取引日のみ残す
            self.df['date'] = self.df['timestamp'].dt.date
            valid_dates = set(trading_calendar.date)
            self.df = self.df[self.df['date'].isin(valid_dates)]
            self.df = self.df.drop(columns=['date'])
            self._log(f"取引日調整: {len(trading_calendar)}日に整合")

        return self

    # ========================================
    # 時間軸変換
    # ========================================

    def resample_timeframe(
        self,
        new_interval: str
    ) -> 'DataCleaner':
        """
        時間軸を変換（リサンプリング）

        Args:
            new_interval: 新しい時間軸
                - '1T' or '1min': 1分
                - '5T' or '5min': 5分
                - '15T' or '15min': 15分
                - '1H': 1時間
                - '1D': 日足

        Returns:
            self: メソッドチェーン用
        """
        # timestampをインデックスに設定
        self.df = self.df.set_index('timestamp')

        # リサンプリング
        resampled = self.df.resample(new_interval).agg({
            'open': 'first',
            'high': 'max',
            'low': 'min',
            'close': 'last',
            'volume': 'sum'
        }).dropna()

        # インデックスを列に戻す
        resampled = resampled.reset_index()

        self.df = resampled
        self._log(f"時間軸変換: {new_interval} に変換（{len(self.df)}行）")

        return self

    # ========================================
    # データ検証
    # ========================================

    def validate(self) -> Tuple[bool, List[str]]:
        """
        データの妥当性を検証

        Returns:
            Tuple[bool, List[str]]: (検証結果, エラーメッセージリスト)
        """
        errors = []

        # 必須カラムチェック
        required_cols = ['timestamp', 'open', 'high', 'low', 'close', 'volume']
        missing_cols = set(required_cols) - set(self.df.columns)
        if missing_cols:
            errors.append(f"必須カラム不足: {missing_cols}")

        # データ型チェック
        if 'timestamp' in self.df.columns:
            if not pd.api.types.is_datetime64_any_dtype(self.df['timestamp']):
                errors.append("timestamp が datetime 型ではありません")

        # OHLCの整合性チェック
        invalid_ohlc = self.df[
            (self.df['high'] < self.df['low']) |
            (self.df['high'] < self.df['open']) |
            (self.df['high'] < self.df['close']) |
            (self.df['low'] > self.df['open']) |
            (self.df['low'] > self.df['close'])
        ]
        if len(invalid_ohlc) > 0:
            errors.append(f"OHLCの整合性エラー: {len(invalid_ohlc)}行")

        # 負の値チェック
        negative_values = self.df[
            (self.df['open'] <= 0) |
            (self.df['high'] <= 0) |
            (self.df['low'] <= 0) |
            (self.df['close'] <= 0) |
            (self.df['volume'] < 0)
        ]
        if len(negative_values) > 0:
            errors.append(f"負の値が存在: {len(negative_values)}行")

        # 時系列順チェック
        if not self.df['timestamp'].is_monotonic_increasing:
            errors.append("タイムスタンプが昇順ではありません")

        return (len(errors) == 0, errors)

    # ========================================
    # ユーティリティ
    # ========================================

    def get_cleaned_data(self) -> pd.DataFrame:
        """
        クリーニング済みデータを取得

        Returns:
            pd.DataFrame: クリーニング済みOHLCVデータ
        """
        return self.df.copy()

    def get_cleaning_summary(self) -> str:
        """
        クリーニングサマリーを取得

        Returns:
            str: サマリーテキスト
        """
        summary = [
            "=" * 60,
            "データクリーニングサマリー",
            "=" * 60,
            f"元のデータ行数: {self.original_length:,}",
            f"クリーニング後: {len(self.df):,}",
            f"削除行数: {self.original_length - len(self.df):,}",
            "",
            "実行した処理:",
        ]

        if self.cleaning_log:
            for log in self.cleaning_log:
                summary.append(f"  - {log}")
        else:
            summary.append("  （処理なし）")

        summary.append("=" * 60)

        return "\n".join(summary)

    def _log(self, message: str):
        """ログ記録"""
        self.cleaning_log.append(message)
        logger.info(message)


# ========================================
# 便利関数
# ========================================

def quick_clean(
    df: pd.DataFrame,
    min_volume: int = 0,
    remove_outliers: bool = False
) -> pd.DataFrame:
    """
    簡易クリーニング

    Args:
        df: OHLCVデータ
        min_volume: 最小出来高
        remove_outliers: 外れ値除去を行うか

    Returns:
        pd.DataFrame: クリーニング済みデータ
    """
    cleaner = DataCleaner(df)
    cleaner = cleaner.remove_anomalies(min_volume=min_volume)
    cleaner = cleaner.remove_duplicates()
    cleaner = cleaner.fill_missing_values(method='ffill', limit=3)

    if remove_outliers:
        cleaner = cleaner.remove_outliers(column='close', method='iqr', threshold=3.0)

    return cleaner.get_cleaned_data()


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

    # 異常データを注入
    df_test.loc[10, 'volume'] = 0  # 出来高ゼロ
    df_test.loc[20, 'close'] = np.nan  # 欠損値
    df_test.loc[30, 'close'] = 5000  # 外れ値

    print("=== クリーニング前 ===")
    print(df_test.head(50))
    print(f"行数: {len(df_test)}")

    # クリーニング
    cleaner = DataCleaner(df_test)
    cleaner = (
        cleaner
        .remove_anomalies(min_volume=0)
        .remove_duplicates()
        .fill_missing_values(method='ffill', limit=3)
        .remove_outliers(column='close', method='iqr', threshold=3.0)
    )

    df_cleaned = cleaner.get_cleaned_data()

    print("\n=== クリーニング後 ===")
    print(df_cleaned.head())
    print(f"行数: {len(df_cleaned)}")

    print("\n" + cleaner.get_cleaning_summary())

    # 検証
    is_valid, errors = cleaner.validate()
    print(f"\n検証結果: {'✅ OK' if is_valid else '❌ NG'}")
    if errors:
        for error in errors:
            print(f"  - {error}")
