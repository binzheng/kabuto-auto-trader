"""
Webhook API endpoints - Receive signals from TradingView
"""
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
import hashlib
import json

from app.database import get_db
from app.schemas import WebhookSignal, WebhookResponse, ErrorResponse
from app.models import Signal, SignalState, Position
from app.core.config import get_settings
from app.core.logging import log_signal_received, log_risk_violation, logger
from app.services.deduplication import DeduplicationService
from app.services.cooldown import CooldownService
from app.services.market_hours import MarketHoursService
from app.services.risk_control import RiskControlService
from app.services.csv_logger import CSVLoggerService

router = APIRouter()


def generate_signal_id(signal: WebhookSignal) -> str:
    """
    Generate unique signal ID

    Format: sig_YYYYMMDD_HHMMSS_TICKER_ACTION
    """
    now = datetime.now()
    timestamp_str = now.strftime("%Y%m%d_%H%M%S")
    return f"sig_{timestamp_str}_{signal.ticker}_{signal.action}"


def generate_checksum(signal: WebhookSignal, signal_id: str) -> str:
    """
    Generate checksum for signal integrity
    """
    core_fields = {
        "signal_id": signal_id,
        "action": signal.action,
        "ticker": signal.ticker,
        "quantity": signal.quantity,
        "entry_price": signal.entry_price,
        "stop_loss": signal.stop_loss,
        "take_profit": signal.take_profit
    }

    canonical = json.dumps(core_fields, sort_keys=True, separators=(',', ':'))
    return hashlib.sha256(canonical.encode('utf-8')).hexdigest()[:16]


@router.post("/webhook", response_model=WebhookResponse)
async def receive_webhook(
    signal: WebhookSignal,
    request: Request,
    db: Session = Depends(get_db)
):
    """
    Receive trading signal from TradingView webhook

    This is the main entry point for signals
    """
    settings = get_settings()

    # 1. Validate passphrase
    if signal.passphrase != settings.security.webhook_secret:
        logger.warning(f"Invalid passphrase from {request.client.host}")
        raise HTTPException(status_code=401, detail="Invalid passphrase")

    # 2. Deduplication check
    dedup_service = DeduplicationService()
    idempotency_key = dedup_service.generate_idempotency_key(
        signal.timestamp,
        signal.ticker,
        signal.action
    )

    if dedup_service.is_duplicate(idempotency_key):
        # Return cached response
        cached = dedup_service.get_cached_response(idempotency_key)
        if cached:
            logger.info(f"Duplicate request detected: {idempotency_key}")
            return WebhookResponse(**cached)

    # 3. Market hours check
    market_hours_service = MarketHoursService()
    market_check = market_hours_service.should_accept_signal()

    if not market_check["accept"]:
        if market_check["action"] == "REJECT":
            log_risk_violation(f"market_hours_{market_check['reason']}", signal.ticker)
            raise HTTPException(
                status_code=400,
                detail=f"Signal rejected: {market_check['reason']}"
            )
        # QUEUE action will be handled below

    # 4. Generate signal ID
    signal_id = generate_signal_id(signal)

    # 5. Cooldown check
    cooldown_service = CooldownService()
    cooldown_result = cooldown_service.check_cooldown(signal.ticker, signal.action)

    if not cooldown_result["allowed"]:
        log_risk_violation(f"cooldown_{cooldown_result['reason']}", signal.ticker)
        raise HTTPException(
            status_code=429,
            detail=f"Cooldown active: {cooldown_result['reason']}, retry after {cooldown_result['retry_after']}s"
        )

    # 6. Position check for sell signals
    # TradingViewは内部ポジション状態を知らないため、リレーサーバー側で実際のポジションを確認
    if signal.action == "sell":
        position = db.query(Position).filter(Position.ticker == signal.ticker).first()
        if not position:
            logger.warning(f"Sell signal rejected: No position for {signal.ticker}")
            log_risk_violation("no_position_to_sell", signal.ticker)
            raise HTTPException(
                status_code=400,
                detail=f"Cannot sell {signal.ticker}: No position held"
            )
        elif position.quantity < signal.quantity:
            logger.warning(f"Sell signal rejected: Insufficient position for {signal.ticker} (have {position.quantity}, trying to sell {signal.quantity})")
            log_risk_violation("insufficient_position", signal.ticker)
            raise HTTPException(
                status_code=400,
                detail=f"Cannot sell {signal.quantity} shares of {signal.ticker}: Only {position.quantity} shares held"
            )

    # 7. Generate checksum
    checksum = generate_checksum(signal, signal_id)

    # 8. Create signal in database
    expires_at = datetime.now() + timedelta(minutes=settings.signal.expiration_minutes)

    db_signal = Signal(
        signal_id=signal_id,
        action=signal.action,
        ticker=signal.ticker,
        quantity=signal.quantity,
        price=signal.price,
        entry_price=signal.entry_price,
        stop_loss=signal.stop_loss,
        take_profit=signal.take_profit,
        atr=signal.atr,
        rr_ratio=signal.rr_ratio,
        rsi=signal.rsi,
        state=SignalState.PENDING,
        checksum=checksum,
        passphrase_valid=True,
        expires_at=expires_at
    )

    db.add(db_signal)
    db.commit()
    db.refresh(db_signal)

    # 9. Log to CSV file
    csv_logger = CSVLoggerService()
    csv_logger.log_signal(
        signal_data={
            "signal_id": signal_id,
            "action": signal.action,
            "ticker": signal.ticker,
            "quantity": signal.quantity,
            "price": signal.price,
            "entry_price": signal.entry_price,
            "stop_loss": signal.stop_loss,
            "take_profit": signal.take_profit,
            "atr": signal.atr,
            "rr_ratio": signal.rr_ratio,
            "rsi": signal.rsi,
            "checksum": checksum,
            "state": SignalState.PENDING.value
        },
        source_ip=request.client.host
    )

    # 10. Set cooldown
    cooldown_service.set_cooldown(signal.ticker, signal.action)

    # 11. Log signal received
    log_signal_received(
        signal_id=signal_id,
        ticker=signal.ticker,
        action=signal.action,
        quantity=signal.quantity,
        entry_price=signal.entry_price
    )

    # 12. Prepare response
    response_data = {
        "status": "success",
        "signal_id": signal_id,
        "message": "Signal received and queued",
        "timestamp": datetime.now()
    }

    # Cache response for idempotency
    dedup_service.mark_processed(idempotency_key, response_data)

    return WebhookResponse(**response_data)


@router.post("/webhook/test", response_model=WebhookResponse)
async def test_webhook(
    signal: WebhookSignal,
    request: Request,
    db: Session = Depends(get_db)
):
    """
    Test webhook endpoint (dry run - doesn't create signal)

    Useful for testing TradingView webhook configuration
    """
    settings = get_settings()

    # Validate passphrase
    if signal.passphrase != settings.security.webhook_secret:
        logger.warning(f"Test webhook: Invalid passphrase from {request.client.host}")
        raise HTTPException(status_code=401, detail="Invalid passphrase")

    logger.info(f"Test webhook received: {signal.action} {signal.ticker}")

    return WebhookResponse(
        status="test_success",
        signal_id="test_signal_id",
        message="Test webhook received successfully (dry run)",
        timestamp=datetime.now()
    )
