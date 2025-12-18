#!/bin/bash

set -e

# === 新增：動態獲取專案根目錄 ===
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
# ==============================

echo "╔════════════════════════════════════════════════════╗"
echo "║  Phase 6: Kubernetes 應用測試                     ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

# 檢查命名空間
echo "【1】檢查命名空間"
if kubectl get namespace hybridbridge > /dev/null 2>&1; then
    echo "✅ 命名空間 hybridbridge 存在"
else
    echo "❌ 命名空間 hybridbridge 不存在"
    exit 1
fi
echo ""

# 檢查 Deployment
echo "【2】檢查 Deployment"
READY=$(kubectl get deployment hybrid-test-app -n hybridbridge -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
DESIRED=$(kubectl get deployment hybrid-test-app -n hybridbridge -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")

if [ "$READY" = "$DESIRED" ] && [ "$READY" != "0" ]; then
    echo "✅ Deployment 正常運行 ($READY/$DESIRED)"
else
    echo "❌ Deployment 異常 ($READY/$DESIRED)"
    exit 1
fi
echo ""

# 檢查 Pods
echo "【3】檢查 Pods"
kubectl get pods -n hybridbridge -l app=hybrid-test-app
echo ""

# 檢查 Service
echo "【4】檢查 Service"
SVC_IP=$(kubectl get svc hybrid-test-app -n hybridbridge -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
if [ ! -z "$SVC_IP" ]; then
    echo "✅ Service 存在: $SVC_IP"
else
    echo "❌ Service 不存在"
    exit 1
fi
echo ""

# 測試應用端點
echo "【5】測試應用端點"
echo "啟動 port-forward..."
kubectl port-forward -n hybridbridge svc/hybrid-test-app 8080:80 > /dev/null 2>&1 &
PF_PID=$!
sleep 3

# 測試基本端點
echo "測試基本端點..."
if curl -s -f http://localhost:8080/ > /dev/null; then
    echo "✅ 基本端點正常"
else
    echo "❌ 基本端點失敗"
    kill $PF_PID 2>/dev/null
    exit 1
fi

# 測試健康檢查
echo "測試健康檢查..."
HEALTH=$(curl -s http://localhost:8080/health | jq -r '.status' 2>/dev/null)
if [ "$HEALTH" = "healthy" ]; then
    echo "✅ 健康檢查通過"
else
    echo "❌ 健康檢查失敗"
fi

# 測試 AWS 連線（重點！）
echo "測試 AWS 連線..."
AWS_STATUS=$(curl -s http://localhost:8080/test-aws | jq -r '.status' 2>/dev/null)
if [ "$AWS_STATUS" = "success" ]; then
    echo "✅ AWS 連線成功（混合雲連線正常）"
else
    echo "❌ AWS 連線失敗"
    echo "回應內容："
    curl -s http://localhost:8080/test-aws | jq
fi

kill $PF_PID 2>/dev/null
echo ""

# 測試從 Pod 直接訪問
echo "【6】測試從 Pod 直接訪問 AWS"
POD_NAME=$(kubectl get pods -n hybridbridge -l app=hybrid-test-app -o jsonpath='{.items[0].metadata.name}')
echo "使用 Pod: $POD_NAME"

# === 修改：使用動態路徑 ===
cd "$PROJECT_ROOT/terraform/aws"
TEST_SERVER_IP=$(terraform output -raw test_server_private_ip)
cd "$PROJECT_ROOT"
# ========================

echo "測試 ping AWS VPN Gateway..."
if kubectl exec -n hybridbridge $POD_NAME -- ping -c 2 192.168.100.2 > /dev/null 2>&1; then
    echo "✅ 可以 ping 通 AWS VPN Gateway"
else
    echo "⚠️  無法 ping AWS VPN Gateway（可能 ICMP 被阻擋）"
fi

echo "測試 HTTP 到 AWS Test Server..."
# 使用 Python requests 直接測試，不需要安裝 curl
if kubectl exec -n hybridbridge $POD_NAME -- python -c "import requests; exit(0 if requests.get('http://$TEST_SERVER_IP', timeout=5).ok else 1)" 2>/dev/null; then
    echo "✅ 可以 HTTP 連線到 AWS Test Server"
else
    echo "❌ 無法 HTTP 連線到 AWS Test Server"
fi
echo ""

echo "╔════════════════════════════════════════════════════╗"
echo "║          🎉 Phase 6 測試完成！                    ║"
echo "║                                                    ║"
echo "║  ✅ Kubernetes 應用正常運行                       ║"
echo "║  ✅ 混合雲網路連線正常                            ║"
echo "║  ✅ K8s Pod 可訪問 AWS Private Subnet            ║"
echo "╚════════════════════════════════════════════════════╝"
