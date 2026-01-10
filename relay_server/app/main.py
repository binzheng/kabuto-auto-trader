"""
Kabuto Relay Server - Main FastAPI Application
"""
from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import time
from datetime import datetime

from app.core.config import get_settings
from app.core.logging import setup_logging, log_api_request, logger
from app.core.notification import init_notification_manager
from app.database import init_database
from app.redis_client import init_redis
from app.api import webhook, signals, health, admin


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Lifespan context manager for startup and shutdown events
    """
    # Startup
    logger.info("=" * 60)
    logger.info("Kabuto Relay Server Starting...")
    logger.info("=" * 60)

    # Initialize logging
    setup_logging()
    logger.info("Logging initialized")

    # Load settings
    settings = get_settings()
    logger.info(f"Configuration loaded from config.yaml")

    # Initialize database
    init_database()
    logger.info("Database initialized")

    # Initialize Redis
    try:
        redis_client = init_redis()
        logger.info(f"Redis initialized: {settings.redis.host}:{settings.redis.port}")
    except Exception as e:
        logger.error(f"Failed to initialize Redis: {e}")
        logger.warning("Continuing without Redis (some features may be disabled)")
        redis_client = None

    # Initialize notification manager
    try:
        init_notification_manager(settings, redis_client)
        logger.info("Notification manager initialized")
    except Exception as e:
        logger.error(f"Failed to initialize notification manager: {e}")
        logger.warning("Continuing without notifications")

    logger.info(f"Server: {settings.server.host}:{settings.server.port}")
    logger.info(f"Database: {settings.database.url}")
    logger.info(f"Redis: {settings.redis.host}:{settings.redis.port}")

    logger.info("=" * 60)
    logger.info("Kabuto Relay Server Started Successfully")
    logger.info("=" * 60)

    yield

    # Shutdown
    logger.info("Shutting down Kabuto Relay Server...")


# Create FastAPI application
app = FastAPI(
    title="Kabuto Relay Server",
    description="Relay server for Japanese stock automated trading system",
    version="1.0.0",
    lifespan=lifespan
)

# CORS middleware (for web dashboard if needed)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Adjust for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Request logging middleware
@app.middleware("http")
async def log_requests(request: Request, call_next):
    """
    Log all HTTP requests
    """
    start_time = time.time()

    # Process request
    response = await call_next(request)

    # Calculate duration
    duration_ms = (time.time() - start_time) * 1000

    # Log request
    log_api_request(
        endpoint=request.url.path,
        method=request.method,
        status_code=response.status_code,
        client_ip=request.client.host,
        duration_ms=duration_ms
    )

    return response


# Exception handlers
@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    """
    Handle validation errors
    """
    logger.error(f"Validation error: {exc.errors()}")

    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={
            "status": "error",
            "error_code": "VALIDATION_ERROR",
            "error_message": "Invalid request data",
            "details": exc.errors(),
            "timestamp": datetime.now().isoformat()
        }
    )


@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception):
    """
    Handle general exceptions
    """
    logger.error(f"Unhandled exception: {str(exc)}", exc_info=True)

    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={
            "status": "error",
            "error_code": "INTERNAL_SERVER_ERROR",
            "error_message": "An internal error occurred",
            "details": str(exc),
            "timestamp": datetime.now().isoformat()
        }
    )


# Include routers
app.include_router(webhook.router, tags=["Webhook"])
app.include_router(signals.router, prefix="/api", tags=["Signals"])
app.include_router(health.router, tags=["Health"])
app.include_router(admin.router, prefix="/api", tags=["Admin"])

# Also mount heartbeat at root level for convenience
app.include_router(admin.router, tags=["Heartbeat"], include_in_schema=False)


# Root endpoint
@app.get("/")
async def root():
    """
    Root endpoint - API information
    """
    settings = get_settings()

    return {
        "name": "Kabuto Relay Server",
        "version": "1.0.0",
        "status": "running",
        "timestamp": datetime.now().isoformat(),
        "endpoints": {
            "webhook": "/webhook",
            "signals": "/api/signals/pending",
            "health": "/health",
            "status": "/status",
            "docs": "/docs",
            "redoc": "/redoc"
        }
    }


# Health check endpoint (duplicate for convenience)
@app.get("/ping")
async def ping():
    """
    Simple ping endpoint
    """
    return {"status": "pong", "timestamp": datetime.now().isoformat()}


if __name__ == "__main__":
    import uvicorn

    settings = get_settings()

    # SQLite does not support multi-process writes safely.
    workers = 1 if settings.database.url.startswith("sqlite") else settings.server.workers

    uvicorn.run(
        "app.main:app",
        host=settings.server.host,
        port=settings.server.port,
        reload=settings.server.debug,
        workers=1 if settings.server.debug else workers
    )
