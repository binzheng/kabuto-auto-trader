"""
Kabuto Auto Trader - パラメータ最適化ライブラリ
実トレード結果を分析してPine Scriptパラメータを推奨
"""

import pandas as pd
from typing import Dict, List, Tuple
from datetime import datetime
import logging
from .analytics import PerformanceAnalyzer

logger = logging.getLogger(__name__)


class ParameterOptimizer:
    """パラメータ最適化クラス"""

    def __init__(self, trades: pd.DataFrame):
        """
        Args:
            trades: 取引データ (ExecutionLogのsellのみ)
        """
        self.trades = trades
        self.analyzer = PerformanceAnalyzer(trades)
        self.report = self.analyzer.get_full_report()

    # ========================================
    # 問題診断
    # ========================================

    def diagnose_problems(self) -> Dict[str, Dict]:
        """
        パフォーマンス問題を診断

        Returns:
            Dict: 問題リスト
                - category: 問題カテゴリ
                - severity: 深刻度 (high/medium/low)
                - current_value: 現在値
                - target_value: 目標値
                - description: 説明
        """
        problems = {}

        # 基本統計
        basic = self.report['basic_stats']
        pf = self.report['profit_factor']
        dd = self.report['drawdown_stats']
        win_loss = self.report['win_loss_stats']
        sharpe = self.report['sharpe_ratio']

        # 1. 勝率チェック
        if basic['win_rate'] < 0.45:
            problems['win_rate_low'] = {
                'category': 'エントリー条件',
                'severity': 'high',
                'current_value': f"{basic['win_rate']:.1%}",
                'target_value': '> 50%',
                'description': '勝率が低すぎます。エントリー条件を厳しくする必要があります。'
            }
        elif basic['win_rate'] < 0.50:
            problems['win_rate_marginal'] = {
                'category': 'エントリー条件',
                'severity': 'medium',
                'current_value': f"{basic['win_rate']:.1%}",
                'target_value': '> 50%',
                'description': '勝率が目標を下回っています。'
            }

        # 2. プロフィットファクター
        if pf < 1.3:
            problems['pf_low'] = {
                'category': '損益バランス',
                'severity': 'high',
                'current_value': f"{pf:.2f}",
                'target_value': '> 1.5',
                'description': 'プロフィットファクターが低いです。TP/SL比率を改善してください。'
            }
        elif pf < 1.5:
            problems['pf_marginal'] = {
                'category': '損益バランス',
                'severity': 'medium',
                'current_value': f"{pf:.2f}",
                'target_value': '> 1.5',
                'description': 'プロフィットファクターが目標を下回っています。'
            }

        # 3. 最大ドローダウン
        if dd['max_drawdown'] > 100000:
            problems['dd_too_large'] = {
                'category': 'リスク管理',
                'severity': 'high',
                'current_value': f"{dd['max_drawdown']:,.0f}円",
                'target_value': '< 50,000円',
                'description': 'ドローダウンが大きすぎます。リスク管理を強化してください。'
            }
        elif dd['max_drawdown'] > 50000:
            problems['dd_large'] = {
                'category': 'リスク管理',
                'severity': 'medium',
                'current_value': f"{dd['max_drawdown']:,.0f}円",
                'target_value': '< 50,000円',
                'description': 'ドローダウンが目標を超えています。'
            }

        # 4. 勝敗比率
        if win_loss['win_loss_ratio'] < 1.0:
            problems['win_loss_ratio_low'] = {
                'category': '損益バランス',
                'severity': 'high',
                'current_value': f"{win_loss['win_loss_ratio']:.2f}",
                'target_value': '> 1.5',
                'description': '平均利益が平均損失より小さいです。TP/SL比率を見直してください。'
            }
        elif win_loss['win_loss_ratio'] < 1.5:
            problems['win_loss_ratio_marginal'] = {
                'category': '損益バランス',
                'severity': 'medium',
                'current_value': f"{win_loss['win_loss_ratio']:.2f}",
                'target_value': '> 1.5',
                'description': '勝敗比率が目標を下回っています。'
            }

        # 5. シャープレシオ
        if sharpe < 0.5:
            problems['sharpe_low'] = {
                'category': 'リスク調整後リターン',
                'severity': 'medium',
                'current_value': f"{sharpe:.2f}",
                'target_value': '> 1.0',
                'description': 'リスクに対するリターンが低いです。'
            }

        # 6. 取引回数
        if basic['total_trades'] < 30:
            problems['sample_size_small'] = {
                'category': 'データ不足',
                'severity': 'low',
                'current_value': f"{basic['total_trades']}回",
                'target_value': '> 100回',
                'description': '取引回数が少なく、統計的信頼性が低いです。'
            }

        return problems

    # ========================================
    # パラメータ推奨
    # ========================================

    def recommend_parameters(self) -> Dict[str, any]:
        """
        推奨パラメータを計算

        Returns:
            Dict: 推奨パラメータ
                - recommended: 推奨値
                - current: 現在値（推定）
                - reason: 推奨理由
        """
        problems = self.diagnose_problems()
        recommendations = {}

        basic = self.report['basic_stats']
        pf = self.report['profit_factor']
        dd = self.report['drawdown_stats']
        win_loss = self.report['win_loss_stats']

        # 勝率が低い場合 → エントリー条件を厳しく
        if 'win_rate_low' in problems or 'win_rate_marginal' in problems:
            recommendations['rsiLower'] = {
                'recommended': 55,
                'current': 50,
                'reason': '勝率向上のため、より強いトレンドのみエントリー'
            }
            recommendations['volumeMultiplier'] = {
                'recommended': 1.5,
                'current': 1.2,
                'reason': '出来高条件を厳しくして質の高いエントリーを狙う'
            }

        # PFが低い、または勝敗比率が低い場合 → TP/SL比率を調整
        if 'pf_low' in problems or 'pf_marginal' in problems or \
           'win_loss_ratio_low' in problems or 'win_loss_ratio_marginal' in problems:
            recommendations['atrTpMultiplier'] = {
                'recommended': 5.0,
                'current': 4.0,
                'reason': 'テイクプロフィットを拡大して利益を伸ばす'
            }
            recommendations['minRrRatio'] = {
                'recommended': 2.0,
                'current': 1.5,
                'reason': 'リスクリワード比率を改善'
            }

        # DDが大きい場合 → リスク管理を強化
        if 'dd_too_large' in problems or 'dd_large' in problems:
            recommendations['atrSlMultiplier'] = {
                'recommended': 1.5,
                'current': 2.0,
                'reason': 'ストップロスを小さくしてリスクを削減'
            }
            recommendations['maxDailyEntries'] = {
                'recommended': 2,
                'current': 3,
                'reason': '1日の取引回数を減らしてリスクを分散'
            }

        # シャープレシオが低い場合 → ボラティリティを抑える
        if 'sharpe_low' in problems:
            recommendations['emaMediumPeriod'] = {
                'recommended': 30,
                'current': 25,
                'reason': 'より長期のトレンドを捉えてボラティリティを抑える'
            }

        return recommendations

    # ========================================
    # Pine Script生成
    # ========================================

    def generate_pine_script(self, params: Dict[str, any] = None) -> str:
        """
        Pine Scriptパラメータ部分を生成

        Args:
            params: カスタムパラメータ（Noneの場合は推奨値）

        Returns:
            str: Pine Scriptコード
        """
        if params is None:
            params_dict = self.recommend_parameters()
            params = {k: v['recommended'] for k, v in params_dict.items()}

        # デフォルト値
        defaults = {
            'emaFastPeriod': 5,
            'emaMediumPeriod': 25,
            'emaSlowPeriod': 75,
            'rsiPeriod': 14,
            'rsiLower': 50,
            'rsiUpper': 70,
            'volumePeriod': 20,
            'volumeMultiplier': 1.2,
            'atrPeriod': 14,
            'atrSlMultiplier': 2.0,
            'atrTpMultiplier': 4.0,
            'minRrRatio': 1.5,
            'maxDailyEntries': 3,
            'cooldownMinutes': 30,
            'cooldownAfterLoss': 60
        }

        # 推奨値で上書き
        for key, value in params.items():
            defaults[key] = value

        # Pine Scriptコード生成
        script = f'''// ============================================================================
// 最適化されたパラメータ
// 生成日時: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
// ============================================================================

// --- 移動平均線設定 ---
emaFastPeriod = input.int({defaults['emaFastPeriod']}, "短期EMA期間", minval=1, group="移動平均線")
emaMediumPeriod = input.int({defaults['emaMediumPeriod']}, "中期EMA期間", minval=1, group="移動平均線")
emaSlowPeriod = input.int({defaults['emaSlowPeriod']}, "長期EMA期間", minval=1, group="移動平均線")

// --- RSIフィルター ---
rsiPeriod = input.int({defaults['rsiPeriod']}, "RSI期間", minval=1, group="テクニカル指標")
rsiLower = input.int({defaults['rsiLower']}, "RSI下限", minval=0, maxval=100, group="テクニカル指標")
rsiUpper = input.int({defaults['rsiUpper']}, "RSI上限", minval=0, maxval=100, group="テクニカル指標")

// --- 出来高フィルター ---
volumePeriod = input.int({defaults['volumePeriod']}, "出来高平均期間", minval=1, group="テクニカル指標")
volumeMultiplier = input.float({defaults['volumeMultiplier']}, "出来高倍率", minval=1.0, step=0.1, group="テクニカル指標")

// --- ATR設定 ---
atrPeriod = input.int({defaults['atrPeriod']}, "ATR期間", minval=1, group="ATR設定")
atrSlMultiplier = input.float({defaults['atrSlMultiplier']}, "ストップロス倍率", minval=0.5, step=0.1, group="ATR設定")
atrTpMultiplier = input.float({defaults['atrTpMultiplier']}, "テイクプロフィット倍率", minval=1.0, step=0.1, group="ATR設定")
minRrRatio = input.float({defaults['minRrRatio']}, "最低リスクリワード比", minval=1.0, step=0.1, group="ATR設定")

// --- リスク管理 ---
maxDailyEntries = input.int({defaults['maxDailyEntries']}, "1日最大エントリー数", minval=1, maxval=10, group="リスク管理")
cooldownMinutes = input.int({defaults['cooldownMinutes']}, "クールダウン時間（分）", minval=0, group="リスク管理")
cooldownAfterLoss = input.int({defaults['cooldownAfterLoss']}, "損切り後待機時間（分）", minval=0, group="リスク管理")

// ============================================================================
// このコードを kabuto_strategy_v1.pine の該当部分（20-46行目）に貼り付けてください
// ============================================================================
'''

        return script

    # ========================================
    # レポート生成
    # ========================================

    def generate_optimization_report(self) -> str:
        """
        最適化レポートを生成

        Returns:
            str: レポート（テキスト形式）
        """
        problems = self.diagnose_problems()
        recommendations = self.recommend_parameters()

        report = []
        report.append("=" * 70)
        report.append("Kabuto Auto Trader - パラメータ最適化レポート")
        report.append("=" * 70)
        report.append("")

        # 現在のパフォーマンス
        report.append("【現在のパフォーマンス】")
        basic = self.report['basic_stats']
        pf = self.report['profit_factor']
        dd = self.report['drawdown_stats']

        report.append(f"  総取引数:       {basic['total_trades']:,}回")
        report.append(f"  勝率:           {basic['win_rate']:.1%}")
        report.append(f"  総損益:         {basic['total_pnl']:,.0f}円")
        report.append(f"  PF:             {pf:.2f}")
        report.append(f"  最大DD:         {dd['max_drawdown']:,.0f}円")
        report.append("")

        # 問題診断
        if problems:
            report.append("【検出された問題】")
            for problem_name, problem in problems.items():
                severity_icon = {
                    'high': '🔴',
                    'medium': '🟡',
                    'low': '⚪'
                }[problem['severity']]

                report.append(f"  {severity_icon} {problem['category']}")
                report.append(f"     現在値: {problem['current_value']}")
                report.append(f"     目標値: {problem['target_value']}")
                report.append(f"     説明: {problem['description']}")
                report.append("")
        else:
            report.append("【検出された問題】")
            report.append("  ✅ 深刻な問題は検出されませんでした")
            report.append("")

        # 推奨パラメータ
        if recommendations:
            report.append("【推奨パラメータ】")
            for param_name, param in recommendations.items():
                report.append(f"  📌 {param_name}")
                report.append(f"     現在値: {param['current']}")
                report.append(f"     推奨値: {param['recommended']}")
                report.append(f"     理由: {param['reason']}")
                report.append("")
        else:
            report.append("【推奨パラメータ】")
            report.append("  ✅ 現在のパラメータで問題ありません")
            report.append("")

        # 次のステップ
        report.append("【次のステップ】")
        if recommendations:
            report.append("  1. 下記の Pine Script コードをコピー")
            report.append("  2. TradingView で kabuto_strategy_v1.pine を開く")
            report.append("  3. パラメータ部分（20-46行目）を置き換え")
            report.append("  4. Strategy Tester でバックテスト実行")
            report.append("  5. 改善を確認")
        else:
            report.append("  現在のパラメータで運用を継続してください")
        report.append("")

        report.append("=" * 70)

        return "\n".join(report)

    # ========================================
    # 便利メソッド
    # ========================================

    def print_optimization_report(self):
        """最適化レポートを出力"""
        print(self.generate_optimization_report())

    def save_pine_script(self, filename: str = 'optimized_parameters.pine'):
        """Pine Scriptをファイル保存"""
        script = self.generate_pine_script()
        with open(filename, 'w', encoding='utf-8') as f:
            f.write(script)
        logger.info(f"Pine Script saved to {filename}")


if __name__ == '__main__':
    # テスト実行
    from data_loader import KabutoDataLoader

    # サンプルデータ生成
    sample_trades = KabutoDataLoader.generate_sample_data(100)

    # 最適化
    optimizer = ParameterOptimizer(sample_trades)
    optimizer.print_optimization_report()

    print("\n" + "=" * 70)
    print("Pine Script コード:")
    print("=" * 70)
    print(optimizer.generate_pine_script())
