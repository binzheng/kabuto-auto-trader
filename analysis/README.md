# Kabuto Auto Trader - データ分析環境

**既存の取引データを使って、パフォーマンス分析・バックテストを行う環境**

---

## 📊 概要

このディレクトリには、Kabuto Auto Traderの取引データを分析するためのツールが含まれています。

**できること**:
- ✅ ExecutionLog/OrderHistory/SignalLogからデータ読み込み
- ✅ パフォーマンス指標計算（勝率、PF、シャープレシオ、最大DD等）
- ✅ グラフ可視化（累積損益、ドローダウン、損益分布等）
- ✅ 銘柄別分析
- ✅ 日次・月次レポート生成

---

## 📁 ディレクトリ構成

```
analysis/
├── README.md                      # このファイル
├── requirements.txt               # 依存ライブラリ
│
├── lib/                           # 分析ライブラリ
│   ├── __init__.py
│   ├── data_loader.py             # データローダー（Excel/DB対応）
│   └── analytics.py               # 分析関数（統計指標計算）
│
├── notebooks/                     # Jupyter Notebook
│   ├── 01_daily_performance.ipynb # 日次パフォーマンス分析
│   ├── 02_monthly_report.ipynb    # 月次レポート
│   ├── 03_trade_analysis.ipynb    # 個別トレード分析
│   └── 04_backtest_simulator.ipynb # バックテストシミュレーター
│
├── scripts/                       # Python スクリプト
│   ├── generate_daily_report.py   # 日次レポート自動生成
│   └── export_to_csv.py           # データCSVエクスポート
│
├── data/                          # データ保存用
│   └── (Excel/CSV ファイルを配置)
│
└── reports/                       # 生成レポート保存先
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

### 2. Jupyter Notebook 起動

```bash
cd notebooks
jupyter notebook
```

ブラウザが開いたら、`01_daily_performance.ipynb` を開いてください。

---

## 📊 使い方

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

---

## 🔧 高度な使い方

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

- **基本**: `01_daily_performance.ipynb` を参照
- **API仕様**: `lib/analytics.py` のdocstringを参照
- **TradingViewバックテスト**: `../doc/20_tradingview_backtest_forwardtest_guide.md`
- **日次運用**: `../doc/22_daily_operations.md`

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

**🎉 データ分析を活用して、戦略を継続的に改善しましょう！**

最終更新: 2025-12-27
