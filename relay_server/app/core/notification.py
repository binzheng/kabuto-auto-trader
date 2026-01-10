"""
Kabuto Auto Trader - Notification Module
Slack / Email notification functionality
"""

import requests
import json
from typing import Dict, List, Any, Optional
from datetime import datetime, timedelta
import logging
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import redis

logger = logging.getLogger(__name__)


class SlackNotifier:
    """Slack通知クラス"""

    def __init__(self, webhook_urls: Dict[str, str]):
        """
        Args:
            webhook_urls: レベル別のWebhook URL辞書
                例: {'INFO': 'https://...', 'WARNING': 'https://...'}
        """
        self.webhook_urls = webhook_urls

    def send(
        self,
        level: str,
        title: str,
        fields: List[Dict[str, Any]],
        mention_channel: bool = False
    ) -> bool:
        """
        Slack通知を送信

        Args:
            level: 通知レベル（INFO/WARNING/ERROR/CRITICAL）
            title: タイトル
            fields: フィールドのリスト
            mention_channel: @channel メンションするか

        Returns:
            送信成功: True、失敗: False
        """
        webhook_url = self.webhook_urls.get(level)
        if not webhook_url:
            logger.warning(f"Slack webhook URL not configured for level: {level}")
            return False

        payload = self._build_payload(level, title, fields, mention_channel)

        try:
            response = requests.post(
                webhook_url,
                data=json.dumps(payload),
                headers={'Content-Type': 'application/json'},
                timeout=10
            )

            if response.status_code == 200:
                logger.info(f"Slack notification sent: {title}")
                return True
            else:
                logger.error(f"Slack notification failed: HTTP {response.status_code}")
                return False

        except Exception as e:
            logger.error(f"Slack notification error: {e}")
            return False

    def _build_payload(
        self,
        level: str,
        title: str,
        fields: List[Dict[str, Any]],
        mention_channel: bool
    ) -> Dict[str, Any]:
        """Slackペイロードを構築"""

        colors = {
            'INFO': '#36a64f',
            'WARNING': 'warning',
            'ERROR': 'danger',
            'CRITICAL': '#FF0000'
        }

        icons = {
            'INFO': ':information_source:',
            'WARNING': ':warning:',
            'ERROR': ':x:',
            'CRITICAL': ':rotating_light:'
        }

        prefixes = {
            'INFO': 'ℹ️',
            'WARNING': '⚠️',
            'ERROR': '🚨',
            'CRITICAL': '🚨🚨🚨'
        }

        payload = {
            'username': 'Kabuto Auto Trader',
            'icon_emoji': icons.get(level, ':robot:'),
            'attachments': [{
                'color': colors.get(level, '#36a64f'),
                'title': f"{prefixes.get(level, '')} {title}",
                'fields': fields,
                'footer': 'Kabuto Auto Trader',
                'ts': int(datetime.now().timestamp())
            }]
        }

        if mention_channel:
            payload['text'] = '@channel'

        return payload


class EmailNotifier:
    """メール通知クラス"""

    def __init__(self, smtp_config: Dict[str, Any]):
        """
        Args:
            smtp_config: SMTP設定辞書
                例: {
                    'server': 'smtp.gmail.com',
                    'port': 587,
                    'use_tls': True,
                    'username': 'user@example.com',
                    'password': 'password',
                    'from': 'sender@example.com',
                    'to': 'recipient@example.com'
                }
        """
        self.smtp_config = smtp_config

    def send(
        self,
        level: str,
        title: str,
        fields: List[Dict[str, Any]]
    ) -> bool:
        """
        メール通知を送信

        Args:
            level: 通知レベル
            title: タイトル
            fields: フィールドのリスト

        Returns:
            送信成功: True、失敗: False
        """
        try:
            # メール作成
            msg = MIMEMultipart('alternative')
            msg['Subject'] = f"[Kabuto] {level.upper()} - {title}"
            msg['From'] = self.smtp_config['from']
            msg['To'] = self.smtp_config['to']

            # HTML本文
            html_body = self._build_html_body(level, title, fields)
            msg.attach(MIMEText(html_body, 'html'))

            # SMTP送信
            with smtplib.SMTP(
                self.smtp_config['server'],
                self.smtp_config['port']
            ) as server:
                if self.smtp_config.get('use_tls', True):
                    server.starttls()

                if self.smtp_config.get('username'):
                    server.login(
                        self.smtp_config['username'],
                        self.smtp_config['password']
                    )

                server.send_message(msg)

            logger.info(f"Email notification sent: {title}")
            return True

        except Exception as e:
            logger.error(f"Email notification error: {e}")
            return False

    def _build_html_body(
        self,
        level: str,
        title: str,
        fields: List[Dict[str, Any]]
    ) -> str:
        """HTML本文を構築"""

        level_classes = {
            'WARNING': 'warning',
            'ERROR': 'error',
            'CRITICAL': 'critical'
        }

        icons = {
            'WARNING': '⚠️',
            'ERROR': '🚨',
            'CRITICAL': '🚨🚨🚨'
        }

        fields_html = ''
        for field in fields:
            value = str(field['value']).replace('\n', '<br>')
            fields_html += f'''
            <div class="field">
                <div class="field-title">{field['title']}</div>
                <div class="field-value">{value}</div>
            </div>
            '''

        html = f'''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body {{ font-family: Arial, sans-serif; }}
        .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
        .header {{ background-color: #f44336; color: white; padding: 20px; border-radius: 5px; }}
        .header.warning {{ background-color: #ff9800; }}
        .header.error {{ background-color: #f44336; }}
        .header.critical {{ background-color: #d32f2f; }}
        .content {{ padding: 20px; background-color: #f5f5f5; margin-top: 20px; border-radius: 5px; }}
        .field {{ margin-bottom: 15px; }}
        .field-title {{ font-weight: bold; color: #333; }}
        .field-value {{ color: #666; margin-top: 5px; }}
        .footer {{ margin-top: 20px; padding-top: 20px; border-top: 1px solid #ddd; color: #999; font-size: 12px; }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header {level_classes.get(level, 'error')}">
            <h1>{icons.get(level, '🚨')} {title}</h1>
        </div>
        <div class="content">
            {fields_html}
        </div>
        <div class="footer">
            <p>Kabuto Auto Trader</p>
            <p>発生時刻: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
        </div>
    </div>
</body>
</html>
        '''

        return html


class NotificationManager:
    """通知マネージャー"""

    def __init__(self,
                 slack_notifier: Optional[SlackNotifier] = None,
                 email_notifier: Optional[EmailNotifier] = None,
                 redis_client: Optional[redis.Redis] = None,
                 frequency_limits: Optional[Dict[str, int]] = None):
        self.slack = slack_notifier
        self.email = email_notifier
        self.redis = redis_client
        self.frequency_limits = frequency_limits or {
            'WARNING': 30,
            'ERROR': 15,
            'INFO': 60
        }

    def _should_send_notification(self, level: str, title: str) -> bool:
        """
        通知頻度制限チェック

        Args:
            level: 通知レベル
            title: 通知のタイトル

        Returns:
            送信すべきか: True、抑止: False
        """
        # CRITICAL は常に送信
        if level == 'CRITICAL':
            return True

        # Redis が利用できない場合は常に送信
        if not self.redis:
            return True

        key = f"notification:last:{level}:{title}"

        try:
            last_notify_time_str = self.redis.get(key)

            if not last_notify_time_str:
                # 初回通知
                return True

            last_notify_time = datetime.fromisoformat(last_notify_time_str.decode() if isinstance(last_notify_time_str, bytes) else last_notify_time_str)
            elapsed_minutes = (datetime.now() - last_notify_time).total_seconds() / 60

            interval_minutes = self.frequency_limits.get(level, 30)

            return elapsed_minutes >= interval_minutes

        except Exception as e:
            logger.error(f"Error checking notification frequency: {e}")
            return True

    def _record_notification(self, level: str, title: str):
        """
        通知時刻を記録

        Args:
            level: 通知レベル
            title: 通知のタイトル
        """
        if not self.redis:
            return

        key = f"notification:last:{level}:{title}"
        try:
            # 24時間保持
            self.redis.setex(key, 86400, datetime.now().isoformat())
        except Exception as e:
            logger.error(f"Error recording notification: {e}")

    def notify(
        self,
        level: str,
        title: str,
        fields: List[Dict[str, Any]],
        mention_channel: bool = False,
        force: bool = False
    ):
        """
        レベルに応じて通知を送信

        Args:
            level: 通知レベル
            title: タイトル
            fields: フィールドのリスト
            mention_channel: @channel メンションするか
            force: 頻度制限を無視して送信
        """
        # 頻度制限チェック
        if not force and not self._should_send_notification(level, title):
            logger.info(f"Notification suppressed (frequency limit): {title}")
            return

        # Slack通知
        if self.slack:
            self.slack.send(level, title, fields, mention_channel)

        # メール通知（ERROR以上）
        if self.email and level in ['ERROR', 'CRITICAL']:
            self.email.send(level, title, fields)

        # 通知時刻を記録
        self._record_notification(level, title)

    def notify_signal_generation_failed(self, error: Exception):
        """信号生成失敗を通知"""
        fields = [
            {'title': 'エラー種別', 'value': type(error).__name__, 'short': True},
            {'title': 'エラーメッセージ', 'value': str(error), 'short': True}
        ]
        self.notify('ERROR', '信号生成失敗', fields)

    def notify_system_started(self):
        """システム起動を通知"""
        fields = [
            {'title': '起動時刻', 'value': datetime.now().strftime('%Y-%m-%d %H:%M:%S'), 'short': True}
        ]
        self.notify('INFO', 'システム起動', fields)

    def notify_system_stopped(self, reason: str):
        """システム停止を通知"""
        fields = [
            {'title': '停止理由', 'value': reason, 'short': False},
            {'title': '停止時刻', 'value': datetime.now().strftime('%Y-%m-%d %H:%M:%S'), 'short': True}
        ]
        self.notify('ERROR', 'システム停止', fields)

    def notify_heartbeat_missed(self, client_id: str, last_heartbeat: datetime):
        """Heartbeat途絶を通知"""
        elapsed = (datetime.now() - last_heartbeat).total_seconds() / 60

        fields = [
            {'title': 'クライアントID', 'value': client_id, 'short': True},
            {'title': '最終Heartbeat', 'value': last_heartbeat.strftime('%Y-%m-%d %H:%M:%S'), 'short': True},
            {'title': '経過時間', 'value': f'{int(elapsed)}分', 'short': True}
        ]
        self.notify('ERROR', 'Heartbeat途絶', fields)

    def notify_order_failed(self, signal_id: str, ticker: str, reason: str):
        """発注失敗を通知"""
        fields = [
            {'title': 'Signal ID', 'value': signal_id, 'short': True},
            {'title': '銘柄', 'value': ticker, 'short': True},
            {'title': '失敗理由', 'value': reason, 'short': False}
        ]
        self.notify('WARNING', '発注失敗', fields)

    def notify_kill_switch_activated(self, reason: str, daily_stats: Dict[str, Any]):
        """Kill Switch発動を通知"""
        fields = [
            {'title': '発動理由', 'value': reason, 'short': False},
            {'title': '本日の取引成績', 'value': f"損益: {daily_stats.get('pnl', 0):,.0f}円 | 取引回数: {daily_stats.get('trade_count', 0)}回", 'short': False},
            {'title': 'システム状態', 'value': '⛔ 全取引停止', 'short': False}
        ]
        self.notify('CRITICAL', 'KILL SWITCH 発動', fields, mention_channel=True)

    def notify_high_error_rate(self, error_count: int, time_window: str):
        """エラー頻発を通知"""
        fields = [
            {'title': 'エラー回数', 'value': f'{error_count}回 / {time_window}', 'short': True},
            {'title': '閾値', 'value': '10回 / 1時間', 'short': True},
            {'title': '推奨対応', 'value': 'ErrorLogを確認し、共通原因を調査してください', 'short': False}
        ]
        self.notify('ERROR', 'エラー頻発検知', fields)

    def notify_consecutive_failures(self, failure_count: int, last_signal: Dict[str, Any], reason: str):
        """連続失敗を通知"""
        fields = [
            {'title': '失敗数', 'value': f'{failure_count}回連続', 'short': True},
            {'title': '最後の失敗', 'value': f"{last_signal.get('ticker', 'N/A')} {last_signal.get('action', 'N/A')} {last_signal.get('quantity', 0)}株", 'short': True},
            {'title': '最終失敗理由', 'value': reason, 'short': False},
            {'title': '推奨対応', 'value': self._get_recommended_action(reason), 'short': False}
        ]
        self.notify('ERROR', f'連続発注失敗（{failure_count}回）', fields)

    def _get_recommended_action(self, reason: str) -> str:
        """
        エラー理由に応じた推奨対応を返す

        Args:
            reason: エラー理由

        Returns:
            推奨対応文字列
        """
        if 'RSS' in reason:
            return 'RSSの接続状態を確認してください'
        elif 'API' in reason:
            return 'APIサーバーの接続状態を確認してください'
        elif '検証' in reason or 'validation' in reason.lower():
            return '発注パラメータの設定を確認してください'
        elif 'リスク' in reason or 'risk' in reason.lower():
            return 'リスク設定を見直してください'
        elif 'cooldown' in reason.lower() or 'クールダウン' in reason:
            return 'クールダウン設定を確認してください'
        elif 'blacklist' in reason.lower() or 'ブラックリスト' in reason:
            return 'ブラックリストを確認してください'
        else:
            return 'システムログを確認してください'


# Global notification manager instance
_notification_manager: Optional[NotificationManager] = None


def init_notification_manager(settings, redis_client: redis.Redis) -> NotificationManager:
    """
    Initialize global notification manager

    Args:
        settings: Application settings
        redis_client: Redis client instance

    Returns:
        NotificationManager instance
    """
    global _notification_manager

    slack_notifier = None
    email_notifier = None

    # Initialize Slack notifier
    if settings.alerts.enabled and settings.alerts.slack_webhook_urls:
        webhook_urls = {
            k: v for k, v in settings.alerts.slack_webhook_urls.items() if v
        }
        if webhook_urls:
            slack_notifier = SlackNotifier(webhook_urls)
            logger.info("Slack notifier initialized")

    # Initialize Email notifier
    if (settings.alerts.enabled and
        settings.alerts.email_smtp_host and
        settings.alerts.email_from and
        settings.alerts.email_recipients):

        smtp_config = {
            'server': settings.alerts.email_smtp_host,
            'port': settings.alerts.email_smtp_port,
            'use_tls': settings.alerts.email_use_tls,
            'username': settings.alerts.email_smtp_user,
            'password': settings.alerts.email_smtp_password,
            'from': settings.alerts.email_from,
            'to': ', '.join(settings.alerts.email_recipients)
        }
        email_notifier = EmailNotifier(smtp_config)
        logger.info("Email notifier initialized")

    _notification_manager = NotificationManager(
        slack_notifier=slack_notifier,
        email_notifier=email_notifier,
        redis_client=redis_client,
        frequency_limits=settings.alerts.frequency_limits
    )

    logger.info("Notification manager initialized")
    return _notification_manager


def get_notification_manager() -> Optional[NotificationManager]:
    """
    Get global notification manager instance

    Returns:
        NotificationManager instance or None if not initialized
    """
    return _notification_manager
