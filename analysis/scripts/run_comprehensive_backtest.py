"""
包括的な日本株バックテスト
利用可能なすべての銘柄でバックテストを実行し、結果をCSVに保存
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


def quick_backtest(ticker_code, loader, start_date=None, end_date=None, verbose=False):
    """
    高速バックテスト実行（エラーハンドリング込み）
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

        sg = SignalGenerator(df_indicators)
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
            print(f"  ⚠️ 銘柄 {ticker_code}: {str(e)}")
        return None


if __name__ == "__main__":
    print(f"\n{'#'*80}")
    print("# 包括的バックテスト - 日本株データ")
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

    # 全銘柄でバックテスト
    results_list = []
    success_count = 0
    fail_count = 0

    for i, ticker in enumerate(all_tickers, 1):
        print(f"[{i}/{len(all_tickers)}] {ticker}...", end=' ')

        result = quick_backtest(ticker, loader, start_date, end_date, verbose=False)

        if result:
            results_list.append(result)
            success_count += 1
            print(f"✓ ({result['num_trades']}取引, {result['total_return']:.2%})")
        else:
            fail_count += 1
            print("スキップ")

    # 結果をDataFrameに変換
    if results_list:
        results_df = pd.DataFrame(results_list)

        # ソート（総リターン降順）
        results_df = results_df.sort_values('total_return', ascending=False)

        # 結果を保存
        output_dir = os.path.join(os.path.dirname(__file__), '..', 'reports')
        os.makedirs(output_dir, exist_ok=True)

        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        output_file = os.path.join(output_dir, f'backtest_results_{timestamp}.csv')

        results_df.to_csv(output_file, index=False, encoding='utf-8-sig')

        # サマリー表示
        print(f"\n{'='*80}")
        print("バックテスト結果サマリー")
        print(f"{'='*80}")
        print(f"成功: {success_count}銘柄")
        print(f"スキップ: {fail_count}銘柄")
        print(f"\n結果ファイル: {output_file}\n")

        # トップ10表示
        print("【トップ10銘柄（総リターン順）】")
        print(f"{'順位':>4} {'銘柄':>8} {'取引数':>8} {'勝率':>8} {'総リターン':>12} {'PF':>8} {'最大DD':>10}")
        print(f"{'-'*80}")

        for idx, row in results_df.head(10).iterrows():
            print(
                f"{results_df.index.get_loc(idx)+1:>4} "
                f"{row['ticker']:>8} "
                f"{int(row['num_trades']):>8} "
                f"{row['win_rate']:>7.1%} "
                f"{row['total_return']:>11.2%} "
                f"{row['profit_factor']:>8.2f} "
                f"{row['max_drawdown']:>9.2%}"
            )

        print(f"\n{'='*80}\n")

    else:
        print("\n⚠️ バックテスト可能な銘柄がありませんでした。\n")
