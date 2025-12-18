#!/bin/bash

set -e

# 獲取腳本所在目錄和項目根目錄
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

echo "📁 項目根目錄: $PROJECT_ROOT"
echo ""

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "╔════════════════════════════════════════════════════╗"
echo "║     HybridBridge 自動化部署腳本                   ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

# 檢查必要工具
echo "【前置檢查】"
MISSING_TOOLS=""

for tool in terraform aws kubectl curl ssh-keygen; do
    if ! command -v $tool &> /dev/null; then
        MISSING_TOOLS="$MISSING_TOOLS $tool"
    fi
done

if [ ! -z "$MISSING_TOOLS" ]; then
    echo -e "${RED}❌ 缺少必要工具:$MISSING_TOOLS${NC}"
    echo "請安裝缺少的工具後再執行此腳本"
    exit 1
fi

echo -e "${GREEN}✅ 所有必要工具已安裝${NC}"
echo ""

# 步驟 1: 獲取公網 IP
echo "【步驟 1/8】獲取公網 IP"
mkdir -p "$PROJECT_ROOT/docs"
curl -s ifconfig.me > "$PROJECT_ROOT/docs/my-public-ip.txt"
MY_PUBLIC_IP=$(cat "$PROJECT_ROOT/docs/my-public-ip.txt")
echo -e "${GREEN}✅ 您的公網 IP: $MY_PUBLIC_IP${NC}"
echo ""

# 步驟 2: 生成 SSH 金鑰
echo "【步驟 2/8】生成 SSH 金鑰"
if [ ! -f ~/.ssh/hybridbridge-key ]; then
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/hybridbridge-key -N "" -C "hybridbridge"
    echo -e "${GREEN}✅ SSH 金鑰已生成${NC}"
else
    echo -e "${YELLOW}⚠️  SSH 金鑰已存在，跳過生成${NC}"
fi
echo ""

# 步驟 3: 上傳 SSH 金鑰到 AWS
echo "【步驟 3/8】上傳 SSH 金鑰到 AWS"
read -p "請輸入 AWS 區域（預設: us-west-2）: " AWS_REGION
AWS_REGION=${AWS_REGION:-us-west-2}

# 檢查金鑰是否已存在
if aws ec2 describe-key-pairs --key-names hybridbridge-key --region $AWS_REGION &>/dev/null; then
    echo -e "${YELLOW}⚠️  金鑰對已存在於 AWS，跳過上傳${NC}"
else
    aws ec2 import-key-pair \
        --key-name hybridbridge-key \
        --public-key-material fileb://~/.ssh/hybridbridge-key.pub \
        --region $AWS_REGION
    echo -e "${GREEN}✅ SSH 金鑰已上傳到 AWS${NC}"
fi
echo ""

# 步驟 4: 創建 Terraform 變數檔
echo "【步驟 4/8】創建 Terraform 配置"
cd "$PROJECT_ROOT/terraform/aws"

cat > terraform.tfvars <<EOF
aws_region      = "$AWS_REGION"
project_name    = "hybridbridge"
environment     = "dev"
k8s_public_ip   = "$MY_PUBLIC_IP"
key_pair_name   = "hybridbridge-key"
# 限制 SSH 只能從您的 IP 連接（更安全）
allowed_ssh_cidr = ["$MY_PUBLIC_IP/32"]
EOF

echo -e "${GREEN}✅ Terraform 變數檔已創建${NC}"
echo ""

# 步驟 5: 部署 AWS 基礎設施
echo "【步驟 5/8】部署 AWS 基礎設施"
echo -e "${YELLOW}這可能需要 5-10 分鐘...${NC}"

terraform init
terraform apply -auto-approve

terraform output > "$PROJECT_ROOT/docs/aws-outputs.txt"
echo -e "${GREEN}✅ AWS 基礎設施已部署${NC}"
echo ""

# 等待 EC2 實例完全啟動
echo "等待 EC2 實例完全啟動（60 秒）..."
sleep 60

# 步驟 6: 安裝 K3s
echo "【步驟 6/8】安裝 Kubernetes (K3s)"
if command -v kubectl &> /dev/null && kubectl get nodes &>/dev/null; then
    echo -e "${YELLOW}⚠️  K3s 已安裝，跳過安裝${NC}"
else
    curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644 \
        --cluster-cidr=10.244.0.0/16 \
        --service-cidr=10.96.0.0/12
    
    # 設定 kubeconfig
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown $(id -u):$(id -g) ~/.kube/config
    
    echo -e "${GREEN}✅ K3s 已安裝${NC}"
fi
echo ""

# 步驟 7: 設定 VPN
echo "【步驟 7/8】設定 WireGuard VPN"

# 設定 K8s 端
echo "設定 K8s 端 VPN..."
cd "$PROJECT_ROOT"
sudo bash scripts/setup-k8s-vpn.sh

# 設定 AWS 端
echo "設定 AWS 端 VPN..."
bash scripts/setup-aws-vpn.sh

# 啟動 VPN
echo "啟動 K8s 端 VPN..."
sudo wg-quick up wg0
sudo systemctl enable wg-quick@wg0

# 啟動 AWS 端 VPN
AWS_VPN_IP=$(cd "$PROJECT_ROOT/terraform/aws" && terraform output -raw vpn_gateway_public_ip)
echo "啟動 AWS 端 VPN..."
ssh -i ~/.ssh/hybridbridge-key ubuntu@$AWS_VPN_IP \
    "sudo wg-quick up wg0 && sudo systemctl enable wg-quick@wg0"

echo -e "${GREEN}✅ VPN 已啟動${NC}"
echo ""

# 測試 VPN 連線
echo "測試 VPN 連線..."
sleep 5
bash scripts/test-vpn-connectivity.sh

# 步驟 8: 部署 Kubernetes 應用
echo "【步驟 8/8】部署 Kubernetes 應用"

# 更新 ConfigMap
bash scripts/update-configmap.sh

# 部署應用
kubectl apply -f kubernetes/base/namespace.yaml
kubectl apply -f kubernetes/demo-app/
kubectl apply -f kubernetes/network-policies/

echo "等待 Pods 就緒..."
kubectl wait --for=condition=Ready pods -l app=hybrid-test-app -n hybridbridge --timeout=300s

echo -e "${GREEN}✅ 應用已部署${NC}"
echo ""

# 最終測試
echo "【最終驗證】"
bash scripts/test-k8s-app.sh

echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║          🎉 部署完成！                            ║"
echo "╠════════════════════════════════════════════════════╣"
echo "║                                                    ║"
echo "║  ✅ AWS 基礎設施已建立                            ║"
echo "║  ✅ Kubernetes 集群運行中                         ║"
echo "║  ✅ VPN 隧道已連接                                ║"
echo "║  ✅ 混合雲應用運行中                              ║"
echo "║                                                    ║"
echo "║  接下來可以：                                      ║"
echo "║  1. 執行互動式展示: ./scripts/demo-hybrid-cloud.sh ║"
echo "║  2. 查看系統狀態: ./scripts/phase6-final-check.sh  ║"
echo "║                                                    ║"
echo "╚════════════════════════════════════════════════════╝"
