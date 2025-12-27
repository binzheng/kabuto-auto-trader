"""
Logging configuration for Kabuto Relay Server
"""
import sys
import json
from pathlib import Path
from loguru import logger
from datetime import datetime
from typing import Dict, Any

from app.core.config import get_settings


def serialize_log_record(record: Dict[str, Any]) -> str:
    """
    Serialize log record to JSON format
    """
    log_entry = {
        "timestamp": record["time"].strftime("%Y-%m-%dT%H:%M:%S.%f%z"),
        "level": record["level"].name,
        "module": record["name"],
        "function": record["function"],
        "line": record["line"],
        "message": record["message"],
    }

    # Add extra fields if present
    if record.get("extra"):
        log_entry["extra"] = record["extra"]

    return json.dumps(log_entry, ensure_ascii=False)


def setup_logging():
    """
    Setup logging configuration
    """
    settings = get_settings()
    log_config = settings.logging

    # Remove default logger
    logger.remove()

    # Create log directory if it doesn't exist
    log_file_path = Path(log_config.file)
    log_file_path.parent.mkdir(parents=True, exist_ok=True)

    # Console logger (human-readable)
    logger.add(
        sys.stdout,
        level=log_config.level,
        format="<green>{time:YYYY-MM-DD HH:mm:ss}</green> | <level>{level: <8}</level> | <cyan>{name}</cyan>:<cyan>{function}</cyan>:<cyan>{line}</cyan> - <level>{message}</level>",
        colorize=True,
    )

    # File logger (JSON format)
    if log_config.format == "json":
        logger.add(
            log_config.file,
            level=log_config.level,
            rotation=log_config.rotation,
            retention=log_config.retention,
            compression=log_config.compression,
            serialize=True,
            format="{message}",
            enqueue=True,
        )
    else:
        logger.add(
            log_config.file,
            level=log_config.level,
            rotation=log_config.rotation,
            retention=log_config.retention,
            compression=log_config.compression,
            format="{time:YYYY-MM-DD HH:mm:ss} | {level: <8} | {name}:{function}:{line} - {message}",
            enqueue=True,
        )

    logger.info("Logging initialized")


def log_api_request(
    endpoint: str,
    method: str,
    status_code: int,
    client_ip: str,
    duration_ms: float,
    **kwargs
):
    """
    Log API request
    """
    logger.info(
        f"API Request: {method} {endpoint}",
        extra={
            "endpoint": endpoint,
            "method": method,
            "status_code": status_code,
            "client_ip": client_ip,
            "duration_ms": duration_ms,
            **kwargs
        }
    )


def log_signal_received(signal_id: str, ticker: str, action: str, **kwargs):
    """
    Log signal received from TradingView
    """
    logger.info(
        f"Signal received: {signal_id} - {action} {ticker}",
        extra={
            "signal_id": signal_id,
            "ticker": ticker,
            "action": action,
            **kwargs
        }
    )


def log_order_executed(signal_id: str, order_id: str, ticker: str, **kwargs):
    """
    Log order execution
    """
    logger.info(
        f"Order executed: {order_id} (Signal: {signal_id})",
        extra={
            "signal_id": signal_id,
            "order_id": order_id,
            "ticker": ticker,
            **kwargs
        }
    )


def log_risk_violation(reason: str, ticker: str = None, **kwargs):
    """
    Log risk control violation
    """
    logger.warning(
        f"Risk violation: {reason}",
        extra={
            "reason": reason,
            "ticker": ticker,
            **kwargs
        }
    )


def log_error(error_type: str, message: str, **kwargs):
    """
    Log error
    """
    logger.error(
        f"{error_type}: {message}",
        extra={
            "error_type": error_type,
            "message": message,
            **kwargs
        }
    )


def log_critical_alert(alert_type: str, message: str, **kwargs):
    """
    Log critical alert
    """
    logger.critical(
        f"CRITICAL ALERT [{alert_type}]: {message}",
        extra={
            "alert_type": alert_type,
            "message": message,
            **kwargs
        }
    )
