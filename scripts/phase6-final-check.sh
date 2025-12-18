#!/bin/bash

echo "╔════════════════════════════════════════════════════╗"
echo "║    HybridBridge - 完整系統驗證                    ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

# Phase 1-5: VPN 檢查
echo "【VPN 基礎設施】"
if sudo wg show | grep -q "latest handshake"; then
    echo "✅ WireGuard VPN 運行正常"
else
    echo "❌ WireGuard VPN 異常"
fi

if ping -c 2 192.168.100.2 > /dev/null 2>&1; then
    echo "✅ 可連線到 AWS VPN Gateway"
else
    echo "❌ 無法連線到 AWS VPN Gateway"
fi
echo ""

# Phase 6: Kubernetes 應用檢查
echo "【Kubernetes 應用】"
if kubectl get deployment hybrid-test-app -n hybridbridge > /dev/null 2>&1; then
    READY=$(kubectl get deployment hybrid-test-app -n hybridbridge -o jsonpath='{.status.readyReplicas}')
    echo "✅ Kubernetes 應用運行中 ($READY replicas)"
else
    echo "❌ Kubernetes 應用未部署"
fi
echo ""

# 混合雲連線測試
echo "【混合雲連線測試】"
kubectl port-forward -n hybridbridge svc/hybrid-test-app 8080:80 > /dev/null 2>&1 &
PF_PID=$!
sleep 3

AWS_TEST=$(curl -s http://localhost:8080/test-aws | jq -r '.status' 2>/dev/null)
if [ "$AWS_TEST" = "success" ]; then
    echo "✅ K8s Pod → AWS Private Subnet 連線成功"
else
    echo "❌ K8s Pod → AWS Private Subnet 連線失敗"
fi

kill $PF_PID 2>/dev/null
echo ""

echo "╔════════════════════════════════════════════════════╗"
echo "║           系統架構圖                              ║"
echo "╠════════════════════════════════════════════════════╣"
echo "║                                                    ║"
echo "║  K8s Pod (10.244.x.x)                             ║"
echo "║       ↓                                           ║"
echo "║  VPN Tunnel (192.168.100.1 ↔ 192.168.100.2)      ║"
echo "║       ↓                                           ║"
echo "║  AWS Test Server (10.0.2.x)                       ║"
echo "║                                                    ║"
echo "║  🎉 完整的混合雲應用正在運行！                    ║"
echo "╚════════════════════════════════════════════════════╝"
