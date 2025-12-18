# HybridBridge 系統架構文檔

## 目錄

- [架構概覽](#架構概覽)
- [網路拓撲](#網路拓撲)
- [組件說明](#組件說明)
- [數據流向](#數據流向)
- [安全架構](#安全架構)
- [設計決策](#設計決策)
- [擴展性考量](#擴展性考量)

---

## 架構概覽

HybridBridge 採用三層架構設計，透過 WireGuard VPN 實現本地 Kubernetes 環境與 AWS VPC 的安全互連。

### 高階架構圖

```
┌─────────────────────────────────────────────────────────────────────┐
│                        HybridBridge 架構                             │
└─────────────────────────────────────────────────────────────────────┘

         本地環境                               AWS 雲端
    ┌───────────────────┐                 ┌───────────────────┐
    │                   │                 │                   │
    │   應用層          │                 │   應用層          │
    │   (Kubernetes)    │                 │   (EC2/Services)  │
    │                   │                 │                   │
    ├───────────────────┤                 ├───────────────────┤
    │                   │                 │                   │
    │   網路層          │    WireGuard    │   網路層          │
    │   (Calico CNI)    │◄───VPN Tunnel──►│   (AWS VPC)       │
    │                   │                 │                   │
    ├───────────────────┤                 ├───────────────────┤
    │                   │                 │                   │
    │   基礎設施層      │                 │   基礎設施層      │
    │   (K3s + Ubuntu)  │                 │   (EC2 + Terraform)│
    │                   │                 │                   │
    └───────────────────┘                 └───────────────────┘
```

---

## 網路拓撲

### 完整網路拓撲圖

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              網路拓撲詳圖                                    │
└─────────────────────────────────────────────────────────────────────────────┘

本地環境 (192.168.93.0/24)                  AWS us-west-2 (10.0.0.0/16)
┌────────────────────────────┐           ┌────────────────────────────────┐
│                            │           │                                │
│  K8s Master Node           │           │  Internet Gateway              │
│  192.168.93.130            │           │  igw-xxxxxxxxx                 │
│  ┌──────────────────────┐  │           │         │                      │
│  │  Pod Network         │  │           │         ▼                      │
│  │  10.244.0.0/16       │  │           │  ┌──────────────────────────┐  │
│  │  ┌────────────────┐  │  │           │  │  Public Subnet           │  │
│  │  │ Demo App Pods  │  │  │           │  │  10.0.1.0/24             │  │
│  │  │ (Flask App)    │  │  │           │  │  ┌────────────────────┐  │  │
│  │  └────────────────┘  │  │           │  │  │ VPN Gateway EC2    │  │  │
│  └──────────────────────┘  │           │  │  │ t3.micro           │  │  │
│           │                 │           │  │  │ Public IP: 54.x.x.x│  │  │
│           ▼                 │           │  │  │ Private IP:10.0.1.x│  │  │
│  ┌──────────────────────┐  │           │  │  │ VPN IP:192.168.100.2│ │  │
│  │ WireGuard Interface  │  │           │  │  │ WireGuard Installed│  │  │
│  │ wg0: 192.168.100.1   │  │◄─VPN─────►│  │  └────────────────────┘  │  │
│  │ UDP 51820            │  │  Tunnel   │  └──────────────────────────┘  │
│  └──────────────────────┘  │           │         │                      │
│           │                 │           │         │ Route to Private     │
│           ▼                 │           │         ▼                      │
│  Physical Interface         │           │  ┌──────────────────────────┐  │
│  eth0/ens33                 │           │  │  NAT Gateway             │  │
│  192.168.93.130             │           │  │  nat-xxxxxxxxx           │  │
│  (Public IP)                │           │  └──────────────────────────┘  │
│                             │           │         │                      │
└─────────────────────────────┘           │         ▼                      │
                                          │  ┌──────────────────────────┐  │
                                          │  │  Private Subnet          │  │
                                          │  │  10.0.2.0/24             │  │
                                          │  │  ┌────────────────────┐  │  │
                                          │  │  │ Test Server EC2    │  │  │
                                          │  │  │ t3.micro           │  │  │
                                          │  │  │ Private IP:10.0.2.x│  │  │
                                          │  │  │ Nginx Installed    │  │  │
                                          │  │  └────────────────────┘  │  │
                                          │  └──────────────────────────┘  │
                                          │                                │
                                          └────────────────────────────────┘
```

### IP 地址分配詳表

| 網路段 | CIDR | 用途 | 備註 |
|--------|------|------|------|
| **本地環境** | | | |
| K8s Node Network | 192.168.93.0/24 | 實體節點網路 | 可變（依實際環境） |
| K8s Pod CIDR | 10.244.0.0/16 | Pod IP 範圍 | Calico 預設 |
| K8s Service CIDR | 10.96.0.0/12 | Service IP 範圍 | K3s 預設 |
| VPN Tunnel (K8s) | 192.168.100.1/32 | K8s 端 VPN IP | 固定 |
| **AWS 環境** | | | |
| AWS VPC | 10.0.0.0/16 | 主 VPC 範圍 | 65,536 個 IP |
| Public Subnet | 10.0.1.0/24 | 公開子網路 | 256 個 IP |
| Private Subnet | 10.0.2.0/24 | 私有子網路 | 256 個 IP |
| VPN Tunnel (AWS) | 192.168.100.2/32 | AWS 端 VPN IP | 固定 |
| **VPN Tunnel** | | | |
| Tunnel Network | 192.168.100.0/24 | WireGuard 隧道 | 點對點網路 |

---

## 組件說明

### 1. 本地環境組件

#### 1.1 Kubernetes 集群 (K3s)

**角色：** 容器編排平台

**規格：**
- 發行版：K3s v1.28+
- 節點：單節點（可擴展為多節點）
- Runtime：containerd

**關鍵配置：**
```yaml
Cluster CIDR: 10.244.0.0/16
Service CIDR: 10.96.0.0/12
禁用組件: traefik (使用外部 LoadBalancer)
```

**用途：**
- 運行容器化應用
- 提供服務發現和負載均衡
- 管理應用生命周期

#### 1.2 Calico CNI

**角色：** Kubernetes 網路插件

**功能：**
- Pod 間網路連接
- Network Policy 實作
- IP 地址管理（IPAM）
- BGP 路由（可選）

**關鍵特性：**
- 支援 VXLAN 封裝
- 提供 NetworkPolicy API
- 可與 WireGuard 整合

#### 1.3 WireGuard VPN (K8s 端)

**角色：** VPN 客戶端

**配置：**
```ini
Interface: wg0
Address: 192.168.100.1/24
Listen Port: 51820
Private Key: (自動生成)
```

**防火牆規則：**
```bash
PostUp: iptables -A FORWARD -i wg0 -j ACCEPT
PostUp: iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
```

**路由：**
```bash
# 自動添加路由
10.0.0.0/16 dev wg0 scope link
192.168.100.0/24 dev wg0 proto kernel scope link src 192.168.100.1
```

### 2. AWS 環境組件

#### 2.1 VPC 網路架構

**VPC 主體：**
- CIDR: 10.0.0.0/16
- DNS 支援：已啟用
- DNS Hostname：已啟用

**子網路：**

**Public Subnet (10.0.1.0/24)**
- 可用區：us-west-2a
- 自動分配公網 IP：是
- 用途：VPN Gateway

**Private Subnet (10.0.2.0/24)**
- 可用區：us-west-2a
- 自動分配公網 IP：否
- 用途：內部服務

#### 2.2 路由表

**Public Route Table：**
```
目的地                    目標
0.0.0.0/0          →     Internet Gateway
10.0.0.0/16        →     local
```

**Private Route Table：**
```
目的地                    目標
0.0.0.0/0          →     NAT Gateway
10.0.0.0/16        →     local
10.244.0.0/16      →     VPN Gateway (ENI)
```

#### 2.3 EC2 實例

**VPN Gateway：**
- 實例類型：t3.micro
- AMI：Ubuntu 22.04 LTS
- 網路：Public Subnet
- 彈性 IP：已分配
- Source/Dest Check：停用（重要）
- 安裝軟體：WireGuard, iptables

**Test Server：**
- 實例類型：t3.micro
- AMI：Ubuntu 22.04 LTS
- 網路：Private Subnet
- 彈性 IP：無
- 安裝軟體：Nginx

#### 2.4 Security Groups

**VPN Gateway SG：**
```
Inbound:
  - SSH (22/tcp) from K8s Public IP
  - WireGuard (51820/udp) from K8s Public IP
  - ICMP from 10.244.0.0/16
  - All from VPC (10.0.0.0/16)

Outbound:
  - All traffic
```

**Private Server SG：**
```
Inbound:
  - HTTP (80/tcp) from VPC + K8s Pod CIDR
  - HTTPS (443/tcp) from VPC + K8s Pod CIDR
  - SSH (22/tcp) from VPN Gateway SG
  - ICMP from VPC + K8s Pod CIDR

Outbound:
  - All traffic
```

#### 2.5 NAT Gateway

**用途：** 讓 Private Subnet 的實例可以訪問網際網路

**配置：**
- 位置：Public Subnet
- 彈性 IP：已分配
- 狀態：持續運行（產生費用）

---

## 數據流向

### 場景 1: K8s Pod 訪問 AWS Private Subnet

```
┌────────────────────────────────────────────────────────────────┐
│  K8s Pod → AWS Private Server 數據流                          │
└────────────────────────────────────────────────────────────────┘

步驟 1: Pod 發起請求
  Pod (10.244.0.5) → 目標 (10.0.2.108)
  
步驟 2: Calico CNI 處理
  - 查找路由表
  - 轉發到 Node

步驟 3: Node 路由決策
  K8s Node 路由表:
  10.0.0.0/16 dev wg0 scope link
  ↓
  決定: 使用 wg0 介面

步驟 4: WireGuard 封裝
  原始封包: [10.244.0.5 → 10.0.2.108] HTTP Request
  ↓
  WireGuard 封裝:
  [192.168.93.130 → 54.x.x.x] UDP:51820
    └─ [ChaCha20 加密]
         └─ [10.244.0.5 → 10.0.2.108] HTTP Request

步驟 5: 網際網路傳輸
  加密封包透過網際網路傳送到 AWS

步驟 6: AWS VPN Gateway 接收
  54.x.x.x:51820 接收 UDP 封包
  ↓
  WireGuard 解密:
  [10.244.0.5 → 10.0.2.108] HTTP Request

步驟 7: AWS 內部路由
  VPN Gateway 查找路由表:
  10.0.2.0/24 → Private Subnet
  ↓
  轉發封包到 Private Subnet

步驟 8: Security Group 檢查
  Private Server SG:
  - 來源: 10.244.0.5 (K8s Pod CIDR) ✓
  - 目標埠: 80/tcp ✓
  - 允許通過

步驟 9: Test Server 處理
  Nginx 接收請求並回應

步驟 10: 回應路徑（反向）
  Test Server → VPN Gateway → WireGuard 加密
  → 網際網路 → K8s Node → WireGuard 解密
  → Calico CNI → Pod
```

### 場景 2: 外部用戶訪問 K8s Service

```
┌────────────────────────────────────────────────────────────────┐
│  外部用戶 → K8s Service (透過 NodePort)                        │
└────────────────────────────────────────────────────────────────┘

步驟 1: 用戶請求
  外部用戶 → K8s Node IP:NodePort
  例如: http://192.168.93.130:30080

步驟 2: iptables NAT (PREROUTING)
  目標 NAT:
  192.168.93.130:30080 → 10.96.x.x:80 (ClusterIP)

步驟 3: Service 負載均衡
  kube-proxy (iptables mode):
  隨機選擇一個 Pod Endpoint

步驟 4: DNAT 到 Pod
  10.96.x.x:80 → 10.244.0.5:8080 (Pod IP)

步驟 5: Pod 處理請求

步驟 6: 回應路徑
  Pod → Service → iptables SNAT → 用戶
```

### 場景 3: Private Subnet 訪問網際網路

```
┌────────────────────────────────────────────────────────────────┐
│  AWS Private Server → 網際網路 (透過 NAT Gateway)              │
└────────────────────────────────────────────────────────────────┘

步驟 1: Private Server 發起請求
  來源: 10.0.2.108
  目標: 8.8.8.8 (Google DNS)

步驟 2: Private Route Table
  0.0.0.0/0 → NAT Gateway

步驟 3: NAT Gateway 處理
  來源 NAT:
  10.0.2.108 → NAT Gateway Elastic IP

步驟 4: Internet Gateway
  NAT Gateway EIP → 網際網路

步驟 5: 回應路徑
  網際網路 → IGW → NAT Gateway
  → NAT 反向轉換 → Private Server
```

---

## 安全架構

### 加密層級

**Level 1: VPN 傳輸加密**
- 協定：WireGuard
- 加密算法：ChaCha20-Poly1305
- 金鑰交換：Curve25519
- 認證：Poly1305 MAC

**Level 2: 應用層加密（可選）**
- TLS/SSL for HTTPS
- mTLS for service-to-service

### 網路隔離

**分層隔離：**
```
Layer 1: AWS VPC 邊界
  └─ Internet Gateway 控制進出流量

Layer 2: Subnet 隔離
  ├─ Public Subnet: 暴露必要服務
  └─ Private Subnet: 完全隔離

Layer 3: Security Groups
  ├─ 實例級防火牆
  └─ 狀態化規則（Stateful）

Layer 4: Network Policies (K8s)
  ├─ Pod 級網路控制
  └─ Calico 實作

Layer 5: VPN 認證
  └─ 公私鑰對認證
```

### 存取控制矩陣

| 來源 | 目標 | 協定/埠 | 狀態 |
|------|------|---------|------|
| 網際網路 | VPN Gateway | 51820/udp | 允許（特定 IP） |
| 網際網路 | Private Subnet | 任何 | 拒絕 |
| K8s Pod CIDR | AWS VPC | 80,443/tcp | 允許 |
| K8s Pod CIDR | AWS Private | ICMP | 允許 |
| VPN Gateway | Private Subnet | SSH | 允許 |
| Private Subnet | 網際網路 | 任何 | 允許（透過 NAT） |

---

## 設計決策

### 為什麼選擇 WireGuard？

**優勢：**
1. **性能** - 核心程式碼僅 4000 行，執行效率高
2. **安全** - 使用現代加密算法，易於審計
3. **簡單** - 配置簡單，學習曲線平緩
4. **跨平台** - Linux 核心內建支援

**相比其他 VPN 方案：**
- vs OpenVPN: 更快，配置更簡單
- vs IPSec: 更易設定，更少的開銷
- vs SSH Tunnel: 更穩定，專為 VPN 設計

### 為什麼選擇 K3s？

**優勢：**
1. **輕量** - 單一二進位檔案，記憶體佔用低
2. **易部署** - 一條指令完成安裝
3. **功能完整** - 包含所有 Kubernetes 核心功能
4. **適合邊緣** - 適合資源受限環境

### 為什麼選擇 Calico CNI？

**優勢：**
1. **Network Policy** - 原生支援 Kubernetes Network Policy
2. **性能** - 高效的路由模式
3. **彈性** - 支援多種網路拓撲
4. **成熟** - 廣泛的生產使用經驗

### 為什麼選擇 NAT Gateway？

**優勢：**
1. **託管服務** - AWS 管理，無需維護
2. **高可用** - 自動冗餘
3. **彈性** - 自動擴展

**劣勢：**
- 成本較高（$0.045/小時）

**替代方案：**
- NAT Instance (t3.nano) - 成本更低但需要自行管理

---

## 擴展性考量

### 水平擴展

**K8s 集群擴展：**
```
單節點 → 多節點 HA 集群
  - 添加 Worker 節點
  - 配置 Load Balancer
  - 使用 etcd 集群
```

**AWS VPC 擴展：**
```
單 AZ → 多 AZ 部署
  - 每個 AZ 部署子網路
  - 多個 NAT Gateway（每 AZ 一個）
  - 跨 AZ 負載均衡
```

### 多區域架構

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  us-west-2   │     │  us-east-1   │     │  ap-east-1   │
│              │     │              │     │              │
│  VPC + VPN   │◄───►│  VPC + VPN   │◄───►│  VPC + VPN   │
│              │     │              │     │              │
└──────────────┘     └──────────────┘     └──────────────┘
        ▲                   ▲                   ▲
        │                   │                   │
        └───────────────────┴───────────────────┘
                     K8s Cluster
                  (單點或多點)
```

### 性能優化

**網路優化：**
- 啟用 Jumbo Frames (MTU 9000)
- 調整 TCP 參數

**K8s 優化：**
- 調整 Pod CIDR 大小
- 優化 Service 數量
- 使用 NodeLocal DNSCache

**VPN 優化：**
- 調整 WireGuard MTU
- 優化加密算法選擇
- 使用專用 VPN 實例

---

## 監控與可觀測性

### 建議的監控指標

**VPN 層：**
- WireGuard handshake 狀態
- 隧道流量統計
- 封包遺失率

**網路層：**
- Pod 到 AWS 延遲
- 網路吞吐量
- DNS 解析時間

**應用層：**
- HTTP 請求延遲
- 錯誤率
- 服務可用性

### 監控工具建議

**Prometheus + Grafana：**
```yaml
監控項目:
  - WireGuard Exporter
  - Node Exporter
  - AWS CloudWatch Exporter
  - Blackbox Exporter (端到端測試)
```

**日誌收集：**
```yaml
工具: ELK Stack 或 Loki
來源:
  - WireGuard 日誌
  - iptables 日誌
  - K8s 事件
  - 應用日誌
```

---

## 災難復原

### 備份策略

**需要備份的項目：**
1. WireGuard 私鑰
2. Terraform State
3. Kubernetes 配置
4. 應用數據

**備份頻率：**
- 配置檔：每次變更後
- 應用數據：每日
- 快照：每週

### 復原程序

**VPN 連線中斷：**
```bash
1. 檢查 WireGuard 狀態
2. 重啟 WireGuard 服務
3. 驗證路由表
4. 測試連通性
```

**完全災難復原：**
```bash
1. 從備份恢復 Terraform State
2. 執行 terraform apply
3. 恢復 WireGuard 配置
4. 重新部署 K8s 應用
5. 驗證端到端連通性
```

---

## 附錄

### A. 完整的路由表範例

**K8s Node 路由表：**
```
Destination        Gateway         Genmask         Flags Metric Ref    Use Iface
0.0.0.0            192.168.93.2    0.0.0.0         UG    100    0        0 eth0
10.0.0.0           0.0.0.0         255.255.0.0     U     0      0        0 wg0
10.244.0.0         0.0.0.0         255.255.0.0     U     0      0        0 cni0
192.168.93.0       0.0.0.0         255.255.255.0   U     100    0        0 eth0
192.168.100.0      0.0.0.0         255.255.255.0   U     0      0        0 wg0
```

### B. iptables 規則範例

**NAT 表：**
```bash
Chain POSTROUTING (policy ACCEPT)
target     prot opt source               destination
MASQUERADE  all  --  0.0.0.0/0            0.0.0.0/0           /* K8s pod traffic */ 
MASQUERADE  all  --  0.0.0.0/0            0.0.0.0/0           /* WireGuard VPN */   out dev eth0
```

**Filter 表：**
```bash
Chain FORWARD (policy DROP)
target     prot opt source               destination
ACCEPT     all  --  0.0.0.0/0            0.0.0.0/0           /* WireGuard */ in dev wg0
ACCEPT     all  --  0.0.0.0/0            0.0.0.0/0           /* WireGuard */ out dev wg0
```

