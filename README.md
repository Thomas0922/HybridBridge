# 🌉 HybridBridge

> Production-ready hybrid cloud networking solution integrating on-premise Kubernetes with AWS VPC using Infrastructure as Code

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Terraform](https://img.shields.io/badge/Terraform-1.6+-purple.svg)](https://www.terraform.io/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.28+-blue.svg)](https://kubernetes.io/)
[![WireGuard](https://img.shields.io/badge/WireGuard-VPN-success.svg)](https://www.wireguard.com/)

## 📋 目錄

- [專案概述](#專案概述)
- [核心特性](#核心特性)
- [系統架構](#系統架構)
- [技術棧](#技術棧)
- [快速開始](#快速開始)
- [詳細部署指南](#詳細部署指南)
- [驗證測試](#驗證測試)
- [專案結構](#專案結構)
- [故障排除](#故障排除)

---

## 專案概述

HybridBridge 是一個企業級混合雲網路解決方案，實現本地 Kubernetes 集群與 AWS VPC 之間的安全、高效互連。專案完全採用 Infrastructure as Code (IaC) 方式部署，確保環境可重現、易維護。

### 🎯 設計目標

- 🔒 **安全第一**: 端到端加密 VPN 隧道 (WireGuard)
- 🚀 **自動化部署**: 完整的 Terraform IaC 實作
- 📊 **可觀測性**: 內建監控和測試工具
- 💰 **成本優化**: 可運行於 AWS Free Tier
- 🎯 **生產就緒**: 遵循雲端最佳實踐

### 💡 使用場景

- 混合雲部署架構
- 多區域服務連接
- 舊系統雲端遷移
- 開發/測試環境整合
- 地震預警系統雲端整合（原始需求）

---

## 核心特性

### ✨ 網路功能

- ✅ **WireGuard VPN**: 現代化、高效能的 VPN 解決方案
- ✅ **自動路由**: 智慧流量路由和負載分配
- ✅ **網路隔離**: 完整的 VPC 子網路隔離
- ✅ **NAT Gateway**: Private Subnet 安全對外連線
- ✅ **Security Groups**: 細粒度的防火牆控制

### 🛠️ 基礎設施

- ✅ **Terraform IaC**: 完整的基礎設施程式碼化
- ✅ **Kubernetes (K3s)**: 輕量級但功能完整的 K8s
- ✅ **Calico CNI**: 進階網路策略支援
- ✅ **自動化腳本**: 一鍵部署和測試

### 📈 可觀測性

- ✅ **連通性測試**: 自動化端到端測試
- ✅ **健康檢查**: VPN 狀態監控
- ✅ **診斷工具**: 完整的故障排查腳本

---

## 系統架構

### 網路拓撲圖
```
┌─────────────────────────────────────────────────────────────────┐
│                         HybridBridge                             │
└─────────────────────────────────────────────────────────────────┘

    On-Premise Environment              AWS Cloud (us-west-2)
┌──────────────────────────┐      ┌──────────────────────────┐
│   Kubernetes Cluster     │      │      AWS VPC             │
│   (K3s + Calico CNI)     │      │   (10.0.0.0/16)          │
│                          │      │                          │
│  ┌────────────────────┐  │      │  ┌────────────────────┐ │
│  │   Pod Network      │  │      │  │  Public Subnet     │ │
│  │   10.244.0.0/16    │  │      │  │  (10.0.1.0/24)     │ │
│  │                    │  │      │  │                    │ │
│  │  ┌──────────────┐  │  │      │  │  ┌──────────────┐ │ │
│  │  │ Application  │  │  │      │  │  │ VPN Gateway  │ │ │
│  │  │    Pods      │  │  │      │  │  │  (t3.micro)  │ │ │
│  │  └──────────────┘  │  │      │  │  │              │ │ │
│  └────────────────────┘  │      │  │  │ WireGuard    │ │ │
│                          │      │  │  └──────────────┘ │ │
│  192.168.100.1 (VPN IP)  │      │  │ 192.168.100.2    │ │
└────────────┬─────────────┘      └──┴────────┬──────────┴─┘
             │                                 │
             │    ╔═══════════════════════╗   │
             └────╣  WireGuard VPN Tunnel ╠───┘
                  ╚═══════════════════════╝
                    • ChaCha20 Encryption
                    • UDP Port 51820
                    • ~15-25ms latency
                    
                  ┌──────────────────────────┐
                  │  Private Subnet          │
                  │  (10.0.2.0/24)           │
                  │                          │
                  │  ┌────────────────────┐  │
                  │  │  Test Server       │  │
                  │  │  (Nginx)           │  │
                  │  │  No Public IP      │  │
                  │  └────────────────────┘  │
                  └──────────────────────────┘
```

### 資料流向
```
┌─────────────────────────────────────────────────────────────┐
│ K8s Pod (10.244.x.x) 發起 HTTP 請求到 AWS (10.0.2.x)      │
└─────────────────────────────────────────────────────────────┘
         │
         ▼
    Calico CNI 路由
         │
         ▼
    K8s Node (192.168.93.130)
         │
         ▼
    路由表查找: 10.0.0.0/16 → dev wg0
         │
         ▼
    WireGuard 介面 (192.168.100.1)
         │
         ▼
    加密封包 (ChaCha20-Poly1305)
         │
         ▼
    透過網際網路傳輸 (UDP 51820)
         │
         ▼
    AWS VPN Gateway (54.xxx.xxx.xxx:51820)
         │
         ▼
    WireGuard 解密
         │
         ▼
    AWS VPN Gateway (192.168.100.2)
         │
         ▼
    路由到 Private Subnet
         │
         ▼
    Test Server (10.0.2.x) 收到請求
```

### IP 地址規劃

| 組件 | CIDR / IP | 說明 |
|------|-----------|------|
| **AWS VPC** | 10.0.0.0/16 | 主 VPC 範圍 (65,536 IPs) |
| Public Subnet | 10.0.1.0/24 | 可連網資源 (256 IPs) |
| Private Subnet | 10.0.2.0/24 | 內部資源 (256 IPs) |
| **VPN Tunnel** | 192.168.100.0/24 | 隧道網段 |
| K8s VPN IP | 192.168.100.1 | K8s 端隧道 IP |
| AWS VPN IP | 192.168.100.2 | AWS 端隧道 IP |
| **K8s Cluster** | | |
| Node Network | 192.168.93.0/24 | 實體節點網路 |
| Pod CIDR | 10.244.0.0/16 | Pod IP 範圍 (65,536 IPs) |
| Service CIDR | 10.96.0.0/12 | Service IP 範圍 (1M IPs) |

---

## 技術棧

### 雲端基礎設施
```
┌─────────────────────────────────────┐
│        Infrastructure Layer          │
├─────────────────────────────────────┤
│ • AWS EC2 (t3.micro instances)      │
│ • AWS VPC (Networking)              │
│ • AWS Security Groups (Firewall)    │
│ • Terraform 1.6+ (IaC)              │
│ • Ubuntu 22.04 LTS (OS)             │
└─────────────────────────────────────┘
```

### 容器編排
```
┌─────────────────────────────────────┐
│      Container Orchestration         │
├─────────────────────────────────────┤
│ • Kubernetes (K3s) 1.28+            │
│ • Calico CNI 3.27 (Networking)      │
│ • containerd (Runtime)              │
│ • CoreDNS (Service Discovery)       │
│ • Helm 3 (Package Manager)          │
└─────────────────────────────────────┘
```

### 網路與安全
```
┌─────────────────────────────────────┐
│       Network & Security             │
├─────────────────────────────────────┤
│ • WireGuard VPN (Encryption)        │
│ • iptables (Firewall Rules)         │
│ • AWS NAT Gateway (Outbound)        │
│ • Calico Network Policies           │
│ • ChaCha20-Poly1305 (Crypto)        │
└─────────────────────────────────────┘
```

---

## 快速開始

### 前置需求

**硬體需求**:
- CPU: 2 cores (最低)
- RAM: 4GB (最低), 8GB (建議)
- Disk: 40GB
- OS: Ubuntu 22.04 LTS

**軟體需求**:
- AWS 帳號 (Free Tier 可用)
- 固定公網 IP 或 DDNS
- SSH 金鑰對
- 基本 Linux 操作知識

### 30 分鐘快速部署
```bash
# 1. Clone 專案
git clone https://github.com/yourusername/hybridbridge.git
cd hybridbridge

# 2. 設定 AWS 憑證
aws configure
# 輸入 Access Key ID
# 輸入 Secret Access Key
# Region: us-west-2

# 3. 取得公網 IP
curl -s ifconfig.me > docs/my-public-ip.txt

# 4. 設定 Terraform 變數
cd terraform/aws
cat > terraform.tfvars << TFVARS
aws_region      = "us-west-2"
project_name    = "hybridbridge"
environment     = "dev"
k8s_public_ip   = "$(cat ../../docs/my-public-ip.txt)"
key_pair_name   = "hybridbridge-key"
TFVARS

# 5. 生成 SSH 金鑰
ssh-keygen -t rsa -b 4096 -f ~/.ssh/hybridbridge-key -N ""

# 6. 上傳金鑰到 AWS
aws ec2 import-key-pair \
    --key-name hybridbridge-key \
    --public-key-material fileb://~/.ssh/hybridbridge-key.pub \
    --region us-west-2

# 7. 部署 AWS 基礎設施
terraform init
terraform apply

# 8. 安裝 K3s
cd ~/hybridbridge
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644 \
    --cluster-cidr=10.244.0.0/16 \
    --service-cidr=10.96.0.0/12

# 9. 設定 VPN
./scripts/setup-k8s-vpn.sh
./scripts/setup-aws-vpn.sh
sudo wg-quick up wg0

# 10. 驗證部署
./scripts/test-vpn-connectivity.sh
```

---

## 詳細部署指南

### Phase 1: 環境準備

#### 1.1 安裝必要工具
```bash
# 更新系統
sudo apt update && sudo apt upgrade -y

# 安裝基礎工具
sudo apt install -y curl wget git vim net-tools

# 安裝 Terraform
wget https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip
unzip terraform_1.6.6_linux_amd64.zip
sudo mv terraform /usr/local/bin/
terraform version

# 安裝 AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version
```

#### 1.2 設定 AWS 憑證
```bash
# 設定 AWS CLI
aws configure
# AWS Access Key ID: YOUR_ACCESS_KEY
# AWS Secret Access Key: YOUR_SECRET_KEY
# Default region: us-west-2
# Default output format: json

# 驗證設定
aws sts get-caller-identity
```

### Phase 2: Kubernetes 安裝

#### 2.1 系統準備
```bash
# 關閉 Swap
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# 載入核心模組
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# 設定 sysctl
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

#### 2.2 安裝 K3s
```bash
# 安裝 K3s
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644 \
    --disable traefik \
    --cluster-cidr=10.244.0.0/16 \
    --service-cidr=10.96.0.0/12

# 設定 kubectl
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

# 驗證
kubectl get nodes
kubectl get pods -A
```

#### 2.3 安裝 Calico CNI
```bash
# 安裝 Calico Operator
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml

# 設定 Calico
cat <<EOF | kubectl apply -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: 10.244.0.0/16
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
EOF

# 等待 Calico 啟動
kubectl wait --for=condition=Ready pods --all -n calico-system --timeout=300s
```

### Phase 3: AWS 基礎設施部署

#### 3.1 建立 Terraform 設定
```bash
cd ~/hybridbridge/terraform/aws

# 建立變數檔案
cat > terraform.tfvars << EOF
aws_region      = "us-west-2"
project_name    = "hybridbridge"
environment     = "dev"
k8s_public_ip   = "$(cat ~/hybridbridge/docs/my-public-ip.txt)"
key_pair_name   = "hybridbridge-key"
EOF
```

#### 3.2 部署 AWS 資源
```bash
# 初始化 Terraform
terraform init

# 驗證設定
terraform validate

# 預覽變更
terraform plan

# 部署
terraform apply
# 輸入 yes 確認

# 儲存輸出
terraform output > ../../docs/aws-outputs.txt
```

### Phase 4: WireGuard VPN 設定

#### 4.1 K8s 端設定
```bash
# 安裝 WireGuard
sudo apt install -y wireguard wireguard-tools

# 生成密鑰
sudo mkdir -p /etc/wireguard
cd /etc/wireguard
sudo wg genkey | sudo tee privatekey | sudo wg pubkey | sudo tee publickey
sudo chmod 600 privatekey

# 儲存公鑰
sudo cat /etc/wireguard/publickey > ~/hybridbridge/docs/k8s-vpn-pubkey.txt

# 取得 AWS VPN 公鑰
cd ~/hybridbridge/terraform/aws
AWS_VPN_IP=$(terraform output -raw vpn_gateway_public_ip)
ssh -i ~/.ssh/hybridbridge-key ubuntu@$AWS_VPN_IP \
    'sudo cat /etc/wireguard/publickey' > ~/hybridbridge/docs/aws-vpn-pubkey.txt

# 建立 WireGuard 設定
cd ~/hybridbridge
K8S_PRIVATE_KEY=$(sudo cat /etc/wireguard/privatekey)
AWS_PUBKEY=$(cat docs/aws-vpn-pubkey.txt)
AWS_VPN_IP=$(cd terraform/aws && terraform output -raw vpn_gateway_public_ip)

sudo tee /etc/wireguard/wg0.conf > /dev/null <<WGCONF
[Interface]
PrivateKey = $K8S_PRIVATE_KEY
Address = 192.168.100.1/24
ListenPort = 51820

PostUp = iptables -A FORWARD -i wg0 -j ACCEPT
PostUp = iptables -A FORWARD -o wg0 -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
PostDown = iptables -D FORWARD -o wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = $AWS_PUBKEY
Endpoint = $AWS_VPN_IP:51820
AllowedIPs = 10.0.0.0/16, 192.168.100.2/32
PersistentKeepalive = 25
WGCONF

sudo chmod 600 /etc/wireguard/wg0.conf
```

#### 4.2 AWS 端設定
```bash
# 執行 AWS VPN 設定腳本
./scripts/setup-aws-vpn.sh
```

#### 4.3 啟動 VPN
```bash
# 啟動 K8s 端 VPN
sudo wg-quick up wg0

# 啟用自動啟動
sudo systemctl enable wg-quick@wg0

# 檢查狀態
sudo wg show
```

---

## 驗證測試

### 自動化測試
```bash
# 完整連通性測試
./scripts/test-vpn-connectivity.sh

# 預期輸出：
# ✅ VPN 連線正常
# ✅ 可以 ping 通 AWS VPN Gateway
# ✅ 可以 ping 通 Test Server
# ✅ HTTP 請求成功
# ✅ 路由設定正確
```

### 手動驗證

#### 1. VPN 狀態
```bash
sudo wg show

# 預期輸出：
# interface: wg0
#   public key: xxx...
#   listening port: 51820
#
# peer: xxx...
#   endpoint: 54.xxx.xxx.xxx:51820
#   allowed ips: 10.0.0.0/16, 192.168.100.2/32
#   latest handshake: 30 seconds ago
#   transfer: 15.2 KiB received, 12.8 KiB sent
```

#### 2. 網路測試
```bash
# Ping VPN Gateway
ping -c 4 192.168.100.2

# Ping Test Server
TEST_IP=$(cd terraform/aws && terraform output -raw test_server_private_ip)
ping -c 4 $TEST_IP

# HTTP 測試
curl http://$TEST_IP
```

#### 3. 路由檢查
```bash
# 查看路由表
ip route | grep wg0

# 預期輸出：
# 10.0.0.0/16 dev wg0 scope link
# 192.168.100.0/24 dev wg0 proto kernel scope link src 192.168.100.1
```

---

## 專案結構
```
hybridbridge/
├── README.md                        # 本文件
├── LICENSE                          # MIT 授權
├── .gitignore                       # Git 忽略規則
│
├── terraform/                       # Terraform IaC 程式碼
│   └── aws/
│       ├── versions.tf             # Provider 設定
│       ├── variables.tf            # 變數定義
│       ├── terraform.tfvars        # 變數值（需自行建立）
│       ├── vpc.tf                  # VPC 資源
│       ├── security.tf             # Security Groups
│       ├── ec2.tf                  # EC2 實例
│       └── outputs.tf              # 輸出定義
│
├── kubernetes/                      # Kubernetes 設定
│   ├── base/
│   │   ├── namespace.yaml          # 命名空間
│   │   └── rbac.yaml               # 權限控制
│   ├── demo-app/
│   │   ├── deployment.yaml         # 應用部署
│   │   ├── service.yaml            # 服務定義
│   │   └── configmap.yaml          # 設定檔
│   └── network-policies/
│       ├── allow-aws.yaml          # 允許 AWS 流量
│       └── default-deny.yaml       # 預設拒絕
│
├── scripts/                         # 自動化腳本
│   ├── setup-k8s-vpn.sh            # K8s VPN 設定
│   ├── setup-aws-vpn.sh            # AWS VPN 設定
│   ├── test-vpn-connectivity.sh    # 連通性測試
│   ├── phase5-final-check.sh       # 完整驗證
│   ├── diagnose-wg.sh              # 診斷工具
│   └── cleanup.sh                  # 資源清理
│
└── docs/                            # 文檔目錄
    ├── architecture.md              # 架構文件
    ├── deployment-guide.md          # 部署指南
    ├── troubleshooting.md           # 故障排除
    ├── aws-outputs.txt             # Terraform 輸出
    ├── aws-vpn-pubkey.txt          # AWS VPN 公鑰
    ├── k8s-vpn-pubkey.txt          # K8s VPN 公鑰
    └── my-public-ip.txt            # 本機公網 IP
```

---

## 故障排除

### 常見問題

#### 1. VPN 無法連線

**症狀**: `sudo wg show` 沒有 "latest handshake"

**可能原因**:
- 防火牆阻擋 UDP 51820
- 公網 IP 不正確
- 設定檔錯誤

**解決方法**:
```bash
# 檢查防火牆
sudo ufw status
sudo ufw allow 51820/udp

# 檢查設定檔
sudo cat /etc/wireguard/wg0.conf

# 重啟 VPN
sudo wg-quick down wg0
sudo wg-quick up wg0

# 查看日誌
sudo journalctl -u wg-quick@wg0 -f
```

#### 2. Ping 不通 AWS

**症狀**: VPN 連線正常但無法 ping

**可能原因**:
- 路由設定錯誤
- IP forwarding 未啟用
- Security Group 阻擋 ICMP

**解決方法**:
```bash
# 檢查路由
ip route | grep wg0

# 檢查 IP forwarding
sysctl net.ipv4.ip_forward  # 應該是 1

# 啟用 IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1

# 檢查 iptables
sudo iptables -L -n -v | grep wg0
```

#### 3. HTTP 連不上

**症狀**: Ping 通但 HTTP 失敗

**可能原因**:
- Nginx 未啟動
- Security Group 未開放 HTTP
- 防火牆阻擋

**解決方法**:
```bash
# SSH 到 test server
AWS_VPN_IP=$(cd terraform/aws && terraform output -raw vpn_gateway_public_ip)
ssh -i ~/.ssh/hybridbridge-key ubuntu@$AWS_VPN_IP
TEST_IP=$(hostname -I | awk '{print $1}')
ssh ubuntu@$TEST_IP

# 檢查 Nginx
sudo systemctl status nginx
sudo systemctl restart nginx
```

#### 4. Terraform Apply 失敗

**症狀**: EC2 instance 建立失敗

**可能原因**:
- 未上傳 SSH key
- 超過 Free Tier
- 區域不支援 instance type

**解決方法**:
```bash
# 檢查 key pair
aws ec2 describe-key-pairs --key-names hybridbridge-key

# 改用 t3.micro (如果 t2.micro 失敗)
sed -i 's/t2.micro/t3.micro/g' terraform/aws/ec2.tf

# 重新 apply
terraform apply
```

### 診斷工具
```bash
# 執行完整診斷
./scripts/diagnose-wg.sh

# 手動診斷步驟
echo "=== VPN 狀態 ==="
sudo wg show

echo "=== 路由表 ==="
ip route | grep wg0

echo "=== 防火牆 ==="
sudo iptables -L FORWARD -n -v

echo "=== 連通性 ==="
ping -c 2 192.168.100.2
ping -c 2 $TEST_SERVER_IP

echo "=== DNS ==="
nslookup google.com
```

---


</div>
