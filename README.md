# HybridBridge

使用基礎設施即程式碼（Infrastructure as Code）實現本地 Kubernetes 與 AWS VPC 安全互連的混合雲網路解決方案。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Terraform](https://img.shields.io/badge/Terraform-1.6+-purple.svg)](https://www.terraform.io/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.28+-blue.svg)](https://kubernetes.io/)
[![WireGuard](https://img.shields.io/badge/WireGuard-VPN-success.svg)](https://www.wireguard.com/)

## 專案簡介

HybridBridge 是一個生產級的混合雲網路解決方案，透過 WireGuard VPN 建立本地 Kubernetes 集群與 AWS VPC 之間的加密隧道。本專案完全採用 Infrastructure as Code 方式實作，確保部署過程可重現、可追蹤、易於維護。

### 核心問題與解決方案

**問題：** 企業在混合雲架構中，如何讓本地 Kubernetes 應用安全地訪問 AWS 私有網路資源？

**解決方案：** 透過 WireGuard VPN 建立加密隧道，配合 Terraform 自動化部署，實現端到端的安全連線。

### 專案特色

- **自動化部署** - 使用 Terraform 一鍵部署完整基礎設施
- **生產就緒** - 遵循雲端安全最佳實踐，包含 Network Policies 和 Security Groups
- **成本優化** - 可運行於 AWS Free Tier，適合學習和測試
- **完整測試** - 內建自動化測試腳本，確保系統正常運作
- **文件齊全** - 詳細的部署指南和故障排除文件

### 適用場景

- **混合雲部署** - 需要整合本地機房與公有雲資源
- **多區域整合** - 跨地區服務互連
- **系統遷移** - 舊系統逐步遷移到雲端
- **開發測試** - 開發環境與雲端服務整合
- **災難復原** - 本地與雲端的備援架構

## 系統架構

### 網路拓撲

```
┌─────────────────────────────────────────────────────────────────┐
│                     混合雲網路架構                               │
└─────────────────────────────────────────────────────────────────┘

    本地環境                    VPN 隧道               AWS 雲端
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│                  │    │                  │    │                  │
│  Kubernetes      │    │   WireGuard      │    │   AWS VPC        │
│  集群            │◄──►│   加密隧道       │◄──►│   私有網路       │
│                  │    │                  │    │                  │
│  Pod Network     │    │  UDP 51820       │    │  Private Subnet  │
│  10.244.0.0/16   │    │  ChaCha20 加密   │    │  10.0.0.0/16     │
│                  │    │                  │    │                  │
└──────────────────┘    └──────────────────┘    └──────────────────┘
         │                                                │
         │                                                │
         └────────── 透過 VPN 直接訪問 ──────────────────┘
```

### 技術架構

**基礎設施層（Infrastructure Layer）**
- AWS VPC 與子網路配置
- NAT Gateway 用於對外連線
- Security Groups 控制網路存取
- EC2 實例作為 VPN Gateway

**網路層（Network Layer）**
- WireGuard VPN 提供加密隧道
- iptables 管理封包轉發
- 自動路由設定

**容器編排層（Orchestration Layer）**
- K3s 輕量級 Kubernetes 發行版
- Calico CNI 提供進階網路功能
- Network Policies 控制 Pod 間通訊

**自動化層（Automation Layer）**
- Terraform 管理整個基礎設施
- Shell 腳本自動化配置和測試

## 技術堆疊

| 類別 | 技術 | 版本 |
|------|------|------|
| **雲端平台** | AWS (EC2, VPC) | - |
| **IaC 工具** | Terraform | 1.6+ |
| **容器編排** | Kubernetes (K3s) | 1.28+ |
| **網路插件** | Calico CNI | 3.27 |
| **VPN 技術** | WireGuard | Latest |
| **作業系統** | Ubuntu | 22.04 LTS |

## 快速開始

### 環境準備

在開始部署之前，請先安裝必要的工具。

#### 安裝 AWS CLI

AWS CLI 是與 AWS 服務互動的命令行工具，部署過程中會用到。

**Ubuntu/Debian：**
```bash
# 方法 1：使用官方安裝腳本（推薦）
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
sudo apt install -y unzip
unzip awscliv2.zip
sudo ./aws/install

# 驗證安裝
aws --version
# 應該顯示：aws-cli/2.x.x ...
```

**macOS：**
```bash
# 使用 Homebrew
brew install awscli

# 驗證安裝
aws --version
```

**其他安裝方式：**
- 官方文檔：https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

#### 安裝 Terraform

```bash
# Ubuntu/Debian
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform

# 驗證安裝
terraform --version
```

**其他安裝方式：**
- 官方文檔：https://developer.hashicorp.com/terraform/install

#### 安裝其他必要工具

```bash
# Git（通常已預裝）
sudo apt install -y git

# curl（通常已預裝）
sudo apt install -y curl

# kubectl 會由 K3s 安裝腳本自動安裝
```

#### 配置 AWS 憑證

安裝 AWS CLI 後，需要配置你的 AWS 憑證：

```bash
aws configure
```

系統會提示輸入以下資訊：
```
AWS Access Key ID [None]: 你的-ACCESS-KEY-ID
AWS Secret Access Key [None]: 你的-SECRET-ACCESS-KEY
Default region name [None]: us-west-2
Default output format [None]: json
```

**獲取 AWS 憑證的步驟：**
1. 登入 [AWS Console](https://console.aws.amazon.com/)
2. 點擊右上角的帳戶名稱 → Security credentials
3. 在「Access keys」區域點擊「Create access key」
4. 下載並保存你的 Access Key ID 和 Secret Access Key

**驗證配置：**
```bash
aws sts get-caller-identity
```

應該會顯示你的 AWS 帳戶資訊，表示配置成功。

---
### 前置需求

**環境需求：**
- Ubuntu 22.04 LTS 主機（4GB RAM，2 CPU，40GB 磁碟）
- AWS 帳號（支援 Free Tier）
- 固定公網 IP 或 DDNS
- Git、Terraform、AWS CLI

**必要知識：**
- 基本 Linux 指令操作
- Kubernetes 基礎概念
- AWS 服務基本了解

### 一鍵部署（推薦）

如果你想快速完成部署，使用自動化腳本：

```bash
# 1. 複製專案
git clone <YOUR_REPO_URL>
cd hybridbridge

# 2. 設定腳本執行權限
chmod +x scripts/*.sh

# 3. 配置 AWS 憑證
aws configure

# 4. 執行自動化部署
./scripts/deploy.sh
```

自動化腳本會完成以下操作：
- ✅ 生成 SSH 金鑰並上傳到 AWS
- ✅ 部署 AWS 基礎設施
- ✅ 安裝 Kubernetes (K3s)
- ✅ 配置 VPN 連線
- ✅ 部署測試應用
- ✅ 執行完整驗證


如果你想了解詳細步驟或進行客製化部署，請繼續閱讀「手動部署步驟」。

---

### 手動部署步驟

#### **1. 複製專案並設定權限**

```bash
git clone <YOUR_REPO_URL>
cd hybridbridge

# 設定腳本執行權限（重要！）
chmod +x scripts/*.sh
```

#### **2. 設定 AWS 憑證**

```bash
aws configure
# 輸入你的 AWS Access Key 和 Secret Key
```

#### **3. 準備配置檔**

```bash
# 建立必要目錄
mkdir -p docs

# 取得本機公網 IP
curl -s ifconfig.me > docs/my-public-ip.txt

# 建立 Terraform 變數檔
cd terraform/aws

# 讀取 IP 並創建配置（變數會正確展開）
MY_IP=$(cat ../../docs/my-public-ip.txt)
cat > terraform.tfvars << EOF
aws_region       = "us-west-2"
project_name     = "hybridbridge"
environment      = "dev"
k8s_public_ip    = "$MY_IP"
key_pair_name    = "hybridbridge-key"
allowed_ssh_cidr = ["$MY_IP/32"]
EOF

cd ../..
```

**重要說明：**
- `k8s_public_ip` 和 `allowed_ssh_cidr` 使用你的實際公網 IP
- 如果 IP 改變（例如重新連線），需要更新此檔案並執行 `terraform apply`

#### **4. 生成並上傳 SSH 金鑰**

```bash
# 生成 SSH 金鑰
ssh-keygen -t rsa -b 4096 -f ~/.ssh/hybridbridge-key -N ""

# 上傳到 AWS
aws ec2 import-key-pair \
    --key-name hybridbridge-key \
    --public-key-material fileb://~/.ssh/hybridbridge-key.pub \
    --region us-west-2
```

#### **5. 部署 AWS 基礎設施**

```bash
cd terraform/aws

# 初始化並部署 AWS 資源
terraform init
terraform apply

# 儲存輸出（可選，便於後續查詢）
terraform output > ../../docs/aws-outputs.txt
```

**成功標誌：**
- VPC、子網路、安全組已建立
- 2 個 EC2 實例正在運行
- NAT Gateway 已部署

#### **6. 安裝 Kubernetes**

```bash
cd ~/hybridbridge

# 安裝 K3s
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644 \
    --cluster-cidr=10.244.0.0/16 \
    --service-cidr=10.96.0.0/12

# 設定 kubeconfig
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

# 驗證
kubectl get nodes
```

**成功標誌：**
```
NAME    STATUS   ROLES                  AGE   VERSION
node1   Ready    control-plane,master   30s   v1.28.x
```

#### **7. 設定 VPN**

```bash
# 設定 K8s 端 VPN（會自動等待 AWS 實例就緒）
./scripts/setup-k8s-vpn.sh

# 設定 AWS 端 VPN
./scripts/setup-aws-vpn.sh

# 啟動 K8s 端 VPN
sudo wg-quick up wg0
sudo systemctl enable wg-quick@wg0

# 啟動 AWS 端 VPN（透過 SSH）
AWS_VPN_IP=$(cd terraform/aws && terraform output -raw vpn_gateway_public_ip)
ssh -i ~/.ssh/hybridbridge-key ubuntu@$AWS_VPN_IP \
    "sudo wg-quick up wg0 && sudo systemctl enable wg-quick@wg0"
```

**成功標誌：**
```bash
sudo wg show
# 應該看到 "latest handshake" 在幾秒內
```

#### **8. 驗證 VPN 連線**

```bash
# 執行連通性測試
./scripts/test-vpn-connectivity.sh
```

**預期結果：**
- ✅ VPN 連線正常
- ✅ 可以 ping 通 AWS VPN Gateway
- ✅ 可以 ping 通 Test Server
- ✅ HTTP 請求成功
- ✅ 路由設定正確

#### **9. 部署測試應用**

```bash
# 建立命名空間
kubectl apply -f kubernetes/base/namespace.yaml

# 自動更新 ConfigMap 中的 AWS IP 地址
./scripts/update-configmap.sh

# 部署應用
kubectl apply -f kubernetes/demo-app/

# 套用 Network Policy
kubectl apply -f kubernetes/network-policies/

# 等待 Pod 就緒
kubectl wait --for=condition=Ready pods -l app=hybrid-test-app -n hybridbridge --timeout=300s
```

**成功標誌：**
```bash
kubectl get pods -n hybridbridge
# NAME                               READY   STATUS    RESTARTS   AGE
# hybrid-test-app-xxxxxxxxxx-xxxxx   1/1     Running   0          1m
```

#### **10. 驗證應用**

```bash
# 測試 Kubernetes 應用
./scripts/test-k8s-app.sh

# 完整系統驗證
./scripts/phase6-final-check.sh

# 互動式 Demo（可選）
./scripts/demo-hybrid-cloud.sh
```

**預期結果：**
- ✅ 命名空間存在
- ✅ Deployment 正常運行
- ✅ Service 存在
- ✅ 基本端點正常
- ✅ **AWS 連線成功**（混合雲連線正常）

### 預期結果

部署成功後，你將擁有：

- ✅ 運行中的 Kubernetes 集群
- ✅ 與 AWS VPC 的加密 VPN 連線
- ✅ 可從 K8s Pod 直接訪問 AWS 私有子網路的資源
- ✅ 完整的測試和監控腳本

**測試混合雲連線：**
```bash
# 啟動 port-forward
kubectl port-forward -n hybridbridge svc/hybrid-test-app 8080:80

# 在另一個終端測試
curl http://localhost:8080/test-aws
# 應該返回: {"status": "success", "connection": "VPN tunnel working!"}
```

## 專案結構

```
hybridbridge/
├── README.md                          # 本文件
├── LICENSE                            # MIT License
├── .gitignore                         # Git 忽略規則
├── .gitattributes                     # Git 屬性設定
│
├── terraform/                         # Terraform IaC 配置
│   └── aws/
│       ├── versions.tf                # Provider 版本設定
│       ├── variables.tf               # 變數定義
│       ├── terraform.tfvars           # 變數值（需自行建立，不在版控）
│       ├── vpc.tf                     # VPC 和網路配置
│       ├── security.tf                # Security Groups 規則
│       ├── ec2.tf                     # EC2 實例配置
│       ├── outputs.tf                 # 輸出定義
│       └── main.tf                    # 主配置檔（保留供擴展）
│
├── kubernetes/                        # Kubernetes 資源配置
│   ├── base/
│   │   └── namespace.yaml             # 命名空間定義
│   ├── demo-app/
│   │   ├── configmap.yaml             # AWS 端點配置
│   │   ├── deployment.yaml            # Flask 測試應用
│   │   └── service.yaml               # Service 定義
│   └── network-policies/
│       └── allow-aws.yaml             # 允許訪問 AWS 的網路策略
│
├── scripts/                           # 自動化腳本
│   ├── deploy.sh                      # 一鍵自動化部署（新增）
│   ├── setup-k8s-vpn.sh              # K8s 端 VPN 設定
│   ├── setup-aws-vpn.sh              # AWS 端 VPN 設定
│   ├── update-configmap.sh           # 更新 ConfigMap IP（新增）
│   ├── test-vpn-connectivity.sh      # VPN 連通性測試
│   ├── test-k8s-app.sh               # Kubernetes 應用測試
│   ├── phase6-final-check.sh         # 完整系統驗證
│   ├── demo-hybrid-cloud.sh          # 互動式展示
│   ├── collect-vpn-info.sh           # VPN 資訊收集
│   └── cleanup-k8s.sh                # Kubernetes 資源清理
│
└── docs/                              # 文檔目錄
    ├── architecture.md                # 詳細架構說明
    ├── troubleshooting.md             # 故障排除指南（新增）
    ├── my-public-ip.txt               # 本機公網 IP（自動生成）
    ├── aws-outputs.txt                # Terraform 輸出（自動生成）
    ├── k8s-vpn-pubkey.txt             # K8s VPN 公鑰（自動生成）
    └── aws-vpn-pubkey.txt             # AWS VPN 公鑰（自動生成）
```

## 詳細文檔

- **[架構文件](docs/architecture.md)** - 完整的系統架構說明，包含網路拓撲、組件詳解、數據流向分析

## 腳本說明

### 設定腳本

- `deploy.sh` - 一鍵自動化部署完整系統（推薦）
- `setup-k8s-vpn.sh` - 自動設定 K8s 端的 WireGuard VPN
- `setup-aws-vpn.sh` - 透過 SSH 自動設定 AWS 端的 WireGuard VPN
- `update-configmap.sh` - 自動更新 ConfigMap 中的 AWS IP 地址

### 測試腳本

- `test-vpn-connectivity.sh` - 5 項基礎連通性測試（VPN 狀態、Ping、HTTP）
- `test-k8s-app.sh` - 6 項 Kubernetes 應用測試
- `phase6-final-check.sh` - 完整系統驗證

### 工具腳本

- `demo-hybrid-cloud.sh` - 互動式選單展示混合雲功能
- `collect-vpn-info.sh` - 收集並顯示 VPN 配置資訊
- `cleanup-k8s.sh` - 清理 Kubernetes 資源

## 測試與驗證

### 基礎連通性測試

```bash
# VPN 隧道測試
./scripts/test-vpn-connectivity.sh

# 預期輸出：
# ✅ VPN 連線正常
# ✅ 可以 ping 通 AWS VPN Gateway
# ✅ 可以 ping 通 Test Server
# ✅ HTTP 請求成功
# ✅ 路由設定正確
```

### Kubernetes 應用測試

```bash
# 應用層測試
./scripts/test-k8s-app.sh

# 預期輸出：
# ✅ 命名空間存在
# ✅ Deployment 正常運行
# ✅ Service 存在
# ✅ 基本端點正常
# ✅ AWS 連線成功（混合雲連線正常）
```

### 完整系統驗證

```bash
# 端到端驗證
./scripts/phase6-final-check.sh

# 輸出系統架構圖和狀態
```

### 互動式展示

```bash
# 啟動互動式 Demo
./scripts/demo-hybrid-cloud.sh

# 提供 7 種功能選項：
# 1. 顯示 Pod 資訊
# 2. 測試基本端點
# 3. 測試 AWS 連線
# 4. 顯示網路資訊
# 5. 查看 Pod 日誌
# 6. 進入 Pod Shell
# 7. 完整測試
```

## 常見使用情境

### 情境 1: 本地應用訪問 AWS RDS

```bash
# 在 AWS Private Subnet 建立 RDS
# 配置 Security Group 允許來自 K8s Pod CIDR (10.244.0.0/16)
# K8s Pod 透過 VPN 直接連接 RDS
# 連線字串: mysql://rds.endpoint.aws.internal:3306/database
```

### 情境 2: 跨雲端微服務架構

```bash
# 本地 K8s 運行前端服務
# AWS 運行後端 API 和資料庫
# 透過 VPN 實現服務間低延遲通訊
# 無需暴露服務到公網
```

### 情境 3: 開發環境整合雲端服務

```bash
# 本地開發的應用
# 透過 VPN 訪問 AWS S3、DynamoDB、ElastiCache
# 開發環境與生產環境網路一致
# 降低環境差異導致的問題
```

## 故障排除

### 快速診斷

```bash
# 檢查 VPN 狀態
sudo wg show

# 檢查路由
ip route | grep wg0

# 檢查 Pod 狀態
kubectl get pods -n hybridbridge

# 執行完整診斷
./scripts/collect-vpn-info.sh
```

### 常見問題

#### 問題 1: VPN 無法連接

**症狀：** `sudo wg show` 沒有顯示 handshake

**解決方案：**
```bash
# 1. 檢查防火牆
sudo ufw allow 51820/udp

# 2. 檢查 AWS Security Group
# 確認允許你的 IP 連接 UDP 51820

# 3. 重啟 VPN
sudo wg-quick down wg0
sudo wg-quick up wg0
```

#### 問題 2: Pod 無法訪問 AWS

**症狀：** `curl http://localhost:8080/test-aws` 返回 timeout

**解決方案：**
```bash
# 1. 檢查 VPN 連線
sudo wg show | grep handshake

# 2. 檢查路由
ip route | grep "10.0.0.0"

# 3. 測試從節點直接 ping
ping 10.0.2.x  # Test Server IP
```

#### 問題 3: SSH 無法連接 AWS

**症狀：** SSH connection refused

**解決方案：**
```bash
# 1. 檢查你的公網 IP 是否改變
curl ifconfig.me

# 2. 如果 IP 改變，更新 terraform.tfvars
cd terraform/aws
vim terraform.tfvars  # 更新 k8s_public_ip

# 3. 重新 apply
terraform apply
```

## 清理資源

### 清理 Kubernetes 資源

```bash
# 刪除應用但保留命名空間
./scripts/cleanup-k8s.sh

# 或完全刪除命名空間
kubectl delete namespace hybridbridge
```

### 清理 AWS 資源

```bash
# 停止 VPN
sudo wg-quick down wg0

# 刪除 AWS 基礎設施（會終止計費）
cd terraform/aws
terraform destroy

# 確認刪除（輸入 yes）
```

### 完全清理

```bash
# 1. 停止 VPN
sudo wg-quick down wg0
sudo systemctl disable wg-quick@wg0

# 2. 刪除 K8s 資源
kubectl delete namespace hybridbridge

# 3. 刪除 AWS 資源
cd ~/hybridbridge/terraform/aws
terraform destroy

# 4. 刪除本地配置（可選）
sudo rm -rf /etc/wireguard/
rm -rf ~/hybridbridge/docs/*.txt

# 5. 刪除 SSH 金鑰（可選）
rm ~/.ssh/hybridbridge-key*
```

### 成本優化建議

1. **使用 Free Tier** - 新 AWS 帳號前 12 個月可大幅減少成本
2. **測試完畢後刪除** - 使用 `terraform destroy` 刪除所有資源
3. **使用 NAT Instance** - 替代 NAT Gateway 可節省約 $30/月（需自行維護）
4. **選擇更近的區域** - 可降低延遲和數據傳輸費用

## 安全性

### 多層安全防護

**網路安全：**
- ✅ VPN 使用 ChaCha20-Poly1305 加密
- ✅ Security Groups 限制連線來源（僅允許你的 IP）
- ✅ Private Subnet 隔離敏感資源
- ✅ 最小權限原則

**存取控制：**
- ✅ Kubernetes RBAC
- ✅ Calico Network Policies
- ✅ AWS IAM 角色和政策
- ✅ SSH 金鑰認證（無密碼登入）

**監控與稽核：**
- ✅ VPN 連線狀態監控
- ✅ Kubernetes 事件日誌
- 💡 建議啟用 AWS CloudTrail
- 💡 建議啟用 VPC Flow Logs

### 安全最佳實踐

```bash
# 1. 定期輪換 SSH 金鑰
ssh-keygen -t rsa -b 4096 -f ~/.ssh/hybridbridge-key-new
aws ec2 import-key-pair --key-name hybridbridge-key-new ...

# 2. 定期更新系統
ssh -i ~/.ssh/hybridbridge-key ubuntu@$AWS_VPN_IP \
    "sudo apt update && sudo apt upgrade -y"

# 3. 監控 VPN 連線
watch -n 5 'sudo wg show | grep handshake'

# 4. 審查 Security Group 規則
cd terraform/aws
terraform show | grep -A 20 "security_group"
```

### 安全檢查清單

部署後請確認：

- [ ] Security Groups 僅允許你的 IP
- [ ] SSH 使用金鑰認證（非密碼）
- [ ] WireGuard 配置檔權限為 600
- [ ] 私鑰未被版本控制（已在 .gitignore）
- [ ] NAT Gateway 限制 Private Subnet 的外連
- [ ] Network Policies 正確套用



## 貢獻

歡迎提交 Issue 和 Pull Request！

**貢獻流程：**
1. Fork 本專案
2. 建立功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交變更 (`git commit -m 'Add some AmazingFeature'`)
4. Push 到分支 (`git push origin feature/AmazingFeature`)
5. 開啟 Pull Request

**貢獻指南：**
- Shell 腳本使用 `set -e` 和適當的錯誤處理
- Terraform 使用標準格式 (`terraform fmt`)
- 提供清楚的註解和文檔
- 更新相關測試腳本



