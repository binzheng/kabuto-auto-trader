"""
Signals API endpoints - Excel Pull API
"""
from fastapi import APIRouter, Depends, HTTPException, Header
from sqlalchemy.orm import Session
from datetime import datetime
from typing import Optional

from app.database import get_db
from app.schemas import (
    SignalListResponse, SignalResponse,
    SignalAcknowledgeRequest, SignalAcknowledgeResponse,
    SignalExecutionRequest, SignalExecutionResponse,
    SignalFailureRequest, SignalFailureResponse,
    ErrorResponse
)
from app.models import Signal, SignalState, ExecutionLog, Position
from app.core.config import get_settings
from app.core.logging import log_order_executed, log_risk_violation, logger
from app.services.risk_control import RiskControlService
from app.services.pre_order_validation import PreOrderValidationService

router = APIRouter()


def verify_api_key(authorization: str = Header(...)) -> bool:
    """
    Verify API key from Authorization header

    Expects: Bearer <api_key>
    """
    settings = get_settings()

    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid authorization header")

    api_key = authorization.replace("Bearer ", "")

    if api_key != settings.security.api_key:
        raise HTTPException(status_code=401, detail="Invalid API key")

    return True


@router.get("/signals/pending", response_model=SignalListResponse)
async def get_pending_signals(
    db: Session = Depends(get_db),
    authorized: bool = Depends(verify_api_key)
):
    """
    Get list of pending signals (not yet fetched by Excel)

    Excel VBA polls this endpoint every 5 seconds

    **Important**: This endpoint performs 5-level safety validation
    before returning signals. Only validated signals are sent to Excel.
    """
    # Query pending signals that haven't expired
    signals = db.query(Signal).filter(
        Signal.state == SignalState.PENDING,
        Signal.expires_at > datetime.now()
    ).order_by(Signal.created_at.asc()).all()

    if not signals:
        # Return 204 No Content
        from fastapi.responses import Response
        return Response(status_code=204)

    # Initialize validation service
    validator = PreOrderValidationService(db)

    # Validate each signal through 5-level safety system
    validated_signals = []

    for s in signals:
        # Perform 5-level safety validation
        allowed, reason, checks = validator.validate_order(
            ticker=s.ticker,
            action=s.action,
            quantity=s.quantity,
            price_type="market"
        )

        if allowed:
            # Signal passed validation
            validated_signals.append(s)
            logger.info(f"Signal {s.signal_id} passed 5-level validation: {checks}")
        else:
            # Signal failed validation - mark as FAILED
            logger.warning(
                f"Signal {s.signal_id} failed validation: {reason}. "
                f"Checks: {checks}"
            )
            s.state = SignalState.FAILED
            s.error_message = f"Pre-order validation failed: {reason}"
            log_risk_violation(reason, s.ticker)

    # Commit any rejected signals
    db.commit()

    if not validated_signals:
        # No validated signals to return
        from fastapi.responses import Response
        return Response(status_code=204)

    # Convert validated signals to response schema
    signal_list = [
        SignalResponse(
            signal_id=s.signal_id,
            action=s.action,
            ticker=s.ticker,
            quantity=s.quantity,
            price=s.price,
            entry_price=s.entry_price,
            stop_loss=s.stop_loss,
            take_profit=s.take_profit,
            atr=s.atr,
            state=s.state.value,
            created_at=s.created_at,
            expires_at=s.expires_at,
            checksum=s.checksum
        )
        for s in validated_signals
    ]

    return SignalListResponse(
        status="success",
        timestamp=datetime.now(),
        count=len(signal_list),
        signals=signal_list
    )


@router.post("/signals/{signal_id}/ack", response_model=SignalAcknowledgeResponse)
async def acknowledge_signal(
    signal_id: str,
    request: SignalAcknowledgeRequest,
    db: Session = Depends(get_db),
    authorized: bool = Depends(verify_api_key)
):
    """
    Acknowledge signal fetch (mark as FETCHED)

    Excel VBA calls this after successfully receiving the signal
    """
    # Find signal
    signal = db.query(Signal).filter(Signal.signal_id == signal_id).first()

    if not signal:
        raise HTTPException(status_code=404, detail="Signal not found")

    # Verify checksum
    if signal.checksum != request.checksum:
        logger.error(f"Checksum mismatch for signal {signal_id}")
        raise HTTPException(status_code=400, detail="Checksum mismatch")

    # Idempotency: if already fetched, return success
    if signal.state == SignalState.FETCHED:
        logger.info(f"Signal already acknowledged: {signal_id}")
        return SignalAcknowledgeResponse(
            status="success",
            signal_id=signal_id,
            state="fetched",
            acknowledged_at=signal.fetched_at
        )

    # Update signal state
    signal.state = SignalState.FETCHED
    signal.fetched_by = request.client_id
    signal.fetched_at = datetime.now()

    db.commit()

    logger.info(f"Signal acknowledged: {signal_id} by {request.client_id}")

    return SignalAcknowledgeResponse(
        status="success",
        signal_id=signal_id,
        state="fetched",
        acknowledged_at=signal.fetched_at
    )


@router.post("/signals/{signal_id}/executed", response_model=SignalExecutionResponse)
async def report_execution(
    signal_id: str,
    request: SignalExecutionRequest,
    db: Session = Depends(get_db),
    authorized: bool = Depends(verify_api_key)
):
    """
    Report signal execution (mark as EXECUTED)

    Excel VBA calls this after successfully executing the order via RSS
    """
    # Find signal
    signal = db.query(Signal).filter(Signal.signal_id == signal_id).first()

    if not signal:
        raise HTTPException(status_code=404, detail="Signal not found")

    # Idempotency: prevent double execution
    if signal.state == SignalState.EXECUTED:
        logger.warning(f"Signal already executed: {signal_id}")
        raise HTTPException(status_code=409, detail="Signal already executed")

    # Update signal state
    signal.state = SignalState.EXECUTED
    signal.executed_at = request.executed_at
    signal.execution_price = request.execution_price
    signal.order_id = request.order_id

    # Create execution log
    execution_id = f"EXE_{request.executed_at.strftime('%Y%m%d_%H%M%S')}_{signal.ticker}"

    execution_log = ExecutionLog(
        execution_id=execution_id,
        signal_id=signal_id,
        order_id=request.order_id,
        action=signal.action,
        ticker=signal.ticker,
        quantity=request.execution_quantity,
        price=request.execution_price,
        commission=0,  # TODO: Calculate commission
        total_amount=request.execution_price * request.execution_quantity,
        position_effect="open" if signal.action == "buy" else "close",
        executed_at=request.executed_at
    )

    db.add(execution_log)

    # Update position
    _update_position(db, signal, request)

    # Update daily stats
    risk_service = RiskControlService(db)
    risk_service.update_daily_stats(signal.action)

    db.commit()

    # Log execution
    log_order_executed(
        signal_id=signal_id,
        order_id=request.order_id,
        ticker=signal.ticker,
        execution_price=request.execution_price,
        quantity=request.execution_quantity
    )

    return SignalExecutionResponse(
        status="success",
        signal_id=signal_id,
        state="executed",
        execution_logged=True
    )


@router.post("/signals/{signal_id}/failed", response_model=SignalFailureResponse)
async def report_failure(
    signal_id: str,
    request: SignalFailureRequest,
    db: Session = Depends(get_db),
    authorized: bool = Depends(verify_api_key)
):
    """
    Report signal execution failure

    Excel VBA calls this if RSS.ORDER() fails
    """
    # Find signal
    signal = db.query(Signal).filter(Signal.signal_id == signal_id).first()

    if not signal:
        raise HTTPException(status_code=404, detail="Signal not found")

    # Update signal state
    signal.state = SignalState.FAILED
    signal.error_message = request.error

    db.commit()

    logger.error(f"Signal execution failed: {signal_id} - {request.error}")

    # TODO: Send alert

    return SignalFailureResponse(
        status="failure_recorded",
        message=f"Signal {signal_id} marked as failed"
    )


@router.get("/signals/{signal_id}", response_model=SignalResponse)
async def get_signal_by_id(
    signal_id: str,
    db: Session = Depends(get_db),
    authorized: bool = Depends(verify_api_key)
):
    """
    Get specific signal by ID

    Useful for Excel VBA to re-fetch signal after crash/restart
    """
    signal = db.query(Signal).filter(Signal.signal_id == signal_id).first()

    if not signal:
        raise HTTPException(status_code=404, detail="Signal not found")

    return SignalResponse(
        signal_id=signal.signal_id,
        action=signal.action,
        ticker=signal.ticker,
        quantity=signal.quantity,
        price=signal.price,
        entry_price=signal.entry_price,
        stop_loss=signal.stop_loss,
        take_profit=signal.take_profit,
        atr=signal.atr,
        state=signal.state.value,
        created_at=signal.created_at,
        expires_at=signal.expires_at,
        checksum=signal.checksum
    )


def _update_position(
    db: Session,
    signal: Signal,
    request: SignalExecutionRequest
):
    """
    Update position after execution

    Args:
        db: Database session
        signal: Signal object
        request: Execution request
    """
    if signal.action == "buy":
        # Buy: add to position
        position = db.query(Position).filter(
            Position.ticker == signal.ticker
        ).first()

        if position:
            # Update existing position
            total_cost = (position.quantity * position.avg_cost) + (request.execution_quantity * request.execution_price)
            total_quantity = position.quantity + request.execution_quantity
            position.avg_cost = total_cost / total_quantity
            position.quantity = total_quantity
        else:
            # Create new position
            position = Position(
                ticker=signal.ticker,
                ticker_name=None,  # TODO: Get ticker name
                quantity=request.execution_quantity,
                avg_cost=request.execution_price,
                sector=None,  # TODO: Get sector
                entry_signal_id=signal.signal_id
            )
            db.add(position)

    elif signal.action == "sell":
        # Sell: reduce or close position
        position = db.query(Position).filter(
            Position.ticker == signal.ticker
        ).first()

        if position:
            if position.quantity <= request.execution_quantity:
                # Close position
                db.delete(position)
            else:
                # Reduce position
                position.quantity -= request.execution_quantity

    db.commit()
