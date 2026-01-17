"""
Configuration management for Kabuto Relay Server
"""
import yaml
from pathlib import Path
from typing import Optional, List
from pydantic import BaseModel
from pydantic_settings import BaseSettings


class ServerConfig(BaseModel):
    host: str = "0.0.0.0"
    port: int = 5000
    debug: bool = False
    workers: int = 4


class SecurityConfig(BaseModel):
    webhook_secret: str
    api_key: str
    admin_password: str
    allowed_ips: List[str] = []


class DatabaseConfig(BaseModel):
    url: str
    echo: bool = False


class RedisConfig(BaseModel):
    host: str = "localhost"
    port: int = 6379
    db: int = 0
    password: Optional[str] = None
    decode_responses: bool = True


class TestModeConfig(BaseModel):
    enabled: bool = False


class RiskControlConfig(BaseModel):
    max_total_exposure: int = 1000000
    max_position_per_ticker: int = 200000
    max_open_positions: int = 5
    max_sector_exposure_pct: float = 0.30
    max_daily_entries: int = 5
    max_daily_trades: int = 15
    max_trades_per_hour: int = 5
    max_consecutive_losses: int = 5
    max_daily_loss: int = -50000


class CooldownConfig(BaseModel):
    buy_same_ticker: int = 1800
    buy_any_ticker: int = 300
    sell_same_ticker: int = 900
    sell_any_ticker: int = 0


class SignalConfig(BaseModel):
    expiration_minutes: int = 15
    max_pending_signals: int = 100


class MarketHoursConfig(BaseModel):
    timezone: str = "Asia/Tokyo"
    safe_trading_windows: dict = {
        "morning": {"start": "09:30", "end": "11:20"},
        "afternoon": {"start": "13:00", "end": "14:30"}
    }
    off_hours_action: str = "REJECT"


class LoggingConfig(BaseModel):
    level: str = "INFO"
    format: str = "json"
    file: str = "./data/logs/kabuto_{time:YYYY-MM-DD}.log"
    rotation: str = "1 day"
    retention: str = "90 days"
    compression: str = "gz"


class AlertsConfig(BaseModel):
    enabled: bool = True
    slack_webhook_urls: dict = {
        "INFO": None,
        "WARNING": None,
        "ERROR": None,
        "CRITICAL": None
    }
    email_recipients: List[str] = []
    email_smtp_host: Optional[str] = None
    email_smtp_port: int = 587
    email_smtp_user: Optional[str] = None
    email_smtp_password: Optional[str] = None
    email_from: Optional[str] = None
    email_use_tls: bool = True
    # Notification frequency limits (minutes)
    frequency_limits: dict = {
        "WARNING": 30,
        "ERROR": 15,
        "INFO": 60
    }


class HeartbeatConfig(BaseModel):
    timeout_seconds: int = 300
    alert_enabled: bool = True


class Settings(BaseSettings):
    """Main settings class"""
    server: ServerConfig
    security: SecurityConfig
    database: DatabaseConfig
    redis: RedisConfig
    test_mode: TestModeConfig
    risk_control: RiskControlConfig
    cooldown: CooldownConfig
    signal: SignalConfig
    market_hours: MarketHoursConfig
    logging: LoggingConfig
    alerts: AlertsConfig
    heartbeat: HeartbeatConfig

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


def load_config(config_path: str = "config.yaml") -> Settings:
    """
    Load configuration from YAML file
    """
    config_file = Path(config_path)

    if not config_file.exists():
        raise FileNotFoundError(f"Configuration file not found: {config_path}")

    with open(config_file, "r", encoding="utf-8") as f:
        config_data = yaml.safe_load(f)

    return Settings(**config_data)


# Global settings instance
settings: Optional[Settings] = None


def get_settings() -> Settings:
    """Get global settings instance"""
    global settings
    if settings is None:
        settings = load_config()
    return settings
