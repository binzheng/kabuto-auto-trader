"""
Blacklist Management Service
"""
from sqlalchemy.orm import Session
from datetime import datetime, date, timedelta
from typing import Optional, List

from app.models import Blacklist
from app.core.logging import logger


class BlacklistService:
    """
    Ticker blacklist management
    """

    def __init__(self, db: Session):
        self.db = db

    def is_blacklisted(self, ticker: str) -> bool:
        """
        Check if ticker is blacklisted

        Args:
            ticker: Stock ticker code

        Returns:
            True if blacklisted, False otherwise
        """
        # Cleanup expired entries first
        self._cleanup_expired()

        blacklist_entry = self.db.query(Blacklist).filter(
            Blacklist.ticker == ticker
        ).first()

        if not blacklist_entry:
            return False

        # Check if expired
        if blacklist_entry.expires_at:
            if datetime.now() > blacklist_entry.expires_at:
                # Expired, remove and return False
                self.db.delete(blacklist_entry)
                self.db.commit()
                logger.info(f"Removed expired blacklist entry: {ticker}")
                return False

        logger.warning(f"Ticker is blacklisted: {ticker} (Reason: {blacklist_entry.reason})")
        return True

    def add_to_blacklist(
        self,
        ticker: str,
        reason: str,
        blacklist_type: str = "temporary",
        ticker_name: Optional[str] = None,
        expiry_days: Optional[int] = None,
        added_by: str = "auto"
    ) -> Blacklist:
        """
        Add ticker to blacklist

        Args:
            ticker: Stock ticker code
            reason: Reason for blacklisting
            blacklist_type: permanent / temporary / dynamic
            ticker_name: Optional ticker name
            expiry_days: Days until expiration (None for permanent)
            added_by: Who added (auto / manual)

        Returns:
            Blacklist entry
        """
        # Check if already blacklisted
        existing = self.db.query(Blacklist).filter(
            Blacklist.ticker == ticker
        ).first()

        if existing:
            logger.warning(f"Ticker already blacklisted: {ticker}")
            return existing

        # Calculate expiry date
        expires_at = None
        if expiry_days is not None:
            expires_at = datetime.now() + timedelta(days=expiry_days)

        # Create blacklist entry
        blacklist_entry = Blacklist(
            ticker=ticker,
            ticker_name=ticker_name,
            reason=reason,
            blacklist_type=blacklist_type,
            expires_at=expires_at,
            added_by=added_by
        )

        self.db.add(blacklist_entry)
        self.db.commit()

        logger.info(f"Added to blacklist: {ticker} (Type: {blacklist_type}, Expires: {expires_at})")

        return blacklist_entry

    def remove_from_blacklist(self, ticker: str) -> bool:
        """
        Remove ticker from blacklist

        Args:
            ticker: Stock ticker code

        Returns:
            True if removed, False if not found
        """
        blacklist_entry = self.db.query(Blacklist).filter(
            Blacklist.ticker == ticker
        ).first()

        if not blacklist_entry:
            logger.warning(f"Ticker not in blacklist: {ticker}")
            return False

        self.db.delete(blacklist_entry)
        self.db.commit()

        logger.info(f"Removed from blacklist: {ticker}")
        return True

    def get_all_blacklisted(self) -> List[Blacklist]:
        """
        Get all blacklisted tickers

        Returns:
            List of Blacklist entries
        """
        # Cleanup expired first
        self._cleanup_expired()

        return self.db.query(Blacklist).all()

    def _cleanup_expired(self):
        """
        Remove expired blacklist entries
        """
        now = datetime.now()

        expired = self.db.query(Blacklist).filter(
            Blacklist.expires_at.isnot(None),
            Blacklist.expires_at < now
        ).all()

        if expired:
            for entry in expired:
                logger.info(f"Removing expired blacklist: {entry.ticker}")
                self.db.delete(entry)

            self.db.commit()

    def add_auto_blacklist_for_losses(
        self,
        ticker: str,
        consecutive_losses: int
    ):
        """
        Automatically add ticker to blacklist after consecutive losses

        Args:
            ticker: Stock ticker code
            consecutive_losses: Number of consecutive losses
        """
        reason = f"Auto-blacklisted after {consecutive_losses} consecutive losses"

        self.add_to_blacklist(
            ticker=ticker,
            reason=reason,
            blacklist_type="dynamic",
            expiry_days=30,  # 30 days auto-expiry
            added_by="auto"
        )
