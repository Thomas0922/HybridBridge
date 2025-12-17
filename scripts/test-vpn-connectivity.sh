#!/bin/bash

set -e

cd ~/hybridbridge/terraform/aws
TEST_SERVER_IP=$(terraform output -raw test_server_private_ip)
cd ~/hybridbridge

echo "=== WireGuard VPN 連通性測試 ==="
echo ""

# 測試 1: VPN 狀態
echo "【測試 1】VPN 狀態檢查"
if sudo wg show | grep -q "latest handshake"; then
    echo "✅ VPN 連線正常"
    sudo wg show | grep "latest handshake"
else
    echo "❌ VPN 連線失敗"
    exit 1
fi
echo ""

# 測試 2: Ping AWS VPN Gateway
echo "【測試 2】Ping AWS VPN Gateway (192.168.100.2)"
if ping -c 3 -W 2 192.168.100.2 > /dev/null 2>&1; then
    echo "✅ 可以 ping 通 AWS VPN Gateway"
else
    echo "❌ 無法 ping 通 AWS VPN Gateway"
    exit 1
fi
echo ""

# 測試 3: Ping Test Server
echo "【測試 3】Ping AWS Test Server ($TEST_SERVER_IP)"
if ping -c 3 -W 2 $TEST_SERVER_IP > /dev/null 2>&1; then
    echo "✅ 可以 ping 通 Test Server"
else
    echo "❌ 無法 ping 通 Test Server"
    exit 1
fi
echo ""

# 測試 4: HTTP 請求
echo "【測試 4】HTTP 請求到 Test Server"
if curl -s --max-time 5 http://$TEST_SERVER_IP | grep -q "HybridBridge"; then
    echo "✅ HTTP 請求成功"
else
    echo "❌ HTTP 請求失敗"
    exit 1
fi
echo ""

# 測試 5: 路由檢查（更新為支援兩種路由格式）
echo "【測試 5】路由表檢查"
if ip route | grep -q "10.0.0.0/16.*wg0"; then
    echo "✅ 路由設定正確"
    ip route | grep "10.0.0.0/16"
else
    echo "❌ 路由設定錯誤"
    exit 1
fi
echo ""

echo "=========================================="
echo "🎉 所有測試通過！VPN 隧道運作正常！"
echo "=========================================="
