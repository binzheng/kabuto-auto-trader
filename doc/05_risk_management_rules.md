# 日本株自動売買システム - 戦略内リスク管理ルール

## 概要

本文書では、トレード戦略内で実装する4つの主要なリスク管理ルールを定義します。これらは全て TradingView Pine Script で実装され、エントリー前に自動チェックされます。

---

## 1. 日次取引回数制限

### 1.1 設計方針

**目的：** 過剰取引（オーバートレーディング）による手数料負担増加と感情的判断を防止

**制限ルール：**
```yaml
daily_trade_limits:
  max_entries_per_day: 3        # 1日最大3回エントリー
  max_entries_per_ticker: 1     # 同一銘柄は1日1回まで
  reset_time: "00:00 JST"       # 日本時間0時にリセット
```

### 1.2 Pine Script 実装

```pinescript
//@version=5
strategy("Daily Trade Limit", overlay=true)

// === 日次取引回数カウンター ===
var int dailyEntryCount = 0      // 当日のエントリー回数
var int lastEntryDay = 0         // 最後にエントリーした日
var bool enteredToday = false    // 今日既にエントリーしたか（同一銘柄チェック用）

// 現在の日付を取得（JST）
currentDay = dayofmonth(time, "Asia/Tokyo")
currentMonth = month(time, "Asia/Tokyo")
currentYear = year(time, "Asia/Tokyo")

// 日付が変わったらカウンターをリセット
if (currentDay != lastEntryDay)
    dailyEntryCount := 0
    enteredToday := false
    lastEntryDay := currentDay

// === 日次制限チェック関数 ===
MAX_DAILY_ENTRIES = 3

canEnterToday() =>
    // 条件1: 今日のエントリー回数が上限未満
    condition1 = dailyEntryCount < MAX_DAILY_ENTRIES

    // 条件2: この銘柄で今日まだエントリーしていない
    condition2 = not enteredToday

    condition1 and condition2

// === エントリーロジック（簡略版）===
longCondition = <your entry conditions>

// 日次制限を考慮したエントリー
if (longCondition and canEnterToday())
    strategy.entry("Long", strategy.long)

    // カウンター更新
    dailyEntryCount := dailyEntryCount + 1
    enteredToday := true

    // Alert 送信
    alert('{"action":"buy","ticker":"' + syminfo.ticker + '","daily_count":' + str.tostring(dailyEntryCount) + '}', alert.freq_once_per_bar)

// === モニタリング表示 ===
var table infoTable = table.new(position.top_right, 2, 3, border_width=1)
if (barstate.islast)
    table.cell(infoTable, 0, 0, "Daily Entries", bgcolor=color.gray, text_color=color.white)
    table.cell(infoTable, 1, 0, str.tostring(dailyEntryCount) + "/" + str.tostring(MAX_DAILY_ENTRIES),
               bgcolor=dailyEntryCount >= MAX_DAILY_ENTRIES ? color.red : color.green,
               text_color=color.white)

    table.cell(infoTable, 0, 1, "Can Enter", bgcolor=color.gray, text_color=color.white)
    table.cell(infoTable, 1, 1, canEnterToday() ? "YES" : "NO",
               bgcolor=canEnterToday() ? color.green : color.red,
               text_color=color.white)
```

### 1.3 中継サーバー側での二重チェック

```python
# server/risk_manager.py
from datetime import datetime, timezone
from collections import defaultdict

class DailyTradeLimit:
    def __init__(self):
        self.max_daily_entries = 3
        self.daily_counts = defaultdict(int)  # {date: count}
        self.ticker_entries = defaultdict(set)  # {date: {ticker1, ticker2}}

    def can_enter(self, ticker: str) -> tuple[bool, str]:
        """エントリー可否を判定"""
        today = datetime.now(timezone.utc).date()

        # 前日のデータをクリア
        self._cleanup_old_data(today)

        # 日次上限チェック
        if self.daily_counts[today] >= self.max_daily_entries:
            return False, f"Daily entry limit reached ({self.max_daily_entries})"

        # 同一銘柄チェック
        if ticker in self.ticker_entries[today]:
            return False, f"Already entered {ticker} today"

        return True, "OK"

    def record_entry(self, ticker: str):
        """エントリーを記録"""
        today = datetime.now(timezone.utc).date()
        self.daily_counts[today] += 1
        self.ticker_entries[today].add(ticker)

    def _cleanup_old_data(self, today):
        """2日以上前のデータを削除"""
        old_dates = [d for d in self.daily_counts.keys() if (today - d).days > 1]
        for d in old_dates:
            del self.daily_counts[d]
            del self.ticker_entries[d]

# 使用例
trade_limiter = DailyTradeLimit()

@app.post("/webhook")
async def webhook_handler(payload: dict):
    ticker = payload["ticker"]
    action = payload["action"]

    if action == "buy":
        can_trade, reason = trade_limiter.can_enter(ticker)
        if not can_trade:
            logger.warning(f"Entry rejected: {reason}")
            return {"status": "rejected", "reason": reason}

        # エントリー承認
        trade_limiter.record_entry(ticker)
        # ... 注文処理
```

---

## 2. クールダウン（取引間隔制限）

### 2.1 設計方針

**目的：** 連続取引による感情的判断と、同一銘柄への過度な集中を防止

**制限ルール：**
```yaml
cooldown_rules:
  # 任意の銘柄間の最小間隔
  min_interval_any: 30_minutes    # どの銘柄でも30分は空ける

  # 同一銘柄の最小間隔
  min_interval_same_ticker: 240_minutes  # 同一銘柄は4時間空ける

  # 損切り後のペナルティ
  cooldown_after_loss: 60_minutes  # 損切り後は60分待機
```

### 2.2 Pine Script 実装

```pinescript
//@version=5
strategy("Cooldown Manager", overlay=true)

// === クールダウン管理変数 ===
var int lastEntryTime = 0           // 最後のエントリー時刻（any ticker）
var int lastExitTime = 0            // 最後のエグジット時刻
var bool lastExitWasLoss = false    // 最後のエグジットが損切りだったか
var int tickerLastEntryTime = 0     // この銘柄での最後のエントリー時刻

// === クールダウン期間設定（分） ===
COOLDOWN_ANY = 30                   // 30分
COOLDOWN_SAME_TICKER = 240          // 4時間
COOLDOWN_AFTER_LOSS = 60            // 60分

// === クールダウンチェック関数 ===
isInCooldown() =>
    currentTime = time

    // 1. 前回エントリーからの経過時間（任意銘柄）
    timeSinceLastEntry = (currentTime - lastEntryTime) / (1000 * 60)  // ミリ秒→分
    cooldown1 = timeSinceLastEntry < COOLDOWN_ANY

    // 2. 前回エントリーからの経過時間（同一銘柄）
    timeSinceTickerEntry = (currentTime - tickerLastEntryTime) / (1000 * 60)
    cooldown2 = timeSinceTickerEntry < COOLDOWN_SAME_TICKER

    // 3. 損切り後のペナルティ期間
    timeSinceLastExit = (currentTime - lastExitTime) / (1000 * 60)
    cooldown3 = lastExitWasLoss and timeSinceLastExit < COOLDOWN_AFTER_LOSS

    // いずれかのクールダウン中ならtrue
    cooldown1 or cooldown2 or cooldown3

// クールダウン理由を取得（デバッグ用）
getCooldownReason() =>
    currentTime = time
    timeSinceLastEntry = (currentTime - lastEntryTime) / (1000 * 60)
    timeSinceTickerEntry = (currentTime - tickerLastEntryTime) / (1000 * 60)
    timeSinceLastExit = (currentTime - lastExitTime) / (1000 * 60)

    reason = ""
    if timeSinceLastEntry < COOLDOWN_ANY
        reason := "Global cooldown: " + str.tostring(COOLDOWN_ANY - timeSinceLastEntry, "#.#") + "min left"
    else if timeSinceTickerEntry < COOLDOWN_SAME_TICKER
        reason := "Ticker cooldown: " + str.tostring(COOLDOWN_SAME_TICKER - timeSinceTickerEntry, "#.#") + "min left"
    else if lastExitWasLoss and timeSinceLastExit < COOLDOWN_AFTER_LOSS
        reason := "Loss penalty: " + str.tostring(COOLDOWN_AFTER_LOSS - timeSinceLastExit, "#.#") + "min left"
    reason

// === エントリーロジック ===
longCondition = <your conditions>

if (longCondition and not isInCooldown())
    strategy.entry("Long", strategy.long)
    lastEntryTime := time
    tickerLastEntryTime := time

// === エグジットロジック ===
var float entryPrice = na
if strategy.position_size > 0 and na(entryPrice)
    entryPrice := close

stopLoss = entryPrice * 0.985
takeProfit = entryPrice * 1.03

if strategy.position_size > 0
    if close <= stopLoss or close >= takeProfit
        strategy.close("Long")

        // 損切りかどうかを記録
        lastExitWasLoss := close <= stopLoss
        lastExitTime := time
        entryPrice := na

// === 情報表示 ===
var table cooldownTable = table.new(position.bottom_right, 2, 4, border_width=1)
if barstate.islast
    table.cell(cooldownTable, 0, 0, "Cooldown Status", bgcolor=color.gray, text_color=color.white)
    table.cell(cooldownTable, 1, 0, isInCooldown() ? "ACTIVE" : "READY",
               bgcolor=isInCooldown() ? color.red : color.green,
               text_color=color.white)

    if isInCooldown()
        table.cell(cooldownTable, 0, 1, "Reason", bgcolor=color.gray, text_color=color.white)
        table.cell(cooldownTable, 1, 1, getCooldownReason(), text_color=color.white)
```

### 2.3 残り時間の可視化

```pinescript
// チャート上にクールダウン残り時間を表示
var label cooldownLabel = na
if barstate.islast and isInCooldown()
    if na(cooldownLabel)
        cooldownLabel := label.new(bar_index, high, getCooldownReason(),
                                    style=label.style_label_down,
                                    color=color.red,
                                    textcolor=color.white)
    else
        label.set_xy(cooldownLabel, bar_index, high)
        label.set_text(cooldownLabel, getCooldownReason())
else if not na(cooldownLabel)
    label.delete(cooldownLabel)
    cooldownLabel := na
```

---

## 3. ATR ベースの SL / TP

### 3.1 設計方針

**目的：** 銘柄ごとのボラティリティに応じた動的なストップロス・テイクプロフィット設定

**ATR（Average True Range）の利点：**
- 高ボラティリティ銘柄 → 広めの SL/TP（ノイズで刈られない）
- 低ボラティリティ銘柄 → 狭めの SL/TP（小さな変動で利確）

**基本ルール：**
```yaml
atr_settings:
  period: 14                    # ATR 期間
  stop_loss_multiplier: 2.0     # SL = エントリー価格 - (ATR * 2.0)
  take_profit_multiplier: 4.0   # TP = エントリー価格 + (ATR * 4.0)
  min_rr_ratio: 1.5             # 最低リスクリワード比率
```

### 3.2 Pine Script 実装

```pinescript
//@version=5
strategy("ATR-Based SL/TP", overlay=true, initial_capital=1000000, default_qty_type=strategy.percent_of_equity, default_qty_value=10)

// === ATR 設定 ===
ATR_PERIOD = 14
ATR_SL_MULTIPLIER = 2.0
ATR_TP_MULTIPLIER = 4.0
MIN_RR_RATIO = 1.5

// ATR 計算
atrValue = ta.atr(ATR_PERIOD)

// === エントリー条件（簡略版）===
ema5 = ta.ema(close, 5)
ema25 = ta.ema(close, 25)
ema75 = ta.ema(close, 75)

longCondition = ta.crossover(ema5, ema25) and ema25 > ema75

// === ATR ベース SL/TP 計算 ===
var float entryPrice = na
var float stopLossPrice = na
var float takeProfitPrice = na

if (longCondition and strategy.position_size == 0)
    // エントリー価格を現在の終値で仮定
    entryPrice := close

    // ATR ベースの SL/TP を計算
    stopLossPrice := entryPrice - (atrValue * ATR_SL_MULTIPLIER)
    takeProfitPrice := entryPrice + (atrValue * ATR_TP_MULTIPLIER)

    // リスクリワード比率の検証
    riskAmount = entryPrice - stopLossPrice
    rewardAmount = takeProfitPrice - entryPrice
    rrRatio = rewardAmount / riskAmount

    // RR比率が基準を満たす場合のみエントリー
    if (rrRatio >= MIN_RR_RATIO)
        strategy.entry("Long", strategy.long)

        // デバッグログ
        log.info("Entry: " + str.tostring(entryPrice) +
                 " | SL: " + str.tostring(stopLossPrice) +
                 " | TP: " + str.tostring(takeProfitPrice) +
                 " | ATR: " + str.tostring(atrValue) +
                 " | RR: " + str.tostring(rrRatio, "#.##"))

// === エグジット（SL/TP）===
if (strategy.position_size > 0)
    // ストップロス
    strategy.exit("Exit", "Long", stop=stopLossPrice, limit=takeProfitPrice)

// ポジションクローズ時にリセット
if (strategy.position_size == 0 and not na(entryPrice))
    entryPrice := na
    stopLossPrice := na
    takeProfitPrice := na

// === チャート表示 ===
// エントリー価格
plot(strategy.position_size > 0 ? entryPrice : na, "Entry Price", color=color.blue, linewidth=2, style=plot.style_linebr)

// ストップロス
plot(strategy.position_size > 0 ? stopLossPrice : na, "Stop Loss", color=color.red, linewidth=2, style=plot.style_linebr)

// テイクプロフィット
plot(strategy.position_size > 0 ? takeProfitPrice : na, "Take Profit", color=color.green, linewidth=2, style=plot.style_linebr)

// ATR バンド（参考）
plot(close + atrValue * 2, "ATR Upper", color=color.gray, linewidth=1, style=plot.style_circles)
plot(close - atrValue * 2, "ATR Lower", color=color.gray, linewidth=1, style=plot.style_circles)

// === 情報テーブル ===
var table atrTable = table.new(position.top_left, 2, 5, border_width=1)
if barstate.islast
    table.cell(atrTable, 0, 0, "ATR (14)", bgcolor=color.gray, text_color=color.white)
    table.cell(atrTable, 1, 0, str.tostring(atrValue, "#.##"), text_color=color.white)

    table.cell(atrTable, 0, 1, "Entry", bgcolor=color.gray, text_color=color.white)
    table.cell(atrTable, 1, 1, strategy.position_size > 0 ? str.tostring(entryPrice, "#.##") : "-", text_color=color.white)

    table.cell(atrTable, 0, 2, "Stop Loss", bgcolor=color.gray, text_color=color.white)
    table.cell(atrTable, 1, 2, strategy.position_size > 0 ? str.tostring(stopLossPrice, "#.##") : "-",
               bgcolor=color.red, text_color=color.white)

    table.cell(atrTable, 0, 3, "Take Profit", bgcolor=color.gray, text_color=color.white)
    table.cell(atrTable, 1, 3, strategy.position_size > 0 ? str.tostring(takeProfitPrice, "#.##") : "-",
               bgcolor=color.green, text_color=color.white)

    if strategy.position_size > 0
        riskAmount = entryPrice - stopLossPrice
        rewardAmount = takeProfitPrice - entryPrice
        rrRatio = rewardAmount / riskAmount

        table.cell(atrTable, 0, 4, "Risk/Reward", bgcolor=color.gray, text_color=color.white)
        table.cell(atrTable, 1, 4, str.tostring(rrRatio, "#.##") + ":1",
                   bgcolor=rrRatio >= 2 ? color.green : color.orange,
                   text_color=color.white)
```

### 3.3 ATR の適応的調整

```pinescript
// ボラティリティレジームに応じた動的調整
getAtrMultiplier() =>
    // 現在の ATR を長期平均と比較
    atrMa = ta.sma(atrValue, 50)
    volatilityRatio = atrValue / atrMa

    // 高ボラティリティ期間は広めに、低ボラティリティ期間は狭めに
    slMultiplier = volatilityRatio > 1.2 ? 2.5 :  // 高ボラ → 2.5倍
                   volatilityRatio < 0.8 ? 1.5 :  // 低ボラ → 1.5倍
                   2.0                             // 通常 → 2.0倍

    tpMultiplier = slMultiplier * 2  // TPは常にSLの2倍

    [slMultiplier, tpMultiplier]

// 使用例
[dynamicSL, dynamicTP] = getAtrMultiplier()
stopLossPrice := entryPrice - (atrValue * dynamicSL)
takeProfitPrice := entryPrice + (atrValue * dynamicTP)
```

---

## 4. 時間帯制限（日本市場）

### 4.1 設計方針

**日本株市場の特性を考慮した時間帯フィルター：**

```yaml
trading_sessions:
  # 前場
  morning_session:
    start: "09:00"
    end: "11:30"
    avoid_first: 30  # 寄付後30分は避ける → 9:30から
    avoid_last: 10   # 前引け前10分は避ける → 11:20まで

  # 後場
  afternoon_session:
    start: "12:30"
    end: "15:00"
    avoid_first: 15  # 後場寄付後15分は避ける → 12:45から
    avoid_last: 30   # 大引け前30分は避ける → 14:30まで

  # 推奨取引時間
  optimal_hours:
    - "09:30 - 11:20"  # 前場中盤
    - "13:00 - 14:30"  # 後場中盤
```

**除外理由：**
- **寄付直後**：板が薄く、スプレッドが広い、誤発注リスク高
- **引け間際**：急激な値動き、翌日へのポジション持越しリスク
- **昼休み**：取引停止（12:30まで板寄せ待ち）

### 4.2 Pine Script 実装

```pinescript
//@version=5
strategy("Japan Market Hours Filter", overlay=true)

// === 日本時間の取得 ===
jstHour = hour(time, "Asia/Tokyo")
jstMinute = minute(time, "Asia/Tokyo")
jstTime = jstHour * 100 + jstMinute  // 例: 9:30 → 930

// === 取引可能時間帯の判定 ===
isMarketOpen() =>
    // 前場: 9:00-11:30
    morningSession = (jstTime >= 900 and jstTime <= 1130)

    // 後場: 12:30-15:00
    afternoonSession = (jstTime >= 1230 and jstTime <= 1500)

    morningSession or afternoonSession

isSafeToTrade() =>
    // 前場の安全時間: 9:30-11:20
    safeMorning = (jstTime >= 930 and jstTime <= 1120)

    // 後場の安全時間: 13:00-14:30
    safeAfternoon = (jstTime >= 1300 and jstTime <= 1430)

    safeMorning or safeAfternoon

// === より詳細な時間帯分類 ===
getSessionType() =>
    if jstTime >= 900 and jstTime < 930
        "opening_volatility"      // 寄付直後（避ける）
    else if jstTime >= 930 and jstTime <= 1100
        "morning_prime"           // 前場最適時間
    else if jstTime > 1100 and jstTime <= 1130
        "pre_lunch"               // 前引け前（避ける）
    else if jstTime >= 1230 and jstTime < 1300
        "afternoon_opening"       // 後場寄付（避ける）
    else if jstTime >= 1300 and jstTime <= 1430
        "afternoon_prime"         // 後場最適時間
    else if jstTime > 1430 and jstTime <= 1500
        "closing_volatility"      // 大引け前（避ける）
    else
        "closed"                  // 市場外

// === エントリー条件 ===
longCondition = <your conditions>

// 時間フィルター適用
if (longCondition and isSafeToTrade())
    strategy.entry("Long", strategy.long)

    // セッションタイプをログに記録
    sessionType = getSessionType()
    alert('{"action":"buy","session":"' + sessionType + '","time":"' + str.tostring(jstTime) + '"}',
          alert.freq_once_per_bar)

// === エグジットの時間制御 ===
// 大引け15分前（14:45）にはポジションをクローズ
forceCloseTime = 1445

if (strategy.position_size > 0 and jstTime >= forceCloseTime)
    strategy.close("Long", comment="Force close before market close")
    alert('{"action":"sell","reason":"market_close","time":"' + str.tostring(jstTime) + '"}',
          alert.freq_once_per_bar)

// === 背景色で取引時間帯を可視化 ===
bgcolor(getSessionType() == "morning_prime" ? color.new(color.green, 90) :
        getSessionType() == "afternoon_prime" ? color.new(color.blue, 90) :
        getSessionType() == "opening_volatility" or getSessionType() == "closing_volatility" ? color.new(color.red, 95) :
        color.new(color.gray, 98))

// === 時間情報テーブル ===
var table timeTable = table.new(position.bottom_left, 2, 4, border_width=1)
if barstate.islast
    table.cell(timeTable, 0, 0, "JST Time", bgcolor=color.gray, text_color=color.white)
    table.cell(timeTable, 1, 0, str.tostring(jstHour, "#00") + ":" + str.tostring(jstMinute, "#00"),
               text_color=color.white)

    table.cell(timeTable, 0, 1, "Session", bgcolor=color.gray, text_color=color.white)
    sessionType = getSessionType()
    sessionColor = sessionType == "morning_prime" or sessionType == "afternoon_prime" ? color.green :
                   sessionType == "opening_volatility" or sessionType == "closing_volatility" ? color.red :
                   color.orange
    table.cell(timeTable, 1, 1, sessionType, bgcolor=sessionColor, text_color=color.white)

    table.cell(timeTable, 0, 2, "Can Trade", bgcolor=color.gray, text_color=color.white)
    table.cell(timeTable, 1, 2, isSafeToTrade() ? "YES" : "NO",
               bgcolor=isSafeToTrade() ? color.green : color.red,
               text_color=color.white)

    table.cell(timeTable, 0, 3, "Market", bgcolor=color.gray, text_color=color.white)
    table.cell(timeTable, 1, 3, isMarketOpen() ? "OPEN" : "CLOSED",
               bgcolor=isMarketOpen() ? color.green : color.gray,
               text_color=color.white)
```

### 4.3 祝日・休場日の処理

```pinescript
// 日本の祝日判定（簡易版）
// 注: TradingView では祝日データを直接取得できないため、
// データが存在しない（volume == 0が連続）で判定

isHoliday() =>
    // 過去3本のバーで出来高がゼロなら休場日と判定
    noVolume = volume == 0 and volume[1] == 0 and volume[2] == 0
    noVolume

// エントリー条件に追加
if (longCondition and isSafeToTrade() and not isHoliday())
    strategy.entry("Long", strategy.long)
```

### 4.4 曜日フィルター（オプション）

```pinescript
// 曜日による取引制限（オプション）
// 例: 金曜日はポジションを持ち越さない

AVOID_FRIDAY_ENTRIES = true

isFriday() =>
    dayofweek(time, "Asia/Tokyo") == dayofweek.friday

canEnterByDayOfWeek() =>
    if AVOID_FRIDAY_ENTRIES
        not isFriday()
    else
        true

// エントリー条件に追加
if (longCondition and isSafeToTrade() and canEnterByDayOfWeek())
    strategy.entry("Long", strategy.long)
```

---

## 5. 統合リスク管理フレームワーク

### 5.1 全ルールを統合した完全版 Pine Script

```pinescript
//@version=5
strategy("Kabuto Complete Risk Management",
         overlay=true,
         initial_capital=1000000,
         default_qty_type=strategy.percent_of_equity,
         default_qty_value=10,
         commission_type=strategy.commission.percent,
         commission_value=0.05)

// ==========================================
// 1. 日次取引回数制限
// ==========================================
var int dailyEntryCount = 0
var int lastEntryDay = 0
var bool enteredToday = false
MAX_DAILY_ENTRIES = 3

currentDay = dayofmonth(time, "Asia/Tokyo")
if currentDay != lastEntryDay
    dailyEntryCount := 0
    enteredToday := false
    lastEntryDay := currentDay

canEnterDaily() => dailyEntryCount < MAX_DAILY_ENTRIES and not enteredToday

// ==========================================
// 2. クールダウン
// ==========================================
var int lastEntryTime = 0
var int lastExitTime = 0
var bool lastExitWasLoss = false
COOLDOWN_MINUTES = 30
COOLDOWN_AFTER_LOSS = 60

isInCooldown() =>
    timeSinceEntry = (time - lastEntryTime) / (1000 * 60)
    timeSinceExit = (time - lastExitTime) / (1000 * 60)

    globalCooldown = timeSinceEntry < COOLDOWN_MINUTES
    lossCooldown = lastExitWasLoss and timeSinceExit < COOLDOWN_AFTER_LOSS

    globalCooldown or lossCooldown

// ==========================================
// 3. ATR ベース SL/TP
// ==========================================
ATR_PERIOD = 14
ATR_SL_MULT = 2.0
ATR_TP_MULT = 4.0
MIN_RR = 1.5

atr = ta.atr(ATR_PERIOD)

var float entryPrice = na
var float slPrice = na
var float tpPrice = na

// ==========================================
// 4. 時間帯制限
// ==========================================
jstHour = hour(time, "Asia/Tokyo")
jstMinute = minute(time, "Asia/Tokyo")
jstTime = jstHour * 100 + jstMinute

isSafeTime() =>
    (jstTime >= 930 and jstTime <= 1120) or  // 前場
    (jstTime >= 1300 and jstTime <= 1430)     // 後場

// ==========================================
// エントリーロジック
// ==========================================
ema5 = ta.ema(close, 5)
ema25 = ta.ema(close, 25)
ema75 = ta.ema(close, 75)
rsi = ta.rsi(close, 14)

trendUp = ema25 > ema75
goldenCross = ta.crossover(ema5, ema25)
rsiOk = rsi > 50 and rsi < 70

longCondition = trendUp and goldenCross and rsiOk

// 全リスク管理チェック
allChecksPass = canEnterDaily() and not isInCooldown() and isSafeTime()

if (longCondition and allChecksPass and strategy.position_size == 0)
    entryPrice := close
    slPrice := entryPrice - (atr * ATR_SL_MULT)
    tpPrice := entryPrice + (atr * ATR_TP_MULT)

    rr = (tpPrice - entryPrice) / (entryPrice - slPrice)

    if rr >= MIN_RR
        strategy.entry("Long", strategy.long)

        // カウンター更新
        dailyEntryCount := dailyEntryCount + 1
        enteredToday := true
        lastEntryTime := time

// ==========================================
// エグジットロジック
// ==========================================
if strategy.position_size > 0
    strategy.exit("Exit", "Long", stop=slPrice, limit=tpPrice)

    // 大引け前強制クローズ
    if jstTime >= 1445
        strategy.close("Long", comment="Market close")

// エグジット検知
if strategy.position_size == 0 and not na(entryPrice)
    wasLoss = strategy.closedtrades.profit(strategy.closedtrades - 1) < 0
    lastExitWasLoss := wasLoss
    lastExitTime := time
    entryPrice := na

// ==========================================
// 可視化
// ==========================================
plot(strategy.position_size > 0 ? entryPrice : na, "Entry", color.blue, 2)
plot(strategy.position_size > 0 ? slPrice : na, "SL", color.red, 2)
plot(strategy.position_size > 0 ? tpPrice : na, "TP", color.green, 2)

// 取引可能時間帯を背景色で表示
bgcolor(isSafeTime() ? color.new(color.green, 95) : color.new(color.red, 98))

// ==========================================
// 情報パネル
// ==========================================
var table panel = table.new(position.top_right, 2, 6, border_width=1)
if barstate.islast
    // 日次カウント
    table.cell(panel, 0, 0, "Daily Entries", bgcolor=color.gray, text_color=color.white)
    table.cell(panel, 1, 0, str.tostring(dailyEntryCount) + "/" + str.tostring(MAX_DAILY_ENTRIES),
               bgcolor=dailyEntryCount >= MAX_DAILY_ENTRIES ? color.red : color.green,
               text_color=color.white)

    // クールダウン
    table.cell(panel, 0, 1, "Cooldown", bgcolor=color.gray, text_color=color.white)
    table.cell(panel, 1, 1, isInCooldown() ? "ACTIVE" : "OK",
               bgcolor=isInCooldown() ? color.red : color.green,
               text_color=color.white)

    // 時間帯
    table.cell(panel, 0, 2, "Time", bgcolor=color.gray, text_color=color.white)
    table.cell(panel, 1, 2, str.tostring(jstHour, "#00") + ":" + str.tostring(jstMinute, "#00"),
               text_color=color.white)

    table.cell(panel, 0, 3, "Safe Time", bgcolor=color.gray, text_color=color.white)
    table.cell(panel, 1, 3, isSafeTime() ? "YES" : "NO",
               bgcolor=isSafeTime() ? color.green : color.red,
               text_color=color.white)

    // ATR
    table.cell(panel, 0, 4, "ATR(14)", bgcolor=color.gray, text_color=color.white)
    table.cell(panel, 1, 4, str.tostring(atr, "#.##"), text_color=color.white)

    // 総合判定
    table.cell(panel, 0, 5, "Can Trade", bgcolor=color.gray, text_color=color.white)
    table.cell(panel, 1, 5, allChecksPass ? "YES" : "NO",
               bgcolor=allChecksPass ? color.green : color.red,
               text_color=color.white)
```

---

## 6. パフォーマンス指標の監視

```python
# server/performance_monitor.py
from dataclasses import dataclass
from datetime import datetime

@dataclass
class RiskMetrics:
    """リスク管理指標"""
    daily_trade_count: int
    trades_rejected_by_limit: int
    trades_rejected_by_cooldown: int
    trades_rejected_by_time: int
    avg_rr_ratio: float
    sl_triggered_count: int
    tp_triggered_count: int

class RiskMonitor:
    def __init__(self):
        self.metrics = RiskMetrics(
            daily_trade_count=0,
            trades_rejected_by_limit=0,
            trades_rejected_by_cooldown=0,
            trades_rejected_by_time=0,
            avg_rr_ratio=0.0,
            sl_triggered_count=0,
            tp_triggered_count=0
        )

    def generate_report(self) -> dict:
        """日次リスク管理レポート"""
        return {
            "date": datetime.now().date(),
            "metrics": {
                "total_signals": (
                    self.metrics.daily_trade_count +
                    self.metrics.trades_rejected_by_limit +
                    self.metrics.trades_rejected_by_cooldown +
                    self.metrics.trades_rejected_by_time
                ),
                "executed_trades": self.metrics.daily_trade_count,
                "rejection_rate": self._calculate_rejection_rate(),
                "rejection_breakdown": {
                    "daily_limit": self.metrics.trades_rejected_by_limit,
                    "cooldown": self.metrics.trades_rejected_by_cooldown,
                    "time_filter": self.metrics.trades_rejected_by_time
                },
                "exit_breakdown": {
                    "stop_loss": self.metrics.sl_triggered_count,
                    "take_profit": self.metrics.tp_triggered_count
                },
                "avg_risk_reward": round(self.metrics.avg_rr_ratio, 2)
            }
        }

    def _calculate_rejection_rate(self) -> float:
        total = (
            self.metrics.daily_trade_count +
            self.metrics.trades_rejected_by_limit +
            self.metrics.trades_rejected_by_cooldown +
            self.metrics.trades_rejected_by_time
        )
        if total == 0:
            return 0.0
        rejected = total - self.metrics.daily_trade_count
        return round(rejected / total * 100, 1)
```

---

*最終更新: 2025-12-27*

**実装優先度：**
1. **時間帯制限**（最重要）- 市場の特性に直結
2. **ATR ベース SL/TP**（重要）- リスク管理の核
3. **日次取引回数制限**（重要）- 過剰取引防止
4. **クールダウン**（推奨）- 感情的判断の防止
