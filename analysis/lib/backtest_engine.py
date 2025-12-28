"""
Kabuto Auto Trader - バックテストエンジン
K線ごとにシミュレーション、手数料・スリッページを考慮
"""

import pandas as pd
import numpy as np
from typing import Dict, List, Optional
from datetime import datetime
import logging

logger = logging.getLogger(__name__)


class BacktestEngine:
    """バックテストエンジンクラス"""

    def __init__(
        self,
        initial_capital: float = 1000000,  # 初期資金（100万円）
        commission_rate: float = 0.001,  # 手数料（0.1%）
        slippage_rate: float = 0.0005,  # スリッページ（0.05%）
        position_size_pct: float = 0.1,  # ポジションサイズ（資金の10%）
        max_daily_loss: float = 50000,  # 日次最大損失（5万円）
        max_consecutive_losses: int = 5  # 最大連続損失数
    ):
        """
        Args:
            initial_capital: 初期資金
            commission_rate: 手数料率（往復）
            slippage_rate: スリッページ率
            position_size_pct: ポジションサイズ（資金の何%）
            max_daily_loss: 日次最大損失額
            max_consecutive_losses: 最大連続損失数（Kill Switch）
        """
        self.initial_capital = initial_capital
        self.commission_rate = commission_rate
        self.slippage_rate = slippage_rate
        self.position_size_pct = position_size_pct
        self.max_daily_loss = max_daily_loss
        self.max_consecutive_losses = max_consecutive_losses

        # 状態変数
        self.capital = initial_capital
        self.position = None  # 現在のポジション
        self.trades = []  # 取引履歴
        self.daily_pnl = {}  # 日次損益
        self.consecutive_losses = 0  # 連続損失カウント

    # ========================================
    # メインバックテストループ
    # ========================================

    def run(
        self,
        df: pd.DataFrame,
        verbose: bool = False
    ) -> Dict:
        """
        バックテストを実行

        Args:
            df: シグナル付きOHLCVデータ（インジケーター、エントリーシグナル含む）
            verbose: 詳細ログ出力

        Returns:
            Dict: バックテスト結果
                - trades: 取引履歴
                - capital_curve: 資金曲線
                - summary: サマリー統計
        """
        logger.info("バックテスト開始")
        logger.info(f"初期資金: {self.initial_capital:,.0f}円")
        logger.info(f"期間: {df['timestamp'].min()} - {df['timestamp'].max()}")
        logger.info(f"データ行数: {len(df):,}")

        capital_curve = []
        current_date = None

        # K線ごとにシミュレート
        for i in range(len(df)):
            row = df.iloc[i]
            timestamp = row['timestamp']
            date = timestamp.date()

            # 日付が変わったら日次損益をリセット
            if date != current_date:
                current_date = date
                if date not in self.daily_pnl:
                    self.daily_pnl[date] = 0

            # ポジションがある場合、エグジットチェック
            if self.position is not None:
                self._check_exit(row, i, verbose)

            # ポジションがない場合、エントリーチェック
            if self.position is None and row.get('entry_signal', False):
                # リスク管理チェック
                if self._risk_check(date, verbose):
                    # 次のバーがあればエントリー
                    if i + 1 < len(df):
                        next_row = df.iloc[i + 1]
                        self._enter_position(row, next_row, verbose)

            # 資金曲線を記録
            capital_curve.append({
                'timestamp': timestamp,
                'capital': self.capital,
                'position': self.position is not None
            })

        # 最終ポジションをクローズ（未決済がある場合）
        if self.position is not None:
            last_row = df.iloc[-1]
            self._force_close_position(last_row, verbose)

        logger.info(f"バックテスト完了: {len(self.trades)}件の取引")

        # 結果を返す
        return {
            'trades': pd.DataFrame(self.trades),
            'capital_curve': pd.DataFrame(capital_curve),
            'summary': self._generate_summary()
        }

    # ========================================
    # エントリー処理
    # ========================================

    def _enter_position(
        self,
        signal_row: pd.Series,
        entry_row: pd.Series,
        verbose: bool
    ):
        """
        ポジションをエントリー（次のバーの始値で約定）

        Args:
            signal_row: シグナルが出た行
            entry_row: エントリー行（次のバー）
            verbose: 詳細ログ
        """
        # エントリー価格（次のバーの始値 + スリッページ）
        entry_price = entry_row['open'] * (1 + self.slippage_rate)

        # ストップロス・テイクプロフィット
        stop_loss = signal_row['stop_loss']
        take_profit = signal_row['take_profit']

        # ポジションサイズ（株数）
        position_value = self.capital * self.position_size_pct
        shares = int(position_value / entry_price)

        if shares == 0:
            logger.warning(f"資金不足でエントリーできません: 資金 {self.capital:,.0f}円")
            return

        # 手数料（エントリー時）
        commission = shares * entry_price * self.commission_rate

        # ポジション作成
        self.position = {
            'entry_timestamp': entry_row['timestamp'],
            'entry_price': entry_price,
            'shares': shares,
            'stop_loss': stop_loss,
            'take_profit': take_profit,
            'commission_paid': commission
        }

        # 資金から差し引き
        self.capital -= (shares * entry_price + commission)

        if verbose:
            logger.info(
                f"[ENTRY] {entry_row['timestamp']} | "
                f"価格: {entry_price:,.0f}円 | 株数: {shares} | "
                f"SL: {stop_loss:,.0f} | TP: {take_profit:,.0f}"
            )

    # ========================================
    # エグジット処理
    # ========================================

    def _check_exit(
        self,
        row: pd.Series,
        index: int,
        verbose: bool
    ):
        """
        エグジット条件をチェック

        Args:
            row: 現在の行
            index: 行インデックス
            verbose: 詳細ログ
        """
        if self.position is None:
            return

        exit_price = None
        exit_reason = None

        # ストップロス判定（安値がSLに到達）
        if row['low'] <= self.position['stop_loss']:
            exit_price = self.position['stop_loss'] * (1 - self.slippage_rate)
            exit_reason = 'stop_loss'

        # テイクプロフィット判定（高値がTPに到達）
        elif row['high'] >= self.position['take_profit']:
            exit_price = self.position['take_profit'] * (1 - self.slippage_rate)
            exit_reason = 'take_profit'

        # エグジット実行
        if exit_price is not None:
            self._exit_position(row, exit_price, exit_reason, verbose)

    def _exit_position(
        self,
        row: pd.Series,
        exit_price: float,
        exit_reason: str,
        verbose: bool
    ):
        """
        ポジションをエグジット

        Args:
            row: 現在の行
            exit_price: エグジット価格
            exit_reason: エグジット理由
            verbose: 詳細ログ
        """
        if self.position is None:
            return

        # 手数料（エグジット時）
        commission = self.position['shares'] * exit_price * self.commission_rate

        # 資金に戻す
        proceeds = self.position['shares'] * exit_price - commission
        self.capital += proceeds

        # 損益計算
        entry_cost = self.position['shares'] * self.position['entry_price']
        total_commission = self.position['commission_paid'] + commission
        pnl = proceeds - entry_cost - self.position['commission_paid']

        # 取引記録
        trade = {
            'entry_timestamp': self.position['entry_timestamp'],
            'exit_timestamp': row['timestamp'],
            'entry_price': self.position['entry_price'],
            'exit_price': exit_price,
            'shares': self.position['shares'],
            'pnl': pnl,
            'pnl_pct': (pnl / entry_cost) * 100,
            'exit_reason': exit_reason,
            'commission': total_commission,
            'holding_bars': None  # 後で計算
        }

        self.trades.append(trade)

        # 日次損益に加算
        date = row['timestamp'].date()
        if date not in self.daily_pnl:
            self.daily_pnl[date] = 0
        self.daily_pnl[date] += pnl

        # 連続損失カウント
        if pnl < 0:
            self.consecutive_losses += 1
        else:
            self.consecutive_losses = 0

        if verbose:
            logger.info(
                f"[EXIT] {row['timestamp']} | "
                f"理由: {exit_reason} | 価格: {exit_price:,.0f}円 | "
                f"損益: {pnl:+,.0f}円 ({trade['pnl_pct']:+.2f}%)"
            )

        # ポジションクローズ
        self.position = None

    def _force_close_position(
        self,
        row: pd.Series,
        verbose: bool
    ):
        """
        強制的にポジションをクローズ（バックテスト終了時）

        Args:
            row: 最終行
            verbose: 詳細ログ
        """
        exit_price = row['close'] * (1 - self.slippage_rate)
        self._exit_position(row, exit_price, 'backtest_end', verbose)
        logger.warning("バックテスト終了時に未決済ポジションを強制クローズしました")

    # ========================================
    # リスク管理
    # ========================================

    def _risk_check(
        self,
        date,
        verbose: bool
    ) -> bool:
        """
        リスク管理チェック

        Args:
            date: 現在の日付
            verbose: 詳細ログ

        Returns:
            bool: True=エントリー可能、False=エントリー不可
        """
        # 1. 日次最大損失チェック
        daily_loss = self.daily_pnl.get(date, 0)
        if daily_loss < -self.max_daily_loss:
            if verbose:
                logger.warning(
                    f"日次最大損失到達: {daily_loss:,.0f}円 "
                    f"(制限: {-self.max_daily_loss:,.0f}円)"
                )
            return False

        # 2. 最大連続損失チェック（Kill Switch）
        if self.consecutive_losses >= self.max_consecutive_losses:
            if verbose:
                logger.warning(
                    f"連続損失上限到達: {self.consecutive_losses}回 "
                    f"(制限: {self.max_consecutive_losses}回)"
                )
            return False

        # 3. 資金不足チェック
        if self.capital < self.initial_capital * 0.1:
            if verbose:
                logger.error(
                    f"資金が初期資金の10%を下回りました: {self.capital:,.0f}円"
                )
            return False

        return True

    # ========================================
    # サマリー生成
    # ========================================

    def _generate_summary(self) -> Dict:
        """
        バックテストサマリーを生成

        Returns:
            Dict: サマリー統計
        """
        if not self.trades:
            return {
                'total_trades': 0,
                'final_capital': self.capital,
                'total_return': 0,
                'total_return_pct': 0
            }

        trades_df = pd.DataFrame(self.trades)

        # 基本統計
        total_trades = len(trades_df)
        win_trades = len(trades_df[trades_df['pnl'] > 0])
        loss_trades = len(trades_df[trades_df['pnl'] < 0])
        win_rate = win_trades / total_trades if total_trades > 0 else 0

        # 損益
        total_pnl = trades_df['pnl'].sum()
        avg_pnl = trades_df['pnl'].mean()
        total_return_pct = (self.capital - self.initial_capital) / self.initial_capital * 100

        # 勝ち/負け
        gross_profit = trades_df[trades_df['pnl'] > 0]['pnl'].sum()
        gross_loss = abs(trades_df[trades_df['pnl'] < 0]['pnl'].sum())
        profit_factor = gross_profit / gross_loss if gross_loss > 0 else float('inf')

        avg_win = trades_df[trades_df['pnl'] > 0]['pnl'].mean() if win_trades > 0 else 0
        avg_loss = trades_df[trades_df['pnl'] < 0]['pnl'].mean() if loss_trades > 0 else 0
        win_loss_ratio = abs(avg_win / avg_loss) if avg_loss != 0 else 0

        # ドローダウン
        capital_curve = pd.Series([t['pnl'] for t in self.trades]).cumsum() + self.initial_capital
        running_max = capital_curve.cummax()
        drawdown = running_max - capital_curve
        max_drawdown = drawdown.max()
        max_drawdown_pct = (max_drawdown / running_max[drawdown.idxmax()]) * 100 if len(drawdown) > 0 else 0

        # 連勝・連敗
        win_streak = 0
        loss_streak = 0
        current_streak = 0
        max_win_streak = 0
        max_loss_streak = 0

        for pnl in trades_df['pnl']:
            if pnl > 0:
                if current_streak >= 0:
                    current_streak += 1
                else:
                    current_streak = 1
                max_win_streak = max(max_win_streak, current_streak)
            else:
                if current_streak <= 0:
                    current_streak -= 1
                else:
                    current_streak = -1
                max_loss_streak = max(max_loss_streak, abs(current_streak))

        return {
            'total_trades': total_trades,
            'win_trades': win_trades,
            'loss_trades': loss_trades,
            'win_rate': win_rate,
            'final_capital': self.capital,
            'total_pnl': total_pnl,
            'avg_pnl': avg_pnl,
            'total_return_pct': total_return_pct,
            'gross_profit': gross_profit,
            'gross_loss': gross_loss,
            'profit_factor': profit_factor,
            'avg_win': avg_win,
            'avg_loss': avg_loss,
            'win_loss_ratio': win_loss_ratio,
            'max_drawdown': max_drawdown,
            'max_drawdown_pct': max_drawdown_pct,
            'max_win_streak': max_win_streak,
            'max_loss_streak': max_loss_streak
        }

    def print_summary(self, summary: Dict):
        """サマリーを出力"""
        print("=" * 70)
        print("バックテスト結果サマリー")
        print("=" * 70)
        print(f"総取引数:         {summary['total_trades']:,}回")
        print(f"勝ちトレード:     {summary['win_trades']:,}回")
        print(f"負けトレード:     {summary['loss_trades']:,}回")
        print(f"勝率:             {summary['win_rate']:.1%}")
        print()
        print(f"初期資金:         {self.initial_capital:,.0f}円")
        print(f"最終資金:         {summary['final_capital']:,.0f}円")
        print(f"総損益:           {summary['total_pnl']:+,.0f}円")
        print(f"総リターン:       {summary['total_return_pct']:+.2f}%")
        print()
        print(f"総利益:           {summary['gross_profit']:,.0f}円")
        print(f"総損失:           {summary['gross_loss']:,.0f}円")
        print(f"プロフィットファクター: {summary['profit_factor']:.2f}")
        print()
        print(f"平均利益:         {summary['avg_win']:+,.0f}円")
        print(f"平均損失:         {summary['avg_loss']:+,.0f}円")
        print(f"勝敗比率:         {summary['win_loss_ratio']:.2f}")
        print()
        print(f"最大ドローダウン: {summary['max_drawdown']:,.0f}円 ({summary['max_drawdown_pct']:.1f}%)")
        print(f"最大連勝:         {summary['max_win_streak']}回")
        print(f"最大連敗:         {summary['max_loss_streak']}回")
        print("=" * 70)


if __name__ == '__main__':
    # テスト実行
    import logging
    from market_data import MarketDataFetcher
    from data_cleaner import DataCleaner
    from indicators import TechnicalIndicators
    from signal_generator import SignalGenerator

    logging.basicConfig(level=logging.INFO)

    print("=== バックテストエンジンテスト ===\n")

    # 1. データ取得
    print("1. データ取得中...")
    fetcher = MarketDataFetcher()
    df = fetcher.fetch_ohlcv('7203.T', '2024-01-01', '2024-12-31', '1d')

    # 2. データクリーニング
    print("2. データクリーニング...")
    cleaner = DataCleaner(df)
    df = cleaner.remove_anomalies().get_cleaned_data()

    # 3. インジケーター追加
    print("3. インジケーター追加...")
    ti = TechnicalIndicators(df)
    df = ti.add_all_kabuto_indicators().get_data()

    # 4. シグナル生成
    print("4. シグナル生成...")
    sg = SignalGenerator(df)
    df = sg.generate_entry_signals().apply_risk_filters().get_signals()

    # 5. バックテスト実行
    print("5. バックテスト実行...\n")
    engine = BacktestEngine(
        initial_capital=1000000,
        commission_rate=0.001,
        slippage_rate=0.0005
    )

    results = engine.run(df, verbose=True)

    # 6. 結果表示
    print("\n")
    engine.print_summary(results['summary'])

    print("\n=== 取引履歴（最初の5件）===")
    print(results['trades'].head())
