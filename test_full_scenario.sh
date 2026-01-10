#!/bin/bash
# Kabuto Auto Trader - 完全テストシナリオ

set -e

echo "🚀 Kabuto Auto Trader - Full Test Scenario"
echo "=========================================="

# 色定義
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 1. Kill Switch解除
echo -e "\n${YELLOW}1️⃣ Deactivating Kill Switch...${NC}"
python test_send_signal.py kill-off
sleep 2

# 2. システムステータス確認
echo -e "\n${YELLOW}2️⃣ Checking system status...${NC}"
python test_send_signal.py status
sleep 2

# 3. 買いシグナル送信（7203 トヨタ）
echo -e "\n${YELLOW}3️⃣ Sending BUY signal: 7203 x 100...${NC}"
python test_send_signal.py buy 7203 100
sleep 3

# 4. 保留中のシグナル確認
echo -e "\n${YELLOW}4️⃣ Checking pending signals (should see 1 signal)...${NC}"
python test_send_signal.py check
sleep 5

# 5. Excel VBAが取得するまで待機
echo -e "\n${YELLOW}5️⃣ Waiting for Excel VBA to fetch signal (10 seconds)...${NC}"
echo "   ℹ️  Excel VBA should be polling every 5 seconds"
sleep 10

# 6. 再度確認（Excel VBAが取得したか）
echo -e "\n${YELLOW}6️⃣ Checking if Excel VBA fetched signal (should be empty)...${NC}"
python test_send_signal.py check
sleep 2

# 7. 無効な数量テスト（150株 - 100株単位でない）
echo -e "\n${YELLOW}7️⃣ Testing invalid quantity (150 shares - should be rejected)...${NC}"
curl -s -X POST http://localhost:5000/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "passphrase": "test_secret",
    "action": "buy",
    "ticker": "6758",
    "quantity": 150,
    "price": 3000.0,
    "entry_price": 3000.0,
    "stop_loss": 2900.0,
    "take_profit": 3200.0,
    "timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%S")'"
  }' | python -m json.tool
sleep 3

# 8. 保留中のシグナル確認（無効なシグナルは来ないはず）
echo -e "\n${YELLOW}8️⃣ Checking pending signals (should be empty - invalid signal rejected)...${NC}"
python test_send_signal.py check
sleep 2

# 9. Kill Switch発動テスト
echo -e "\n${YELLOW}9️⃣ Activating Kill Switch...${NC}"
python test_send_signal.py kill-on
sleep 2

# 10. Kill Switch発動中に買いシグナル送信
echo -e "\n${YELLOW}🔟 Sending BUY signal with Kill Switch ON (should be rejected)...${NC}"
python test_send_signal.py buy 7201 100
sleep 3

# 11. 保留中のシグナル確認（Kill Switchでブロックされるはず）
echo -e "\n${YELLOW}1️⃣1️⃣ Checking pending signals (should be empty - blocked by Kill Switch)...${NC}"
python test_send_signal.py check
sleep 2

# 12. Kill Switch解除
echo -e "\n${YELLOW}1️⃣2️⃣ Deactivating Kill Switch...${NC}"
python test_send_signal.py kill-off
sleep 2

# 完了
echo -e "\n${GREEN}✅ Test scenario completed!${NC}"
echo ""
echo "Summary:"
echo "  - Kill Switch: Tested ✅"
echo "  - Buy Signal: Tested ✅"
echo "  - Invalid Quantity: Tested ✅"
echo "  - Excel VBA Fetch: Check OrderLog sheet 📋"
echo ""
echo "Next steps:"
echo "  1. Check Excel OrderLog sheet for execution results"
echo "  2. Check Relay Server logs: relay_server/data/logs/test_kabuto_*.log"
echo "  3. Check VBA Debug window (Ctrl+G in Excel)"
