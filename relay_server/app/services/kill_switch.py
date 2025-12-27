"""
Kill Switch Service - Emergency stop mechanism
"""
from sqlalchemy.orm import Session
from datetime import datetime
from typing import Optional, Dict

from app.models import SystemState
from app.core.logging import logger, log_critical_alert


class KillSwitchService:
    """
    Kill switch - manual and automatic trading halt
    """

    def __init__(self, db: Session):
        self.db = db
        self.KEY_TRADING_ENABLED = "trading_enabled"
        self.KEY_KILL_SWITCH_REASON = "kill_switch_reason"
        self.KEY_KILL_SWITCH_ACTIVATED_AT = "kill_switch_activated_at"
        self.KEY_KILL_SWITCH_ACTIVATED_BY = "kill_switch_activated_by"

    def is_trading_enabled(self) -> bool:
        """
        Check if trading is enabled

        Returns:
            True if trading enabled, False if kill switch active
        """
        state = self._get_state(self.KEY_TRADING_ENABLED)

        if state is None:
            # Default to enabled
            self._set_state(self.KEY_TRADING_ENABLED, "true", "bool")
            return True

        return state.value.lower() == "true"

    def activate(
        self,
        activated_by: str,
        reason: str
    ) -> Dict[str, any]:
        """
        Activate kill switch (disable trading)

        Args:
            activated_by: Who activated (manual / auto_trigger)
            reason: Reason for activation

        Returns:
            Result dictionary
        """
        # Set trading disabled
        self._set_state(self.KEY_TRADING_ENABLED, "false", "bool")
        self._set_state(self.KEY_KILL_SWITCH_REASON, reason, "string")
        self._set_state(self.KEY_KILL_SWITCH_ACTIVATED_AT, datetime.now().isoformat(), "string")
        self._set_state(self.KEY_KILL_SWITCH_ACTIVATED_BY, activated_by, "string")

        self.db.commit()

        # Log critical alert
        log_critical_alert(
            "kill_switch_activated",
            f"Kill switch activated by {activated_by}: {reason}"
        )

        logger.critical(f"KILL SWITCH ACTIVATED by {activated_by}: {reason}")

        # TODO: Send emergency alerts (Slack, Email)
        # self._send_emergency_alerts(activated_by, reason)

        return {
            "status": "kill_switch_activated",
            "activated_by": activated_by,
            "reason": reason,
            "timestamp": datetime.now().isoformat()
        }

    def deactivate(
        self,
        deactivated_by: str
    ) -> Dict[str, any]:
        """
        Deactivate kill switch (enable trading)

        Args:
            deactivated_by: Who deactivated

        Returns:
            Result dictionary
        """
        # Set trading enabled
        self._set_state(self.KEY_TRADING_ENABLED, "true", "bool")
        self._set_state(self.KEY_KILL_SWITCH_REASON, "", "string")

        self.db.commit()

        logger.warning(f"Kill switch deactivated by {deactivated_by}")

        return {
            "status": "kill_switch_deactivated",
            "deactivated_by": deactivated_by,
            "timestamp": datetime.now().isoformat()
        }

    def get_status(self) -> Dict[str, any]:
        """
        Get kill switch status

        Returns:
            Status dictionary
        """
        enabled = self.is_trading_enabled()

        if enabled:
            return {
                "trading_enabled": True,
                "kill_switch_active": False
            }
        else:
            reason = self._get_state(self.KEY_KILL_SWITCH_REASON)
            activated_at = self._get_state(self.KEY_KILL_SWITCH_ACTIVATED_AT)
            activated_by = self._get_state(self.KEY_KILL_SWITCH_ACTIVATED_BY)

            return {
                "trading_enabled": False,
                "kill_switch_active": True,
                "reason": reason.value if reason else "Unknown",
                "activated_at": activated_at.value if activated_at else None,
                "activated_by": activated_by.value if activated_by else "Unknown"
            }

    def _get_state(self, key: str) -> Optional[SystemState]:
        """
        Get system state value

        Args:
            key: State key

        Returns:
            SystemState or None
        """
        return self.db.query(SystemState).filter(
            SystemState.key == key
        ).first()

    def _set_state(
        self,
        key: str,
        value: str,
        value_type: str = "string"
    ):
        """
        Set system state value

        Args:
            key: State key
            value: State value
            value_type: Value type (string/int/float/bool/json)
        """
        state = self._get_state(key)

        if state:
            state.value = value
            state.value_type = value_type
            state.updated_at = datetime.now()
        else:
            state = SystemState(
                key=key,
                value=value,
                value_type=value_type
            )
            self.db.add(state)

        self.db.commit()
