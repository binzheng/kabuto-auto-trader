"""
Kabuto Auto Trader - シグナル生成エンジン
戦略ルールに基づいてエントリー/エグジットシグナルを生成
"""

import pandas as pd
import numpy as np
from typing import Dict, Optional
from datetime import timedelta
import logging

logger = logging.getLogger(__name__)


class SignalGenerator:
    """シグナル生成クラス"""

    def __init__(
        self,
        df: pd.DataFrame,
        strategy_params: Optional[Dict] = None
    ):
        """
        Args:
            df: インジケーター付きOHLCVデータ
            strategy_params: 戦略パラメータ
        """
        self.df = df.copy()
        self.params = self._get_default_params()

        if strategy_params:
            self.params.update(strategy_params)

        # シグナル用カラム初期化
        self.df['entry_signal'] = False
        self.df['exit_signal'] = False
        self.df['stop_loss'] = np.nan
        self.df['take_profit'] = np.nan

    # ========================================
    # デフォルトパラメータ
    # ========================================

    def _get_default_params(self) -> Dict:
        """デフォルト戦略パラメータ（kabuto_strategy_v1.pine準拠）"""
        return {
            # 移動平均線
            'ema_fast_period': 5,
            'ema_medium_period': 25,
            'ema_slow_period': 75,

            # RSI
            'rsi_period': 14,
            'rsi_lower': 50,
            'rsi_upper': 70,

            # 出来高
            'volume_period': 20,
            'volume_multiplier': 1.2,

            # ATR
            'atr_period': 14,
            'atr_sl_multiplier': 2.0,
            'atr_tp_multiplier': 4.0,
            'min_rr_ratio': 1.5,

            # リスク管理
            'max_daily_entries': 3,
            'cooldown_minutes': 30,
            'cooldown_after_loss': 60
        }

    # ========================================
    # エントリーシグナル生成
    # ========================================

    def generate_entry_signals(self) -> 'SignalGenerator':
        """
        エントリーシグナルを生成（ロングのみ）

        Kabuto戦略のエントリー条件:
        1. トレンド: 短期EMA > 中期EMA > 長期EMA
        2. モメンタム: rsi_lower < RSI < rsi_upper
        3. 出来高: volume > volume_ma * volume_multiplier
        4. リスクリワード: TP/SL >= min_rr_ratio

        Returns:
            self: メソッドチェーン用
        """
        # 必須インジケーターチェック
        required_cols = ['ema_fast', 'ema_medium', 'ema_slow', 'rsi', 'volume_ma', 'atr']
        missing_cols = set(required_cols) - set(self.df.columns)
        if missing_cols:
            raise ValueError(f"必須インジケーターが不足しています: {missing_cols}")

        # 1. トレンド条件
        trend_condition = (
            (self.df['ema_fast'] > self.df['ema_medium']) &
            (self.df['ema_medium'] > self.df['ema_slow'])
        )

        # 2. モメンタム条件
        momentum_condition = (
            (self.df['rsi'] > self.params['rsi_lower']) &
            (self.df['rsi'] < self.params['rsi_upper'])
        )

        # 3. 出来高条件
        volume_condition = (
            self.df['volume'] > (self.df['volume_ma'] * self.params['volume_multiplier'])
        )

        # 4. リスクリワード条件（後で計算）
        # TP = close + atr * atr_tp_multiplier
        # SL = close - atr * atr_sl_multiplier
        # RR = (TP - close) / (close - SL)
        potential_tp = self.df['close'] + (self.df['atr'] * self.params['atr_tp_multiplier'])
        potential_sl = self.df['close'] - (self.df['atr'] * self.params['atr_sl_multiplier'])
        rr_ratio = (potential_tp - self.df['close']) / (self.df['close'] - potential_sl)
        rr_condition = rr_ratio >= self.params['min_rr_ratio']

        # 全条件を満たす
        self.df['entry_signal'] = (
            trend_condition &
            momentum_condition &
            volume_condition &
            rr_condition
        )

        # ストップロス・テイクプロフィットを計算
        self.df['stop_loss'] = self.df['close'] - (self.df['atr'] * self.params['atr_sl_multiplier'])
        self.df['take_profit'] = self.df['close'] + (self.df['atr'] * self.params['atr_tp_multiplier'])

        logger.info(f"エントリーシグナル生成完了: {self.df['entry_signal'].sum()}個")
        return self

    # ========================================
    # リスク管理フィルター
    # ========================================

    def apply_risk_filters(self) -> 'SignalGenerator':
        """
        リスク管理フィルターを適用

        1. 1日の最大エントリー数制限
        2. クールダウン時間

        Returns:
            self: メソッドチェーン用
        """
        # タイムスタンプから日付を抽出
        if 'timestamp' not in self.df.columns:
            logger.warning("timestamp カラムがないため、リスク管理フィルターをスキップ")
            return self

        self.df['date'] = pd.to_datetime(self.df['timestamp']).dt.date

        # 1日のエントリー数をカウント
        filtered_signals = []
        daily_entry_count = {}
        last_entry_time = None

        for idx, row in self.df.iterrows():
            date = row['date']
            timestamp = row['timestamp']
            signal = row['entry_signal']

            # 日付が変わったらカウントリセット
            if date not in daily_entry_count:
                daily_entry_count[date] = 0

            # シグナルがある場合
            if signal:
                # 1. 1日の最大エントリー数チェック
                if daily_entry_count[date] >= self.params['max_daily_entries']:
                    filtered_signals.append(False)
                    continue

                # 2. クールダウン時間チェック
                if last_entry_time is not None:
                    cooldown = timedelta(minutes=self.params['cooldown_minutes'])
                    if timestamp - last_entry_time < cooldown:
                        filtered_signals.append(False)
                        continue

                # フィルター通過
                filtered_signals.append(True)
                daily_entry_count[date] += 1
                last_entry_time = timestamp
            else:
                filtered_signals.append(False)

        self.df['entry_signal'] = filtered_signals
        self.df = self.df.drop(columns=['date'])

        logger.info(f"リスク管理フィルター適用後: {sum(filtered_signals)}個のシグナル")
        return self

    # ========================================
    # エグジットシグナル生成
    # ========================================

    def generate_exit_signals(
        self,
        entry_price: float,
        stop_loss: float,
        take_profit: float
    ) -> pd.Series:
        """
        エグジットシグナルを生成（単一ポジション用）

        Args:
            entry_price: エントリー価格
            stop_loss: ストップロス価格
            take_profit: テイクプロフィット価格

        Returns:
            pd.Series: エグジットシグナル
                - 'none': エグジットなし
                - 'stop_loss': ストップロス
                - 'take_profit': テイクプロフィット
        """
        exit_signals = pd.Series('none', index=self.df.index)

        # ストップロス条件
        sl_condition = self.df['low'] <= stop_loss
        exit_signals[sl_condition] = 'stop_loss'

        # テイクプロフィット条件（SLより優先）
        tp_condition = self.df['high'] >= take_profit
        exit_signals[tp_condition] = 'take_profit'

        return exit_signals

    # ========================================
    # ユーティリティ
    # ========================================

    def get_signals(self) -> pd.DataFrame:
        """
        シグナル付きデータを取得

        Returns:
            pd.DataFrame: シグナル付きOHLCVデータ
        """
        return self.df.copy()

    def get_entry_points(self) -> pd.DataFrame:
        """
        エントリーポイントのみを取得

        Returns:
            pd.DataFrame: エントリーシグナルがある行のみ
        """
        return self.df[self.df['entry_signal']].copy()

    def print_signal_summary(self):
        """シグナルサマリーを出力"""
        total_bars = len(self.df)
        entry_signals = self.df['entry_signal'].sum()
        entry_pct = (entry_signals / total_bars) * 100 if total_bars > 0 else 0

        print("=" * 60)
        print("シグナル生成サマリー")
        print("=" * 60)
        print(f"総バー数:         {total_bars:,}")
        print(f"エントリーシグナル: {entry_signals:,} ({entry_pct:.2f}%)")
        print()
        print("パラメータ:")
        for key, value in self.params.items():
            print(f"  {key}: {value}")
        print("=" * 60)


# ========================================
# 便利関数
# ========================================

def quick_generate_signals(
    df: pd.DataFrame,
    strategy_params: Optional[Dict] = None
) -> pd.DataFrame:
    """
    簡易シグナル生成

    Args:
        df: インジケーター付きOHLCVデータ
        strategy_params: 戦略パラメータ

    Returns:
        pd.DataFrame: シグナル付きデータ
    """
    sg = SignalGenerator(df, strategy_params)
    sg = sg.generate_entry_signals()
    sg = sg.apply_risk_filters()
    return sg.get_signals()


if __name__ == '__main__':
    # テスト実行
    import logging
    from indicators import TechnicalIndicators

    logging.basicConfig(level=logging.INFO)

    # サンプルデータ作成
    dates = pd.date_range('2024-01-01', '2024-12-31', freq='H')  # 1時間足
    df_test = pd.DataFrame({
        'timestamp': dates,
        'open': np.random.uniform(1000, 1100, len(dates)),
        'high': np.random.uniform(1100, 1200, len(dates)),
        'low': np.random.uniform(900, 1000, len(dates)),
        'close': np.random.uniform(1000, 1100, len(dates)),
        'volume': np.random.randint(100000, 1000000, len(dates))
    })

    # インジケーター追加
    print("=== インジケーター追加 ===")
    ti = TechnicalIndicators(df_test)
    ti = ti.add_all_kabuto_indicators()
    df_with_indicators = ti.get_data()

    # シグナル生成
    print("\n=== シグナル生成 ===")
    sg = SignalGenerator(df_with_indicators)
    sg = sg.generate_entry_signals()
    sg = sg.apply_risk_filters()

    sg.print_signal_summary()

    # エントリーポイント表示
    entry_points = sg.get_entry_points()
    if len(entry_points) > 0:
        print("\n=== エントリーポイント（最初の5件）===")
        print(entry_points[['timestamp', 'close', 'stop_loss', 'take_profit', 'rsi', 'volume_ratio']].head())
    else:
        print("\n⚠️ エントリーシグナルが見つかりませんでした")
