# Kabuto Auto Trader - データ分析環境

**実トレード分析 & 完全バックテスト環境**

---

## 📊 概要

このディレクトリには、Kabuto Auto Traderの**2つの主要な分析機能**が含まれています。

### 🔍 機能1: 実トレード結果分析
実際の取引履歴を分析してパフォーマンスを評価します。

- ✅ ExecutionLog/OrderHistory/SignalLogからデータ読み込み
- ✅ パフォーマンス指標計算（勝率、PF、シャープレシオ、最大DD等）
- ✅ グラフ可視化（累積損益、ドローダウン、損益分布等）
- ✅ 銘柄別分析
- ✅ 日次・月次レポート生成
- ✅ パラメータ最適化推奨（Pine Script生成）

### 🚀 機能2: 完全バックテスト（新規実装）
OHLCVデータから独立した完全なバックテストを実行します。

- ✅ **Step A**: OHLCVデータ取得（Yahoo Finance）
- ✅ **Step B**: データクリーニング & 前処理
- ✅ **Step C**: テクニカルインジケーター計算（EMA, RSI, ATR等）
- ✅ **Step D**: エントリー/エグジットシグナル生成
- ✅ **Step E**: K線シミュレーション（手数料・スリッページ考慮）
- ✅ **Step F**: 詳細レポート生成（年利、月次分布、DD詳細等）

---

## 📁 ディレクトリ構成

```
analysis/
├── README.md                          # このファイル
├── requirements.txt                   # 依存ライブラリ
│
├── lib/                               # 分析ライブラリ
│   ├── __init__.py
│   │
│   │ # 実トレード分析
│   ├── data_loader.py                 # データローダー（Excel/DB対応）
│   ├── analytics.py                   # パフォーマンス分析
│   ├── optimizer.py                   # パラメータ最適化
│   │
│   │ # バックテスト機能
│   ├── market_data.py                 # OHLCVデータ取得（Yahoo Finance）
│   ├── data_cleaner.py                # データクリーニング
│   ├── indicators.py                  # テクニカルインジケーター
│   ├── signal_generator.py            # シグナル生成エンジン
│   ├── backtest_engine.py             # バックテストエンジン
│   └── backtest_analytics.py          # バックテスト結果分析
│
├── notebooks/                         # Jupyter Notebook
│   │ # 実トレード分析
│   ├── 01_daily_performance.ipynb     # 日次パフォーマンス分析
│   ├── 02_monthly_report.ipynb        # 月次レポート
│   ├── 03_trade_analysis.ipynb        # 個別トレード分析
│   ├── 04_backtest_simulator.ipynb    # バックテストシミュレーター
│   ├── 05_parameter_optimization.ipynb # パラメータ最適化
│   │
│   │ # 完全バックテスト
│   └── 06_full_backtest.ipynb         # 完全バックテスト（Step A〜F）
│
├── scripts/                           # Python スクリプト
│   ├── generate_daily_report.py       # 日次レポート自動生成
│   └── export_to_csv.py               # データCSVエクスポート
│
├── data/                              # データ保存用
│   └── (Excel/CSV ファイルを配置)
│
└── reports/                           # 生成レポート保存先
    └── (PDF/HTMLレポート)
```

---

## 🚀 セットアップ

### 1. 依存ライブラリのインストール

```bash
cd analysis
pip install -r requirements.txt
```

**主なライブラリ**:
- pandas - データ処理
- matplotlib, seaborn, plotly - 可視化
- jupyter - Jupyter Notebook
- openpyxl - Excel読み込み
- sqlalchemy - DB連携（オプション）
- **yfinance - 市場データ取得（バックテスト用）**

### 2. Jupyter Notebook 起動

```bash
cd notebooks
jupyter notebook
```

ブラウザが開いたら、`01_daily_performance.ipynb` を開いてください。

---

## 📊 使い方

このセクションでは、**2つの主要機能**の使い方を説明します。

---

## 🔍 使い方A: 実トレード結果分析

### Jupyter Notebook で分析

#### ステップ1: データ読み込み

**オプションA: 実データ（Excelファイル）**:
```python
from data_loader import KabutoDataLoader

EXCEL_PATH = '../../Kabuto Auto Trader.xlsm'
loader = KabutoDataLoader(excel_path=EXCEL_PATH)
trades = loader.load_all_trades(source='excel')
```

**オプションB: サンプルデータ（テスト用）**:
```python
from data_loader import KabutoDataLoader

trades = KabutoDataLoader.generate_sample_data(n_trades=200)
```

#### ステップ2: 分析

```python
from analytics import PerformanceAnalyzer

# 分析器初期化
analyzer = PerformanceAnalyzer(trades)

# レポート出力
analyzer.print_report()

# 個別指標取得
win_rate = analyzer.get_basic_stats()['win_rate']
profit_factor = analyzer.get_profit_factor()
max_dd = analyzer.get_drawdown_stats()['max_drawdown']
sharpe_ratio = analyzer.get_sharpe_ratio()
```

#### ステップ3: グラフ描画

```python
import matplotlib.pyplot as plt

# 累積損益カーブ
trades['cumulative_pnl'] = trades['pnl'].cumsum()
plt.plot(trades['timestamp'], trades['cumulative_pnl'])
plt.title('累積損益カーブ')
plt.show()
```

---

### Python スクリプトで分析

```python
# scripts/analyze.py
import sys
sys.path.append('../lib')

from data_loader import quick_load_trades
from analytics import PerformanceAnalyzer

# データ読み込み
trades = quick_load_trades(excel_path='../../Kabuto Auto Trader.xlsm', days=30)

# 分析
analyzer = PerformanceAnalyzer(trades)
analyzer.print_report()
```

実行:
```bash
cd scripts
python analyze.py
```

---

## 🚀 使い方B: 完全バックテスト

### クイックスタート

```python
import sys
sys.path.append('../lib')

from market_data import MarketDataFetcher
from data_cleaner import DataCleaner
from indicators import TechnicalIndicators
from signal_generator import SignalGenerator
from backtest_engine import BacktestEngine
from backtest_analytics import BacktestAnalyzer

# Step A: OHLCVデータ取得
fetcher = MarketDataFetcher()
df = fetcher.fetch_ohlcv('7203.T', '2024-01-01', '2024-12-31', '1d')

# Step B: データクリーニング
cleaner = DataCleaner(df)
df_clean = cleaner.remove_anomalies().get_cleaned_data()

# Step C: インジケーター追加
ti = TechnicalIndicators(df_clean)
df_indicators = ti.add_all_kabuto_indicators().get_data()

# Step D: シグナル生成
sg = SignalGenerator(df_indicators)
df_signals = sg.generate_entry_signals().apply_risk_filters().get_signals()

# Step E: バックテスト実行
engine = BacktestEngine(initial_capital=1000000)
results = engine.run(df_signals)

# Step F: 詳細レポート
analyzer = BacktestAnalyzer(
    results['trades'],
    results['capital_curve'],
    engine.initial_capital
)
analyzer.print_comprehensive_report()
```

### 日本株の銘柄コード例

| 銘柄コード | 企業名 |
|-----------|--------|
| 7203.T | トヨタ自動車 |
| 9984.T | ソフトバンクグループ |
| 6758.T | ソニーグループ |
| 7974.T | 任天堂 |
| 6861.T | キーエンス |

### 時間軸の指定

| interval | 説明 | 制限 |
|----------|------|-----|
| `'1m'` | 1分足 | 最大7日 |
| `'5m'` | 5分足 | 最大60日 |
| `'15m'` | 15分足 | - |
| `'1h'` | 1時間足 | - |
| `'1d'` | 日足 | - |

### 戦略パラメータのカスタマイズ

```python
# カスタムパラメータ
strategy_params = {
    'rsi_lower': 55,              # RSI下限
    'rsi_upper': 70,              # RSI上限
    'volume_multiplier': 1.5,     # 出来高倍率
    'atr_sl_multiplier': 1.5,     # ストップロス倍率
    'atr_tp_multiplier': 5.0,     # テイクプロフィット倍率
    'min_rr_ratio': 2.0,          # 最低リスクリワード比
    'max_daily_entries': 2,       # 1日最大エントリー数
    'cooldown_minutes': 60        # クールダウン時間（分）
}

sg = SignalGenerator(df_indicators, strategy_params)
```

### バックテスト設定のカスタマイズ

```python
engine = BacktestEngine(
    initial_capital=1000000,      # 初期資金（100万円）
    commission_rate=0.001,        # 手数料（0.1%）
    slippage_rate=0.0005,         # スリッページ（0.05%）
    position_size_pct=0.1,        # ポジションサイズ（資金の10%）
    max_daily_loss=50000,         # 日次最大損失（5万円）
    max_consecutive_losses=5      # 最大連続損失（Kill Switch）
)
```

---

## 📈 分析指標一覧

### 基本統計

| 指標 | 説明 | 計算方法 |
|------|------|---------|
| **総取引数** | すべての取引回数 | len(trades) |
| **勝率** | 勝ちトレード / 総トレード | win_trades / total_trades |
| **総損益** | すべての取引損益合計 | sum(pnl) |
| **平均損益** | 1取引あたりの平均損益 | sum(pnl) / total_trades |

### リスク指標

| 指標 | 説明 | 目標値 |
|------|------|-------|
| **プロフィットファクター** | 総利益 / 総損失 | > 1.5 |
| **最大ドローダウン** | 最高値からの最大下落幅 | < 30% |
| **勝敗比率** | 平均利益 / 平均損失 | > 1.5 |

### リスク調整後リターン

| 指標 | 説明 | 目標値 |
|------|------|-------|
| **シャープレシオ** | (リターン - リスクフリーレート) / 標準偏差 | > 1.0 |
| **ソルティノレシオ** | リターン / 下方偏差 | > 1.5 |
| **カルマーレシオ** | 年率リターン / 最大DD | > 1.0 |

---

## 📓 Jupyter Notebook 一覧

### 1. `01_daily_performance.ipynb`

**日次パフォーマンス分析**

- 日次損益グラフ
- 累積損益カーブ
- ドローダウン分析
- 損益分布
- 基本統計レポート

**対象ユーザー**: 初めて分析する方、日々のパフォーマンス確認

### 2. `02_monthly_report.ipynb`

**月次レポート**

- 月次損益集計
- 月別勝率比較
- 取引回数推移
- 戦略パフォーマンス評価

**対象ユーザー**: 月次レビューを行う方

### 3. `03_trade_analysis.ipynb`

**個別トレード分析**

- トレード詳細表示
- 銘柄別パフォーマンス
- 時間帯別分析
- エントリー/エグジット分析

**対象ユーザー**: 戦略改善を検討する方

### 4. `04_backtest_simulator.ipynb`

**バックテストシミュレーター**

- 過去データでの戦略シミュレーション
- パラメータ最適化
- Walk-Forward Analysis
- モンテカルロシミュレーション

**対象ユーザー**: 新戦略をテストする方

### 5. `05_parameter_optimization.ipynb`

**パラメータ最適化**

- 実トレード結果から問題診断
- 最適パラメータ推奨
- Pine Scriptコード生成
- TradingViewへの適用手順

**対象ユーザー**: kabuto_strategy_v1.pineのパラメータを調整したい方

### 6. `06_full_backtest.ipynb` ⭐ **新規**

**完全バックテスト（Step A〜F）**

- OHLCVデータ取得（Yahoo Finance）
- データクリーニング & インジケーター計算
- シグナル生成 & バックテスト実行
- 詳細レポート & グラフ可視化
- パラメータグリッドサーチ

**対象ユーザー**: OHLCVデータから独立したバックテストを実行したい方

**主な機能**:
- ✅ Look-ahead bias回避（未来の情報を使わない）
- ✅ 手数料・スリッページ考慮
- ✅ リスク管理（Kill Switch）
- ✅ 年利・月次分布・ドローダウン詳細分析
- ✅ 複数パラメータセットの比較

---

## 🔧 高度な使い方

### 完全バックテストの重要な特徴

#### 1. Look-ahead Bias回避
```python
# ❌ 間違い: 終値を見て終値で約定（未来の情報を使用）
if df['close'] > df['ema']:
    entry_price = df['close']  # チート！

# ✅ 正しい: シグナルが出たら次のバーの始値で約定
if df['entry_signal']:
    entry_price = next_bar['open']  # 未来の情報を使わない
```

#### 2. 手数料 & スリッページ
```python
# 実際の約定価格
entry_price = next_bar['open'] * (1 + slippage_rate)  # +0.05%
exit_price = target_price * (1 - slippage_rate)       # -0.05%

# 手数料
commission = shares * price * commission_rate  # 0.1%
```

#### 3. リスク管理（Kill Switch）
```python
# 日次最大損失
if daily_pnl < -max_daily_loss:
    return False  # 今日はもうエントリーしない

# 最大連続損失
if consecutive_losses >= max_consecutive_losses:
    return False  # Kill Switch発動
```

#### 4. パラメータグリッドサーチ
```python
param_grid = [
    {'rsi_lower': 45, 'atr_tp_multiplier': 3.0},
    {'rsi_lower': 50, 'atr_tp_multiplier': 4.0},
    {'rsi_lower': 55, 'atr_tp_multiplier': 5.0},
]

for params in param_grid:
    # 各パラメータセットでバックテスト
    results = run_backtest(params)
    # 結果比較
```

### カスタム分析関数の追加

```python
# lib/custom_analytics.py
def calculate_custom_metric(trades):
    """カスタム指標を計算"""
    # 独自の分析ロジック
    return result
```

### データベースから読み込み

```python
from data_loader import KabutoDataLoader

DB_URL = 'sqlite:///../../relay_server/kabuto.db'
loader = KabutoDataLoader(db_url=DB_URL)
trades = loader.load_execution_log_from_db(
    start_date='2025-01-01',
    end_date='2025-01-31'
)
```

### レポート自動生成

```bash
# 毎日自動実行（cron設定例）
0 18 * * * cd /path/to/analysis/scripts && python generate_daily_report.py
```

---

## 📊 サンプル出力

### コンソール出力例

```
============================================================
Kabuto Auto Trader - パフォーマンスレポート
============================================================

【基本統計】
  総取引数:       200回
  勝ちトレード:   115回
  負けトレード:   85回
  勝率:           57.5%
  総損益:         98,500円
  純損益:         58,900円
  平均損益:       492円

【プロフィットファクター】
  PF:             1.82

【勝ち/負け統計】
  平均利益:       1,250円
  平均損失:       -850円
  最大利益:       8,200円
  最大損失:       -6,500円
  勝敗比率:       1.47

【ドローダウン】
  最大DD:         -18,500円 (15.2%)
  平均DD:         -3,200円

【リスク調整後リターン】
  シャープレシオ: 1.35
  ソルティノレシオ: 1.82
  カルマーレシオ: 0.95

【連勝・連敗】
  最大連勝:       8回
  最大連敗:       5回
  現在:           3連勝中

============================================================
```

---

## 💡 ベストプラクティス

### 1. 定期的な分析

```python
# 毎週末に実行
trades = quick_load_trades(excel_path=EXCEL_PATH, days=7)
analyzer = PerformanceAnalyzer(trades)
analyzer.print_report()
```

### 2. 銘柄別パフォーマンス確認

```python
ticker_stats = analyzer.get_ticker_stats()
print(ticker_stats)

# 不振銘柄をフィルタリング
poor_performers = ticker_stats[ticker_stats['win_rate'] < 0.4]
```

### 3. 戦略評価

```python
# 勝率50%以上、PF > 1.5、最大DD < 30%が目標
stats = analyzer.get_basic_stats()
pf = analyzer.get_profit_factor()
dd = analyzer.get_drawdown_stats()

if stats['win_rate'] >= 0.5 and pf > 1.5 and dd['max_drawdown_pct'] < 30:
    print("✅ 戦略は良好")
else:
    print("⚠️ 戦略の見直しが必要")
```

---

## 🐛 トラブルシューティング

### Q1. Excelファイルが読み込めない

**対処法**:
```python
# パスを絶対パスで指定
import os
EXCEL_PATH = os.path.abspath('../../Kabuto Auto Trader.xlsm')
```

### Q2. グラフが文字化けする

**対処法** (macOS):
```python
# Jupyter Notebookの先頭に追加
import matplotlib.pyplot as plt
plt.rcParams['font.family'] = 'Hiragino Sans'
```

**対処法** (Windows):
```python
plt.rcParams['font.family'] = 'MS Gothic'
```

### Q3. メモリ不足エラー

**対処法**:
```python
# 期間を絞る
trades = loader.load_recent_trades(days=30)  # 最近30日のみ
```

---

## 📚 参考資料

### 実トレード分析
- **基本**: `01_daily_performance.ipynb` を参照
- **API仕様**: `lib/analytics.py` のdocstringを参照
- **パラメータ最適化**: `05_parameter_optimization.ipynb` を参照
- **TradingViewバックテスト**: `../doc/20_tradingview_backtest_forwardtest_guide.md`
- **日次運用**: `../doc/22_daily_operations.md`

### 完全バックテスト
- **基本**: `06_full_backtest.ipynb` を参照
- **ライブラリAPI**:
  - `lib/market_data.py` - OHLCVデータ取得
  - `lib/indicators.py` - テクニカルインジケーター
  - `lib/backtest_engine.py` - バックテストエンジン
  - `lib/backtest_analytics.py` - 詳細分析

---

## 🤝 コントリビューション

カスタム分析関数や新しいNotebookを追加した場合:

1. `lib/` に関数を追加
2. `notebooks/` にNotebookを追加
3. このREADMEを更新

---

## 📄 ライセンス

Kabuto Auto Trader プロジェクトに準拠

---

**🎉 実トレード分析 & 完全バックテストで、戦略を継続的に改善しましょう！**

---

## 🆕 更新履歴

### 2025-12-27 - 完全バックテスト機能追加
- ✅ OHLCVデータ取得（Yahoo Finance）
- ✅ データクリーニング & テクニカルインジケーター
- ✅ シグナル生成エンジン（Kabuto戦略）
- ✅ バックテストエンジン（K線シミュレーション）
- ✅ 詳細分析レポート（年利、月次分布、DD詳細）
- ✅ Jupyter Notebook: `06_full_backtest.ipynb`

### 2025-12-27 - パラメータ最適化機能追加
- ✅ 実トレード結果の問題診断
- ✅ 推奨パラメータ計算
- ✅ Pine Scriptコード生成
- ✅ Jupyter Notebook: `05_parameter_optimization.ipynb`

---

最終更新: 2025-12-27
