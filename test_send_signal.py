#!/usr/bin/env python3
"""
Kabuto Auto Trader - Test Signal Sender
テスト用シグナル送信スクリプト
"""
import requests
import json
from datetime import datetime
import sys

# Relay Server設定
BASE_URL = "http://localhost:5000"
WEBHOOK_SECRET = "test_secret"
API_KEY = "test_api_key_12345"


def send_buy_signal(ticker: str = "7203", quantity: int = 100):
    """買いシグナル送信"""
    url = f"{BASE_URL}/webhook"

    signal = {
        "passphrase": WEBHOOK_SECRET,
        "action": "buy",
        "ticker": ticker,
        "quantity": quantity,
        "price": 1850.0,
        "entry_price": 1850.0,
        "stop_loss": 1800.0,
        "take_profit": 1950.0,
        "atr": 50.0,
        "rr_ratio": 2.0,
        "rsi": 45.0,
        "timestamp": datetime.now().isoformat()
    }

    print(f"📤 Sending BUY signal: {ticker} x {quantity}")
    print(f"Signal: {json.dumps(signal, indent=2)}")

    try:
        response = requests.post(url, json=signal, timeout=10)
        print(f"\n✅ Response [{response.status_code}]:")
        print(json.dumps(response.json(), indent=2))
        return response.json()
    except requests.exceptions.RequestException as e:
        print(f"\n❌ Error: {e}")
        return None


def send_sell_signal(ticker: str = "7203", quantity: int = 100):
    """売りシグナル送信"""
    url = f"{BASE_URL}/webhook"

    signal = {
        "passphrase": WEBHOOK_SECRET,
        "action": "sell",
        "ticker": ticker,
        "quantity": quantity,
        "price": 1900.0,
        "entry_price": 1850.0,
        "stop_loss": 1800.0,
        "take_profit": 1950.0,
        "atr": 50.0,
        "rr_ratio": 2.0,
        "rsi": 65.0,
        "timestamp": datetime.now().isoformat()
    }

    print(f"📤 Sending SELL signal: {ticker} x {quantity}")
    print(f"Signal: {json.dumps(signal, indent=2)}")

    try:
        response = requests.post(url, json=signal, timeout=10)
        print(f"\n✅ Response [{response.status_code}]:")
        print(json.dumps(response.json(), indent=2))
        return response.json()
    except requests.exceptions.RequestException as e:
        print(f"\n❌ Error: {e}")
        return None


def check_pending_signals():
    """保留中のシグナル確認"""
    url = f"{BASE_URL}/api/signals/pending"
    headers = {"Authorization": f"Bearer {API_KEY}"}

    try:
        response = requests.get(url, headers=headers, timeout=10)

        if response.status_code == 204:
            print("📭 No pending signals")
            return []

        print(f"📬 Pending signals [{response.status_code}]:")
        data = response.json()
        print(json.dumps(data, indent=2))

        return data.get("signals", [])
    except requests.exceptions.RequestException as e:
        print(f"\n❌ Error: {e}")
        return []


def check_status():
    """システムステータス確認"""
    url = f"{BASE_URL}/status"

    try:
        response = requests.get(url, timeout=10)
        print(f"📊 System Status [{response.status_code}]:")
        data = response.json()
        print(json.dumps(data, indent=2))
        return data
    except requests.exceptions.RequestException as e:
        print(f"\n❌ Error: {e}")
        return None


def activate_kill_switch(reason: str = "Test"):
    """Kill Switch発動"""
    url = f"{BASE_URL}/api/admin/kill-switch/activate"
    headers = {"Content-Type": "application/json"}
    payload = {
        "reason": reason,
        "password": "admin123"
    }

    try:
        response = requests.post(url, json=payload, headers=headers, timeout=10)
        print(f"🛑 Kill Switch Activated [{response.status_code}]:")
        print(json.dumps(response.json(), indent=2))
        return response.json()
    except requests.exceptions.RequestException as e:
        print(f"\n❌ Error: {e}")
        return None


def deactivate_kill_switch():
    """Kill Switch解除"""
    url = f"{BASE_URL}/api/admin/kill-switch/deactivate"
    headers = {"Content-Type": "application/json"}
    payload = {"password": "admin123"}

    try:
        response = requests.post(url, json=payload, headers=headers, timeout=10)
        print(f"✅ Kill Switch Deactivated [{response.status_code}]:")
        print(json.dumps(response.json(), indent=2))
        return response.json()
    except requests.exceptions.RequestException as e:
        print(f"\n❌ Error: {e}")
        return None


def print_usage():
    """使い方を表示"""
    print("""
Kabuto Auto Trader - Test Signal Sender

Usage:
  python test_send_signal.py <command> [options]

Commands:
  buy <ticker> <quantity>   - Send buy signal
  sell <ticker> <quantity>  - Send sell signal
  check                     - Check pending signals
  status                    - Check system status
  kill-on                   - Activate kill switch
  kill-off                  - Deactivate kill switch

Examples:
  python test_send_signal.py buy 7203 100
  python test_send_signal.py sell 7203 100
  python test_send_signal.py check
  python test_send_signal.py status
  python test_send_signal.py kill-on
  python test_send_signal.py kill-off

Default values:
  ticker: 7203 (Toyota)
  quantity: 100
""")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print_usage()
        sys.exit(1)

    command = sys.argv[1].lower()

    if command == "buy":
        ticker = sys.argv[2] if len(sys.argv) > 2 else "7203"
        quantity = int(sys.argv[3]) if len(sys.argv) > 3 else 100
        send_buy_signal(ticker, quantity)

    elif command == "sell":
        ticker = sys.argv[2] if len(sys.argv) > 2 else "7203"
        quantity = int(sys.argv[3]) if len(sys.argv) > 3 else 100
        send_sell_signal(ticker, quantity)

    elif command == "check":
        check_pending_signals()

    elif command == "status":
        check_status()

    elif command == "kill-on":
        activate_kill_switch("Manual test activation")

    elif command == "kill-off":
        deactivate_kill_switch()

    else:
        print(f"❌ Unknown command: {command}")
        print_usage()
        sys.exit(1)
