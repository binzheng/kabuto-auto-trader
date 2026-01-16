"""
Day Trading Check Service
差金決済チェック - Prevents day trading violations (買い→売り or 売り→買い within the same day)
"""
from typing import Tuple
from sqlalchemy.orm import Session
from datetime import datetime, date, time
import logging

from app.models import ExecutionLog

logger = logging.getLogger(__name__)


class DayTradingCheckService:
    """
    差金決済チェックサービス

    日本の現物株取引では、同一銘柄を同一営業日内に「買い→売り」または「売り→買い」
    することはできません（差金決済の禁止）。このサービスはそのルールを実装します。
    """

    def __init__(self, db: Session):
        self.db = db

    def is_day_trading_violation(
        self,
        ticker: str,
        action: str
    ) -> Tuple[bool, str]:
        """
        差金決済違反チェック

        Args:
            ticker: 銘柄コード
            action: "buy" or "sell"

        Returns:
            Tuple of (is_violation: bool, reason: str)
            - is_violation: True if this order would violate day trading rules
            - reason: Description of the violation
        """
        # 今日の日付を取得（0:00:00から23:59:59まで）
        today = date.today()
        today_start = datetime.combine(today, time.min)
        today_end = datetime.combine(today, time.max)

        # 今日のこの銘柄の取引履歴を取得
        today_executions = self.db.query(ExecutionLog).filter(
            ExecutionLog.ticker == ticker,
            ExecutionLog.executed_at >= today_start,
            ExecutionLog.executed_at <= today_end
        ).all()

        if not today_executions:
            # 今日まだ取引していない → OK
            return False, ""

        # 今日の取引アクションをチェック
        today_actions = [exec.action for exec in today_executions]

        if action == "buy":
            # 買い注文を出そうとしている → 今日売った履歴があるか？
            if "sell" in today_actions:
                last_sell = max(
                    (exec for exec in today_executions if exec.action == "sell"),
                    key=lambda x: x.executed_at
                )
                return True, (
                    f"差金決済違反: {ticker}を今日{last_sell.executed_at.strftime('%H:%M:%S')}に売却済み。"
                    f"同日内の買い戻しはできません。"
                )

        elif action == "sell":
            # 売り注文を出そうとしている → 今日買った履歴があるか？
            if "buy" in today_actions:
                last_buy = max(
                    (exec for exec in today_executions if exec.action == "buy"),
                    key=lambda x: x.executed_at
                )
                return True, (
                    f"差金決済違反: {ticker}を今日{last_buy.executed_at.strftime('%H:%M:%S')}に購入済み。"
                    f"同日内の売却はできません。"
                )

        # OK - 違反なし
        return False, ""

    def check_day_trading(
        self,
        ticker: str,
        action: str
    ) -> Tuple[bool, str]:
        """
        差金決済チェック（外部向けインターフェース）

        Args:
            ticker: 銘柄コード
            action: "buy" or "sell"

        Returns:
            Tuple of (allowed: bool, reason: str)
            - allowed: True if the order is allowed
            - reason: If not allowed, the reason for blocking
        """
        is_violation, reason = self.is_day_trading_violation(ticker, action)

        if is_violation:
            logger.warning(f"Day trading violation detected: {ticker} {action} - {reason}")
            return False, reason

        return True, ""

    def get_today_trades(self, ticker: str) -> list:
        """
        今日のこの銘柄の取引履歴を取得（デバッグ用）

        Args:
            ticker: 銘柄コード

        Returns:
            List of ExecutionLog records for today
        """
        today = date.today()
        today_start = datetime.combine(today, time.min)
        today_end = datetime.combine(today, time.max)

        return self.db.query(ExecutionLog).filter(
            ExecutionLog.ticker == ticker,
            ExecutionLog.executed_at >= today_start,
            ExecutionLog.executed_at <= today_end
        ).order_by(ExecutionLog.executed_at).all()

    def get_today_summary(self) -> dict:
        """
        今日の全取引のサマリーを取得（管理用）

        Returns:
            Dictionary with today's trading summary
        """
        today = date.today()
        today_start = datetime.combine(today, time.min)
        today_end = datetime.combine(today, time.max)

        executions = self.db.query(ExecutionLog).filter(
            ExecutionLog.executed_at >= today_start,
            ExecutionLog.executed_at <= today_end
        ).all()

        # 銘柄ごとに集計
        ticker_actions = {}
        for exec in executions:
            if exec.ticker not in ticker_actions:
                ticker_actions[exec.ticker] = {"buy": 0, "sell": 0, "actions": []}

            ticker_actions[exec.ticker][exec.action] += 1
            ticker_actions[exec.ticker]["actions"].append({
                "action": exec.action,
                "time": exec.executed_at.strftime('%H:%M:%S'),
                "quantity": exec.quantity,
                "price": exec.price
            })

        return {
            "date": today.isoformat(),
            "total_trades": len(executions),
            "tickers": ticker_actions
        }
