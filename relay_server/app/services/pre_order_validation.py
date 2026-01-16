"""
Pre-Order Validation Service
5-level safety system for order validation before sending to Excel
"""
from typing import Dict, Any, List, Optional, Tuple
from sqlalchemy.orm import Session
from datetime import date
import re
import logging

from app.services.kill_switch import KillSwitchService
from app.services.market_hours import MarketHoursService
from app.services.cooldown import CooldownService
from app.services.blacklist import BlacklistService
from app.services.day_trading_check import DayTradingCheckService
from app.models import Position, DailyStats
from app.core.config import get_settings

logger = logging.getLogger(__name__)


class PreOrderValidationService:
    """
    Pre-order validation service implementing 5-level safety system
    """

    def __init__(self, db: Session):
        self.db = db
        self.settings = get_settings()
        self.kill_switch = KillSwitchService(db)
        self.market_hours = MarketHoursService()
        self.cooldown = CooldownService()
        self.blacklist = BlacklistService(db)
        self.day_trading_check = DayTradingCheckService(db)

    def validate_order(
        self,
        ticker: str,
        action: str,
        quantity: int,
        price_type: str = "market"
    ) -> Tuple[bool, str, Dict[str, str]]:
        """
        Validate order through 5-level safety system

        Args:
            ticker: Stock ticker code
            action: "buy" or "sell"
            quantity: Order quantity
            price_type: Price type (default: "market")

        Returns:
            Tuple of (allowed: bool, reason: str, checks: dict)
        """
        checks = {}

        # === Level 1: Kill Switch Check ===
        if not self.kill_switch.is_trading_enabled():
            checks["kill_switch"] = "BLOCKED"
            return False, "kill_switch_active", checks
        checks["kill_switch"] = "OK"

        # === Level 2: Market Hours Check ===
        if not self.market_hours.is_safe_trading_window():
            checks["market_hours"] = "BLOCKED"
            return False, "outside_trading_hours", checks
        checks["market_hours"] = "OK"

        # === Level 3: Parameter Validation ===
        param_valid, param_errors = self._validate_parameters(
            ticker, action, quantity, price_type
        )
        if not param_valid:
            checks["parameters"] = "BLOCKED"
            return False, f"parameter_validation_failed: {', '.join(param_errors)}", checks
        checks["parameters"] = "OK"

        # === Level 3.5: Day Trading Check (差金決済チェック) ===
        day_trading_ok, day_trading_reason = self.day_trading_check.check_day_trading(
            ticker, action
        )
        if not day_trading_ok:
            checks["day_trading"] = "BLOCKED"
            return False, f"day_trading_violation: {day_trading_reason}", checks
        checks["day_trading"] = "OK"

        # === Level 4: Daily Limits Check ===
        daily_limit_ok, daily_limit_reason = self._check_daily_limits(action)
        if not daily_limit_ok:
            checks["daily_limits"] = "BLOCKED"
            return False, daily_limit_reason, checks
        checks["daily_limits"] = "OK"

        # === Level 5: Risk Limits Check (for buy orders only) ===
        if action == "buy":
            risk_ok, risk_reason = self._check_risk_limits(ticker, quantity)
            if not risk_ok:
                checks["risk_limits"] = "BLOCKED"
                return False, risk_reason, checks
        checks["risk_limits"] = "OK"

        # === All checks passed ===
        return True, "all_checks_passed", checks

    def _validate_parameters(
        self,
        ticker: str,
        action: str,
        quantity: int,
        price_type: str
    ) -> Tuple[bool, List[str]]:
        """
        Validate all order parameters

        Returns:
            Tuple of (valid: bool, errors: list)
        """
        errors = []

        # 1. Ticker validation
        ticker_errors = self._validate_ticker(ticker)
        errors.extend(ticker_errors)

        # 2. Action validation
        action_errors = self._validate_action(action, ticker)
        errors.extend(action_errors)

        # 3. Quantity validation
        qty_errors = self._validate_quantity(quantity, ticker, action)
        errors.extend(qty_errors)

        # 4. Price type validation
        price_type_errors = self._validate_price_type(price_type)
        errors.extend(price_type_errors)

        return len(errors) == 0, errors

    def _validate_ticker(self, ticker: str) -> List[str]:
        """Validate ticker code"""
        errors = []

        # 1. Required check
        if not ticker:
            errors.append("Ticker is required")
            return errors

        # 2. Format check (4-digit number for Japanese stocks)
        if not re.match(r'^\d{4}$', ticker):
            errors.append(f"Invalid ticker format: {ticker} (must be 4-digit number)")

        # 3. Blacklist check
        if self.blacklist.is_blacklisted(ticker):
            errors.append(f"Ticker {ticker} is blacklisted")

        return errors

    def _validate_action(self, action: str, ticker: str) -> List[str]:
        """Validate buy/sell action"""
        errors = []

        # 1. Valid action check
        if action not in ["buy", "sell"]:
            errors.append(f"Invalid action: {action} (must be 'buy' or 'sell')")
            return errors

        # 2. For sell orders, check if position exists
        if action == "sell":
            position = self.db.query(Position).filter(
                Position.ticker == ticker,
                Position.quantity > 0
            ).first()

            if not position:
                errors.append(f"Cannot sell {ticker}: no position exists")

        return errors

    def _validate_quantity(self, quantity: int, ticker: str, action: str) -> List[str]:
        """Validate order quantity"""
        errors = []

        # 1. Required and positive check
        if quantity <= 0:
            errors.append("Quantity must be positive")
            return errors

        # 2. Unit check (must be multiple of 100 for Japanese stocks)
        if quantity % 100 != 0:
            errors.append(f"Quantity must be multiple of 100 (got {quantity})")

        # 3. Minimum check
        if quantity < 100:
            errors.append(f"Quantity too small: {quantity} (minimum 100)")

        # 4. Maximum check
        if quantity > 10000:
            errors.append(f"Quantity too large: {quantity} (maximum 10,000)")

        # 5. For sell orders, check available quantity
        if action == "sell":
            position = self.db.query(Position).filter(
                Position.ticker == ticker
            ).first()

            if position and quantity > position.quantity:
                errors.append(
                    f"Insufficient quantity to sell: {quantity} > {position.quantity}"
                )

        return errors

    def _validate_price_type(self, price_type: str) -> List[str]:
        """Validate price type"""
        errors = []

        # Only allow market orders for safety
        if price_type != "market":
            errors.append(f"Only market orders allowed (got {price_type})")

        return errors

    def _check_daily_limits(self, action: str) -> Tuple[bool, str]:
        """
        Check daily trading limits

        Returns:
            Tuple of (ok: bool, reason: str)
        """
        today = date.today()
        stats = self.db.query(DailyStats).filter(
            DailyStats.date == today
        ).first()

        if not stats:
            # No trades today, limits OK
            return True, ""

        risk_config = self.settings.risk_control

        # Check daily entry limit (for buy orders)
        if action == "buy":
            if stats.entry_count >= risk_config.max_daily_entries:
                return False, f"daily_entry_limit_exceeded: {stats.entry_count}/{risk_config.max_daily_entries}"

        # Check daily total trades limit
        if stats.total_trades >= risk_config.max_daily_trades:
            return False, f"daily_trade_limit_exceeded: {stats.total_trades}/{risk_config.max_daily_trades}"

        # Check hourly trade limit
        # TODO: Implement hourly tracking if needed

        return True, ""

    def _check_risk_limits(self, ticker: str, quantity: int) -> Tuple[bool, str]:
        """
        Check risk limits (position size, exposure, etc.)

        Returns:
            Tuple of (ok: bool, reason: str)
        """
        risk_config = self.settings.risk_control

        # 1. Check max open positions
        open_positions = self.db.query(Position).filter(
            Position.quantity > 0
        ).count()

        # Check if this is a new position (not adding to existing)
        existing_position = self.db.query(Position).filter(
            Position.ticker == ticker,
            Position.quantity > 0
        ).first()

        if not existing_position:
            # New position
            if open_positions >= risk_config.max_open_positions:
                return False, f"max_open_positions_exceeded: {open_positions}/{risk_config.max_open_positions}"

        # 2. Check total exposure (requires price estimation)
        # For now, we estimate using a conservative price per share
        # In production, this should fetch real-time price
        estimated_price_per_share = 1000  # Conservative estimate
        order_value = quantity * estimated_price_per_share

        current_exposure = sum(
            p.quantity * p.avg_cost
            for p in self.db.query(Position).filter(Position.quantity > 0).all()
        )

        total_exposure = current_exposure + order_value

        if total_exposure > risk_config.max_total_exposure:
            return False, f"max_total_exposure_exceeded: {total_exposure}/{risk_config.max_total_exposure}"

        # 3. Check per-ticker position limit
        if existing_position:
            new_position_value = (existing_position.quantity + quantity) * existing_position.avg_cost
        else:
            new_position_value = order_value

        if new_position_value > risk_config.max_position_per_ticker:
            return False, f"max_position_per_ticker_exceeded: {new_position_value}/{risk_config.max_position_per_ticker}"

        # 4. Check sector exposure (requires sector classification)
        # TODO: Implement sector exposure check if sector data is available

        # 5. Check daily loss limit
        today = date.today()
        stats = self.db.query(DailyStats).filter(
            DailyStats.date == today
        ).first()

        if stats and stats.total_pnl < risk_config.max_daily_loss:
            return False, f"max_daily_loss_exceeded: {stats.total_pnl}/{risk_config.max_daily_loss}"

        # All risk checks passed
        return True, ""
