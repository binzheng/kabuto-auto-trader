# Kabuto Auto Trader - Relay Server テスト計画

**作成日**: 2025-12-27
**ドキュメントID**: doc/21

---

## 目次

1. [テスト戦略](#1-テスト戦略)
2. [テスト環境](#2-テスト環境)
3. [単体テスト計画](#3-単体テスト計画)
4. [統合テスト計画](#4-統合テスト計画)
5. [E2Eテスト計画](#5-e2eテスト計画)
6. [テストツール](#6-テストツール)
7. [テストケース設計](#7-テストケース設計)
8. [CI/CD統合](#8-cicd統合)

---

## 1. テスト戦略

### 1.1 テストピラミッド

```
       /\
      /  \     E2E Tests (10%)
     /    \    - 重要なユーザーフロー
    /------\   - エンドツーエンド
   /        \
  / Integration\ (30%)
 /   Tests     \  - API統合
/               \ - DB統合
/                \
/   Unit Tests   \ (60%)
/  (高速・大量)   \
--------------------
```

**比率目標**:
- **Unit Tests**: 60% - 個別関数・クラスの動作検証
- **Integration Tests**: 30% - コンポーネント間の連携検証
- **E2E Tests**: 10% - システム全体の動作検証

### 1.2 テスト方針

| 原則 | 説明 |
|------|------|
| **Fast** | 単体テストは1秒以内 |
| **Independent** | テストは独立して実行可能 |
| **Repeatable** | 何度実行しても同じ結果 |
| **Self-Validating** | 成功/失敗が明確 |
| **Timely** | コード作成と同時にテスト作成 |

### 1.3 カバレッジ目標

| レイヤー | カバレッジ目標 | 重要度 |
|---------|--------------|--------|
| **Core Business Logic** | 95%以上 | 最高 |
| **API Endpoints** | 90%以上 | 高 |
| **Database Models** | 85%以上 | 高 |
| **Utilities** | 80%以上 | 中 |
| **Config/Settings** | 60%以上 | 低 |

---

## 2. テスト環境

### 2.1 環境構成

| 環境 | 用途 | データベース | 外部API |
|------|------|-------------|---------|
| **Local** | 開発中のテスト | SQLite（メモリ） | Mock |
| **CI/CD** | 自動テスト | SQLite（メモリ） | Mock |
| **Staging** | 統合テスト | PostgreSQL（専用DB） | Sandbox |
| **Production** | 本番環境 | PostgreSQL | 本番API |

### 2.2 テストデータベース

**設定ファイル**: `relay_server/tests/conftest.py`

```python
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.database import Base
from app.main import app

# テスト用のインメモリDB
TEST_DATABASE_URL = "sqlite:///:memory:"

@pytest.fixture(scope="function")
def test_db():
    """
    各テストごとに新しいDBを作成
    """
    engine = create_engine(
        TEST_DATABASE_URL,
        connect_args={"check_same_thread": False}
    )

    # テーブル作成
    Base.metadata.create_all(bind=engine)

    TestingSessionLocal = sessionmaker(
        autocommit=False,
        autoflush=False,
        bind=engine
    )

    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()
        # テーブル削除
        Base.metadata.drop_all(bind=engine)

@pytest.fixture(scope="function")
def client(test_db):
    """
    FastAPIテストクライアント
    """
    from fastapi.testclient import TestClient

    # DBセッションをテスト用に差し替え
    def override_get_db():
        try:
            yield test_db
        finally:
            pass

    app.dependency_overrides[get_db] = override_get_db

    with TestClient(app) as client:
        yield client

    app.dependency_overrides.clear()
```

### 2.3 環境変数（テスト用）

**ファイル**: `relay_server/.env.test`

```bash
# Database
DATABASE_URL=sqlite:///:memory:

# API Keys (Test)
API_KEY_TEST=test-api-key-12345

# Slack (Mock)
SLACK_WEBHOOK_URL=http://localhost:8000/mock/slack

# SMTP (Mock)
SMTP_SERVER=localhost
SMTP_PORT=1025
SMTP_USERNAME=test@example.com
SMTP_PASSWORD=testpassword

# Environment
ENVIRONMENT=test
DEBUG=true
LOG_LEVEL=DEBUG
```

---

## 3. 単体テスト計画

### 3.1 テスト対象モジュール

| モジュール | ファイル | テストファイル | 優先度 |
|-----------|---------|--------------|--------|
| **Signal Generator** | `app/services/signal_generator.py` | `tests/unit/test_signal_generator.py` | 最高 |
| **Risk Manager** | `app/services/risk_manager.py` | `tests/unit/test_risk_manager.py` | 最高 |
| **Position Manager** | `app/services/position_manager.py` | `tests/unit/test_position_manager.py` | 高 |
| **Notification** | `app/core/notification.py` | `tests/unit/test_notification.py` | 高 |
| **Models** | `app/models/*.py` | `tests/unit/test_models.py` | 中 |
| **Utils** | `app/utils/*.py` | `tests/unit/test_utils.py` | 中 |

### 3.2 単体テストケース例

#### 3.2.1 Signal Generator Tests

**ファイル**: `tests/unit/test_signal_generator.py`

```python
import pytest
from datetime import datetime
from app.services.signal_generator import SignalGenerator
from app.models.signal import Signal

class TestSignalGenerator:
    """SignalGeneratorの単体テスト"""

    @pytest.fixture
    def signal_generator(self):
        """テスト用のSignalGeneratorインスタンス"""
        return SignalGenerator()

    def test_generate_signal_with_valid_data(self, signal_generator):
        """正常なデータでシグナルを生成"""
        # Arrange
        market_data = {
            'ticker': '7203',
            'price': 2500.0,
            'volume': 1000000,
            'momentum': 0.85
        }

        # Act
        signal = signal_generator.generate(
            strategy='momentum_breakout',
            market_data=market_data
        )

        # Assert
        assert signal is not None
        assert signal.ticker == '7203'
        assert signal.action in ['buy', 'sell']
        assert signal.quantity > 0
        assert 0.0 <= signal.signal_strength <= 1.0
        assert signal.signal_id.startswith('SIG-')

    def test_generate_signal_with_invalid_ticker(self, signal_generator):
        """不正な銘柄コードでエラー"""
        # Arrange
        market_data = {
            'ticker': 'INVALID',
            'price': 2500.0,
            'volume': 1000000
        }

        # Act & Assert
        with pytest.raises(ValueError) as exc:
            signal_generator.generate('momentum_breakout', market_data)

        assert 'Invalid ticker' in str(exc.value)

    def test_generate_signal_with_missing_data(self, signal_generator):
        """必須データ欠落でエラー"""
        # Arrange
        market_data = {
            'ticker': '7203'
            # price, volumeが欠落
        }

        # Act & Assert
        with pytest.raises(KeyError):
            signal_generator.generate('momentum_breakout', market_data)

    def test_signal_strength_calculation(self, signal_generator):
        """シグナル強度の計算"""
        # Arrange
        market_data = {
            'ticker': '7203',
            'price': 2500.0,
            'volume': 1000000,
            'momentum': 0.85,
            'volatility': 0.15
        }

        # Act
        signal = signal_generator.generate('momentum_breakout', market_data)

        # Assert
        assert 0.5 <= signal.signal_strength <= 1.0  # 強いシグナル
        assert signal.signal_strength > 0.7  # momentum 0.85なら強度も高い

    def test_checksum_generation(self, signal_generator):
        """チェックサム生成の検証"""
        # Arrange
        market_data = {
            'ticker': '7203',
            'price': 2500.0,
            'volume': 1000000
        }

        # Act
        signal1 = signal_generator.generate('momentum_breakout', market_data)
        signal2 = signal_generator.generate('momentum_breakout', market_data)

        # Assert
        # 同じデータから生成されたチェックサムは同じ（タイムスタンプ除く）
        assert signal1.checksum is not None
        assert len(signal1.checksum) == 64  # SHA256
        # 異なるタイムスタンプなら異なるチェックサム
        assert signal1.checksum != signal2.checksum

    @pytest.mark.parametrize("strategy,expected_action", [
        ("momentum_breakout", "buy"),
        ("mean_reversion", "sell"),
        ("trend_following", "buy"),
    ])
    def test_different_strategies(self, signal_generator, strategy, expected_action):
        """複数の戦略をテスト"""
        # Arrange
        market_data = {
            'ticker': '7203',
            'price': 2500.0,
            'volume': 1000000,
            'momentum': 0.85
        }

        # Act
        signal = signal_generator.generate(strategy, market_data)

        # Assert
        assert signal.strategy == strategy
        assert signal.action == expected_action
```

#### 3.2.2 Risk Manager Tests

**ファイル**: `tests/unit/test_risk_manager.py`

```python
import pytest
from app.services.risk_manager import RiskManager
from app.models.signal import Signal

class TestRiskManager:
    """RiskManagerの単体テスト"""

    @pytest.fixture
    def risk_manager(self):
        """テスト用のRiskManagerインスタンス"""
        config = {
            'max_position_size': 1000000,  # 100万円
            'max_daily_loss': 50000,       # -5万円
            'max_positions': 3
        }
        return RiskManager(config)

    def test_validate_signal_within_limits(self, risk_manager):
        """リスク限度内のシグナルは通過"""
        # Arrange
        signal = Signal(
            ticker='7203',
            action='buy',
            quantity=100,
            price=2500.0
        )

        # Act
        result = risk_manager.validate(signal)

        # Assert
        assert result.passed is True
        assert result.reason is None

    def test_validate_signal_exceeds_position_size(self, risk_manager):
        """ポジションサイズ超過でブロック"""
        # Arrange
        signal = Signal(
            ticker='7203',
            action='buy',
            quantity=5000,  # 2500 * 5000 = 1250万円 > 100万円
            price=2500.0
        )

        # Act
        result = risk_manager.validate(signal)

        # Assert
        assert result.passed is False
        assert 'position size' in result.reason.lower()

    def test_daily_loss_limit(self, risk_manager):
        """日次損失限度のチェック"""
        # Arrange
        # 既存の損失を設定
        risk_manager.daily_pnl = -45000

        signal = Signal(
            ticker='7203',
            action='sell',
            quantity=100,
            price=2450.0,  # 損失予測
            entry_price=2500.0
        )

        # Act
        result = risk_manager.validate(signal)

        # Assert
        # -45000 + (-5000) = -50000 で限度到達
        assert result.passed is False
        assert 'daily loss limit' in result.reason.lower()

    def test_max_positions_limit(self, risk_manager):
        """最大ポジション数のチェック"""
        # Arrange
        # 既に3ポジション保有
        risk_manager.current_positions = ['7203', '9984', '6758']

        signal = Signal(
            ticker='4063',  # 新規銘柄
            action='buy',
            quantity=100,
            price=1000.0
        )

        # Act
        result = risk_manager.validate(signal)

        # Assert
        assert result.passed is False
        assert 'max positions' in result.reason.lower()

    def test_add_to_existing_position(self, risk_manager):
        """既存ポジションへの追加は許可"""
        # Arrange
        risk_manager.current_positions = ['7203', '9984']

        signal = Signal(
            ticker='7203',  # 既存銘柄
            action='buy',
            quantity=100,
            price=2500.0
        )

        # Act
        result = risk_manager.validate(signal)

        # Assert
        assert result.passed is True  # 既存銘柄なので追加可能
```

#### 3.2.3 Model Tests

**ファイル**: `tests/unit/test_models.py`

```python
import pytest
from datetime import datetime
from app.models.signal import Signal
from app.models.position import Position

class TestSignalModel:
    """Signalモデルのテスト"""

    def test_create_signal(self):
        """シグナルの作成"""
        # Act
        signal = Signal(
            signal_id='SIG-20250127-001',
            strategy='momentum_breakout',
            ticker='7203',
            action='buy',
            quantity=100,
            price_type='market',
            signal_strength=0.85
        )

        # Assert
        assert signal.signal_id == 'SIG-20250127-001'
        assert signal.ticker == '7203'
        assert signal.action == 'buy'
        assert signal.quantity == 100

    def test_signal_validation(self):
        """シグナルのバリデーション"""
        # Act & Assert
        with pytest.raises(ValueError):
            Signal(
                signal_id='SIG-001',
                strategy='momentum_breakout',
                ticker='7203',
                action='invalid_action',  # 不正なアクション
                quantity=100
            )

    def test_signal_to_dict(self):
        """シグナルの辞書変換"""
        # Arrange
        signal = Signal(
            signal_id='SIG-20250127-001',
            strategy='momentum_breakout',
            ticker='7203',
            action='buy',
            quantity=100
        )

        # Act
        signal_dict = signal.to_dict()

        # Assert
        assert isinstance(signal_dict, dict)
        assert signal_dict['signal_id'] == 'SIG-20250127-001'
        assert signal_dict['ticker'] == '7203'
        assert 'timestamp' in signal_dict

class TestPositionModel:
    """Positionモデルのテスト"""

    def test_create_position(self):
        """ポジションの作成"""
        # Act
        position = Position(
            ticker='7203',
            quantity=100,
            entry_price=2500.0,
            current_price=2550.0
        )

        # Assert
        assert position.ticker == '7203'
        assert position.quantity == 100
        assert position.entry_price == 2500.0

    def test_position_pnl_calculation(self):
        """損益計算"""
        # Arrange
        position = Position(
            ticker='7203',
            quantity=100,
            entry_price=2500.0,
            current_price=2550.0
        )

        # Act
        pnl = position.calculate_pnl()

        # Assert
        # (2550 - 2500) * 100 = 5000
        assert pnl == 5000.0

    def test_position_update_price(self):
        """価格更新"""
        # Arrange
        position = Position(
            ticker='7203',
            quantity=100,
            entry_price=2500.0,
            current_price=2500.0
        )

        # Act
        position.update_price(2600.0)

        # Assert
        assert position.current_price == 2600.0
        assert position.calculate_pnl() == 10000.0
```

### 3.3 単体テスト実行

**コマンド**:
```bash
# 全単体テスト実行
pytest tests/unit/ -v

# カバレッジ付き
pytest tests/unit/ --cov=app --cov-report=html

# 特定のテストファイルのみ
pytest tests/unit/test_signal_generator.py -v

# 特定のテストケースのみ
pytest tests/unit/test_signal_generator.py::TestSignalGenerator::test_generate_signal_with_valid_data -v
```

---

## 4. 統合テスト計画

### 4.1 テスト対象

| レイヤー | テスト内容 | 優先度 |
|---------|-----------|--------|
| **API Endpoints** | REST API の動作検証 | 最高 |
| **Database** | DB操作の統合検証 | 最高 |
| **External Services** | Webhook、通知の統合 | 高 |
| **Authentication** | 認証・認可の統合 | 高 |

### 4.2 API統合テストケース

#### 4.2.1 Signal API Tests

**ファイル**: `tests/integration/test_signal_api.py`

```python
import pytest
from fastapi.testclient import TestClient
from app.main import app

class TestSignalAPI:
    """Signal APIの統合テスト"""

    @pytest.fixture
    def client(self):
        """テストクライアント"""
        return TestClient(app)

    def test_get_pending_signals_empty(self, client):
        """未処理シグナル取得（空）"""
        # Act
        response = client.get("/api/signals/pending")

        # Assert
        assert response.status_code == 200
        assert response.json() == []

    def test_create_signal(self, client):
        """シグナル作成"""
        # Arrange
        signal_data = {
            "strategy": "momentum_breakout",
            "ticker": "7203",
            "action": "buy",
            "quantity": 100,
            "price_type": "market",
            "signal_strength": 0.85
        }

        # Act
        response = client.post("/api/signals", json=signal_data)

        # Assert
        assert response.status_code == 201
        data = response.json()
        assert data['ticker'] == '7203'
        assert data['action'] == 'buy'
        assert 'signal_id' in data

    def test_get_signal_by_id(self, client):
        """シグナルID指定取得"""
        # Arrange - まずシグナルを作成
        signal_data = {
            "strategy": "momentum_breakout",
            "ticker": "7203",
            "action": "buy",
            "quantity": 100
        }
        create_response = client.post("/api/signals", json=signal_data)
        signal_id = create_response.json()['signal_id']

        # Act
        response = client.get(f"/api/signals/{signal_id}")

        # Assert
        assert response.status_code == 200
        data = response.json()
        assert data['signal_id'] == signal_id
        assert data['ticker'] == '7203'

    def test_acknowledge_signal(self, client):
        """シグナルACK"""
        # Arrange
        signal_data = {
            "strategy": "momentum_breakout",
            "ticker": "7203",
            "action": "buy",
            "quantity": 100
        }
        create_response = client.post("/api/signals", json=signal_data)
        signal_id = create_response.json()['signal_id']
        checksum = create_response.json()['checksum']

        # Act
        ack_data = {"checksum": checksum}
        response = client.post(f"/api/signals/{signal_id}/ack", json=ack_data)

        # Assert
        assert response.status_code == 200
        data = response.json()
        assert data['status'] == 'acknowledged'

    def test_acknowledge_signal_invalid_checksum(self, client):
        """無効なチェックサムでACK拒否"""
        # Arrange
        signal_data = {
            "strategy": "momentum_breakout",
            "ticker": "7203",
            "action": "buy",
            "quantity": 100
        }
        create_response = client.post("/api/signals", json=signal_data)
        signal_id = create_response.json()['signal_id']

        # Act
        ack_data = {"checksum": "invalid_checksum"}
        response = client.post(f"/api/signals/{signal_id}/ack", json=ack_data)

        # Assert
        assert response.status_code == 400
        assert 'checksum' in response.json()['detail'].lower()

    def test_report_execution(self, client):
        """約定報告"""
        # Arrange
        signal_data = {
            "strategy": "momentum_breakout",
            "ticker": "7203",
            "action": "buy",
            "quantity": 100
        }
        create_response = client.post("/api/signals", json=signal_data)
        signal_id = create_response.json()['signal_id']

        # Act
        execution_data = {
            "order_id": "ORD-001",
            "price": 2500.0,
            "quantity": 100
        }
        response = client.post(
            f"/api/signals/{signal_id}/executed",
            json=execution_data
        )

        # Assert
        assert response.status_code == 200
        data = response.json()
        assert data['status'] == 'executed'

    def test_report_failure(self, client):
        """失敗報告"""
        # Arrange
        signal_data = {
            "strategy": "momentum_breakout",
            "ticker": "7203",
            "action": "buy",
            "quantity": 100
        }
        create_response = client.post("/api/signals", json=signal_data)
        signal_id = create_response.json()['signal_id']

        # Act
        failure_data = {
            "error_message": "RSS connection timeout"
        }
        response = client.post(
            f"/api/signals/{signal_id}/failed",
            json=failure_data
        )

        # Assert
        assert response.status_code == 200
        data = response.json()
        assert data['status'] == 'failed'

    def test_get_pending_signals_with_data(self, client):
        """未処理シグナル取得（データあり）"""
        # Arrange - 複数のシグナルを作成
        for i in range(3):
            signal_data = {
                "strategy": "momentum_breakout",
                "ticker": f"720{i}",
                "action": "buy",
                "quantity": 100
            }
            client.post("/api/signals", json=signal_data)

        # Act
        response = client.get("/api/signals/pending")

        # Assert
        assert response.status_code == 200
        data = response.json()
        assert len(data) == 3
        assert all('signal_id' in signal for signal in data)
```

#### 4.2.2 Heartbeat API Tests

**ファイル**: `tests/integration/test_heartbeat_api.py`

```python
import pytest
from fastapi.testclient import TestClient
from datetime import datetime

class TestHeartbeatAPI:
    """Heartbeat APIの統合テスト"""

    @pytest.fixture
    def client(self):
        return TestClient(app)

    def test_send_heartbeat(self, client):
        """Heartbeat送信"""
        # Arrange
        heartbeat_data = {
            "client_id": "excel-client-001",
            "status": "running",
            "system_info": {
                "version": "1.0.0",
                "os": "Windows 10"
            }
        }

        # Act
        response = client.post("/api/heartbeat", json=heartbeat_data)

        # Assert
        assert response.status_code == 200
        data = response.json()
        assert data['status'] == 'ok'
        assert 'last_heartbeat' in data

    def test_heartbeat_timeout_detection(self, client, test_db):
        """Heartbeatタイムアウト検出"""
        # Arrange - 古いHeartbeatを作成
        from app.models.heartbeat import Heartbeat
        from datetime import timedelta

        old_heartbeat = Heartbeat(
            client_id="excel-client-001",
            last_heartbeat=datetime.now() - timedelta(minutes=15)
        )
        test_db.add(old_heartbeat)
        test_db.commit()

        # Act
        response = client.get("/api/heartbeat/check")

        # Assert
        assert response.status_code == 200
        data = response.json()
        assert 'timeout_clients' in data
        assert 'excel-client-001' in data['timeout_clients']
```

### 4.3 Database統合テスト

**ファイル**: `tests/integration/test_database.py`

```python
import pytest
from sqlalchemy.orm import Session
from app.models.signal import Signal
from app.models.position import Position
from app.database import SessionLocal

class TestDatabaseIntegration:
    """データベース統合テスト"""

    @pytest.fixture
    def db(self, test_db):
        """テストDB"""
        return test_db

    def test_create_and_retrieve_signal(self, db: Session):
        """シグナル作成と取得"""
        # Arrange
        signal = Signal(
            signal_id='SIG-20250127-001',
            strategy='momentum_breakout',
            ticker='7203',
            action='buy',
            quantity=100
        )

        # Act - 作成
        db.add(signal)
        db.commit()
        db.refresh(signal)

        # Assert - 取得
        retrieved = db.query(Signal).filter(
            Signal.signal_id == 'SIG-20250127-001'
        ).first()

        assert retrieved is not None
        assert retrieved.ticker == '7203'
        assert retrieved.action == 'buy'

    def test_update_signal_status(self, db: Session):
        """シグナル状態更新"""
        # Arrange
        signal = Signal(
            signal_id='SIG-20250127-001',
            strategy='momentum_breakout',
            ticker='7203',
            action='buy',
            quantity=100,
            status='pending'
        )
        db.add(signal)
        db.commit()

        # Act
        signal.status = 'acknowledged'
        db.commit()

        # Assert
        retrieved = db.query(Signal).filter(
            Signal.signal_id == 'SIG-20250127-001'
        ).first()
        assert retrieved.status == 'acknowledged'

    def test_cascade_delete(self, db: Session):
        """カスケード削除"""
        # Arrange
        signal = Signal(
            signal_id='SIG-20250127-001',
            strategy='momentum_breakout',
            ticker='7203',
            action='buy',
            quantity=100
        )
        db.add(signal)
        db.commit()

        # 関連するポジションを作成（仮）
        # ... (実装による)

        # Act
        db.delete(signal)
        db.commit()

        # Assert
        retrieved = db.query(Signal).filter(
            Signal.signal_id == 'SIG-20250127-001'
        ).first()
        assert retrieved is None

    def test_transaction_rollback(self, db: Session):
        """トランザクションロールバック"""
        # Arrange
        signal1 = Signal(
            signal_id='SIG-20250127-001',
            strategy='momentum_breakout',
            ticker='7203',
            action='buy',
            quantity=100
        )

        # Act
        try:
            db.add(signal1)
            db.flush()

            # 意図的にエラーを発生
            signal2 = Signal(
                signal_id='SIG-20250127-001',  # 重複ID
                strategy='momentum_breakout',
                ticker='9984',
                action='buy',
                quantity=100
            )
            db.add(signal2)
            db.commit()
        except:
            db.rollback()

        # Assert
        count = db.query(Signal).count()
        assert count == 0  # ロールバックされて0件
```

---

## 5. E2Eテスト計画

### 5.1 E2Eテストシナリオ

| シナリオ名 | 説明 | 優先度 |
|-----------|------|--------|
| **Complete Trading Flow** | シグナル生成→ACK→約定報告 | 最高 |
| **Error Handling Flow** | エラー発生→リトライ→失敗報告 | 高 |
| **Heartbeat Monitoring** | Heartbeat送信→タイムアウト検知 | 高 |
| **Risk Management Flow** | リスク超過→シグナルブロック | 中 |

### 5.2 E2Eテストケース

**ファイル**: `tests/e2e/test_trading_flow.py`

```python
import pytest
from fastapi.testclient import TestClient
import time

class TestCompleteTradingFlow:
    """完全な取引フローのE2Eテスト"""

    @pytest.fixture
    def client(self):
        return TestClient(app)

    def test_complete_trading_flow(self, client):
        """
        シグナル生成 → 取得 → ACK → 約定報告の完全フロー
        """
        # ========================================
        # Step 1: シグナル生成
        # ========================================
        signal_data = {
            "strategy": "momentum_breakout",
            "ticker": "7203",
            "action": "buy",
            "quantity": 100,
            "price_type": "market",
            "signal_strength": 0.85
        }

        create_response = client.post("/api/signals", json=signal_data)
        assert create_response.status_code == 201

        signal = create_response.json()
        signal_id = signal['signal_id']
        checksum = signal['checksum']

        print(f"✅ Step 1: Signal created - {signal_id}")

        # ========================================
        # Step 2: 未処理シグナル取得
        # ========================================
        pending_response = client.get("/api/signals/pending")
        assert pending_response.status_code == 200

        pending_signals = pending_response.json()
        assert len(pending_signals) == 1
        assert pending_signals[0]['signal_id'] == signal_id

        print(f"✅ Step 2: Signal retrieved from pending queue")

        # ========================================
        # Step 3: シグナルACK
        # ========================================
        ack_response = client.post(
            f"/api/signals/{signal_id}/ack",
            json={"checksum": checksum}
        )
        assert ack_response.status_code == 200
        assert ack_response.json()['status'] == 'acknowledged'

        print(f"✅ Step 3: Signal acknowledged")

        # ========================================
        # Step 4: 約定報告
        # ========================================
        time.sleep(0.1)  # 実際の約定までの遅延をシミュレート

        execution_response = client.post(
            f"/api/signals/{signal_id}/executed",
            json={
                "order_id": "ORD-20250127-001",
                "price": 2500.0,
                "quantity": 100
            }
        )
        assert execution_response.status_code == 200
        assert execution_response.json()['status'] == 'executed'

        print(f"✅ Step 4: Execution reported")

        # ========================================
        # Step 5: 最終確認
        # ========================================
        final_response = client.get(f"/api/signals/{signal_id}")
        assert final_response.status_code == 200

        final_signal = final_response.json()
        assert final_signal['status'] == 'executed'
        assert final_signal['order_id'] == 'ORD-20250127-001'

        print(f"✅ Step 5: Final verification passed")
        print(f"✅ Complete trading flow test PASSED")

    def test_error_handling_flow(self, client):
        """
        エラーハンドリングフロー
        """
        # Step 1: シグナル生成
        signal_data = {
            "strategy": "momentum_breakout",
            "ticker": "7203",
            "action": "buy",
            "quantity": 100
        }

        create_response = client.post("/api/signals", json=signal_data)
        signal_id = create_response.json()['signal_id']
        checksum = create_response.json()['checksum']

        # Step 2: ACK
        client.post(
            f"/api/signals/{signal_id}/ack",
            json={"checksum": checksum}
        )

        # Step 3: 失敗報告
        failure_response = client.post(
            f"/api/signals/{signal_id}/failed",
            json={
                "error_message": "RSS connection timeout",
                "error_code": "RSS_ERR_001"
            }
        )

        assert failure_response.status_code == 200
        assert failure_response.json()['status'] == 'failed'

        # Step 4: 最終確認
        final_response = client.get(f"/api/signals/{signal_id}")
        final_signal = final_response.json()

        assert final_signal['status'] == 'failed'
        assert final_signal['error_message'] == 'RSS connection timeout'

        print(f"✅ Error handling flow test PASSED")
```

---

## 6. テストツール

### 6.1 使用ツール一覧

| ツール | 用途 | バージョン |
|--------|------|-----------|
| **pytest** | テストフレームワーク | 7.4+ |
| **pytest-cov** | カバレッジ測定 | 4.1+ |
| **pytest-asyncio** | 非同期テスト | 0.21+ |
| **httpx** | HTTP クライアント | 0.24+ |
| **faker** | テストデータ生成 | 19.0+ |
| **factory-boy** | モデルファクトリ | 3.3+ |
| **freezegun** | 時間モック | 1.2+ |

### 6.2 pytest設定

**ファイル**: `relay_server/pytest.ini`

```ini
[pytest]
testpaths = tests
python_files = test_*.py
python_classes = Test*
python_functions = test_*

# マーカー定義
markers =
    unit: Unit tests
    integration: Integration tests
    e2e: End-to-end tests
    slow: Slow running tests
    db: Tests requiring database

# カバレッジ設定
addopts =
    --cov=app
    --cov-report=html
    --cov-report=term-missing
    --cov-fail-under=80
    -v
    --strict-markers

# 並列実行
# addopts = -n auto

# 環境変数
env =
    ENVIRONMENT=test
    DATABASE_URL=sqlite:///:memory:
```

### 6.3 依存関係

**ファイル**: `relay_server/requirements-test.txt`

```
# Testing
pytest==7.4.3
pytest-cov==4.1.0
pytest-asyncio==0.21.1
pytest-env==1.1.1
pytest-xdist==3.5.0  # 並列実行

# HTTP Testing
httpx==0.25.2
requests-mock==1.11.0

# Test Data
faker==19.13.0
factory-boy==3.3.0

# Time Mocking
freezegun==1.2.2

# Database Testing
pytest-postgresql==5.0.0
```

---

## 7. テストケース設計

### 7.1 テストケーステンプレート

```python
def test_<機能名>_<条件>_<期待結果>(self, fixtures):
    """
    テストの説明

    Given: 前提条件
    When: 実行する操作
    Then: 期待される結果
    """
    # ========================================
    # Arrange（準備）
    # ========================================
    # テストデータの準備

    # ========================================
    # Act（実行）
    # ========================================
    # テスト対象の実行

    # ========================================
    # Assert（検証）
    # ========================================
    # 結果の検証
```

### 7.2 テストデータファクトリ

**ファイル**: `tests/factories.py`

```python
import factory
from faker import Faker
from app.models.signal import Signal
from app.models.position import Position

fake = Faker('ja_JP')

class SignalFactory(factory.Factory):
    """Signalモデルのファクトリ"""

    class Meta:
        model = Signal

    signal_id = factory.Sequence(lambda n: f'SIG-20250127-{n:03d}')
    strategy = factory.Iterator(['momentum_breakout', 'mean_reversion', 'trend_following'])
    ticker = factory.Iterator(['7203', '9984', '6758', '4063'])
    action = factory.Iterator(['buy', 'sell'])
    quantity = factory.Faker('random_int', min=100, max=1000, step=100)
    price_type = 'market'
    signal_strength = factory.Faker('random.uniform', min=0.5, max=1.0)
    checksum = factory.Faker('sha256')

class PositionFactory(factory.Factory):
    """Positionモデルのファクトリ"""

    class Meta:
        model = Position

    ticker = factory.Iterator(['7203', '9984', '6758'])
    quantity = factory.Faker('random_int', min=100, max=1000, step=100)
    entry_price = factory.Faker('random.uniform', min=1000, max=5000)
    current_price = factory.LazyAttribute(
        lambda obj: obj.entry_price * fake.random.uniform(0.95, 1.05)
    )

# 使用例
def test_with_factory():
    # 1つのシグナルを生成
    signal = SignalFactory()

    # 複数のシグナルを生成
    signals = SignalFactory.create_batch(5)

    # カスタマイズ
    custom_signal = SignalFactory(ticker='7203', action='buy')
```

### 7.3 モック・スタブ

**ファイル**: `tests/mocks.py`

```python
from unittest.mock import Mock, MagicMock
from typing import Dict, Any

class MockSlackNotifier:
    """Slack通知のモック"""

    def __init__(self):
        self.sent_messages = []

    def send(self, level: str, title: str, fields: list, mention_channel: bool = False):
        """通知送信をモック"""
        message = {
            'level': level,
            'title': title,
            'fields': fields,
            'mention_channel': mention_channel
        }
        self.sent_messages.append(message)
        return True

    def assert_sent(self, title: str):
        """特定のタイトルが送信されたか確認"""
        assert any(msg['title'] == title for msg in self.sent_messages), \
            f"Message with title '{title}' was not sent"

class MockEmailNotifier:
    """メール通知のモック"""

    def __init__(self):
        self.sent_emails = []

    def send(self, level: str, title: str, fields: list):
        """メール送信をモック"""
        email = {
            'level': level,
            'title': title,
            'fields': fields
        }
        self.sent_emails.append(email)
        return True

# 使用例
@pytest.fixture
def mock_notifier(monkeypatch):
    """通知のモックフィクスチャ"""
    mock_slack = MockSlackNotifier()
    mock_email = MockEmailNotifier()

    # 実際のNotificationManagerを差し替え
    from app.core import notification
    monkeypatch.setattr(notification, 'slack_notifier', mock_slack)
    monkeypatch.setattr(notification, 'email_notifier', mock_email)

    return {
        'slack': mock_slack,
        'email': mock_email
    }

def test_notification_sent(mock_notifier):
    """通知が送信されるかテスト"""
    # Act
    from app.services.signal_generator import SignalGenerator
    generator = SignalGenerator()
    generator.generate_and_notify(...)

    # Assert
    mock_notifier['slack'].assert_sent('Signal Generated')
```

---

## 8. CI/CD統合

### 8.1 GitHub Actions設定

**ファイル**: `.github/workflows/test.yml`

```yaml
name: Tests

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main, develop ]

jobs:
  test:
    runs-on: ubuntu-latest

    strategy:
      matrix:
        python-version: ['3.9', '3.10', '3.11']

    steps:
    - uses: actions/checkout@v3

    - name: Set up Python ${{ matrix.python-version }}
      uses: actions/setup-python@v4
      with:
        python-version: ${{ matrix.python-version }}

    - name: Cache dependencies
      uses: actions/cache@v3
      with:
        path: ~/.cache/pip
        key: ${{ runner.os }}-pip-${{ hashFiles('**/requirements*.txt') }}
        restore-keys: |
          ${{ runner.os }}-pip-

    - name: Install dependencies
      run: |
        cd relay_server
        python -m pip install --upgrade pip
        pip install -r requirements.txt
        pip install -r requirements-test.txt

    - name: Run unit tests
      run: |
        cd relay_server
        pytest tests/unit/ -v --cov=app --cov-report=xml

    - name: Run integration tests
      run: |
        cd relay_server
        pytest tests/integration/ -v

    - name: Run E2E tests
      run: |
        cd relay_server
        pytest tests/e2e/ -v

    - name: Upload coverage to Codecov
      uses: codecov/codecov-action@v3
      with:
        files: ./relay_server/coverage.xml
        flags: unittests
        name: codecov-umbrella

    - name: Check coverage threshold
      run: |
        cd relay_server
        pytest --cov=app --cov-fail-under=80
```

### 8.2 pre-commit フック

**ファイル**: `.pre-commit-config.yaml`

```yaml
repos:
  - repo: local
    hooks:
      - id: pytest-unit
        name: Run unit tests
        entry: bash -c 'cd relay_server && pytest tests/unit/ -v'
        language: system
        pass_filenames: false
        always_run: true

      - id: pytest-coverage
        name: Check coverage
        entry: bash -c 'cd relay_server && pytest --cov=app --cov-fail-under=80 --cov-report=term-missing'
        language: system
        pass_filenames: false
        always_run: true
```

### 8.3 テスト実行スクリプト

**ファイル**: `relay_server/scripts/run_tests.sh`

```bash
#!/bin/bash

# テスト実行スクリプト

set -e  # エラーで停止

echo "========================================="
echo "Kabuto Relay Server - Test Runner"
echo "========================================="

# 引数処理
TEST_TYPE=${1:-all}  # all, unit, integration, e2e

# 環境変数設定
export ENVIRONMENT=test
export DATABASE_URL=sqlite:///:memory:

cd "$(dirname "$0")/.."

# 単体テスト
if [ "$TEST_TYPE" = "all" ] || [ "$TEST_TYPE" = "unit" ]; then
    echo ""
    echo "Running Unit Tests..."
    pytest tests/unit/ -v --cov=app --cov-report=html --cov-report=term-missing
fi

# 統合テスト
if [ "$TEST_TYPE" = "all" ] || [ "$TEST_TYPE" = "integration" ]; then
    echo ""
    echo "Running Integration Tests..."
    pytest tests/integration/ -v
fi

# E2Eテスト
if [ "$TEST_TYPE" = "all" ] || [ "$TEST_TYPE" = "e2e" ]; then
    echo ""
    echo "Running E2E Tests..."
    pytest tests/e2e/ -v
fi

echo ""
echo "========================================="
echo "All tests completed!"
echo "========================================="
echo ""
echo "Coverage report: htmlcov/index.html"
```

**使用方法**:
```bash
# 全テスト実行
./scripts/run_tests.sh all

# 単体テストのみ
./scripts/run_tests.sh unit

# 統合テストのみ
./scripts/run_tests.sh integration

# E2Eテストのみ
./scripts/run_tests.sh e2e
```

---

## まとめ

### 実装必要項目

#### ディレクトリ構造
```
relay_server/
├── tests/
│   ├── __init__.py
│   ├── conftest.py           # pytest設定・フィクスチャ
│   ├── factories.py          # テストデータファクトリ
│   ├── mocks.py              # モック・スタブ
│   ├── unit/
│   │   ├── __init__.py
│   │   ├── test_signal_generator.py
│   │   ├── test_risk_manager.py
│   │   ├── test_models.py
│   │   └── test_utils.py
│   ├── integration/
│   │   ├── __init__.py
│   │   ├── test_signal_api.py
│   │   ├── test_heartbeat_api.py
│   │   └── test_database.py
│   └── e2e/
│       ├── __init__.py
│       └── test_trading_flow.py
├── scripts/
│   └── run_tests.sh
├── pytest.ini
├── requirements-test.txt
└── .github/
    └── workflows/
        └── test.yml
```

#### テストカバレッジ目標
- **Core Business Logic**: 95%以上
- **API Endpoints**: 90%以上
- **Database Models**: 85%以上
- **全体**: 80%以上

#### CI/CD統合
- GitHub Actions で自動テスト
- pre-commit フックでローカルテスト
- Codecov でカバレッジ可視化

---

**テスト計画完成日**: 2025-12-27
