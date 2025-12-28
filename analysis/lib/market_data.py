"""
Kabuto Auto Trader - 市場データ取得ライブラリ
OHLCVデータをYahoo Financeから取得
"""

import pandas as pd
import numpy as np
from typing import Optional, List, Dict
from datetime import datetime, timedelta
import logging

try:
    import yfinance as yf
except ImportError:
    raise ImportError("yfinance が必要です: pip install yfinance")

logger = logging.getLogger(__name__)


class MarketDataFetcher:
    """市場データ取得クラス"""

    def __init__(self):
        """初期化"""
        self.cache = {}

    # ========================================
    # OHLCVデータ取得
    # ========================================

    def fetch_ohlcv(
        self,
        ticker: str,
        start_date: str,
        end_date: str,
        interval: str = '1d'
    ) -> pd.DataFrame:
        """
        OHLCVデータを取得

        Args:
            ticker: 銘柄コード（例: "7203.T" = トヨタ自動車）
            start_date: 開始日 (YYYY-MM-DD)
            end_date: 終了日 (YYYY-MM-DD)
            interval: 時間軸
                - '1m': 1分足（最大7日）
                - '5m': 5分足（最大60日）
                - '15m': 15分足
                - '1h': 1時間足
                - '1d': 日足（デフォルト）

        Returns:
            pd.DataFrame: OHLCVデータ
                - timestamp: タイムスタンプ
                - open: 始値
                - high: 高値
                - low: 安値
                - close: 終値
                - volume: 出来高
        """
        # キャッシュチェック
        cache_key = f"{ticker}_{start_date}_{end_date}_{interval}"
        if cache_key in self.cache:
            logger.info(f"キャッシュからデータ取得: {cache_key}")
            return self.cache[cache_key].copy()

        # Yahoo Financeから取得
        logger.info(f"データ取得中: {ticker} ({start_date} - {end_date}, {interval})")

        try:
            # yfinance でダウンロード
            df = yf.download(
                ticker,
                start=start_date,
                end=end_date,
                interval=interval,
                progress=False,
                auto_adjust=True  # 株式分割調整済み
            )

            if df.empty:
                raise ValueError(f"データが取得できませんでした: {ticker}")

            # カラム名を標準化
            df.columns = [col.lower() for col in df.columns]
            df = df.reset_index()
            df.rename(columns={'date': 'timestamp', 'datetime': 'timestamp'}, inplace=True)

            # タイムスタンプをdatetime型に変換
            if not pd.api.types.is_datetime64_any_dtype(df['timestamp']):
                df['timestamp'] = pd.to_datetime(df['timestamp'])

            # 必要なカラムのみ残す
            required_cols = ['timestamp', 'open', 'high', 'low', 'close', 'volume']
            df = df[required_cols]

            # 検証
            self._validate_ohlcv(df)

            # キャッシュに保存
            self.cache[cache_key] = df.copy()

            logger.info(f"データ取得完了: {len(df)}行")
            return df

        except Exception as e:
            logger.error(f"データ取得エラー: {ticker} - {str(e)}")
            raise

    def fetch_multiple_tickers(
        self,
        tickers: List[str],
        start_date: str,
        end_date: str,
        interval: str = '1d'
    ) -> Dict[str, pd.DataFrame]:
        """
        複数銘柄のOHLCVデータを取得

        Args:
            tickers: 銘柄コードリスト
            start_date: 開始日
            end_date: 終了日
            interval: 時間軸

        Returns:
            Dict[str, pd.DataFrame]: 銘柄コードをキーとしたDataFrame辞書
        """
        results = {}
        for ticker in tickers:
            try:
                df = self.fetch_ohlcv(ticker, start_date, end_date, interval)
                results[ticker] = df
            except Exception as e:
                logger.warning(f"{ticker} のデータ取得失敗: {str(e)}")
                continue

        return results

    # ========================================
    # データ検証
    # ========================================

    def _validate_ohlcv(self, df: pd.DataFrame):
        """
        OHLCVデータの妥当性をチェック

        Raises:
            ValueError: データが無効な場合
        """
        # 必須カラムチェック
        required_cols = ['timestamp', 'open', 'high', 'low', 'close', 'volume']
        missing_cols = set(required_cols) - set(df.columns)
        if missing_cols:
            raise ValueError(f"必須カラムが不足しています: {missing_cols}")

        # データ型チェック
        if not pd.api.types.is_datetime64_any_dtype(df['timestamp']):
            raise ValueError("timestamp が datetime 型ではありません")

        # OHLC整合性チェック
        invalid_rows = df[
            (df['high'] < df['low']) |
            (df['high'] < df['open']) |
            (df['high'] < df['close']) |
            (df['low'] > df['open']) |
            (df['low'] > df['close'])
        ]

        if len(invalid_rows) > 0:
            logger.warning(f"OHLCの整合性エラー: {len(invalid_rows)}行")

        # 負の値チェック
        negative_prices = df[
            (df['open'] <= 0) |
            (df['high'] <= 0) |
            (df['low'] <= 0) |
            (df['close'] <= 0)
        ]

        if len(negative_prices) > 0:
            raise ValueError(f"負の価格が存在します: {len(negative_prices)}行")

    # ========================================
    # ユーティリティ
    # ========================================

    def get_latest_price(self, ticker: str) -> Dict:
        """
        最新価格を取得

        Args:
            ticker: 銘柄コード

        Returns:
            Dict: 最新価格情報
                - price: 現在値
                - volume: 出来高
                - timestamp: タイムスタンプ
        """
        try:
            stock = yf.Ticker(ticker)
            info = stock.info

            return {
                'price': info.get('currentPrice', info.get('regularMarketPrice')),
                'volume': info.get('volume', info.get('regularMarketVolume')),
                'timestamp': datetime.now()
            }
        except Exception as e:
            logger.error(f"最新価格取得エラー: {ticker} - {str(e)}")
            raise

    def get_trading_calendar(
        self,
        start_date: str,
        end_date: str,
        exchange: str = 'JPX'
    ) -> pd.DatetimeIndex:
        """
        取引日カレンダーを取得

        Args:
            start_date: 開始日
            end_date: 終了日
            exchange: 取引所（JPX=東京証券取引所）

        Returns:
            pd.DatetimeIndex: 取引日の日付リスト
        """
        # 簡易実装：任意の銘柄から取引日を抽出
        # 本格実装なら pandas_market_calendars を使用
        try:
            df = self.fetch_ohlcv('9984.T', start_date, end_date, '1d')  # ソフトバンクG
            trading_days = pd.to_datetime(df['timestamp'].dt.date.unique())
            return trading_days
        except Exception as e:
            logger.warning(f"取引日カレンダー取得失敗: {str(e)}")
            # フォールバック: 土日を除外
            date_range = pd.date_range(start=start_date, end=end_date, freq='B')
            return date_range

    def clear_cache(self):
        """キャッシュをクリア"""
        self.cache = {}
        logger.info("キャッシュをクリアしました")


# ========================================
# 便利関数
# ========================================

def quick_fetch(
    ticker: str,
    days: int = 365,
    interval: str = '1d'
) -> pd.DataFrame:
    """
    簡易データ取得（直近N日分）

    Args:
        ticker: 銘柄コード
        days: 日数（デフォルト365日 = 1年）
        interval: 時間軸

    Returns:
        pd.DataFrame: OHLCVデータ
    """
    end_date = datetime.now()
    start_date = end_date - timedelta(days=days)

    fetcher = MarketDataFetcher()
    return fetcher.fetch_ohlcv(
        ticker,
        start_date.strftime('%Y-%m-%d'),
        end_date.strftime('%Y-%m-%d'),
        interval
    )


if __name__ == '__main__':
    # テスト実行
    import logging
    logging.basicConfig(level=logging.INFO)

    # データ取得テスト
    fetcher = MarketDataFetcher()

    # 日足データ（トヨタ自動車、1年分）
    print("=== 日足データ取得テスト ===")
    df_daily = fetcher.fetch_ohlcv('7203.T', '2024-01-01', '2025-01-01', '1d')
    print(df_daily.head())
    print(f"取得行数: {len(df_daily)}")

    # 5分足データ（直近30日）
    print("\n=== 5分足データ取得テスト ===")
    end = datetime.now()
    start = end - timedelta(days=30)
    df_5m = fetcher.fetch_ohlcv(
        '7203.T',
        start.strftime('%Y-%m-%d'),
        end.strftime('%Y-%m-%d'),
        '5m'
    )
    print(df_5m.head())
    print(f"取得行数: {len(df_5m)}")

    # 最新価格
    print("\n=== 最新価格取得テスト ===")
    latest = fetcher.get_latest_price('7203.T')
    print(latest)
