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

### 安裝步驟

**1. 複製專案**

```bash
git clone https://github.com/yourusername/hybridbridge.git
cd hybridbridge
```

**2. 設定 AWS 憑證**

```bash
aws configure
# 輸入你的 AWS Access Key 和 Secret Key
```

**3. 準備配置檔**

```bash
# 取得本機公網 IP
curl -s ifconfig.me > docs/my-public-ip.txt

# 建立 Terraform 變數檔
cd terraform/aws
cp terraform.tfvars.example terraform.tfvars
# 編輯 terraform.tfvars，填入你的設定
```

**4. 部署基礎設施**

```bash
# 初始化並部署 AWS 資源
terraform init
terraform apply

# 安裝 Kubernetes
cd ~/hybridbridge
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

# 設定 VPN
./scripts/setup-k8s-vpn.sh
./scripts/setup-aws-vpn.sh
sudo wg-quick up wg0
```

**5. 驗證部署**

```bash
# 執行自動化測試
./scripts/test-vpn-connectivity.sh

# 部署測試應用
kubectl apply -f kubernetes/demo-app/
```

### 預期結果

部署成功後，你將擁有：

- 運行中的 Kubernetes 集群
- 與 AWS VPC 的加密 VPN 連線
- 可從 K8s Pod 直接訪問 AWS 私有子網路的資源
- 完整的測試和監控腳本

## 專案結構

```
hybridbridge/
├── terraform/              # Terraform IaC 配置
│   └── aws/               # AWS 資源定義
│       ├── vpc.tf         # VPC 和網路配置
│       ├── security.tf    # 安全群組規則
│       └── ec2.tf         # EC2 實例配置
│
├── kubernetes/            # Kubernetes 資源配置
│   ├── demo-app/         # 示範應用
│   └── network-policies/ # 網路策略
│
├── scripts/              # 自動化腳本
│   ├── setup-k8s-vpn.sh  # K8s VPN 設定
│   ├── setup-aws-vpn.sh  # AWS VPN 設定
│   └── test-*.sh         # 測試腳本
│
└── docs/                 # 詳細文檔
    ├── deployment-guide.md    # 完整部署指南
    ├── architecture.md        # 架構詳細說明
    └── troubleshooting.md     # 故障排除手冊
```

## 詳細文檔

- **[架構文件](docs/architecture.md)** - 詳細的系統架構說明


## 常見使用情境

### 情境 1: 本地應用訪問 AWS RDS

```bash
# 在 AWS 建立 RDS 實例於私有子網路
# 配置 Security Group 允許來自 VPN 的連線
# 從 K8s Pod 直接連接 RDS
```

### 情境 2: 跨雲端的微服務架構

```bash
# 部分服務運行於本地 K8s
# 部分服務運行於 AWS
# 透過 VPN 實現服務間通訊
```

### 情境 3: 開發環境整合雲端服務

```bash
# 本地開發環境的應用
# 直接使用 AWS 的託管服務（如 S3、DynamoDB）
# 無需暴露服務到公網
```

## 測試與驗證

專案包含完整的測試套件：

```bash
# 基礎連通性測試
./scripts/test-vpn-connectivity.sh

# Kubernetes 應用測試
./scripts/test-k8s-app.sh

# 完整系統驗證
./scripts/phase6-final-check.sh

# 互動式展示
./scripts/demo-hybrid-cloud.sh
```

## 清理資源

不使用時可以完全清理所有資源：

```bash
# 刪除 Kubernetes 資源
kubectl delete namespace hybridbridge

# 刪除 AWS 資源（會終止計費）
cd terraform/aws
terraform destroy

# 停止 VPN
sudo wg-quick down wg0
```


## 安全性

本專案實作多層安全措施：

**網路安全：**
- VPN 使用 ChaCha20-Poly1305 加密
- Security Groups 限制連線來源
- Private Subnet 隔離敏感資源

**存取控制：**
- Kubernetes RBAC
- Calico Network Policies
- AWS IAM 最小權限原則

**監控與稽核：**
- VPN 連線狀態監控
- Kubernetes 事件日誌
- 建議啟用 AWS CloudTrail

## 貢獻

歡迎提交 Issue 和 Pull Request！

**貢獻流程：**
1. Fork 本專案
2. 建立功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交變更 (`git commit -m 'Add some AmazingFeature'`)
4. Push 到分支 (`git push origin feature/AmazingFeature`)
5. 開啟 Pull Request

