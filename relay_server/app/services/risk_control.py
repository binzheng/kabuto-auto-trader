"""
Final Risk Control Service - Last line of defense
"""
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from datetime import datetime, date
from typing import Dict, Optional

from app.models import Position, DailyStats, Signal
from app.core.config import get_settings
from app.core.logging import log_risk_violation, logger


class RiskControlService:
    """
    Final risk control - independent from strategy logic
    """

    def __init__(self, db: Session):
        self.db = db
        self.settings = get_settings()
        self.config = self.settings.risk_control

    def validate_order(
        self,
        ticker: str,
        action: str,
        quantity: int,
        price: float,
        sector: Optional[str] = None
    ) -> Dict[str, any]:
        """
        Comprehensive risk validation

        Returns:
            {"allowed": True/False, "reason": str}
        """
        # 1. Kill switch check (highest priority)
        if not self._is_trading_enabled():
            log_risk_violation("kill_switch_active", ticker)
            return {"allowed": False, "reason": "kill_switch_active"}

        # 2. Blacklist check
        from app.services.blacklist import BlacklistService
        blacklist_service = BlacklistService(self.db)
        if blacklist_service.is_blacklisted(ticker):
            log_risk_violation("ticker_blacklisted", ticker)
            return {"allowed": False, "reason": "ticker_blacklisted"}

        # 3. Daily hard limits check
        if not self._check_daily_limits(action):
            log_risk_violation("daily_limit_exceeded", ticker)
            return {"allowed": False, "reason": "daily_limit_exceeded"}

        # 4. Position limits check (for buy orders)
        if action == "buy":
            position_value = quantity * price

            if not self._check_position_limits(ticker, position_value, sector):
                log_risk_violation("position_limit_exceeded", ticker)
                return {"allowed": False, "reason": "position_limit_exceeded"}

        # 5. Auto kill-switch triggers check
        if self._should_trigger_auto_killswitch():
            log_risk_violation("auto_kill_switch_triggered", ticker)
            from app.services.kill_switch import KillSwitchService
            kill_switch = KillSwitchService(self.db)
            kill_switch.activate("auto_trigger", "Risk limits exceeded")
            return {"allowed": False, "reason": "auto_kill_switch_triggered"}

        return {"allowed": True, "reason": "all_checks_passed"}

    def _is_trading_enabled(self) -> bool:
        """Check if kill switch is active"""
        from app.services.kill_switch import KillSwitchService
        kill_switch = KillSwitchService(self.db)
        return kill_switch.is_trading_enabled()

    def _check_daily_limits(self, action: str) -> bool:
        """Check daily hard limits"""
        today = date.today()
        stats = self.db.query(DailyStats).filter(
            DailyStats.date == today
        ).first()

        if not stats:
            return True  # No stats yet, allow

        # Check entry limit
        if action == "buy" and stats.entry_count >= self.config.max_daily_entries:
            return False

        # Check total trades limit
        if stats.total_trades >= self.config.max_daily_trades:
            return False

        return True

    def _check_position_limits(
        self,
        ticker: str,
        position_value: float,
        sector: Optional[str] = None
    ) -> bool:
        """Check position limits"""
        # Get current positions
        positions = self.db.query(Position).all()

        # Check max open positions
        if len(positions) >= self.config.max_open_positions:
            # Check if we already have this ticker
            existing = self.db.query(Position).filter(
                Position.ticker == ticker
            ).first()
            if not existing:
                return False  # New position would exceed limit

        # Calculate total exposure
        total_exposure = sum(p.quantity * p.avg_cost for p in positions) + position_value

        if total_exposure > self.config.max_total_exposure:
            return False

        # Check per-ticker limit
        existing_position = self.db.query(Position).filter(
            Position.ticker == ticker
        ).first()

        if existing_position:
            new_total = (existing_position.quantity * existing_position.avg_cost) + position_value
            if new_total > self.config.max_position_per_ticker:
                return False
        else:
            if position_value > self.config.max_position_per_ticker:
                return False

        # Check sector exposure (if sector provided)
        if sector:
            sector_exposure = sum(
                p.quantity * p.avg_cost
                for p in positions
                if p.sector == sector
            ) + position_value

            max_sector_exposure = self.config.max_total_exposure * self.config.max_sector_exposure_pct

            if sector_exposure > max_sector_exposure:
                return False

        return True

    def _should_trigger_auto_killswitch(self) -> bool:
        """Check if auto kill-switch should be triggered"""
        today = date.today()
        stats = self.db.query(DailyStats).filter(
            DailyStats.date == today
        ).first()

        if not stats:
            return False

        # Consecutive losses
        if stats.consecutive_losses >= self.config.max_consecutive_losses:
            return True

        # Daily loss limit
        if stats.total_pnl <= self.config.max_daily_loss:
            return True

        # Trade frequency check
        if stats.total_trades >= self.config.max_daily_trades:
            return True

        return False

    def update_daily_stats(
        self,
        action: str,
        pnl: Optional[float] = None,
        is_win: Optional[bool] = None
    ):
        """Update daily statistics"""
        today = date.today()

        # Get or create daily stats record (with retry on UNIQUE constraint violation)
        stats = self.db.query(DailyStats).filter(
            DailyStats.date == today
        ).first()

        if not stats:
            # Use INSERT OR IGNORE for SQLite to handle race conditions
            from sqlalchemy import text
            from datetime import datetime as dt
            try:
                # Try to insert with OR IGNORE (SQLite specific - won't raise error if exists)
                now = dt.now()
                self.db.execute(text("""
                    INSERT OR IGNORE INTO daily_stats
                    (date, entry_count, exit_count, total_trades, error_count, total_pnl, total_commission, consecutive_losses, consecutive_wins, created_at, updated_at)
                    VALUES (:date, 0, 0, 0, 0, 0.0, 0.0, 0, 0, :now, NULL)
                """), {"date": today, "now": now})
                # Flush to sync with DB (OR IGNORE won't raise error)
                self.db.flush()
                logger.info(f"Executed INSERT OR IGNORE for daily_stats {today}")
            except Exception as e:
                logger.warning(f"Error in INSERT OR IGNORE: {e}")
                # Continue anyway - query might still find it

            # Query again to get the record (either newly created or existing)
            stats = self.db.query(DailyStats).filter(
                DailyStats.date == today
            ).first()

            if not stats:
                logger.error(f"Cannot find or create daily_stats for {today} even after INSERT OR IGNORE, skipping stats update")
                return  # Skip stats update rather than crash

        # Update counts
        if action == "buy":
            stats.entry_count += 1
        elif action == "sell":
            stats.exit_count += 1

        stats.total_trades += 1

        # Update PnL
        if pnl is not None:
            stats.total_pnl += pnl

            # Update consecutive wins/losses
            if is_win is not None:
                if is_win:
                    stats.consecutive_wins += 1
                    stats.consecutive_losses = 0
                else:
                    stats.consecutive_losses += 1
                    stats.consecutive_wins = 0

        # Note: commit is called by the caller (signals.py)
