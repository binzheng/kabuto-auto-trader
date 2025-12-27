"""
Pydantic schemas for request/response validation
"""
from pydantic import BaseModel, Field, validator
from typing import Optional, List
from datetime import datetime
from enum import Enum


# ========== Enums ==========

class ActionType(str, Enum):
    BUY = "buy"
    SELL = "sell"


class SignalStateEnum(str, Enum):
    PENDING = "pending"
    FETCHED = "fetched"
    EXECUTED = "executed"
    FAILED = "failed"
    EXPIRED = "expired"


class PriceType(str, Enum):
    MARKET = "market"
    LIMIT = "limit"


# ========== Webhook Schemas ==========

class WebhookSignal(BaseModel):
    """
    Signal from TradingView webhook
    """
    action: ActionType
    ticker: str = Field(..., min_length=4, max_length=10)
    quantity: int = Field(..., gt=0)
    price: str = Field(default="market")
    entry_price: float = Field(..., gt=0)
    stop_loss: Optional[float] = Field(default=None, gt=0)
    take_profit: Optional[float] = Field(default=None, gt=0)
    atr: Optional[float] = Field(default=None, gt=0)
    rr_ratio: Optional[float] = Field(default=None)
    rsi: Optional[float] = Field(default=None, ge=0, le=100)
    timestamp: str
    passphrase: str

    @validator("ticker")
    def ticker_must_be_numeric(cls, v):
        """Validate ticker is numeric (Japanese stock codes)"""
        if not v.isdigit():
            raise ValueError("Ticker must be numeric for Japanese stocks")
        return v

    class Config:
        json_schema_extra = {
            "example": {
                "action": "buy",
                "ticker": "9984",
                "quantity": 100,
                "price": "market",
                "entry_price": 3000.50,
                "stop_loss": 2940.25,
                "take_profit": 3120.75,
                "atr": 30.12,
                "rr_ratio": 2.0,
                "rsi": 62.5,
                "timestamp": "1735279200000",
                "passphrase": "your-secret-passphrase"
            }
        }


class WebhookResponse(BaseModel):
    """
    Response for webhook requests
    """
    status: str
    signal_id: str
    message: str
    timestamp: datetime


# ========== Signal Schemas ==========

class SignalResponse(BaseModel):
    """
    Signal response for Excel Pull API
    """
    signal_id: str
    action: str
    ticker: str
    quantity: int
    price: str
    entry_price: float
    stop_loss: Optional[float]
    take_profit: Optional[float]
    atr: Optional[float]
    state: str
    created_at: datetime
    expires_at: datetime
    checksum: str

    class Config:
        from_attributes = True


class SignalListResponse(BaseModel):
    """
    List of signals response
    """
    status: str
    timestamp: datetime
    count: int
    signals: List[SignalResponse]


class SignalAcknowledgeRequest(BaseModel):
    """
    Request to acknowledge signal fetch
    """
    client_id: str
    checksum: str


class SignalAcknowledgeResponse(BaseModel):
    """
    Response for signal acknowledgment
    """
    status: str
    signal_id: str
    state: str
    acknowledged_at: datetime


class SignalExecutionRequest(BaseModel):
    """
    Request to report signal execution
    """
    client_id: str
    execution_price: float = Field(..., gt=0)
    execution_quantity: int = Field(..., gt=0)
    order_id: str
    executed_at: datetime


class SignalExecutionResponse(BaseModel):
    """
    Response for signal execution report
    """
    status: str
    signal_id: str
    state: str
    execution_logged: bool


class SignalFailureRequest(BaseModel):
    """
    Request to report signal execution failure
    """
    client_id: str
    error: str


class SignalFailureResponse(BaseModel):
    """
    Response for signal failure report
    """
    status: str
    message: str


# ========== Position Schemas ==========

class PositionResponse(BaseModel):
    """
    Position response
    """
    ticker: str
    ticker_name: Optional[str]
    quantity: int
    avg_cost: float
    sector: Optional[str]
    entry_date: datetime

    class Config:
        from_attributes = True


class PositionListResponse(BaseModel):
    """
    List of positions response
    """
    status: str
    count: int
    total_exposure: float
    positions: List[PositionResponse]


# ========== System Schemas ==========

class HealthResponse(BaseModel):
    """
    Health check response
    """
    status: str
    timestamp: datetime
    version: str
    database: str
    redis: str


class StatusResponse(BaseModel):
    """
    System status response
    """
    status: str
    trading_enabled: bool
    market_open: bool
    daily_stats: dict
    risk_metrics: dict
    timestamp: datetime


class KillSwitchRequest(BaseModel):
    """
    Request to toggle kill switch
    """
    password: str
    enabled: bool
    reason: Optional[str] = None


class KillSwitchResponse(BaseModel):
    """
    Response for kill switch operation
    """
    status: str
    trading_enabled: bool
    message: str
    timestamp: datetime


# ========== Heartbeat Schemas ==========

class HeartbeatRequest(BaseModel):
    """
    Heartbeat request from client
    """
    client_id: str
    timestamp: datetime


class HeartbeatResponse(BaseModel):
    """
    Heartbeat response
    """
    status: str
    message: str


# ========== Error Schemas ==========

class ErrorResponse(BaseModel):
    """
    Standard error response
    """
    status: str = "error"
    error_code: str
    error_message: str
    details: Optional[dict] = None
    timestamp: datetime

    class Config:
        json_schema_extra = {
            "example": {
                "status": "error",
                "error_code": "VALIDATION_ERROR",
                "error_message": "Invalid ticker format",
                "details": {"field": "ticker", "value": "INVALID"},
                "timestamp": "2025-12-27T09:35:10+09:00"
            }
        }
