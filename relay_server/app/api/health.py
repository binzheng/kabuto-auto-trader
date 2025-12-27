"""
Health and Status API endpoints
"""
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from datetime import datetime, date
import redis

from app.database import get_db
from app.schemas import HealthResponse, StatusResponse
from app.core.config import get_settings
from app.models import DailyStats, Position
from app.services.kill_switch import KillSwitchService
from app.services.market_hours import MarketHoursService

router = APIRouter()


@router.get("/health", response_model=HealthResponse)
async def health_check(db: Session = Depends(get_db)):
    """
    Health check endpoint

    Returns system health status
    """
    settings = get_settings()

    # Check database
    try:
        db.execute("SELECT 1")
        db_status = "OK"
    except Exception as e:
        db_status = f"ERROR: {str(e)}"

    # Check Redis
    try:
        redis_config = settings.redis
        r = redis.Redis(
            host=redis_config.host,
            port=redis_config.port,
            db=redis_config.db,
            password=redis_config.password
        )
        r.ping()
        redis_status = "OK"
    except Exception as e:
        redis_status = f"ERROR: {str(e)}"

    # Determine overall status
    overall_status = "healthy" if (db_status == "OK" and redis_status == "OK") else "unhealthy"

    return HealthResponse(
        status=overall_status,
        timestamp=datetime.now(),
        version="1.0.0",
        database=db_status,
        redis=redis_status
    )


@router.get("/status", response_model=StatusResponse)
async def get_status(db: Session = Depends(get_db)):
    """
    Get comprehensive system status

    Returns trading status, daily stats, and risk metrics
    """
    # Get kill switch status
    kill_switch = KillSwitchService(db)
    trading_enabled = kill_switch.is_trading_enabled()

    # Get market hours status
    market_hours = MarketHoursService()
    market_open = market_hours.is_safe_trading_window()

    # Get daily stats
    today = date.today()
    stats = db.query(DailyStats).filter(DailyStats.date == today).first()

    if stats:
        daily_stats = {
            "entry_count": stats.entry_count,
            "exit_count": stats.exit_count,
            "total_trades": stats.total_trades,
            "total_pnl": stats.total_pnl,
            "consecutive_losses": stats.consecutive_losses,
            "error_count": stats.error_count
        }
    else:
        daily_stats = {
            "entry_count": 0,
            "exit_count": 0,
            "total_trades": 0,
            "total_pnl": 0,
            "consecutive_losses": 0,
            "error_count": 0
        }

    # Get risk metrics
    positions = db.query(Position).all()
    total_exposure = sum(p.quantity * p.avg_cost for p in positions)
    open_positions = len(positions)

    settings = get_settings()
    risk_config = settings.risk_control

    risk_metrics = {
        "total_exposure": total_exposure,
        "max_total_exposure": risk_config.max_total_exposure,
        "exposure_utilization_pct": (total_exposure / risk_config.max_total_exposure * 100) if risk_config.max_total_exposure > 0 else 0,
        "open_positions": open_positions,
        "max_open_positions": risk_config.max_open_positions,
        "daily_entries": daily_stats["entry_count"],
        "max_daily_entries": risk_config.max_daily_entries
    }

    return StatusResponse(
        status="active" if trading_enabled else "disabled",
        trading_enabled=trading_enabled,
        market_open=market_open,
        daily_stats=daily_stats,
        risk_metrics=risk_metrics,
        timestamp=datetime.now()
    )
