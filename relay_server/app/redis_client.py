"""
Redis client setup and management
"""
import redis
from typing import Optional

from app.core.config import get_settings

# Global Redis client
_redis_client: Optional[redis.Redis] = None


def init_redis() -> redis.Redis:
    """
    Initialize Redis client connection

    Returns:
        Redis client instance
    """
    global _redis_client

    settings = get_settings()
    redis_config = settings.redis

    _redis_client = redis.Redis(
        host=redis_config.host,
        port=redis_config.port,
        db=redis_config.db,
        password=redis_config.password,
        decode_responses=redis_config.decode_responses
    )

    # Test connection
    _redis_client.ping()

    return _redis_client


def get_redis() -> redis.Redis:
    """
    Get Redis client instance

    Returns:
        Redis client instance

    Raises:
        RuntimeError: If Redis client is not initialized
    """
    if _redis_client is None:
        raise RuntimeError("Redis client not initialized. Call init_redis() first.")

    return _redis_client
