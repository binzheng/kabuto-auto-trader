"""
Database models for Kabuto Relay Server
"""
from sqlalchemy import Column, String, Integer, Float, Boolean, DateTime, Enum as SQLEnum, Text, JSON
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.sql import func
from datetime import datetime
from enum import Enum

Base = declarative_base()


class SignalState(str, Enum):
    """Signal state enumeration"""
    PENDING = "pending"
    FETCHED = "fetched"
    EXECUTED = "executed"
    FAILED = "failed"
    EXPIRED = "expired"


class Signal(Base):
    """
    Signal model - stores trading signals from TradingView
    """
    __tablename__ = "signals"

    signal_id = Column(String(100), primary_key=True, index=True)
    action = Column(String(10), nullable=False)  # buy / sell
    ticker = Column(String(10), nullable=False, index=True)
    quantity = Column(Integer, nullable=False)
    price = Column(String(20), default="market")
    entry_price = Column(Float, nullable=False)
    stop_loss = Column(Float)
    take_profit = Column(Float)
    atr = Column(Float)
    rr_ratio = Column(Float)
    rsi = Column(Float)

    # State management
    state = Column(SQLEnum(SignalState), default=SignalState.PENDING, index=True)
    fetched_by = Column(String(50))
    fetched_at = Column(DateTime(timezone=True))
    executed_at = Column(DateTime(timezone=True))
    execution_price = Column(Float)
    order_id = Column(String(100))

    # Metadata
    checksum = Column(String(50))
    passphrase_valid = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)
    expires_at = Column(DateTime(timezone=True), index=True)
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    # Error tracking
    error_message = Column(Text)

    def __repr__(self):
        return f"<Signal(signal_id='{self.signal_id}', action='{self.action}', ticker='{self.ticker}', state='{self.state}')>"


class Position(Base):
    """
    Position model - tracks current positions
    """
    __tablename__ = "positions"

    id = Column(Integer, primary_key=True, autoincrement=True)
    ticker = Column(String(10), unique=True, nullable=False, index=True)
    ticker_name = Column(String(100))
    quantity = Column(Integer, nullable=False)
    avg_cost = Column(Float, nullable=False)
    sector = Column(String(50))

    # Entry information
    entry_signal_id = Column(String(100))
    entry_date = Column(DateTime(timezone=True), server_default=func.now())

    # Timestamps
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    def __repr__(self):
        return f"<Position(ticker='{self.ticker}', quantity={self.quantity}, avg_cost={self.avg_cost})>"


class ExecutionLog(Base):
    """
    Execution log - records all executed trades
    """
    __tablename__ = "execution_log"

    id = Column(Integer, primary_key=True, autoincrement=True)
    execution_id = Column(String(100), unique=True, nullable=False, index=True)
    signal_id = Column(String(100), nullable=False, index=True)
    order_id = Column(String(100), index=True)

    action = Column(String(10), nullable=False)
    ticker = Column(String(10), nullable=False, index=True)
    quantity = Column(Integer, nullable=False)
    price = Column(Float, nullable=False)
    commission = Column(Float, default=0)
    total_amount = Column(Float)

    # PnL
    position_effect = Column(String(10))  # open / close
    realized_pnl = Column(Float)

    # Timestamps
    executed_at = Column(DateTime(timezone=True), nullable=False, index=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    def __repr__(self):
        return f"<ExecutionLog(execution_id='{self.execution_id}', ticker='{self.ticker}', action='{self.action}')>"


class DailyStats(Base):
    """
    Daily statistics - tracks daily limits and metrics
    """
    __tablename__ = "daily_stats"

    id = Column(Integer, primary_key=True, autoincrement=True)
    date = Column(DateTime(timezone=True), unique=True, nullable=False, index=True)

    # Counts
    entry_count = Column(Integer, default=0)
    exit_count = Column(Integer, default=0)
    total_trades = Column(Integer, default=0)
    error_count = Column(Integer, default=0)

    # Financial
    total_pnl = Column(Float, default=0)
    total_commission = Column(Float, default=0)
    consecutive_losses = Column(Integer, default=0)
    consecutive_wins = Column(Integer, default=0)

    # Timestamps
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    def __repr__(self):
        return f"<DailyStats(date='{self.date}', entry_count={self.entry_count}, total_pnl={self.total_pnl})>"


class Blacklist(Base):
    """
    Blacklist - tracks blacklisted tickers
    """
    __tablename__ = "blacklist"

    id = Column(Integer, primary_key=True, autoincrement=True)
    ticker = Column(String(10), unique=True, nullable=False, index=True)
    ticker_name = Column(String(100))
    reason = Column(Text, nullable=False)
    blacklist_type = Column(String(20), nullable=False)  # permanent / temporary / dynamic

    # Expiration
    added_at = Column(DateTime(timezone=True), server_default=func.now())
    expires_at = Column(DateTime(timezone=True))
    added_by = Column(String(50), default="auto")

    # Metadata
    metadata_json = Column("metadata", JSON)

    def __repr__(self):
        return f"<Blacklist(ticker='{self.ticker}', type='{self.blacklist_type}', reason='{self.reason}')>"


class SystemState(Base):
    """
    System state - stores global system state
    """
    __tablename__ = "system_state"

    key = Column(String(50), primary_key=True)
    value = Column(Text, nullable=False)
    value_type = Column(String(20), default="string")  # string / int / float / bool / json
    description = Column(Text)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    def __repr__(self):
        return f"<SystemState(key='{self.key}', value='{self.value}')>"


class Heartbeat(Base):
    """
    Heartbeat - tracks client heartbeats
    """
    __tablename__ = "heartbeat"

    id = Column(Integer, primary_key=True, autoincrement=True)
    client_id = Column(String(50), unique=True, nullable=False, index=True)
    last_heartbeat = Column(DateTime(timezone=True), nullable=False)
    status = Column(String(20), default="active")  # active / inactive / error

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    def __repr__(self):
        return f"<Heartbeat(client_id='{self.client_id}', last_heartbeat='{self.last_heartbeat}')>"
