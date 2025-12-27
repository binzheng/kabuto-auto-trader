# 日本株自動売買システム - Webhook API 設計書

## 概要

本文書では、TradingView からの Webhook を受信し、トレードシグナルを処理するサーバー API の設計を定義します。**言語非依存**の設計とし、HTTP プロトコル、REST 原則に基づいて記述します。

---

## 1. API エンドポイント設計

### 1.1 ベースURL

```
Production:  https://api.yourdomain.com
Development: https://dev-api.yourdomain.com
Local:       http://localhost:8000
```

### 1.2 エンドポイント一覧

| エンドポイント | メソッド | 用途 | 認証 |
|---------------|---------|------|------|
| `/webhook` | POST | TradingView シグナル受信 | ✅ Passphrase |
| `/webhook/test` | POST | Webhook テスト用 | ✅ Passphrase |
| `/health` | GET | ヘルスチェック | ❌ 不要 |
| `/status` | GET | システム状態取得 | ✅ API Key |
| `/orders` | GET | 注文履歴取得 | ✅ API Key |
| `/orders/{order_id}` | GET | 個別注文詳細 | ✅ API Key |
| `/positions` | GET | 現在ポジション取得 | ✅ API Key |
| `/admin/kill-switch` | POST | 緊急停止 | ✅ Admin Password |

---

## 2. メインエンドポイント詳細

### 2.1 POST /webhook

**用途：** TradingView からトレードシグナルを受信

#### リクエスト仕様

**Headers:**
```http
POST /webhook HTTP/1.1
Host: api.yourdomain.com
Content-Type: application/json
User-Agent: TradingView-Webhook
X-Request-ID: <optional-uuid>
```

**Body (JSON):**

#### エントリーシグナル
```json
{
  "action": "buy",
  "ticker": "9984",
  "quantity": 100,
  "price": "market",
  "entry_price": 3000.50,
  "stop_loss": 2940.25,
  "take_profit": 3120.75,
  "atr": 30.12,
  "rr_ratio": 2.0,
  "rsi": 62.5,
  "timestamp": "1735279200000",
  "passphrase": "your-secret-passphrase-here"
}
```

#### エグジットシグナル
```json
{
  "action": "sell",
  "ticker": "9984",
  "quantity": 100,
  "price": "market",
  "exit_reason": "take_profit",
  "exit_price": 3120.75,
  "timestamp": "1735365600000",
  "passphrase": "your-secret-passphrase-here"
}
```

#### フィールド定義

| フィールド | 型 | 必須 | 説明 | 制約 |
|-----------|-----|------|------|------|
| `action` | string | ✅ | 売買区分 | `"buy"` または `"sell"` |
| `ticker` | string | ✅ | 銘柄コード | 4桁の数字（例: "9984"） |
| `quantity` | integer | ✅ | 数量 | > 0、100の倍数 |
| `price` | string\|number | ✅ | 価格 | `"market"` または数値 |
| `entry_price` | number | ❌ | エントリー価格 | > 0（buyのみ） |
| `stop_loss` | number | ❌ | 損切り価格 | > 0（buyのみ） |
| `take_profit` | number | ❌ | 利確価格 | > 0（buyのみ） |
| `atr` | number | ❌ | ATR値 | > 0 |
| `rr_ratio` | number | ❌ | リスクリワード比 | > 0 |
| `rsi` | number | ❌ | RSI値 | 0-100 |
| `exit_reason` | string | ❌ | エグジット理由 | `"stop_loss"`, `"take_profit"`, `"market_close"` |
| `exit_price` | number | ❌ | エグジット価格 | > 0（sellのみ） |
| `timestamp` | string | ✅ | タイムスタンプ | Unix時間（ミリ秒）の文字列 |
| `passphrase` | string | ✅ | 認証パスフレーズ | 20文字以上 |

#### レスポンス仕様

**成功時（200 OK）:**
```json
{
  "status": "success",
  "message": "Signal received and processed",
  "data": {
    "request_id": "req_1234567890abcdef",
    "ticker": "9984",
    "action": "buy",
    "quantity": 100,
    "order_id": "ORD_20251227_001",
    "timestamp": "2025-12-27T10:30:45.123Z",
    "processing_time_ms": 127
  }
}
```

**受理済み（202 Accepted）:**
```json
{
  "status": "accepted",
  "message": "Signal queued for processing",
  "data": {
    "request_id": "req_1234567890abcdef",
    "queue_position": 3,
    "estimated_processing_time_ms": 500
  }
}
```

**バリデーションエラー（400 Bad Request）:**
```json
{
  "status": "error",
  "message": "Validation failed",
  "errors": [
    {
      "field": "ticker",
      "message": "Invalid ticker format. Expected 4-digit code.",
      "value": "999"
    },
    {
      "field": "quantity",
      "message": "Quantity must be multiple of 100",
      "value": 150
    }
  ],
  "request_id": "req_1234567890abcdef",
  "timestamp": "2025-12-27T10:30:45.123Z"
}
```

**認証エラー（401 Unauthorized）:**
```json
{
  "status": "error",
  "message": "Invalid passphrase",
  "error_code": "AUTH_FAILED",
  "request_id": "req_1234567890abcdef",
  "timestamp": "2025-12-27T10:30:45.123Z"
}
```

**リスク制限超過（403 Forbidden）:**
```json
{
  "status": "error",
  "message": "Risk limit exceeded",
  "error_code": "RISK_LIMIT_EXCEEDED",
  "details": {
    "limit_type": "daily_trade_count",
    "current_value": 3,
    "max_value": 3,
    "reset_at": "2025-12-28T00:00:00Z"
  },
  "request_id": "req_1234567890abcdef",
  "timestamp": "2025-12-27T10:30:45.123Z"
}
```

**サーバーエラー（500 Internal Server Error）:**
```json
{
  "status": "error",
  "message": "Internal server error",
  "error_code": "INTERNAL_ERROR",
  "request_id": "req_1234567890abcdef",
  "timestamp": "2025-12-27T10:30:45.123Z"
}
```

---

### 2.2 POST /webhook/test

**用途：** Webhook の接続テスト（注文は実行しない）

#### リクエスト仕様

**Body (JSON):**
```json
{
  "action": "buy",
  "ticker": "9984",
  "quantity": 100,
  "price": "market",
  "passphrase": "your-secret-passphrase-here",
  "test_mode": true
}
```

#### レスポンス仕様

**成功時（200 OK）:**
```json
{
  "status": "success",
  "message": "Test webhook received successfully",
  "data": {
    "request_id": "req_test_1234567890",
    "validation_results": {
      "passphrase": "✅ Valid",
      "ticker": "✅ Valid (9984)",
      "quantity": "✅ Valid (100)",
      "price": "✅ Valid (market)",
      "json_format": "✅ Valid"
    },
    "risk_checks": {
      "daily_limit": "✅ OK (2/3)",
      "cooldown": "✅ OK (45 minutes since last trade)",
      "market_hours": "✅ OK (10:30 JST, within trading hours)"
    },
    "would_execute": true,
    "estimated_order_amount": 300000,
    "timestamp": "2025-12-27T10:30:45.123Z"
  }
}
```

---

### 2.3 GET /health

**用途：** サーバーのヘルスチェック

#### リクエスト仕様

```http
GET /health HTTP/1.1
Host: api.yourdomain.com
```

#### レスポンス仕様

**正常時（200 OK）:**
```json
{
  "status": "healthy",
  "timestamp": "2025-12-27T10:30:45.123Z",
  "uptime_seconds": 86400,
  "components": {
    "database": "healthy",
    "redis": "healthy",
    "windows_vm": "healthy",
    "market_data": "healthy"
  }
}
```

**異常時（503 Service Unavailable）:**
```json
{
  "status": "unhealthy",
  "timestamp": "2025-12-27T10:30:45.123Z",
  "components": {
    "database": "healthy",
    "redis": "healthy",
    "windows_vm": "unhealthy",
    "market_data": "healthy"
  },
  "errors": [
    {
      "component": "windows_vm",
      "message": "Connection timeout after 5000ms"
    }
  ]
}
```

---

### 2.4 GET /status

**用途：** システムの現在状態を取得

#### リクエスト仕様

```http
GET /status HTTP/1.1
Host: api.yourdomain.com
Authorization: Bearer <api-key>
```

#### レスポンス仕様

**成功時（200 OK）:**
```json
{
  "status": "success",
  "data": {
    "system_enabled": true,
    "trading_active": true,
    "market_open": true,
    "daily_stats": {
      "entries": 2,
      "exits": 1,
      "realized_pnl": 12500,
      "unrealized_pnl": 5000,
      "total_pnl": 17500
    },
    "current_positions": [
      {
        "ticker": "9984",
        "quantity": 100,
        "entry_price": 3000.50,
        "current_price": 3050.00,
        "unrealized_pnl": 4950
      }
    ],
    "risk_status": {
      "daily_entries": "2/3",
      "cooldown": "ready",
      "daily_loss": -0,
      "total_exposure": 305000
    },
    "timestamp": "2025-12-27T10:30:45.123Z"
  }
}
```

---

### 2.5 POST /admin/kill-switch

**用途：** システムの緊急停止

#### リクエスト仕様

```http
POST /admin/kill-switch HTTP/1.1
Host: api.yourdomain.com
Content-Type: application/json

{
  "password": "admin-password-here",
  "reason": "Manual emergency stop"
}
```

#### レスポンス仕様

**成功時（200 OK）:**
```json
{
  "status": "success",
  "message": "Kill switch activated - All trading stopped",
  "data": {
    "system_enabled": false,
    "stopped_at": "2025-12-27T10:30:45.123Z",
    "reason": "Manual emergency stop",
    "positions_at_stop": [
      {
        "ticker": "9984",
        "quantity": 100,
        "entry_price": 3000.50
      }
    ]
  }
}
```

---

## 3. 認証方法

### 3.1 Webhook 認証（Passphrase）

**方式：** リクエストボディ内の passphrase フィールドによる認証

**仕様：**
```yaml
method: "body_passphrase"
field_name: "passphrase"
storage: "environment_variable"  # WEBHOOK_SECRET
min_length: 20
validation: "constant_time_comparison"  # タイミング攻撃対策
```

**実装例（疑似コード）:**
```
function authenticate_webhook(request_body):
    received_passphrase = request_body.get("passphrase")
    expected_passphrase = env.get("WEBHOOK_SECRET")

    if not received_passphrase:
        return error(401, "Missing passphrase")

    # 定数時間比較（タイミング攻撃対策）
    if not constant_time_compare(received_passphrase, expected_passphrase):
        return error(401, "Invalid passphrase")

    return success()
```

**セキュリティ考慮事項：**
- パスフレーズは環境変数に保存、コードに直接書かない
- 定数時間比較を使用（タイミング攻撃対策）
- ログにパスフレーズを記録しない
- 定期的な変更（3ヶ月ごと推奨）

### 3.2 API Key 認証（管理用エンドポイント）

**方式：** HTTP Authorization ヘッダーによる Bearer トークン認証

**仕様：**
```yaml
method: "bearer_token"
header: "Authorization: Bearer <api-key>"
format: "API_" + base64(random(32))  # 例: API_a1b2c3d4e5f6...
storage: "database"  # ハッシュ化して保存
expiration: "never"  # または 90日
```

**実装例（疑似コード）:**
```
function authenticate_api_key(request):
    auth_header = request.headers.get("Authorization")

    if not auth_header or not auth_header.startswith("Bearer "):
        return error(401, "Missing or invalid Authorization header")

    api_key = auth_header.replace("Bearer ", "")

    # DBで検証（ハッシュ化されたキーと比較）
    hashed_key = hash_api_key(api_key)
    if not db.api_keys.exists(hashed_key):
        return error(401, "Invalid API key")

    # 有効期限チェック
    key_record = db.api_keys.get(hashed_key)
    if key_record.expired:
        return error(401, "API key expired")

    return success(user_id=key_record.user_id)
```

### 3.3 Admin Password 認証（Kill Switch）

**方式：** リクエストボディ内の password フィールドによる認証

**仕様：**
```yaml
method: "body_password"
field_name: "password"
storage: "environment_variable"  # ADMIN_PASSWORD
min_length: 16
validation: "constant_time_comparison + bcrypt"
rate_limit: "5 requests per 5 minutes"
```

**実装例（疑似コード）:**
```
function authenticate_admin(request_body):
    received_password = request_body.get("password")
    expected_password_hash = env.get("ADMIN_PASSWORD_HASH")

    if not received_password:
        return error(401, "Missing password")

    # レート制限チェック
    if rate_limiter.exceeded("admin_auth", limit=5, window=300):
        return error(429, "Too many authentication attempts")

    # bcrypt検証
    if not bcrypt.verify(received_password, expected_password_hash):
        rate_limiter.increment("admin_auth")
        return error(401, "Invalid password")

    return success()
```

### 3.4 IP ホワイトリスト（オプション）

**方式：** 送信元IPアドレスによる制限

**仕様：**
```yaml
method: "ip_whitelist"
allowed_ips:
  - "52.89.214.238"    # TradingView
  - "34.212.75.30"     # TradingView
  - "54.218.53.128"    # TradingView
  - "52.32.178.7"      # TradingView
  - "192.168.1.0/24"   # 内部ネットワーク
enforcement: "warning"  # "strict" or "warning"
```

**実装例（疑似コード）:**
```
function check_ip_whitelist(request):
    client_ip = request.remote_addr
    allowed_ips = config.get("allowed_ips")

    if client_ip not in allowed_ips:
        if config.ip_enforcement == "strict":
            return error(403, "IP address not allowed")
        else:
            log.warning(f"Request from non-whitelisted IP: {client_ip}")

    return success()
```

---

## 4. エラー処理

### 4.1 エラー分類

| カテゴリ | HTTPステータス | error_code | 対処方法 |
|---------|---------------|------------|---------|
| **認証エラー** | 401 | AUTH_FAILED | パスフレーズ確認 |
| **バリデーションエラー** | 400 | VALIDATION_ERROR | リクエスト修正 |
| **リスク制限** | 403 | RISK_LIMIT_EXCEEDED | 制限解除待ち |
| **リソース未発見** | 404 | NOT_FOUND | URL確認 |
| **レート制限** | 429 | RATE_LIMIT_EXCEEDED | 待機後再試行 |
| **サーバーエラー** | 500 | INTERNAL_ERROR | 管理者連絡 |
| **サービス停止** | 503 | SERVICE_UNAVAILABLE | 復旧待ち |

### 4.2 統一エラーレスポンス形式

```json
{
  "status": "error",
  "message": "<human-readable error message>",
  "error_code": "<machine-readable code>",
  "details": {
    "<additional context>"
  },
  "request_id": "req_1234567890abcdef",
  "timestamp": "2025-12-27T10:30:45.123Z",
  "help_url": "https://docs.yourdomain.com/errors/<error_code>"
}
```

### 4.3 エラー処理フロー

```
┌─────────────────────────────────────┐
│     Webhook リクエスト受信           │
└──────────────┬──────────────────────┘
               │
               ▼
      【認証チェック】
      passphrase 検証
               │
         失敗  │  成功
    ┌──────────┴──────────┐
    │                     │
    ▼                     ▼
【401 Unauthorized】  【JSON パース】
return error         JSONデコード
                          │
                    失敗  │  成功
                 ┌────────┴────────┐
                 │                 │
                 ▼                 ▼
          【400 Bad Request】 【バリデーション】
          return error       必須フィールド、型、範囲
                                  │
                            失敗  │  成功
                         ┌────────┴────────┐
                         │                 │
                         ▼                 ▼
                  【400 Bad Request】 【ビジネスロジック検証】
                  return error       リスク制限、クールダウン等
                                          │
                                    失敗  │  成功
                                 ┌────────┴────────┐
                                 │                 │
                                 ▼                 ▼
                          【403 Forbidden】   【注文処理】
                          return error       Windows VMへ送信
                                                  │
                                            失敗  │  成功
                                         ┌────────┴────────┐
                                         │                 │
                                         ▼                 ▼
                                  【500 Error】      【200 OK】
                                  return error       return success
```

### 4.4 バリデーションルール

#### 必須フィールドチェック
```
required_fields = ["action", "ticker", "quantity", "price", "timestamp", "passphrase"]

for field in required_fields:
    if field not in request_body:
        return error(400, f"Missing required field: {field}")
```

#### 型チェック
```
type_rules = {
    "action": "string",
    "ticker": "string",
    "quantity": "integer",
    "price": "string|number",
    "timestamp": "string",
    "passphrase": "string"
}

for field, expected_type in type_rules.items():
    if not validate_type(request_body[field], expected_type):
        return error(400, f"Invalid type for {field}: expected {expected_type}")
```

#### 値の範囲チェック
```
# ticker: 4桁の数字
if not regex.match("^\d{4}$", request_body["ticker"]):
    return error(400, "Ticker must be 4-digit code")

# quantity: 正の整数、100の倍数
if request_body["quantity"] <= 0 or request_body["quantity"] % 100 != 0:
    return error(400, "Quantity must be positive and multiple of 100")

# action: buy or sell
if request_body["action"] not in ["buy", "sell"]:
    return error(400, "Action must be 'buy' or 'sell'")

# timestamp: 有効な時刻、5分以内
timestamp_ms = int(request_body["timestamp"])
current_ms = current_time_milliseconds()
if abs(current_ms - timestamp_ms) > 300000:  # 5分
    return error(400, "Timestamp expired (must be within 5 minutes)")
```

### 4.5 エラーログ記録

```json
{
  "level": "error",
  "timestamp": "2025-12-27T10:30:45.123Z",
  "request_id": "req_1234567890abcdef",
  "error_code": "VALIDATION_ERROR",
  "message": "Invalid ticker format",
  "details": {
    "field": "ticker",
    "value": "999",
    "expected": "4-digit code"
  },
  "request": {
    "method": "POST",
    "path": "/webhook",
    "source_ip": "52.89.214.238",
    "user_agent": "TradingView-Webhook"
  },
  "stack_trace": "<if applicable>"
}
```

---

## 5. リトライ・冪等性

### 5.1 冪等性の保証

**問題：** ネットワークエラー等でTradingViewが同じリクエストを複数回送信する可能性

**解決策：** リクエストIDによる重複排除

```yaml
idempotency:
  key_source: "timestamp + ticker + action"
  storage: "redis"
  ttl: 300  # 5分間保持
```

**実装例（疑似コード）:**
```
function ensure_idempotency(request_body):
    # 一意キーを生成
    idempotency_key = hash(
        request_body["timestamp"] +
        request_body["ticker"] +
        request_body["action"]
    )

    # Redisでチェック
    if redis.exists(f"idempotency:{idempotency_key}"):
        # 既に処理済み
        cached_response = redis.get(f"idempotency:{idempotency_key}")
        return cached_response

    # 新規リクエスト
    response = process_request(request_body)

    # 結果をキャッシュ（5分間）
    redis.setex(
        f"idempotency:{idempotency_key}",
        300,
        json.dumps(response)
    )

    return response
```

### 5.2 リトライポリシー（クライアント側）

**TradingView からのリトライ：**
- TradingView は自動リトライしない
- 手動で Alert を再送信する必要がある

**推奨リトライロジック（中継サーバー → Windows VM）:**
```yaml
retry_policy:
  max_attempts: 3
  initial_delay_ms: 1000
  max_delay_ms: 5000
  backoff_multiplier: 2
  retryable_errors:
    - "CONNECTION_TIMEOUT"
    - "SERVICE_UNAVAILABLE"
  non_retryable_errors:
    - "VALIDATION_ERROR"
    - "AUTH_FAILED"
```

**実装例（疑似コード）:**
```
function send_order_with_retry(order, max_attempts=3):
    attempt = 0
    delay = 1000  # 初期遅延1秒

    while attempt < max_attempts:
        try:
            response = send_to_windows_vm(order)
            return response

        except RetryableError as e:
            attempt += 1
            if attempt >= max_attempts:
                raise MaxRetriesExceeded(e)

            log.warning(f"Retry {attempt}/{max_attempts} after {delay}ms")
            sleep(delay)
            delay = min(delay * 2, 5000)  # 指数バックオフ

        except NonRetryableError as e:
            log.error(f"Non-retryable error: {e}")
            raise

    raise MaxRetriesExceeded()
```

---

## 6. レート制限

### 6.1 レート制限ポリシー

```yaml
rate_limits:
  webhook:
    per_minute: 60
    per_hour: 300
    per_day: 1000

  api_status:
    per_minute: 30

  admin_kill_switch:
    per_5_minutes: 5
```

### 6.2 レート制限レスポンス

**429 Too Many Requests:**
```json
{
  "status": "error",
  "message": "Rate limit exceeded",
  "error_code": "RATE_LIMIT_EXCEEDED",
  "details": {
    "limit": 60,
    "window": "1 minute",
    "retry_after_seconds": 42
  },
  "request_id": "req_1234567890abcdef",
  "timestamp": "2025-12-27T10:30:45.123Z"
}
```

**Headers:**
```http
HTTP/1.1 429 Too Many Requests
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1735279887
Retry-After: 42
```

---

## 7. セキュリティ考慮事項

### 7.1 HTTPS 必須

```yaml
https:
  enforced: true
  redirect_http_to_https: true
  certificate: "Let's Encrypt"
  tls_version: "1.2+"
  cipher_suites: "modern"
```

### 7.2 CORS 設定

```yaml
cors:
  enabled: false  # Webhook用エンドポイントはCORS不要
  allowed_origins: []
  allowed_methods: []
```

### 7.3 リクエストサイズ制限

```yaml
request_limits:
  max_body_size: "1MB"
  max_headers_size: "8KB"
  timeout_seconds: 30
```

### 7.4 ログ管理

```yaml
logging:
  # ログに含めない機密情報
  redact_fields:
    - "passphrase"
    - "password"
    - "api_key"

  # ログレベル
  levels:
    production: "INFO"
    development: "DEBUG"

  # ログ保持期間
  retention:
    audit_logs: 7_years
    error_logs: 1_year
    access_logs: 90_days
```

---

## 8. OpenAPI 仕様（抜粋）

```yaml
openapi: 3.0.0
info:
  title: Kabuto Trading System API
  version: 1.0.0
  description: TradingView Webhook受信API

servers:
  - url: https://api.yourdomain.com
    description: Production
  - url: http://localhost:8000
    description: Local development

paths:
  /webhook:
    post:
      summary: Receive trading signal from TradingView
      tags: [Webhook]
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/TradingSignal'
      responses:
        '200':
          description: Signal processed successfully
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/SuccessResponse'
        '400':
          description: Validation error
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ErrorResponse'
        '401':
          description: Authentication failed
        '403':
          description: Risk limit exceeded
        '500':
          description: Internal server error

components:
  schemas:
    TradingSignal:
      type: object
      required:
        - action
        - ticker
        - quantity
        - price
        - timestamp
        - passphrase
      properties:
        action:
          type: string
          enum: [buy, sell]
        ticker:
          type: string
          pattern: '^\d{4}$'
        quantity:
          type: integer
          minimum: 100
          multipleOf: 100
        price:
          oneOf:
            - type: string
              enum: [market]
            - type: number
              minimum: 0
        timestamp:
          type: string
        passphrase:
          type: string
          minLength: 20

    SuccessResponse:
      type: object
      properties:
        status:
          type: string
          enum: [success]
        message:
          type: string
        data:
          type: object

    ErrorResponse:
      type: object
      properties:
        status:
          type: string
          enum: [error]
        message:
          type: string
        error_code:
          type: string
        request_id:
          type: string
        timestamp:
          type: string
```

---

## まとめ

### 実装チェックリスト

```
✅ エンドポイント設計
  - POST /webhook（メイン）
  - POST /webhook/test（テスト用）
  - GET /health（ヘルスチェック）
  - GET /status（システム状態）
  - POST /admin/kill-switch（緊急停止）

✅ 認証方式
  - Passphraseベース（Webhook用）
  - API Keyベース（管理用）
  - Admin Passwordベース（Kill Switch用）
  - IP ホワイトリスト（オプション）

✅ バリデーション
  - 必須フィールドチェック
  - 型チェック
  - 値の範囲チェック
  - タイムスタンプ検証

✅ エラー処理
  - 統一エラーレスポンス形式
  - 詳細なエラーメッセージ
  - エラーログ記録

✅ セキュリティ
  - HTTPS必須
  - 定数時間比較
  - レート制限
  - ログの機密情報削除

✅ 冪等性・リトライ
  - リクエストID重複排除
  - 指数バックオフリトライ
  - タイムアウト処理
```

---

*最終更新: 2025-12-27*
