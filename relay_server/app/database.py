"""
Database setup and session management
"""
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session
from sqlalchemy.pool import StaticPool
from contextlib import contextmanager
from typing import Generator

from app.core.config import get_settings
from app.models import Base

# Global engine and session maker
engine = None
SessionLocal = None


def init_database():
    """
    Initialize database connection and create tables
    """
    global engine, SessionLocal

    settings = get_settings()

    # Create engine
    if settings.database.url.startswith("sqlite"):
        # SQLite configuration
        engine = create_engine(
            settings.database.url,
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
            echo=settings.database.echo,
        )
    else:
        # PostgreSQL or other databases
        engine = create_engine(
            settings.database.url,
            pool_pre_ping=True,
            echo=settings.database.echo,
        )

    # Create session factory
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

    # Create all tables
    Base.metadata.create_all(bind=engine)


def get_db() -> Generator[Session, None, None]:
    """
    Dependency to get database session
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


@contextmanager
def get_db_context():
    """
    Context manager for database session
    """
    db = SessionLocal()
    try:
        yield db
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()
