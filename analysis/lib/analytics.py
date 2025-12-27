"""
Kabuto Auto Trader - 分析関数ライブラリ
パフォーマンス指標計算、統計分析、リスク分析
"""

import pandas as pd
import numpy as np
from typing import Dict, Optional, Tuple
import logging

logger = logging.getLogger(__name__)


class PerformanceAnalyzer:
    """パフォーマンス分析クラス"""

    def __init__(self, trades: pd.DataFrame):
        """
        Args:
            trades: 取引データ (ExecutionLogのsellのみ)
                必須カラム: timestamp, pnl, commission
        """
        self.trades = trades.copy()
        self.trades = self.trades.sort_values('timestamp').reset_index(drop=True)

    # ========================================
    # 基本統計
    # ========================================

    def get_basic_stats(self) -> Dict:
        """
        基本統計指標を計算

        Returns:
            Dict: 基本統計
                - total_trades: 総取引数
                - win_trades: 勝ちトレード数
                - lose_trades: 負けトレード数
                - total_pnl: 総損益
                - total_commission: 総手数料
                - net_pnl: 純損益
                - average_pnl: 平均損益
                - win_rate: 勝率
        """
        total_trades = len(self.trades)
        win_trades = (self.trades['pnl'] > 0).sum()
        lose_trades = (self.trades['pnl'] < 0).sum()
        total_pnl = self.trades['pnl'].sum()
        total_commission = self.trades['commission'].sum() if 'commission' in self.trades.columns else 0
        net_pnl = total_pnl - total_commission
        average_pnl = total_pnl / total_trades if total_trades > 0 else 0
        win_rate = win_trades / total_trades if total_trades > 0 else 0

        return {
            'total_trades': total_trades,
            'win_trades': win_trades,
            'lose_trades': lose_trades,
            'total_pnl': total_pnl,
            'total_commission': total_commission,
            'net_pnl': net_pnl,
            'average_pnl': average_pnl,
            'win_rate': win_rate
        }

    def get_profit_factor(self) -> float:
        """
        プロフィットファクターを計算

        Returns:
            float: プロフィットファクター（総利益 / 総損失）
        """
        gross_profit = self.trades[self.trades['pnl'] > 0]['pnl'].sum()
        gross_loss = abs(self.trades[self.trades['pnl'] < 0]['pnl'].sum())

        if gross_loss == 0:
            return float('inf') if gross_profit > 0 else 0

        return gross_profit / gross_loss

    def get_win_loss_stats(self) -> Dict:
        """
        勝ち/負けトレードの統計

        Returns:
            Dict: 勝ち/負け統計
                - average_win: 平均利益
                - average_loss: 平均損失
                - max_win: 最大利益
                - max_loss: 最大損失
                - win_loss_ratio: 勝ち/負け比率
        """
        wins = self.trades[self.trades['pnl'] > 0]['pnl']
        losses = self.trades[self.trades['pnl'] < 0]['pnl']

        average_win = wins.mean() if len(wins) > 0 else 0
        average_loss = losses.mean() if len(losses) > 0 else 0
        max_win = wins.max() if len(wins) > 0 else 0
        max_loss = losses.min() if len(losses) > 0 else 0
        win_loss_ratio = abs(average_win / average_loss) if average_loss != 0 else 0

        return {
            'average_win': average_win,
            'average_loss': average_loss,
            'max_win': max_win,
            'max_loss': max_loss,
            'win_loss_ratio': win_loss_ratio
        }

    # ========================================
    # ドローダウン分析
    # ========================================

    def get_drawdown_stats(self) -> Dict:
        """
        ドローダウン統計を計算

        Returns:
            Dict: ドローダウン統計
                - max_drawdown: 最大ドローダウン（円）
                - max_drawdown_pct: 最大ドローダウン（%）
                - average_drawdown: 平均ドローダウン
                - drawdown_duration: 最大DD継続期間（日数）
        """
        # 累積損益
        cumulative_pnl = self.trades['pnl'].cumsum()

        # 累積最大値
        running_max = cumulative_pnl.cummax()

        # ドローダウン
        drawdown = running_max - cumulative_pnl

        max_drawdown = drawdown.max()
        max_dd_idx = drawdown.idxmax()
        max_dd_pct = (max_drawdown / running_max[max_dd_idx]) * 100 if running_max[max_dd_idx] != 0 else 0
        average_drawdown = drawdown[drawdown > 0].mean() if (drawdown > 0).any() else 0

        # DD継続期間（簡易計算）
        dd_periods = drawdown[drawdown > 0]
        drawdown_duration = len(dd_periods) if len(dd_periods) > 0 else 0

        return {
            'max_drawdown': max_drawdown,
            'max_drawdown_pct': max_dd_pct,
            'average_drawdown': average_drawdown,
            'drawdown_duration': drawdown_duration
        }

    # ========================================
    # リスク調整後リターン
    # ========================================

    def get_sharpe_ratio(self, risk_free_rate: float = 0.0) -> float:
        """
        シャープレシオを計算

        Args:
            risk_free_rate: リスクフリーレート（年率）

        Returns:
            float: シャープレシオ
        """
        returns = self.trades['pnl']

        if len(returns) == 0 or returns.std() == 0:
            return 0

        # 日次リターンと仮定
        average_return = returns.mean()
        std_return = returns.std()

        # 年率換算（252営業日）
        sharpe = (average_return - risk_free_rate) / std_return * np.sqrt(252)

        return sharpe

    def get_sortino_ratio(self, risk_free_rate: float = 0.0) -> float:
        """
        ソルティノレシオを計算（下方リスクのみ考慮）

        Args:
            risk_free_rate: リスクフリーレート

        Returns:
            float: ソルティノレシオ
        """
        returns = self.trades['pnl']

        if len(returns) == 0:
            return 0

        average_return = returns.mean()

        # 下方偏差（マイナスリターンの標準偏差）
        downside_returns = returns[returns < 0]
        if len(downside_returns) == 0 or downside_returns.std() == 0:
            return 0

        downside_std = downside_returns.std()

        # 年率換算
        sortino = (average_return - risk_free_rate) / downside_std * np.sqrt(252)

        return sortino

    def get_calmar_ratio(self) -> float:
        """
        カルマーレシオを計算（年率リターン / 最大DD）

        Returns:
            float: カルマーレシオ
        """
        dd_stats = self.get_drawdown_stats()
        max_dd = dd_stats['max_drawdown']

        if max_dd == 0:
            return 0

        # 年率リターン推定
        total_pnl = self.trades['pnl'].sum()
        days = (self.trades['timestamp'].max() - self.trades['timestamp'].min()).days
        if days == 0:
            return 0

        annual_return = total_pnl * (365 / days)

        calmar = annual_return / max_dd

        return calmar

    # ========================================
    # 連勝・連敗分析
    # ========================================

    def get_streak_stats(self) -> Dict:
        """
        連勝・連敗統計

        Returns:
            Dict: 連勝・連敗統計
                - max_win_streak: 最大連勝数
                - max_loss_streak: 最大連敗数
                - current_streak: 現在の連勝/連敗（正=連勝、負=連敗）
        """
        wins = (self.trades['pnl'] > 0).astype(int)
        losses = (self.trades['pnl'] < 0).astype(int)

        # 連勝
        win_streaks = []
        current_win_streak = 0
        for w in wins:
            if w == 1:
                current_win_streak += 1
            else:
                if current_win_streak > 0:
                    win_streaks.append(current_win_streak)
                current_win_streak = 0
        if current_win_streak > 0:
            win_streaks.append(current_win_streak)

        # 連敗
        loss_streaks = []
        current_loss_streak = 0
        for l in losses:
            if l == 1:
                current_loss_streak += 1
            else:
                if current_loss_streak > 0:
                    loss_streaks.append(current_loss_streak)
                current_loss_streak = 0
        if current_loss_streak > 0:
            loss_streaks.append(current_loss_streak)

        # 現在のストリーク
        if len(self.trades) > 0:
            last_pnl = self.trades.iloc[-1]['pnl']
            current_streak = 0
            for i in range(len(self.trades) - 1, -1, -1):
                if (last_pnl > 0 and self.trades.iloc[i]['pnl'] > 0) or \
                   (last_pnl < 0 and self.trades.iloc[i]['pnl'] < 0):
                    current_streak += 1
                else:
                    break
            current_streak = current_streak if last_pnl > 0 else -current_streak
        else:
            current_streak = 0

        return {
            'max_win_streak': max(win_streaks) if win_streaks else 0,
            'max_loss_streak': max(loss_streaks) if loss_streaks else 0,
            'current_streak': current_streak
        }

    # ========================================
    # 銘柄別分析
    # ========================================

    def get_ticker_stats(self) -> pd.DataFrame:
        """
        銘柄別統計

        Returns:
            DataFrame: 銘柄別統計
                - ticker: 銘柄コード
                - trades: 取引回数
                - total_pnl: 総損益
                - win_rate: 勝率
                - average_pnl: 平均損益
        """
        if 'ticker' not in self.trades.columns:
            logger.warning("'ticker' column not found in trades")
            return pd.DataFrame()

        ticker_stats = self.trades.groupby('ticker').agg({
            'pnl': ['count', 'sum', 'mean', lambda x: (x > 0).sum() / len(x)]
        }).reset_index()

        ticker_stats.columns = ['ticker', 'trades', 'total_pnl', 'average_pnl', 'win_rate']
        ticker_stats = ticker_stats.sort_values('total_pnl', ascending=False)

        return ticker_stats

    # ========================================
    # 包括的レポート
    # ========================================

    def get_full_report(self) -> Dict:
        """
        包括的パフォーマンスレポート

        Returns:
            Dict: すべての統計指標
        """
        report = {}

        # 基本統計
        report['basic_stats'] = self.get_basic_stats()

        # プロフィットファクター
        report['profit_factor'] = self.get_profit_factor()

        # 勝ち/負け統計
        report['win_loss_stats'] = self.get_win_loss_stats()

        # ドローダウン
        report['drawdown_stats'] = self.get_drawdown_stats()

        # リスク調整後リターン
        report['sharpe_ratio'] = self.get_sharpe_ratio()
        report['sortino_ratio'] = self.get_sortino_ratio()
        report['calmar_ratio'] = self.get_calmar_ratio()

        # 連勝・連敗
        report['streak_stats'] = self.get_streak_stats()

        return report

    def print_report(self):
        """レポートを整形して出力"""
        report = self.get_full_report()

        print("=" * 60)
        print("Kabuto Auto Trader - パフォーマンスレポート")
        print("=" * 60)

        # 基本統計
        print("\n【基本統計】")
        bs = report['basic_stats']
        print(f"  総取引数:       {bs['total_trades']:,}回")
        print(f"  勝ちトレード:   {bs['win_trades']:,}回")
        print(f"  負けトレード:   {bs['lose_trades']:,}回")
        print(f"  勝率:           {bs['win_rate']:.1%}")
        print(f"  総損益:         {bs['total_pnl']:,.0f}円")
        print(f"  純損益:         {bs['net_pnl']:,.0f}円")
        print(f"  平均損益:       {bs['average_pnl']:,.0f}円")

        # プロフィットファクター
        print(f"\n【プロフィットファクター】")
        print(f"  PF:             {report['profit_factor']:.2f}")

        # 勝ち/負け統計
        print(f"\n【勝ち/負け統計】")
        wl = report['win_loss_stats']
        print(f"  平均利益:       {wl['average_win']:,.0f}円")
        print(f"  平均損失:       {wl['average_loss']:,.0f}円")
        print(f"  最大利益:       {wl['max_win']:,.0f}円")
        print(f"  最大損失:       {wl['max_loss']:,.0f}円")
        print(f"  勝敗比率:       {wl['win_loss_ratio']:.2f}")

        # ドローダウン
        print(f"\n【ドローダウン】")
        dd = report['drawdown_stats']
        print(f"  最大DD:         {dd['max_drawdown']:,.0f}円 ({dd['max_drawdown_pct']:.1f}%)")
        print(f"  平均DD:         {dd['average_drawdown']:,.0f}円")

        # リスク調整後リターン
        print(f"\n【リスク調整後リターン】")
        print(f"  シャープレシオ: {report['sharpe_ratio']:.2f}")
        print(f"  ソルティノレシオ: {report['sortino_ratio']:.2f}")
        print(f"  カルマーレシオ: {report['calmar_ratio']:.2f}")

        # 連勝・連敗
        print(f"\n【連勝・連敗】")
        streak = report['streak_stats']
        print(f"  最大連勝:       {streak['max_win_streak']}回")
        print(f"  最大連敗:       {streak['max_loss_streak']}回")
        current = streak['current_streak']
        if current > 0:
            print(f"  現在:           {current}連勝中")
        elif current < 0:
            print(f"  現在:           {abs(current)}連敗中")
        else:
            print(f"  現在:           ストリークなし")

        print("=" * 60)


if __name__ == '__main__':
    # テスト実行
    from data_loader import KabutoDataLoader

    # サンプルデータ生成
    sample_trades = KabutoDataLoader.generate_sample_data(100)

    # 分析
    analyzer = PerformanceAnalyzer(sample_trades)
    analyzer.print_report()
