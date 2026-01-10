"""
戦略比較バックテスト
Trend State vs Golden Cross (Pine Script準拠)
"""
import sys
import os
import pandas as pd
from datetime import datetime

# プロジェクトルートとlibディレクトリをパスに追加
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lib'))

from load_jp_data import JapanStockDataLoader
from data_cleaner import DataCleaner
from indicators import TechnicalIndicators
from signal_generator import SignalGenerator
from backtest_engine import BacktestEngine


def quick_backtest_with_strategy(ticker_code, loader, strategy_type, start_date=None, end_date=None, verbose=False):
    """
    指定された戦略でバックテスト実行

    Args:
        ticker_code: 銘柄コード
        loader: データローダー
        strategy_type: 'trend_state' or 'golden_cross'
        start_date: 開始日
        end_date: 終了日
        verbose: 詳細ログ

    Returns:
        dict: バックテスト結果
    """
    try:
        # Step A: データ読み込み
        df = loader.load_stock(ticker_code)

        # 期間指定
        if start_date:
            df = df[df.index >= start_date]
        if end_date:
            df = df[df.index <= end_date]

        if len(df) < 100:  # データが少なすぎる場合はスキップ
            return None

        # Step B-D: クリーニング、インジケーター、シグナル
        cleaner = DataCleaner(df)
        df_clean = cleaner.remove_anomalies().get_cleaned_data()

        ti = TechnicalIndicators(df_clean)
        df_indicators = ti.add_all_kabuto_indicators().get_data()

        # 戦略タイプを指定してシグナル生成
        sg = SignalGenerator(df_indicators, strategy_type=strategy_type)
        df_signals = sg.generate_entry_signals().apply_risk_filters().get_signals()

        entry_signals = df_signals['entry_signal'].sum()
        if entry_signals == 0:
            return None

        # Step E: バックテスト
        engine = BacktestEngine(
            initial_capital=1000000,
            commission_rate=0.001,
            slippage_rate=0.0005,
            position_size_pct=0.1,
            max_daily_loss=50000,
            max_consecutive_losses=5
        )
        results = engine.run(df_signals)

        if len(results['trades']) == 0:
            return None

        # 結果サマリー
        trades_df = pd.DataFrame(results['trades'])
        final_capital = results['capital_curve']['capital'].iloc[-1]
        total_return = (final_capital - 1000000) / 1000000
        total_pnl = trades_df['pnl'].sum()
        win_trades = len(trades_df[trades_df['pnl'] > 0])
        lose_trades = len(trades_df[trades_df['pnl'] <= 0])
        win_rate = win_trades / len(trades_df) if len(trades_df) > 0 else 0

        # 平均利益/損失
        avg_win = trades_df[trades_df['pnl'] > 0]['pnl'].mean() if win_trades > 0 else 0
        avg_loss = trades_df[trades_df['pnl'] <= 0]['pnl'].mean() if lose_trades > 0 else 0

        # プロフィットファクター
        total_win = trades_df[trades_df['pnl'] > 0]['pnl'].sum() if win_trades > 0 else 0
        total_loss = abs(trades_df[trades_df['pnl'] <= 0]['pnl'].sum()) if lose_trades > 0 else 0
        profit_factor = total_win / total_loss if total_loss > 0 else 0

        # 最大ドローダウン
        capital_curve = results['capital_curve']['capital']
        peak = capital_curve.expanding().max()
        drawdown = (capital_curve - peak) / peak
        max_dd = drawdown.min()

        # テスト期間
        test_days = (df_signals.index[-1] - df_signals.index[0]).days

        return {
            'ticker': ticker_code,
            'strategy': strategy_type,
            'start_date': df_signals.index[0].strftime('%Y-%m-%d'),
            'end_date': df_signals.index[-1].strftime('%Y-%m-%d'),
            'test_days': test_days,
            'num_trades': len(trades_df),
            'entry_signals': entry_signals,
            'win_trades': win_trades,
            'lose_trades': lose_trades,
            'win_rate': win_rate,
            'total_return': total_return,
            'total_pnl': total_pnl,
            'avg_win': avg_win,
            'avg_loss': avg_loss,
            'profit_factor': profit_factor,
            'max_drawdown': max_dd,
            'final_capital': final_capital
        }

    except Exception as e:
        if verbose:
            print(f"  ⚠️ 銘柄 {ticker_code} ({strategy_type}): {str(e)}")
        return None


if __name__ == "__main__":
    print(f"\n{'#'*80}")
    print("# 戦略比較バックテスト")
    print("# Trend State (EMA状態) vs Golden Cross (Pine Script準拠)")
    print(f"{'#'*80}\n")

    # データローダー準備
    base_path = os.path.join(os.path.dirname(__file__), '..', 'data', 'daily', 'jp', 'tse stocks')
    loader = JapanStockDataLoader(base_path=base_path)

    # 利用可能な銘柄リストを取得（最大100銘柄）
    print("利用可能な銘柄を検索中...")
    all_tickers = loader.list_available_tickers(limit=100)
    print(f"見つかった銘柄: {len(all_tickers)}個\n")

    # バックテスト期間
    start_date = "2020-01-01"
    end_date = "2024-12-31"

    print(f"テスト期間: {start_date} 〜 {end_date}")
    print(f"バックテスト開始...\n")

    # 両戦略でバックテスト
    results_trend_state = []
    results_golden_cross = []

    for i, ticker in enumerate(all_tickers, 1):
        print(f"[{i}/{len(all_tickers)}] {ticker}...")

        # Trend State戦略
        result_ts = quick_backtest_with_strategy(
            ticker, loader, 'trend_state', start_date, end_date, verbose=False
        )

        # Golden Cross戦略
        result_gc = quick_backtest_with_strategy(
            ticker, loader, 'golden_cross', start_date, end_date, verbose=False
        )

        # 結果表示
        ts_status = f"✓ {result_ts['num_trades']}取引" if result_ts else "スキップ"
        gc_status = f"✓ {result_gc['num_trades']}取引" if result_gc else "スキップ"

        print(f"  Trend State: {ts_status:20} | Golden Cross: {gc_status}")

        if result_ts:
            results_trend_state.append(result_ts)
        if result_gc:
            results_golden_cross.append(result_gc)

    # 結果をDataFrameに変換
    df_ts = pd.DataFrame(results_trend_state) if results_trend_state else pd.DataFrame()
    df_gc = pd.DataFrame(results_golden_cross) if results_golden_cross else pd.DataFrame()

    # 結果を保存
    output_dir = os.path.join(os.path.dirname(__file__), '..', 'reports')
    os.makedirs(output_dir, exist_ok=True)

    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')

    if not df_ts.empty:
        output_file_ts = os.path.join(output_dir, f'strategy_comparison_trend_state_{timestamp}.csv')
        df_ts.to_csv(output_file_ts, index=False, encoding='utf-8-sig')

    if not df_gc.empty:
        output_file_gc = os.path.join(output_dir, f'strategy_comparison_golden_cross_{timestamp}.csv')
        df_gc.to_csv(output_file_gc, index=False, encoding='utf-8-sig')

    # サマリー表示
    print(f"\n{'='*80}")
    print("戦略比較結果")
    print(f"{'='*80}\n")

    if not df_ts.empty and not df_gc.empty:
        print(f"【Trend State戦略】")
        print(f"  成功銘柄数: {len(df_ts)}")
        print(f"  平均リターン: {df_ts['total_return'].mean():.2%}")
        print(f"  平均勝率: {df_ts['win_rate'].mean():.1%}")
        print(f"  平均PF: {df_ts['profit_factor'].mean():.2f}")
        print(f"  平均取引数: {df_ts['num_trades'].mean():.1f}")
        print()

        print(f"【Golden Cross戦略】(Pine Script準拠)")
        print(f"  成功銘柄数: {len(df_gc)}")
        print(f"  平均リターン: {df_gc['total_return'].mean():.2%}")
        print(f"  平均勝率: {df_gc['win_rate'].mean():.1%}")
        print(f"  平均PF: {df_gc['profit_factor'].mean():.2f}")
        print(f"  平均取引数: {df_gc['num_trades'].mean():.1f}")
        print()

        # 比較
        print(f"【比較】")
        return_diff = (df_ts['total_return'].mean() - df_gc['total_return'].mean()) * 100
        trades_diff = df_ts['num_trades'].mean() - df_gc['num_trades'].mean()

        winner = "Trend State" if return_diff > 0 else "Golden Cross"
        print(f"  リターン差: {abs(return_diff):.2f}% ({winner}が優位)")
        print(f"  取引数差: {abs(trades_diff):.1f}回 ({'Trend State' if trades_diff > 0 else 'Golden Cross'}が多い)")
        print()

        # トップ10比較
        print(f"【Trend State - トップ10】")
        df_ts_sorted = df_ts.sort_values('total_return', ascending=False)
        print(f"{'順位':>4} {'銘柄':>8} {'リターン':>10} {'勝率':>8} {'PF':>8} {'取引数':>8}")
        print(f"{'-'*60}")
        for idx, row in df_ts_sorted.head(10).iterrows():
            rank = df_ts_sorted.index.get_loc(idx) + 1
            print(
                f"{rank:>4} {row['ticker']:>8} {row['total_return']:>9.2%} "
                f"{row['win_rate']:>7.1%} {row['profit_factor']:>8.2f} {int(row['num_trades']):>8}"
            )

        print()
        print(f"【Golden Cross - トップ10】")
        df_gc_sorted = df_gc.sort_values('total_return', ascending=False)
        print(f"{'順位':>4} {'銘柄':>8} {'リターン':>10} {'勝率':>8} {'PF':>8} {'取引数':>8}")
        print(f"{'-'*60}")
        for idx, row in df_gc_sorted.head(10).iterrows():
            rank = df_gc_sorted.index.get_loc(idx) + 1
            print(
                f"{rank:>4} {row['ticker']:>8} {row['total_return']:>9.2%} "
                f"{row['win_rate']:>7.1%} {row['profit_factor']:>8.2f} {int(row['num_trades']):>8}"
            )

        print(f"\n{'='*80}")
        print(f"結果ファイル:")
        if not df_ts.empty:
            print(f"  Trend State: {output_file_ts}")
        if not df_gc.empty:
            print(f"  Golden Cross: {output_file_gc}")
        print(f"{'='*80}\n")

    else:
        print("\n⚠️ バックテスト可能な銘柄がありませんでした。\n")
