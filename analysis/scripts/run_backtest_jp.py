"""
日本株データでバックテスト実行
"""
import sys
import os

# プロジェクトルートとlibディレクトリをパスに追加
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lib'))

from load_jp_data import JapanStockDataLoader
from data_cleaner import DataCleaner
from indicators import TechnicalIndicators
from signal_generator import SignalGenerator
from backtest_engine import BacktestEngine
from backtest_analytics import BacktestAnalyzer


def run_backtest_for_ticker(ticker_code, start_date=None, end_date=None):
    """
    指定された銘柄でバックテストを実行

    Args:
        ticker_code: 銘柄コード（例: "1301"）
        start_date: 開始日（例: "2020-01-01"）
        end_date: 終了日（例: "2024-12-31"）
    """
    print(f"\n{'='*80}")
    print(f"バックテスト開始: 銘柄 {ticker_code}")
    print(f"{'='*80}\n")

    # Step A: データ読み込み
    print("Step A: データ読み込み中...")
    # scriptsディレクトリから実行するため、パスを調整
    base_path = os.path.join(os.path.dirname(__file__), '..', 'data', 'daily', 'jp', 'tse stocks')
    loader = JapanStockDataLoader(base_path=base_path)
    df = loader.load_stock(ticker_code)

    # 期間指定があれば絞り込み
    if start_date:
        df = df[df.index >= start_date]
    if end_date:
        df = df[df.index <= end_date]

    print(f"  期間: {df.index[0].strftime('%Y-%m-%d')} 〜 {df.index[-1].strftime('%Y-%m-%d')}")
    print(f"  データ数: {len(df)}日")

    # Step B: データクリーニング
    print("\nStep B: データクリーニング...")
    cleaner = DataCleaner(df)
    df_clean = cleaner.remove_anomalies().get_cleaned_data()
    print(f"  クリーニング後: {len(df_clean)}日 (削除: {len(df) - len(df_clean)}日)")

    # Step C: テクニカルインジケーター計算
    print("\nStep C: テクニカルインジケーター計算...")
    ti = TechnicalIndicators(df_clean)
    df_indicators = ti.add_all_kabuto_indicators().get_data()
    print(f"  インジケーター追加完了")

    # Step D: シグナル生成
    print("\nStep D: エントリー/エグジットシグナル生成...")
    sg = SignalGenerator(df_indicators)
    df_signals = sg.generate_entry_signals().apply_risk_filters().get_signals()

    entry_signals = df_signals['entry_signal'].sum()
    print(f"  エントリーシグナル: {entry_signals}回")

    if entry_signals == 0:
        print("\n  ⚠️ エントリーシグナルが0件です。パラメータを調整してください。")
        return None

    # Step E: バックテスト実行
    print("\nStep E: バックテスト実行中...")
    engine = BacktestEngine(
        initial_capital=1000000,      # 100万円
        commission_rate=0.001,        # 0.1%
        slippage_rate=0.0005,         # 0.05%
        position_size_pct=0.1,        # 資金の10%
        max_daily_loss=50000,         # 日次最大損失5万円
        max_consecutive_losses=5      # 最大連続損失5回
    )
    results = engine.run(df_signals)

    print(f"  約定トレード数: {len(results['trades'])}回")

    if len(results['trades']) == 0:
        print("\n  ⚠️ 約定トレードが0件です。")
        return None

    # Step F: 詳細分析
    print("\nStep F: 詳細レポート生成...\n")
    analyzer = BacktestAnalyzer(
        results['trades'],
        results['capital_curve'],
        engine.initial_capital
    )

    # レポート表示
    analyzer.print_comprehensive_report()

    return {
        'ticker': ticker_code,
        'results': results,
        'analyzer': analyzer,
        'signals_df': df_signals
    }


if __name__ == "__main__":
    # バックテスト実行
    # 銘柄リスト（代表的な日本株）
    tickers_to_test = [
        "1301",  # 極洋（水産）
        "1332",  # 日本水産
        "1491",  # 中外鉱業
    ]

    # 期間指定（最近5年間）
    start_date = "2020-01-01"
    end_date = "2024-12-31"

    print(f"\n{'#'*80}")
    print(f"# 日本株バックテスト")
    print(f"# 期間: {start_date} 〜 {end_date}")
    print(f"# 銘柄数: {len(tickers_to_test)}")
    print(f"{'#'*80}")

    results_summary = []

    for ticker in tickers_to_test:
        try:
            result = run_backtest_for_ticker(ticker, start_date, end_date)
            if result:
                # 総リターンを計算
                final_capital = result['results']['capital_curve']['capital'].iloc[-1]
                total_return = (final_capital - 1000000) / 1000000

                results_summary.append({
                    'ticker': ticker,
                    'total_return': total_return,
                    'num_trades': len(result['results']['trades']),
                    'final_capital': final_capital
                })
        except Exception as e:
            print(f"\n❌ 銘柄 {ticker} でエラー: {str(e)}\n")
            continue

    # サマリー表示
    if results_summary:
        print(f"\n\n{'='*80}")
        print("バックテスト サマリー")
        print(f"{'='*80}")
        print(f"{'銘柄':>10} {'トレード数':>12} {'総リターン':>15}")
        print(f"{'-'*80}")
        for r in results_summary:
            print(f"{r['ticker']:>10} {r['num_trades']:>12} {r['total_return']:>14.2%}")
        print(f"{'='*80}\n")
