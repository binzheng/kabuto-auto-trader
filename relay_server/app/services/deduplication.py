"""
Deduplication Service - Layer 1 defense using Redis
"""
import hashlib
import redis
from typing import Optional, Dict
from datetime import datetime

from app.core.config import get_settings
from app.core.logging import logger


class DeduplicationService:
    """
    Idempotency and deduplication using Redis
    """

    def __init__(self):
        self.settings = get_settings()
        redis_config = self.settings.redis

        self.redis_client = redis.Redis(
            host=redis_config.host,
            port=redis_config.port,
            db=redis_config.db,
            password=redis_config.password,
            decode_responses=redis_config.decode_responses
        )

        # TTL for idempotency keys (5 minutes)
        self.idempotency_ttl = 300

    def generate_idempotency_key(
        self,
        timestamp: str,
        ticker: str,
        action: str
    ) -> str:
        """
        Generate idempotency key from signal components

        Format: idempotency:<hash>
        """
        components = [timestamp, ticker, action]
        key_string = "|".join(str(c) for c in components)
        hash_value = hashlib.sha256(key_string.encode()).hexdigest()
        return f"idempotency:{hash_value}"

    def is_duplicate(self, idempotency_key: str) -> bool:
        """
        Check if request is duplicate

        Returns:
            True if duplicate, False if new
        """
        try:
            return self.redis_client.exists(idempotency_key) > 0
        except Exception as e:
            logger.error(f"Redis error in is_duplicate: {e}")
            # Fail-safe: if Redis is down, allow the request
            return False

    def mark_processed(
        self,
        idempotency_key: str,
        response_data: Optional[Dict] = None
    ):
        """
        Mark request as processed and cache response

        Args:
            idempotency_key: The idempotency key
            response_data: Optional response data to cache
        """
        try:
            if response_data:
                import json
                self.redis_client.setex(
                    idempotency_key,
                    self.idempotency_ttl,
                    json.dumps(response_data)
                )
            else:
                self.redis_client.setex(
                    idempotency_key,
                    self.idempotency_ttl,
                    "processed"
                )

            logger.debug(f"Marked as processed: {idempotency_key}")
        except Exception as e:
            logger.error(f"Redis error in mark_processed: {e}")

    def get_cached_response(self, idempotency_key: str) -> Optional[Dict]:
        """
        Get cached response for duplicate request

        Returns:
            Cached response data or None
        """
        try:
            cached = self.redis_client.get(idempotency_key)
            if cached and cached != "processed":
                import json
                return json.loads(cached)
            return None
        except Exception as e:
            logger.error(f"Redis error in get_cached_response: {e}")
            return None

    def cleanup_expired(self):
        """
        Cleanup expired keys (handled automatically by Redis TTL)
        """
        pass
