"""
Kabuto Auto Trader - データローダー
Excel VBAログシートおよびRelay Server DBからデータを読み込む
"""

import pandas as pd
from pathlib import Path
from typing import Optional, List
import logging
from datetime import datetime, timedelta

logger = logging.getLogger(__name__)


class KabutoDataLoader:
    """Kabuto Auto Trader データローダー"""

    def __init__(self, excel_path: Optional[str] = None, db_url: Optional[str] = None):
        """
        Args:
            excel_path: Excelブックのパス (例: "Kabuto Auto Trader.xlsm")
            db_url: Relay Server DB URL (例: "sqlite:///kabuto.db")
        """
        self.excel_path = excel_path
        self.db_url = db_url

    # ========================================
    # Excel読み込み
    # ========================================

    def load_execution_log_from_excel(self) -> pd.DataFrame:
        """
        ExecutionLog シートを読み込む

        Returns:
            DataFrame: 約定履歴データ
                - execution_id: 約定ID
                - timestamp: 約定時刻
                - signal_id: シグナルID
                - ticker: 銘柄コード
                - ticker_name: 銘柄名
                - action: 売買区分 (buy/sell)
                - quantity: 数量
                - price: 価格
                - commission: 手数料
                - pnl: 実現損益 (sell時のみ)
        """
        if not self.excel_path:
            raise ValueError("Excel path not specified")

        df = pd.read_excel(
            self.excel_path,
            sheet_name='ExecutionLog',
            header=0
        )

        # timestamp を datetime 型に変換
        df['timestamp'] = pd.to_datetime(df['timestamp'])

        logger.info(f"Loaded {len(df)} execution records from Excel")
        return df

    def load_order_history_from_excel(self) -> pd.DataFrame:
        """
        OrderHistory シートを読み込む

        Returns:
            DataFrame: 注文履歴データ
        """
        if not self.excel_path:
            raise ValueError("Excel path not specified")

        df = pd.read_excel(
            self.excel_path,
            sheet_name='OrderHistory',
            header=0
        )

        df['submitted_at'] = pd.to_datetime(df['submitted_at'])

        logger.info(f"Loaded {len(df)} order records from Excel")
        return df

    def load_signal_log_from_excel(self) -> pd.DataFrame:
        """
        SignalLog シートを読み込む

        Returns:
            DataFrame: シグナル履歴データ
        """
        if not self.excel_path:
            raise ValueError("Excel path not specified")

        df = pd.read_excel(
            self.excel_path,
            sheet_name='SignalLog',
            header=0
        )

        df['timestamp'] = pd.to_datetime(df['timestamp'])

        logger.info(f"Loaded {len(df)} signal records from Excel")
        return df

    def load_error_log_from_excel(self) -> pd.DataFrame:
        """
        ErrorLog シートを読み込む

        Returns:
            DataFrame: エラーログデータ
        """
        if not self.excel_path:
            raise ValueError("Excel path not specified")

        df = pd.read_excel(
            self.excel_path,
            sheet_name='ErrorLog',
            header=0
        )

        df['timestamp'] = pd.to_datetime(df['timestamp'])

        logger.info(f"Loaded {len(df)} error records from Excel")
        return df

    # ========================================
    # Database読み込み
    # ========================================

    def load_execution_log_from_db(
        self,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None
    ) -> pd.DataFrame:
        """
        Relay Server DB から約定履歴を読み込む

        Args:
            start_date: 開始日時
            end_date: 終了日時

        Returns:
            DataFrame: 約定履歴データ
        """
        if not self.db_url:
            raise ValueError("Database URL not specified")

        from sqlalchemy import create_engine, text

        engine = create_engine(self.db_url)

        query = "SELECT * FROM execution_log WHERE 1=1"
        params = {}

        if start_date:
            query += " AND timestamp >= :start_date"
            params['start_date'] = start_date

        if end_date:
            query += " AND timestamp <= :end_date"
            params['end_date'] = end_date

        df = pd.read_sql(text(query), engine, params=params)
        df['timestamp'] = pd.to_datetime(df['timestamp'])

        logger.info(f"Loaded {len(df)} execution records from DB")
        return df

    # ========================================
    # 統合データ取得
    # ========================================

    def load_all_trades(self, source: str = 'excel') -> pd.DataFrame:
        """
        すべての取引データを取得（sell のみ = 確定損益）

        Args:
            source: データソース ('excel' or 'db')

        Returns:
            DataFrame: sell 約定のみのデータ
        """
        if source == 'excel':
            df = self.load_execution_log_from_excel()
        elif source == 'db':
            df = self.load_execution_log_from_db()
        else:
            raise ValueError(f"Unknown source: {source}")

        # sell（売却）のみフィルタ
        trades = df[df['action'] == 'sell'].copy()

        logger.info(f"Loaded {len(trades)} trades (sell only)")
        return trades

    def load_recent_trades(self, days: int = 30, source: str = 'excel') -> pd.DataFrame:
        """
        最近N日間の取引データを取得

        Args:
            days: 日数
            source: データソース

        Returns:
            DataFrame: 最近の取引データ
        """
        all_trades = self.load_all_trades(source=source)

        cutoff_date = datetime.now() - timedelta(days=days)
        recent_trades = all_trades[all_trades['timestamp'] >= cutoff_date]

        logger.info(f"Loaded {len(recent_trades)} trades from last {days} days")
        return recent_trades

    # ========================================
    # サンプルデータ生成（テスト用）
    # ========================================

    @staticmethod
    def generate_sample_data(n_trades: int = 100) -> pd.DataFrame:
        """
        サンプルデータを生成（テスト用）

        Args:
            n_trades: 生成する取引数

        Returns:
            DataFrame: サンプル取引データ
        """
        import numpy as np

        np.random.seed(42)

        # ランダムな取引データ生成
        data = {
            'execution_id': [f'EXE-20250101-{i:03d}' for i in range(1, n_trades + 1)],
            'timestamp': pd.date_range(start='2025-01-01', periods=n_trades, freq='H'),
            'signal_id': [f'SIG-20250101-{i:03d}' for i in range(1, n_trades + 1)],
            'ticker': np.random.choice(['7203', '9984', '6758', '6861', '4063'], n_trades),
            'ticker_name': np.random.choice(['トヨタ', 'ソフトバンク', 'ソニー', 'キーエンス', '信越化学'], n_trades),
            'action': 'sell',
            'quantity': np.random.choice([100, 200, 300], n_trades),
            'price': np.random.uniform(1000, 5000, n_trades),
            'commission': 198,
            'pnl': np.random.normal(500, 2000, n_trades)  # 平均+500円、標準偏差2000円
        }

        df = pd.DataFrame(data)

        logger.info(f"Generated {len(df)} sample trades")
        return df


# ========================================
# 便利関数
# ========================================

def quick_load_trades(excel_path: Optional[str] = None, days: int = 30) -> pd.DataFrame:
    """
    クイックロード：最近N日間の取引データを取得

    Args:
        excel_path: Excelブックのパス（Noneの場合はサンプルデータ）
        days: 日数

    Returns:
        DataFrame: 取引データ
    """
    if excel_path:
        loader = KabutoDataLoader(excel_path=excel_path)
        return loader.load_recent_trades(days=days)
    else:
        # Excelパスが指定されていない場合はサンプルデータ
        logger.warning("No Excel path specified, using sample data")
        return KabutoDataLoader.generate_sample_data()


if __name__ == '__main__':
    # テスト実行
    logging.basicConfig(level=logging.INFO)

    # サンプルデータ生成
    sample_trades = KabutoDataLoader.generate_sample_data(100)
    print(f"Sample trades: {len(sample_trades)} records")
    print(sample_trades.head())

    # 統計
    print(f"\n総損益: {sample_trades['pnl'].sum():,.0f}円")
    print(f"平均損益: {sample_trades['pnl'].mean():,.0f}円")
    print(f"勝率: {(sample_trades['pnl'] > 0).sum() / len(sample_trades):.1%}")
