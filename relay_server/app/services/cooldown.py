"""
Cooldown Service - Layer 2 defense using Redis
"""
import redis
from datetime import datetime, timedelta
from typing import Dict

from app.core.config import get_settings
from app.core.logging import logger


class CooldownService:
    """
    Cooldown management using Redis
    """

    def __init__(self):
        self.settings = get_settings()
        redis_config = self.settings.redis
        self.cooldown_config = self.settings.cooldown

        self.redis_client = redis.Redis(
            host=redis_config.host,
            port=redis_config.port,
            db=redis_config.db,
            password=redis_config.password,
            decode_responses=redis_config.decode_responses
        )

    def check_cooldown(self, ticker: str, action: str) -> Dict[str, any]:
        """
        Check if action is allowed based on cooldown rules

        Returns:
            {"allowed": True/False, "reason": str, "retry_after": int}
        """
        # Get cooldown duration
        if action == "buy":
            same_ticker_cooldown = self.cooldown_config.buy_same_ticker
            any_ticker_cooldown = self.cooldown_config.buy_any_ticker
        else:  # sell
            same_ticker_cooldown = self.cooldown_config.sell_same_ticker
            any_ticker_cooldown = self.cooldown_config.sell_any_ticker

        # Check same ticker cooldown
        if same_ticker_cooldown > 0:
            same_ticker_key = f"cooldown:{action}:{ticker}"
            if self.redis_client.exists(same_ticker_key):
                ttl = self.redis_client.ttl(same_ticker_key)
                logger.warning(f"Cooldown active for {action} {ticker}, retry after {ttl}s")
                return {
                    "allowed": False,
                    "reason": f"cooldown_same_ticker",
                    "retry_after": ttl
                }

        # Check any ticker cooldown
        if any_ticker_cooldown > 0:
            any_ticker_key = f"cooldown:{action}:*"
            # Get all keys matching pattern
            keys = self.redis_client.keys(f"cooldown:{action}:*")
            if keys:
                # Find the one with longest TTL
                max_ttl = 0
                for key in keys:
                    ttl = self.redis_client.ttl(key)
                    if ttl > max_ttl:
                        max_ttl = ttl

                if max_ttl > 0:
                    logger.warning(f"Cooldown active for any {action}, retry after {max_ttl}s")
                    return {
                        "allowed": False,
                        "reason": f"cooldown_any_ticker",
                        "retry_after": max_ttl
                    }

        return {"allowed": True, "reason": "no_cooldown", "retry_after": 0}

    def set_cooldown(self, ticker: str, action: str):
        """
        Set cooldown timer after action

        Args:
            ticker: Stock ticker
            action: buy or sell
        """
        try:
            if action == "buy":
                same_ticker_cooldown = self.cooldown_config.buy_same_ticker
                any_ticker_cooldown = self.cooldown_config.buy_any_ticker
            else:  # sell
                same_ticker_cooldown = self.cooldown_config.sell_same_ticker
                any_ticker_cooldown = self.cooldown_config.sell_any_ticker

            # Set same ticker cooldown
            if same_ticker_cooldown > 0:
                same_ticker_key = f"cooldown:{action}:{ticker}"
                self.redis_client.setex(same_ticker_key, same_ticker_cooldown, "1")
                logger.debug(f"Set cooldown for {action} {ticker}: {same_ticker_cooldown}s")

            # Set any ticker cooldown
            if any_ticker_cooldown > 0:
                any_ticker_key = f"cooldown:{action}:global"
                self.redis_client.setex(any_ticker_key, any_ticker_cooldown, "1")
                logger.debug(f"Set global cooldown for {action}: {any_ticker_cooldown}s")

        except Exception as e:
            logger.error(f"Redis error in set_cooldown: {e}")

    def reset_cooldown(self, ticker: str, action: str):
        """
        Reset cooldown timer (for manual intervention)

        Args:
            ticker: Stock ticker (use "*" for all)
            action: buy or sell (use "*" for all)
        """
        try:
            if ticker == "*" and action == "*":
                # Reset all cooldowns
                keys = self.redis_client.keys("cooldown:*")
            elif ticker == "*":
                # Reset all cooldowns for action
                keys = self.redis_client.keys(f"cooldown:{action}:*")
            elif action == "*":
                # Reset all cooldowns for ticker
                keys = self.redis_client.keys(f"cooldown:*:{ticker}")
            else:
                # Reset specific cooldown
                keys = [f"cooldown:{action}:{ticker}"]

            if keys:
                self.redis_client.delete(*keys)
                logger.info(f"Reset cooldown: action={action}, ticker={ticker}")

        except Exception as e:
            logger.error(f"Redis error in reset_cooldown: {e}")

    def get_all_cooldowns(self) -> Dict[str, int]:
        """
        Get all active cooldowns with remaining time

        Returns:
            {"cooldown:buy:9984": 120, ...}
        """
        try:
            cooldowns = {}
            keys = self.redis_client.keys("cooldown:*")

            for key in keys:
                ttl = self.redis_client.ttl(key)
                if ttl > 0:
                    cooldowns[key] = ttl

            return cooldowns

        except Exception as e:
            logger.error(f"Redis error in get_all_cooldowns: {e}")
            return {}
