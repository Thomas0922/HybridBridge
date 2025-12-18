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

# 定義金鑰路徑變數 (方便管理)
KEY_NAME="hybridbridge-key"
KEY_PATH="$HOME/.ssh/hybridbridge-key"

# 步驟 2: 生成與檢查 SSH 金鑰
echo "【步驟 2 & 3 / 8】SSH 金鑰生成與同步"

# 2.1 確保本地金鑰存在
if [ ! -f "$KEY_PATH" ]; then
    echo "本地未找到金鑰，正在生成..."
    ssh-keygen -t rsa -b 4096 -f "$KEY_PATH" -N "" -C "hybridbridge"
    echo -e "${GREEN}✅ 本地 SSH 金鑰已生成${NC}"
else
    echo -e "${YELLOW}⚠️  本地 SSH 金鑰已存在${NC}"
fi

# 2.2 設定 AWS 區域
read -p "請輸入 AWS 區域（預設: us-west-2）: " AWS_REGION
AWS_REGION=${AWS_REGION:-us-west-2}

# 2.3 檢查與同步 AWS 金鑰
echo "檢查 AWS 上的金鑰狀態..."

# 檢查 AWS 上是否已有同名金鑰
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$AWS_REGION" &>/dev/null; then
    
    # 獲取 AWS 上的指紋 (Import 的金鑰 AWS 儲存的是 MD5 指紋)
    AWS_FP=$(aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$AWS_REGION" --query 'KeyPairs[0].KeyFingerprint' --output text)
    
    # 計算本地公鑰的 MD5 指紋 (與 AWS 格式對齊)
    # ssh-keygen 輸出格式通常為: "4096 MD5:xx:xx... comment (RSA)"
    LOCAL_FP=$(ssh-keygen -l -E md5 -f "${KEY_PATH}.pub" | awk '{print $2}' | sed 's/MD5://')

    echo "AWS 指紋:  $AWS_FP"
    echo "本地指紋:  $LOCAL_FP"

    if [ "$AWS_FP" != "$LOCAL_FP" ]; then
        echo -e "${RED}❌ 偵測到指紋不匹配！${NC}"
        echo "AWS 上的金鑰與本地不同（可能是舊部署殘留）。"
        echo "正在刪除 AWS 舊金鑰以強制同步..."
        
        # 刪除不匹配的舊金鑰
        aws ec2 delete-key-pair --key-name "$KEY_NAME" --region "$AWS_REGION"
        
        # 重新上傳
        echo "正在上傳正確的本地金鑰..."
        aws ec2 import-key-pair \
            --key-name "$KEY_NAME" \
            --public-key-material "fileb://${KEY_PATH}.pub" \
            --region "$AWS_REGION"
        echo -e "${GREEN}✅ 金鑰已更新並重新上傳${NC}"
    else
        echo -e "${GREEN}✅ 金鑰指紋完全匹配，無需變更${NC}"
    fi
else
    echo "AWS 上尚無此金鑰，正在上傳..."
    aws ec2 import-key-pair \
        --key-name "$KEY_NAME" \
        --public-key-material "fileb://${KEY_PATH}.pub" \
        --region "$AWS_REGION"
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

cd "$PROJECT_ROOT/terraform/aws"

# 初始化
terraform init

# 1. 先嘗試刷新狀態 (這步通常能解決大部分狀態不同步問題)
echo "正在刷新 Terraform 狀態..."
terraform refresh

# 2. 執行 Apply 並捕捉潛在錯誤
echo "正在應用 Terraform 配置..."
set +e  # 【關鍵】暫時關閉「發生錯誤即中止」，讓我們有機會處理錯誤
terraform apply -auto-approve 2> terraform_error.log
APPLY_EXIT_CODE=$?
set -e  # 恢復「發生錯誤即中止」保護

# 3. 檢查結果並執行自動修復
if [ $APPLY_EXIT_CODE -ne 0 ]; then
    echo -e "${YELLOW}⚠️  Terraform 部署遇到錯誤，正在診斷是否為已知問題...${NC}"
    
    # 檢查錯誤日誌中是否包含特定的路由錯誤訊息
    if grep -q "Use CreateRoute instead" terraform_error.log; then
        echo -e "${YELLOW}🔍 偵測到「路由狀態不一致」問題 (Route State Mismatch)。${NC}"
        echo "原因：AWS 上找不到路由，但 Terraform 狀態檔認為它存在。"
        echo "正在執行自動修復 (清除該路由狀態)..."
        
        # 執行修復指令
        terraform state rm aws_route.to_k8s || true
        
        echo -e "${GREEN}✅ 狀態已清除，正在重新嘗試部署...${NC}"
        # 重新執行部署 (這次應該會成功觸發 CreateRoute)
        terraform apply -auto-approve
        
    else
        # 如果是其他我們沒見過的錯誤，則原樣顯示並退出
        echo -e "${RED}❌ 部署失敗 (非路由狀態問題)，請檢查以下錯誤：${NC}"
        cat terraform_error.log
        rm -f terraform_error.log
        exit $APPLY_EXIT_CODE
    fi
fi

# 清理暫存日誌
rm -f terraform_error.log

# --------------------

terraform output > "$PROJECT_ROOT/docs/aws-outputs.txt"
echo -e "${GREEN}✅ AWS 基礎設施已部署${NC}"
echo ""

# 等待 EC2 實例完全啟動
echo "等待 EC2 實例完全啟動（60 秒）..."
sleep 60

# 步驟 6: 安裝 Kubernetes (K3s)
echo "【步驟 6/8】安裝 Kubernetes (K3s)"

# 【檢查】是否已有 Kubernetes/K3s 安裝
# 邏輯：如果 (kubectl 可用且能連線) 或者 (k3s 服務正在執行)，則視為已安裝
if (command -v kubectl &> /dev/null && kubectl get nodes &>/dev/null) || (systemctl is-active --quiet k3s); then
    echo -e "${YELLOW}⚠️  偵測到 Kubernetes (K3s) 已安裝，跳過安裝${NC}"
else
    # --- 如果沒安裝，才執行以下步驟 ---

    # 1. 檢查並關閉 Swap (K3s 建議需求)
    echo "檢查並關閉 Swap..."
    if [ $(sudo swapon --show | wc -l) -gt 0 ]; then
        echo "⚠️  偵測到 Swap 已啟用，正在關閉..."
        sudo swapoff -a
        sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
        echo "✅ Swap 已關閉"
    fi

    # 2. 執行 K3s 安裝
    echo "開始下載並安裝 K3s..."
    curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644 \
        --cluster-cidr=10.244.0.0/16 \
        --service-cidr=10.96.0.0/12
    
    # 3. 設定 kubeconfig
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown $(id -u):$(id -g) ~/.kube/config
    
    echo -e "${GREEN}✅ K3s 安裝完成${NC}"
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

# === 新增：先停止舊連線，忽略錯誤 (|| true) ===
sudo wg-quick down wg0 2>/dev/null || true
# ==========================================
sudo wg-quick up wg0
sudo systemctl enable wg-quick@wg0

# 改為只檢查狀態
AWS_VPN_IP=$(cd "$PROJECT_ROOT/terraform/aws" && terraform output -raw vpn_gateway_public_ip)
echo "檢查 AWS 端 VPN 狀態..."
ssh -i ~/.ssh/hybridbridge-key ubuntu@$AWS_VPN_IP "sudo wg show wg0"

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
