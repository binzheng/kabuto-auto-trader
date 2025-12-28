"""
Kabuto Auto Trader - バックテスト結果分析ライブラリ
年利、月次分布、詳細ドローダウン分析等
"""

import pandas as pd
import numpy as np
from typing import Dict, List, Optional
from datetime import datetime
import logging

logger = logging.getLogger(__name__)


class BacktestAnalyzer:
    """バックテスト結果分析クラス"""

    def __init__(
        self,
        trades: pd.DataFrame,
        capital_curve: pd.DataFrame,
        initial_capital: float
    ):
        """
        Args:
            trades: 取引履歴
            capital_curve: 資金曲線
            initial_capital: 初期資金
        """
        self.trades = trades.copy()
        self.capital_curve = capital_curve.copy()
        self.initial_capital = initial_capital

        # タイムスタンプをdatetime型に変換
        if 'entry_timestamp' in self.trades.columns:
            self.trades['entry_timestamp'] = pd.to_datetime(self.trades['entry_timestamp'])
        if 'exit_timestamp' in self.trades.columns:
            self.trades['exit_timestamp'] = pd.to_datetime(self.trades['exit_timestamp'])
        if 'timestamp' in self.capital_curve.columns:
            self.capital_curve['timestamp'] = pd.to_datetime(self.capital_curve['timestamp'])

    # ========================================
    # 年利・月利計算
    # ========================================

    def calculate_annual_return(self) -> float:
        """
        年利を計算（複利ベース）

        Returns:
            float: 年利（%）
        """
        if len(self.capital_curve) == 0:
            return 0.0

        start_date = self.capital_curve['timestamp'].min()
        end_date = self.capital_curve['timestamp'].max()
        days = (end_date - start_date).days

        if days == 0:
            return 0.0

        final_capital = self.capital_curve['capital'].iloc[-1]
        total_return = (final_capital / self.initial_capital) - 1

        # 年率換算
        annual_return = ((1 + total_return) ** (365 / days) - 1) * 100

        return annual_return

    def calculate_monthly_returns(self) -> pd.DataFrame:
        """
        月次リターンを計算

        Returns:
            pd.DataFrame: 月次リターン
                - year: 年
                - month: 月
                - trades: 取引数
                - pnl: 月次損益
                - return_pct: 月次リターン（%）
        """
        if len(self.trades) == 0:
            return pd.DataFrame()

        self.trades['year'] = self.trades['exit_timestamp'].dt.year
        self.trades['month'] = self.trades['exit_timestamp'].dt.month

        monthly = self.trades.groupby(['year', 'month']).agg({
            'pnl': ['count', 'sum'],
            'exit_timestamp': 'first'  # 月の開始時刻
        }).reset_index()

        monthly.columns = ['year', 'month', 'trades', 'pnl', 'timestamp']

        # 月次リターン（%）
        monthly['return_pct'] = (monthly['pnl'] / self.initial_capital) * 100

        return monthly

    # ========================================
    # ドローダウン詳細分析
    # ========================================

    def calculate_drawdown_details(self) -> Dict:
        """
        ドローダウンの詳細分析

        Returns:
            Dict: ドローダウン詳細
                - max_drawdown: 最大ドローダウン（絶対額）
                - max_drawdown_pct: 最大ドローダウン（%）
                - max_drawdown_duration: 最大ドローダウン期間（日数）
                - recovery_time: リカバリー時間（日数）
                - current_drawdown: 現在のドローダウン
                - drawdown_history: ドローダウン履歴
        """
        if len(self.capital_curve) == 0:
            return {}

        capital = self.capital_curve['capital']
        timestamp = self.capital_curve['timestamp']

        # 累積最大値
        running_max = capital.cummax()

        # ドローダウン
        drawdown = running_max - capital
        drawdown_pct = (drawdown / running_max) * 100

        # 最大ドローダウン
        max_dd_idx = drawdown.idxmax()
        max_drawdown = drawdown[max_dd_idx]
        max_drawdown_pct = drawdown_pct[max_dd_idx]

        # 最大ドローダウン期間
        # ピークから最大DD到達までの期間
        peak_idx = running_max[:max_dd_idx].idxmax()
        max_dd_duration = (timestamp[max_dd_idx] - timestamp[peak_idx]).days

        # リカバリー時間
        # 最大DDから元の水準に戻るまでの期間
        recovery_idx = None
        peak_value = running_max[peak_idx]
        for i in range(max_dd_idx, len(capital)):
            if capital.iloc[i] >= peak_value:
                recovery_idx = i
                break

        if recovery_idx is not None:
            recovery_time = (timestamp.iloc[recovery_idx] - timestamp[max_dd_idx]).days
        else:
            recovery_time = None  # まだリカバリーしていない

        # 現在のドローダウン
        current_drawdown = drawdown.iloc[-1]
        current_drawdown_pct = drawdown_pct.iloc[-1]

        return {
            'max_drawdown': max_drawdown,
            'max_drawdown_pct': max_drawdown_pct,
            'max_drawdown_date': timestamp[max_dd_idx],
            'max_drawdown_duration': max_dd_duration,
            'recovery_time': recovery_time,
            'current_drawdown': current_drawdown,
            'current_drawdown_pct': current_drawdown_pct,
            'drawdown_series': drawdown,
            'drawdown_pct_series': drawdown_pct
        }

    # ========================================
    # 時間帯別分析
    # ========================================

    def analyze_by_hour(self) -> pd.DataFrame:
        """
        時間帯別パフォーマンス分析

        Returns:
            pd.DataFrame: 時間帯別統計
                - hour: 時間帯
                - trades: 取引数
                - win_rate: 勝率
                - avg_pnl: 平均損益
                - total_pnl: 総損益
        """
        if len(self.trades) == 0:
            return pd.DataFrame()

        self.trades['hour'] = self.trades['entry_timestamp'].dt.hour

        hourly = self.trades.groupby('hour').agg({
            'pnl': ['count', lambda x: (x > 0).sum(), 'mean', 'sum']
        }).reset_index()

        hourly.columns = ['hour', 'trades', 'win_trades', 'avg_pnl', 'total_pnl']
        hourly['win_rate'] = hourly['win_trades'] / hourly['trades']

        return hourly

    def analyze_by_day_of_week(self) -> pd.DataFrame:
        """
        曜日別パフォーマンス分析

        Returns:
            pd.DataFrame: 曜日別統計
                - day_of_week: 曜日（0=月曜日、6=日曜日）
                - trades: 取引数
                - win_rate: 勝率
                - avg_pnl: 平均損益
                - total_pnl: 総損益
        """
        if len(self.trades) == 0:
            return pd.DataFrame()

        self.trades['day_of_week'] = self.trades['entry_timestamp'].dt.dayofweek

        daily = self.trades.groupby('day_of_week').agg({
            'pnl': ['count', lambda x: (x > 0).sum(), 'mean', 'sum']
        }).reset_index()

        daily.columns = ['day_of_week', 'trades', 'win_trades', 'avg_pnl', 'total_pnl']
        daily['win_rate'] = daily['win_trades'] / daily['trades']

        # 曜日名を追加
        day_names = ['月', '火', '水', '木', '金', '土', '日']
        daily['day_name'] = daily['day_of_week'].apply(lambda x: day_names[x])

        return daily

    # ========================================
    # 連続損益分析
    # ========================================

    def analyze_streaks(self) -> Dict:
        """
        連勝・連敗の詳細分析

        Returns:
            Dict: 連勝・連敗統計
                - max_win_streak: 最大連勝
                - max_loss_streak: 最大連敗
                - avg_win_streak: 平均連勝
                - avg_loss_streak: 平均連敗
                - streak_history: 連勝・連敗履歴
        """
        if len(self.trades) == 0:
            return {}

        streaks = []
        current_streak = 0

        for pnl in self.trades['pnl']:
            if pnl > 0:
                if current_streak >= 0:
                    current_streak += 1
                else:
                    streaks.append(current_streak)
                    current_streak = 1
            else:
                if current_streak <= 0:
                    current_streak -= 1
                else:
                    streaks.append(current_streak)
                    current_streak = -1

        # 最後のstreakを追加
        if current_streak != 0:
            streaks.append(current_streak)

        streaks = np.array(streaks)
        win_streaks = streaks[streaks > 0]
        loss_streaks = streaks[streaks < 0]

        return {
            'max_win_streak': win_streaks.max() if len(win_streaks) > 0 else 0,
            'max_loss_streak': abs(loss_streaks.min()) if len(loss_streaks) > 0 else 0,
            'avg_win_streak': win_streaks.mean() if len(win_streaks) > 0 else 0,
            'avg_loss_streak': abs(loss_streaks.mean()) if len(loss_streaks) > 0 else 0,
            'streak_history': streaks
        }

    # ========================================
    # エグジット理由別分析
    # ========================================

    def analyze_by_exit_reason(self) -> pd.DataFrame:
        """
        エグジット理由別パフォーマンス分析

        Returns:
            pd.DataFrame: エグジット理由別統計
        """
        if len(self.trades) == 0 or 'exit_reason' not in self.trades.columns:
            return pd.DataFrame()

        exit_stats = self.trades.groupby('exit_reason').agg({
            'pnl': ['count', 'sum', 'mean'],
            'pnl_pct': 'mean'
        }).reset_index()

        exit_stats.columns = ['exit_reason', 'trades', 'total_pnl', 'avg_pnl', 'avg_pnl_pct']

        return exit_stats

    # ========================================
    # 包括的レポート生成
    # ========================================

    def generate_comprehensive_report(self) -> str:
        """
        包括的なバックテストレポートを生成

        Returns:
            str: レポート（テキスト形式）
        """
        report = []
        report.append("=" * 80)
        report.append("Kabuto Auto Trader - バックテスト詳細レポート")
        report.append("=" * 80)
        report.append("")

        # 期間
        if len(self.trades) > 0:
            start_date = self.trades['entry_timestamp'].min()
            end_date = self.trades['exit_timestamp'].max()
            days = (end_date - start_date).days
            report.append(f"テスト期間: {start_date.date()} - {end_date.date()} ({days}日)")
        report.append("")

        # 年利
        annual_return = self.calculate_annual_return()
        report.append(f"年利: {annual_return:.2f}%")
        report.append("")

        # 月次リターン
        monthly = self.calculate_monthly_returns()
        if len(monthly) > 0:
            report.append("【月次リターン】")
            for _, row in monthly.iterrows():
                report.append(
                    f"  {int(row['year'])}/{int(row['month']):02d}: "
                    f"{row['trades']:.0f}回取引, "
                    f"{row['pnl']:+,.0f}円 ({row['return_pct']:+.2f}%)"
                )
            report.append("")

        # ドローダウン詳細
        dd = self.calculate_drawdown_details()
        if dd:
            report.append("【ドローダウン詳細】")
            report.append(f"  最大ドローダウン: {dd['max_drawdown']:,.0f}円 ({dd['max_drawdown_pct']:.2f}%)")
            report.append(f"  最大DD発生日: {dd['max_drawdown_date'].date()}")
            report.append(f"  最大DD期間: {dd['max_drawdown_duration']}日")
            if dd['recovery_time'] is not None:
                report.append(f"  リカバリー時間: {dd['recovery_time']}日")
            else:
                report.append(f"  リカバリー時間: まだリカバリーしていません")
            report.append(f"  現在のドローダウン: {dd['current_drawdown']:,.0f}円 ({dd['current_drawdown_pct']:.2f}%)")
            report.append("")

        # 連勝・連敗
        streaks = self.analyze_streaks()
        if streaks:
            report.append("【連勝・連敗】")
            report.append(f"  最大連勝: {streaks['max_win_streak']:.0f}回")
            report.append(f"  最大連敗: {streaks['max_loss_streak']:.0f}回")
            report.append(f"  平均連勝: {streaks['avg_win_streak']:.1f}回")
            report.append(f"  平均連敗: {streaks['avg_loss_streak']:.1f}回")
            report.append("")

        # エグジット理由別
        exit_stats = self.analyze_by_exit_reason()
        if len(exit_stats) > 0:
            report.append("【エグジット理由別】")
            for _, row in exit_stats.iterrows():
                report.append(
                    f"  {row['exit_reason']}: "
                    f"{row['trades']:.0f}回, "
                    f"平均 {row['avg_pnl']:+,.0f}円 ({row['avg_pnl_pct']:+.2f}%)"
                )
            report.append("")

        # 曜日別
        day_stats = self.analyze_by_day_of_week()
        if len(day_stats) > 0:
            report.append("【曜日別パフォーマンス】")
            for _, row in day_stats.iterrows():
                report.append(
                    f"  {row['day_name']}: "
                    f"{row['trades']:.0f}回, "
                    f"勝率 {row['win_rate']:.1%}, "
                    f"平均 {row['avg_pnl']:+,.0f}円"
                )
            report.append("")

        report.append("=" * 80)

        return "\n".join(report)

    def print_comprehensive_report(self):
        """包括的レポートを出力"""
        print(self.generate_comprehensive_report())


if __name__ == '__main__':
    # テスト実行
    import logging
    logging.basicConfig(level=logging.INFO)

    # サンプルデータ
    dates = pd.date_range('2024-01-01', '2024-12-31', freq='D')
    trades_data = {
        'entry_timestamp': dates[:100],
        'exit_timestamp': dates[:100] + pd.Timedelta(hours=2),
        'entry_price': np.random.uniform(1000, 1100, 100),
        'exit_price': np.random.uniform(1000, 1100, 100),
        'shares': [100] * 100,
        'pnl': np.random.uniform(-5000, 10000, 100),
        'pnl_pct': np.random.uniform(-2, 5, 100),
        'exit_reason': np.random.choice(['stop_loss', 'take_profit'], 100),
        'commission': [500] * 100
    }

    capital_data = {
        'timestamp': dates,
        'capital': 1000000 + np.cumsum(np.random.uniform(-1000, 2000, len(dates))),
        'position': [False] * len(dates)
    }

    trades_df = pd.DataFrame(trades_data)
    capital_df = pd.DataFrame(capital_data)

    # 分析
    analyzer = BacktestAnalyzer(trades_df, capital_df, 1000000)
    analyzer.print_comprehensive_report()
