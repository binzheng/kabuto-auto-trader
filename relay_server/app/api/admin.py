"""
Admin API endpoints
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas import KillSwitchRequest, KillSwitchResponse, HeartbeatRequest, HeartbeatResponse
from app.models import Heartbeat
from app.core.config import get_settings
from app.core.logging import logger
from app.services.kill_switch import KillSwitchService
from datetime import datetime

router = APIRouter()


@router.post("/admin/kill-switch", response_model=KillSwitchResponse)
async def toggle_kill_switch(
    request: KillSwitchRequest,
    db: Session = Depends(get_db)
):
    """
    Toggle kill switch (emergency stop)

    Requires admin password
    """
    settings = get_settings()

    # Verify admin password
    if request.password != settings.security.admin_password:
        logger.warning("Kill switch: Invalid admin password")
        raise HTTPException(status_code=401, detail="Invalid admin password")

    kill_switch = KillSwitchService(db)

    if request.enabled:
        # Deactivate kill switch (enable trading)
        result = kill_switch.deactivate("admin")
        message = "Trading enabled"
    else:
        # Activate kill switch (disable trading)
        reason = request.reason or "Manual activation by admin"
        result = kill_switch.activate("admin", reason)
        message = f"Trading disabled: {reason}"

    return KillSwitchResponse(
        status="success",
        trading_enabled=request.enabled,
        message=message,
        timestamp=datetime.now()
    )


@router.get("/admin/kill-switch/status", response_model=KillSwitchResponse)
async def get_kill_switch_status(db: Session = Depends(get_db)):
    """
    Get kill switch status (no authentication required for read)
    """
    kill_switch = KillSwitchService(db)
    status = kill_switch.get_status()

    return KillSwitchResponse(
        status="success",
        trading_enabled=status["trading_enabled"],
        message="Trading enabled" if status["trading_enabled"] else f"Trading disabled: {status.get('reason', 'Unknown')}",
        timestamp=datetime.now()
    )


@router.post("/heartbeat", response_model=HeartbeatResponse)
async def receive_heartbeat(
    request: HeartbeatRequest,
    db: Session = Depends(get_db)
):
    """
    Receive heartbeat from Excel VBA client

    Tracks client liveness
    """
    # Update or create heartbeat record
    heartbeat = db.query(Heartbeat).filter(
        Heartbeat.client_id == request.client_id
    ).first()

    if heartbeat:
        heartbeat.last_heartbeat = request.timestamp
        heartbeat.status = "active"
    else:
        heartbeat = Heartbeat(
            client_id=request.client_id,
            last_heartbeat=request.timestamp,
            status="active"
        )
        db.add(heartbeat)

    db.commit()

    logger.debug(f"Heartbeat received from {request.client_id}")

    return HeartbeatResponse(
        status="success",
        message=f"Heartbeat acknowledged for {request.client_id}"
    )


@router.get("/admin/heartbeats")
async def get_all_heartbeats(db: Session = Depends(get_db)):
    """
    Get all client heartbeats

    Monitor client liveness
    """
    heartbeats = db.query(Heartbeat).all()

    result = []
    for hb in heartbeats:
        # Check if client is inactive (no heartbeat for 5 minutes)
        time_since_last = (datetime.now() - hb.last_heartbeat).total_seconds()
        is_active = time_since_last < 300  # 5 minutes

        result.append({
            "client_id": hb.client_id,
            "last_heartbeat": hb.last_heartbeat.isoformat(),
            "status": "active" if is_active else "inactive",
            "seconds_since_last": int(time_since_last)
        })

    return {
        "status": "success",
        "count": len(result),
        "heartbeats": result
    }
