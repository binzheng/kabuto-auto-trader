"""
日本株データローダー
analysis/data/daily/jp/tse stocks/ にあるtxtファイルを読み込む
"""
import pandas as pd
import os
from datetime import datetime


class JapanStockDataLoader:
    """日本株データローダー"""

    def __init__(self, base_path="analysis/data/daily/jp/tse stocks"):
        self.base_path = base_path

    def load_stock(self, ticker_code):
        """
        特定の銘柄コードのデータを読み込む

        Args:
            ticker_code: 銘柄コード（例: "7203", "1301"）

        Returns:
            pandas.DataFrame: OHLCVデータ
        """
        # ファイルを探す
        file_path = self._find_ticker_file(ticker_code)
        if not file_path:
            raise FileNotFoundError(f"Ticker {ticker_code} not found")

        # データ読み込み
        df = pd.read_csv(
            file_path,
            names=['ticker', 'period', 'date', 'time', 'open', 'high', 'low', 'close', 'volume', 'openint']
        )

        # ヘッダー行を削除
        df = df[df['ticker'] != '<TICKER>'].copy()

        # 日付をパース
        df['date'] = pd.to_datetime(df['date'], format='%Y%m%d')

        # 数値型に変換
        for col in ['open', 'high', 'low', 'close', 'volume']:
            df[col] = pd.to_numeric(df[col], errors='coerce')

        # timestampカラムを保持してからインデックスを日付に設定
        df['timestamp'] = df['date']
        df = df.set_index('date')

        # 必要なカラムのみ選択
        df = df[['timestamp', 'open', 'high', 'low', 'close', 'volume']].copy()

        # NaNを削除
        df = df.dropna()

        # ソート
        df = df.sort_index()

        return df

    def _find_ticker_file(self, ticker_code):
        """銘柄コードからファイルパスを検索"""
        # 1/, 2/ サブディレクトリを検索
        for subdir in ['1', '2']:
            dir_path = os.path.join(self.base_path, subdir)
            if not os.path.exists(dir_path):
                continue

            # {ticker}.jp.txt を探す
            file_path = os.path.join(dir_path, f"{ticker_code}.jp.txt")
            if os.path.exists(file_path):
                return file_path

        return None

    def list_available_tickers(self, limit=50):
        """利用可能な銘柄コードのリストを取得"""
        tickers = []
        for subdir in ['1', '2']:
            dir_path = os.path.join(self.base_path, subdir)
            if not os.path.exists(dir_path):
                continue

            for filename in os.listdir(dir_path):
                if filename.endswith('.jp.txt') and not filename.startswith('.'):
                    # ファイルサイズチェック（空ファイルを除外）
                    file_path = os.path.join(dir_path, filename)
                    if os.path.getsize(file_path) > 100:  # 100バイト以上
                        ticker = filename.replace('.jp.txt', '')
                        tickers.append(ticker)

                if len(tickers) >= limit:
                    break

            if len(tickers) >= limit:
                break

        return sorted(tickers)


if __name__ == "__main__":
    # テスト実行
    loader = JapanStockDataLoader()

    # 利用可能な銘柄リスト
    print("利用可能な銘柄（最初の20個）:")
    tickers = loader.list_available_tickers(20)
    for ticker in tickers:
        print(f"  - {ticker}")

    # サンプルデータ読み込み
    print("\n1301のデータサンプル:")
    df = loader.load_stock("1301")
    print(f"期間: {df.index[0]} 〜 {df.index[-1]}")
    print(f"データ数: {len(df)}行")
    print("\n最初の5行:")
    print(df.head())
    print("\n最後の5行:")
    print(df.tail())
