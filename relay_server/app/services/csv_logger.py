"""
CSV Logger Service - Record signals to CSV file
"""
import csv
import os
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Dict, Any
from threading import Lock

from app.core.logging import logger

# JST timezone
JST = timezone(timedelta(hours=9))


class CSVLoggerService:
    """
    CSV file logging service for signals
    """

    def __init__(self, csv_path: str = None):
        """
        Initialize CSV logger

        Args:
            csv_path: Path to CSV file (default: data/logs/signals.csv)
        """
        if csv_path is None:
            base_dir = Path(__file__).parent.parent.parent
            csv_path = base_dir / "data" / "logs" / "signals.csv"

        self.csv_path = Path(csv_path)
        self.lock = Lock()

        # Ensure directory exists
        self.csv_path.parent.mkdir(parents=True, exist_ok=True)

        # Initialize CSV file with header if it doesn't exist
        if not self.csv_path.exists():
            self._write_header()

    def _write_header(self):
        """Write CSV header"""
        header = [
            "timestamp",
            "signal_id",
            "action",
            "ticker",
            "quantity",
            "price",
            "entry_price",
            "stop_loss",
            "take_profit",
            "atr",
            "rr_ratio",
            "rsi",
            "checksum",
            "state",
            "source_ip"
        ]

        try:
            with open(self.csv_path, 'w', newline='', encoding='utf-8') as f:
                writer = csv.writer(f)
                writer.writerow(header)
            logger.info(f"CSV log file initialized: {self.csv_path}")
        except Exception as e:
            logger.error(f"Failed to initialize CSV file: {e}")

    def log_signal(self, signal_data: Dict[str, Any], source_ip: str = None):
        """
        Log signal to CSV file

        Args:
            signal_data: Signal data dictionary
            source_ip: Source IP address
        """
        try:
            with self.lock:
                # Use JST timezone
                jst_now = datetime.now(JST)
                row = [
                    jst_now.strftime("%Y-%m-%d %H:%M:%S"),
                    signal_data.get("signal_id", ""),
                    signal_data.get("action", ""),
                    signal_data.get("ticker", ""),
                    signal_data.get("quantity", ""),
                    signal_data.get("price", ""),
                    signal_data.get("entry_price", ""),
                    signal_data.get("stop_loss", ""),
                    signal_data.get("take_profit", ""),
                    signal_data.get("atr", ""),
                    signal_data.get("rr_ratio", ""),
                    signal_data.get("rsi", ""),
                    signal_data.get("checksum", ""),
                    signal_data.get("state", "PENDING"),
                    source_ip or ""
                ]

                # Append to CSV file
                with open(self.csv_path, 'a', newline='', encoding='utf-8') as f:
                    writer = csv.writer(f)
                    writer.writerow(row)

                logger.debug(f"Signal logged to CSV: {signal_data.get('signal_id')}")

        except Exception as e:
            logger.error(f"Failed to log signal to CSV: {e}")

    def update_signal_state(self, signal_id: str, new_state: str):
        """
        Update signal state in CSV (Note: This reads entire file and rewrites)

        Args:
            signal_id: Signal ID to update
            new_state: New state value
        """
        try:
            with self.lock:
                # Read all rows
                rows = []
                with open(self.csv_path, 'r', newline='', encoding='utf-8') as f:
                    reader = csv.reader(f)
                    rows = list(reader)

                # Update matching row
                updated = False
                for i, row in enumerate(rows):
                    if i == 0:  # Skip header
                        continue
                    if len(row) > 1 and row[1] == signal_id:  # signal_id is column 1
                        row[13] = new_state  # state is column 13
                        updated = True
                        break

                if updated:
                    # Write back
                    with open(self.csv_path, 'w', newline='', encoding='utf-8') as f:
                        writer = csv.writer(f)
                        writer.writerows(rows)
                    logger.debug(f"Updated signal state in CSV: {signal_id} -> {new_state}")

        except Exception as e:
            logger.error(f"Failed to update signal state in CSV: {e}")

    def get_csv_path(self) -> str:
        """Get CSV file path"""
        return str(self.csv_path.absolute())
