#!/bin/bash

set -e

echo "=== 更新 Kubernetes ConfigMap 中的 AWS IP 地址 ==="
echo ""

# 檢查 Terraform 狀態
cd ~/hybridbridge/terraform/aws

if [ ! -f "terraform.tfstate" ]; then
    echo "❌ 找不到 terraform.tfstate"
    echo "請先完成 AWS 基礎設施部署"
    exit 1
fi

# 獲取 AWS 資源 IP
echo "【1】從 Terraform 獲取 IP 地址..."
TEST_SERVER_IP=$(terraform output -raw test_server_private_ip 2>/dev/null)
VPN_GATEWAY_IP=$(terraform output -raw vpn_gateway_private_ip 2>/dev/null)

if [ -z "$TEST_SERVER_IP" ] || [ -z "$VPN_GATEWAY_IP" ]; then
    echo "❌ 無法獲取 IP 地址"
    exit 1
fi

echo "Test Server IP: $TEST_SERVER_IP"
echo "VPN Gateway IP: $VPN_GATEWAY_IP"
echo ""

# 更新 ConfigMap
echo "【2】更新 ConfigMap..."
cd ~/hybridbridge

# 備份原始檔案
cp kubernetes/demo-app/configmap.yaml kubernetes/demo-app/configmap.yaml.bak

# 使用 cat 創建新的 ConfigMap（避免 sed 的轉義問題）
cat > kubernetes/demo-app/configmap.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-endpoints
  namespace: hybridbridge
data:
  # AWS Private Subnet 的 Test Server
  aws-test-server: "http://$TEST_SERVER_IP"
  
  # AWS VPN Gateway
  aws-vpn-gateway: "$VPN_GATEWAY_IP"
  
  # AWS VPC CIDR
  aws-vpc-cidr: "10.0.0.0/16"
EOF

echo "✅ ConfigMap 已更新"
echo ""

# 如果 ConfigMap 已部署，更新它
if kubectl get configmap aws-endpoints -n hybridbridge &>/dev/null; then
    echo "【3】更新已部署的 ConfigMap..."
    kubectl apply -f kubernetes/demo-app/configmap.yaml
    
    # 重啟 Pod 以使用新的配置
    echo "【4】重啟 Pods 以載入新配置..."
    kubectl rollout restart deployment hybrid-test-app -n hybridbridge
    
    echo "等待 Pods 就緒..."
    kubectl wait --for=condition=Ready pods -l app=hybrid-test-app -n hybridbridge --timeout=120s
    echo "✅ Pods 已重啟並就緒"
else
    echo "⚠️  ConfigMap 尚未部署，請執行："
    echo "   kubectl apply -f kubernetes/demo-app/"
fi

echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║         ConfigMap 更新完成                        ║"
echo "╠════════════════════════════════════════════════════╣"
echo "║ Test Server:  $TEST_SERVER_IP"
echo "║ VPN Gateway:  $VPN_GATEWAY_IP"
echo "╚════════════════════════════════════════════════════╝"
