"""
Market Hours Control Service
"""
import pytz
import jpholiday
from datetime import datetime, time
from enum import Enum
from typing import Dict

from app.core.config import get_settings
from app.core.logging import logger


class MarketSession(str, Enum):
    """Market session states"""
    PRE_MARKET = "pre_market"
    MORNING_AUCTION = "morning_auction"
    MORNING_TRADING = "morning_trading"
    LUNCH_BREAK = "lunch_break"
    AFTERNOON_AUCTION = "afternoon_auction"
    AFTERNOON_TRADING = "afternoon_trading"
    POST_MARKET = "post_market"
    CLOSED = "closed"


class MarketHoursService:
    """
    Japanese market hours and trading time control
    """

    def __init__(self):
        self.settings = get_settings()
        self.config = self.settings.market_hours
        self.timezone = pytz.timezone(self.config.timezone)

    def get_current_session(self) -> MarketSession:
        """
        Get current market session

        Returns:
            MarketSession enum
        """
        now = datetime.now(self.timezone)
        current_time = now.time()
        current_date = now.date()

        # Check if trading day
        if not self.is_trading_day(current_date):
            return MarketSession.CLOSED

        # Check session
        if current_time < time(8, 0):
            return MarketSession.PRE_MARKET
        elif current_time < time(9, 0):
            return MarketSession.MORNING_AUCTION
        elif current_time < time(11, 30):
            return MarketSession.MORNING_TRADING
        elif current_time < time(12, 30):
            return MarketSession.LUNCH_BREAK
        elif current_time < time(15, 0):
            return MarketSession.AFTERNOON_TRADING
        else:
            return MarketSession.POST_MARKET

    def is_trading_day(self, date: datetime.date) -> bool:
        """
        Check if given date is a trading day

        Args:
            date: Date to check

        Returns:
            True if trading day, False otherwise
        """
        # Weekend check
        if date.weekday() in [5, 6]:  # Saturday, Sunday
            return False

        # Holiday check (using jpholiday)
        if jpholiday.is_holiday(date):
            return False

        # Special cases can be added here
        # e.g., Year-end special trading days

        return True

    def is_safe_trading_window(self) -> bool:
        """
        Check if current time is within safe trading windows
        (avoiding opening/closing volatility)

        Returns:
            True if safe to trade, False otherwise
        """
        now = datetime.now(self.timezone)
        current_time = now.time()
        current_date = now.date()

        if not self.is_trading_day(current_date):
            return False

        # Morning safe window
        morning_start = time(9, 30)
        morning_end = time(11, 20)

        # Afternoon safe window
        afternoon_start = time(13, 0)
        afternoon_end = time(14, 30)

        # Check if in safe windows
        in_morning = morning_start <= current_time <= morning_end
        in_afternoon = afternoon_start <= current_time <= afternoon_end

        return in_morning or in_afternoon

    def should_accept_signal(self) -> Dict[str, any]:
        """
        Determine if signal should be accepted based on market hours

        Returns:
            {"accept": True/False, "reason": str, "action": "QUEUE/REJECT/ACCEPT"}
        """
        session = self.get_current_session()

        # Market closed
        if session == MarketSession.CLOSED:
            return {
                "accept": False,
                "reason": "market_closed",
                "action": self.config.off_hours_action
            }

        # Pre-market
        if session == MarketSession.PRE_MARKET:
            return {
                "accept": False,
                "reason": "pre_market",
                "action": "QUEUE"  # Queue for market open
            }

        # Lunch break
        if session == MarketSession.LUNCH_BREAK:
            return {
                "accept": False,
                "reason": "lunch_break",
                "action": "QUEUE"  # Queue for afternoon session
            }

        # Post-market
        if session == MarketSession.POST_MARKET:
            return {
                "accept": False,
                "reason": "post_market",
                "action": self.config.off_hours_action  # Use config setting
            }

        # Auction periods - reject to avoid volatility
        if session in [MarketSession.MORNING_AUCTION, MarketSession.AFTERNOON_AUCTION]:
            return {
                "accept": False,
                "reason": "auction_period",
                "action": "QUEUE"
            }

        # Trading hours - check if in safe window
        if not self.is_safe_trading_window():
            return {
                "accept": False,
                "reason": "outside_safe_window",
                "action": "QUEUE"
            }

        # All checks passed
        return {
            "accept": True,
            "reason": "trading_hours",
            "action": "ACCEPT"
        }

    def get_next_trading_window(self) -> datetime:
        """
        Get the next safe trading window

        Returns:
            Datetime of next safe trading window
        """
        now = datetime.now(self.timezone)
        current_time = now.time()
        current_date = now.date()

        # If not trading day, find next trading day
        if not self.is_trading_day(current_date):
            next_date = current_date
            while not self.is_trading_day(next_date):
                from datetime import timedelta
                next_date += timedelta(days=1)

            # Return morning opening
            return datetime.combine(next_date, time(9, 30), tzinfo=self.timezone)

        # If before morning window
        if current_time < time(9, 30):
            return datetime.combine(current_date, time(9, 30), tzinfo=self.timezone)

        # If in morning window
        if current_time < time(11, 20):
            return now  # Already in window

        # If in lunch break
        if current_time < time(13, 0):
            return datetime.combine(current_date, time(13, 0), tzinfo=self.timezone)

        # If in afternoon window
        if current_time < time(14, 30):
            return now  # Already in window

        # If after trading hours, next day morning
        from datetime import timedelta
        next_date = current_date + timedelta(days=1)
        while not self.is_trading_day(next_date):
            next_date += timedelta(days=1)

        return datetime.combine(next_date, time(9, 30), tzinfo=self.timezone)

    def get_market_status(self) -> Dict[str, any]:
        """
        Get comprehensive market status

        Returns:
            Dictionary with market status information
        """
        session = self.get_current_session()
        is_safe = self.is_safe_trading_window()
        accept_result = self.should_accept_signal()

        return {
            "session": session.value,
            "is_trading_day": self.is_trading_day(datetime.now(self.timezone).date()),
            "is_safe_trading_window": is_safe,
            "accept_signals": accept_result["accept"],
            "current_time": datetime.now(self.timezone).isoformat(),
            "next_trading_window": self.get_next_trading_window().isoformat()
        }
