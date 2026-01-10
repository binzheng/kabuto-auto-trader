#!/usr/bin/env python3
"""
Kabuto Auto Trader - Mock Relay Server
Excel VBA単体テスト用の軽量モックサーバー

このスクリプトは完全なRelay Serverの代わりに使用できます。
Excel VBAのロジックだけをテストしたい場合に便利です。

起動方法:
    python mock_relay_server.py

特徴:
- Redis不要
- データベース不要
- 設定ファイル不要
- 5段階セーフティなし（全て許可）
- メモリ内でシグナル管理
"""
from flask import Flask, request, jsonify, Response
from datetime import datetime, timedelta
import hashlib
import json
import logging
from typing import Dict, List
import uuid

# ロギング設定
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# メモリ内シグナルストレージ
signals: Dict[str, dict] = {}

# 設定
CONFIG = {
    "webhook_secret": "test_secret",
    "api_key": "test_api_key_12345",
}


def generate_signal_id(ticker: str, action: str) -> str:
    """シグナルID生成"""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    return f"sig_{timestamp}_{ticker}_{action}"


def generate_checksum(signal: dict) -> str:
    """チェックサム生成"""
    core_fields = {
        "signal_id": signal["signal_id"],
        "action": signal["action"],
        "ticker": signal["ticker"],
        "quantity": signal["quantity"]
    }
    canonical = json.dumps(core_fields, sort_keys=True)
    return hashlib.sha256(canonical.encode()).hexdigest()[:16]


@app.route('/ping', methods=['GET'])
def ping():
    """Pingエンドポイント"""
    return jsonify({"status": "pong", "timestamp": datetime.now().isoformat()})


@app.route('/webhook', methods=['POST'])
def webhook():
    """
    TradingViewからのWebhook受信（モック版）

    モック版では検証をスキップして全て受け入れます
    """
    data = request.get_json()

    # パスフレーズチェック（簡易）
    if data.get("passphrase") != CONFIG["webhook_secret"]:
        logger.warning(f"Invalid passphrase from {request.remote_addr}")
        return jsonify({"detail": "Invalid passphrase"}), 401

    # シグナルID生成
    signal_id = generate_signal_id(data["ticker"], data["action"])

    # シグナル作成
    signal = {
        "signal_id": signal_id,
        "action": data["action"],
        "ticker": data["ticker"],
        "quantity": data["quantity"],
        "price": data.get("price", 0),
        "entry_price": data.get("entry_price", 0),
        "stop_loss": data.get("stop_loss", 0),
        "take_profit": data.get("take_profit", 0),
        "atr": data.get("atr", 0),
        "state": "PENDING",
        "created_at": datetime.now().isoformat(),
        "expires_at": (datetime.now() + timedelta(minutes=30)).isoformat(),
        "fetched_by": None,
        "fetched_at": None,
        "executed_at": None,
        "execution_price": None,
        "order_id": None,
        "error_message": None
    }

    # チェックサム生成
    signal["checksum"] = generate_checksum(signal)

    # メモリに保存
    signals[signal_id] = signal

    logger.info(f"✅ Signal received: {signal_id} ({data['ticker']} {data['action']} {data['quantity']})")

    return jsonify({
        "status": "success",
        "signal_id": signal_id,
        "timestamp": datetime.now().isoformat(),
        "message": "Signal received and queued"
    }), 200


@app.route('/api/signals/pending', methods=['GET'])
def get_pending_signals():
    """
    保留中のシグナル取得（Excel VBAからポーリングされる）

    モック版では全てのPENDINGシグナルを返します（検証なし）
    """
    # API Key検証
    auth_header = request.headers.get('Authorization', '')
    if not auth_header.startswith('Bearer '):
        return jsonify({"detail": "Invalid authorization header"}), 401

    api_key = auth_header.replace('Bearer ', '')
    if api_key != CONFIG["api_key"]:
        return jsonify({"detail": "Invalid API key"}), 401

    # PENDING状態のシグナルを取得
    pending_signals = [
        {
            "signal_id": s["signal_id"],
            "action": s["action"],
            "ticker": s["ticker"],
            "quantity": s["quantity"],
            "price": s["price"],
            "entry_price": s["entry_price"],
            "stop_loss": s["stop_loss"],
            "take_profit": s["take_profit"],
            "atr": s["atr"],
            "state": s["state"],
            "created_at": s["created_at"],
            "expires_at": s["expires_at"],
            "checksum": s["checksum"]
        }
        for s in signals.values()
        if s["state"] == "PENDING"
    ]

    if not pending_signals:
        logger.info("📭 No pending signals")
        return Response(status=204)

    logger.info(f"📬 Returning {len(pending_signals)} pending signal(s)")

    return jsonify({
        "status": "success",
        "timestamp": datetime.now().isoformat(),
        "count": len(pending_signals),
        "signals": pending_signals
    }), 200


@app.route('/api/signals/<signal_id>/ack', methods=['POST'])
def acknowledge_signal(signal_id: str):
    """シグナル取得確認（ACK）"""
    data = request.get_json()

    if signal_id not in signals:
        return jsonify({"detail": "Signal not found"}), 404

    signal = signals[signal_id]

    # チェックサム検証
    if signal["checksum"] != data.get("checksum"):
        logger.error(f"❌ Checksum mismatch for {signal_id}")
        return jsonify({"detail": "Checksum mismatch"}), 400

    # 状態更新
    signal["state"] = "FETCHED"
    signal["fetched_by"] = data.get("client_id")
    signal["fetched_at"] = datetime.now().isoformat()

    logger.info(f"✅ Signal acknowledged: {signal_id} by {data.get('client_id')}")

    return jsonify({
        "status": "success",
        "signal_id": signal_id,
        "state": "fetched",
        "acknowledged_at": signal["fetched_at"]
    }), 200


@app.route('/api/signals/<signal_id>/executed', methods=['POST'])
def report_execution(signal_id: str):
    """実行報告"""
    data = request.get_json()

    if signal_id not in signals:
        return jsonify({"detail": "Signal not found"}), 404

    signal = signals[signal_id]

    # 状態更新
    signal["state"] = "EXECUTED"
    signal["executed_at"] = data.get("executed_at")
    signal["execution_price"] = data.get("execution_price")
    signal["order_id"] = data.get("order_id")

    logger.info(
        f"✅ Execution reported: {signal_id} - "
        f"Order {data.get('order_id')} @ {data.get('execution_price')}"
    )

    return jsonify({
        "status": "success",
        "signal_id": signal_id,
        "state": "executed",
        "execution_logged": True
    }), 200


@app.route('/api/signals/<signal_id>/failed', methods=['POST'])
def report_failure(signal_id: str):
    """失敗報告"""
    data = request.get_json()

    if signal_id not in signals:
        return jsonify({"detail": "Signal not found"}), 404

    signal = signals[signal_id]

    # 状態更新
    signal["state"] = "FAILED"
    signal["error_message"] = data.get("error")

    logger.error(f"❌ Execution failed: {signal_id} - {data.get('error')}")

    return jsonify({
        "status": "failure_recorded",
        "message": f"Signal {signal_id} marked as failed"
    }), 200


@app.route('/status', methods=['GET'])
def get_status():
    """システムステータス"""
    total_signals = len(signals)
    pending_count = sum(1 for s in signals.values() if s["state"] == "PENDING")
    fetched_count = sum(1 for s in signals.values() if s["state"] == "FETCHED")
    executed_count = sum(1 for s in signals.values() if s["state"] == "EXECUTED")
    failed_count = sum(1 for s in signals.values() if s["state"] == "FAILED")

    return jsonify({
        "status": "active",
        "trading_enabled": True,
        "market_open": True,
        "timestamp": datetime.now().isoformat(),
        "signals": {
            "total": total_signals,
            "pending": pending_count,
            "fetched": fetched_count,
            "executed": executed_count,
            "failed": failed_count
        },
        "mock_mode": True,
        "message": "This is a MOCK server for Excel VBA unit testing"
    }), 200


@app.route('/api/admin/kill-switch/activate', methods=['POST'])
def activate_kill_switch():
    """Kill Switch発動（モック - 何もしない）"""
    logger.info("⚠️ Kill Switch activation requested (ignored in mock mode)")
    return jsonify({
        "status": "success",
        "message": "Kill Switch activated (mock mode - no effect)"
    }), 200


@app.route('/api/admin/kill-switch/deactivate', methods=['POST'])
def deactivate_kill_switch():
    """Kill Switch解除（モック - 何もしない）"""
    logger.info("✅ Kill Switch deactivation requested (ignored in mock mode)")
    return jsonify({
        "status": "success",
        "message": "Kill Switch deactivated (mock mode - no effect)"
    }), 200


@app.route('/health', methods=['GET'])
def health_check():
    """ヘルスチェック"""
    return jsonify({
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "version": "1.0.0-mock",
        "database": "memory",
        "redis": "not required"
    }), 200


@app.route('/', methods=['GET'])
def root():
    """ルートエンドポイント"""
    return jsonify({
        "name": "Kabuto Relay Server (MOCK)",
        "version": "1.0.0-mock",
        "status": "running",
        "timestamp": datetime.now().isoformat(),
        "mode": "MOCK - Excel VBA Unit Testing",
        "endpoints": {
            "webhook": "/webhook",
            "signals": "/api/signals/pending",
            "health": "/health",
            "status": "/status",
            "ping": "/ping"
        },
        "note": "This is a lightweight mock server for testing Excel VBA only. No validation, no database, no Redis required."
    }), 200


if __name__ == '__main__':
    print("=" * 60)
    print("🧪 Kabuto Mock Relay Server")
    print("=" * 60)
    print("Purpose: Excel VBA Unit Testing")
    print("Mode: MOCK (no validation, no database, no Redis)")
    print("")
    print("Configuration:")
    print(f"  Webhook Secret: {CONFIG['webhook_secret']}")
    print(f"  API Key: {CONFIG['api_key']}")
    print("")
    print("Starting server on http://localhost:5000")
    print("=" * 60)
    print("")

    app.run(
        host='0.0.0.0',
        port=5000,
        debug=True
    )
