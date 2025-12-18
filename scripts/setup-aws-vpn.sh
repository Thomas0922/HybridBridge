#!/bin/bash

set -e

# 定義路徑
PROJECT_ROOT=~/HybridBridge
DOCS_DIR=$PROJECT_ROOT/docs
TF_DIR=$PROJECT_ROOT/terraform/aws

echo "=== 設定 AWS VPN Gateway ==="

# 檢查必要檔案是否存在
if [ ! -f "$DOCS_DIR/k8s-vpn-pubkey.txt" ]; then
    echo "❌ 錯誤：找不到 K8s 公鑰 ($DOCS_DIR/k8s-vpn-pubkey.txt)"
    echo "請先執行 ./scripts/setup-k8s-vpn.sh"
    exit 1
fi

# 收集資訊
echo "【1】讀取設定資訊..."
K8S_PUBKEY=$(cat $DOCS_DIR/k8s-vpn-pubkey.txt)
K8S_PUBLIC_IP=$(cat $DOCS_DIR/my-public-ip.txt)

cd $TF_DIR
AWS_VPN_IP=$(terraform output -raw vpn_gateway_public_ip)

echo "K8s 公鑰: $K8S_PUBKEY"
echo "K8s 公網 IP: $K8S_PUBLIC_IP"
echo "AWS VPN IP: $AWS_VPN_IP"
echo ""

# SSH 到 AWS 並建立設定
echo "【2】連線到 AWS 進行設定..."
ssh -i ~/.ssh/hybridbridge-key -o StrictHostKeyChecking=no ubuntu@$AWS_VPN_IP << EOFSSH
set -e

# 1. 等待 EC2 初始化完成 (修復 Race Condition)
echo "檢查 EC2 初始化狀態..."
timeout=300 # 5分鐘超時
elapsed=0
while [ ! -f /var/log/setup-complete.log ]; do
    if [ \$elapsed -ge \$timeout ]; then
        echo "❌ 錯誤：等待 EC2 初始化超時"
        exit 1
    fi
    echo "正在等待 cloud-init 完成 (已耗時 \${elapsed}s)..."
    sleep 10
    elapsed=\$((elapsed+10))
done
echo "✅ EC2 初始化已完成，開始設定 VPN..."

# 2. 自動偵測 AWS 網卡介面 (取代寫死的 ens5)
DEFAULT_IF=\$(ip route | grep default | awk '{print \$5}' | head -n1)
echo "偵測到主要網卡: \$DEFAULT_IF"

# 3. 讀取 AWS 私鑰 (由 user_data 生成)
AWS_PRIVATE_KEY=\$(sudo cat /etc/wireguard/privatekey)

# 4. 建立設定檔
echo "寫入 WireGuard 設定..."
sudo tee /etc/wireguard/wg0.conf > /dev/null <<EOF
[Interface]
PrivateKey = \$AWS_PRIVATE_KEY
Address = 192.168.100.2/24
ListenPort = 51820

# 路由與 NAT 設定
# 啟用 IP Masquerade 以允許回程流量
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o \$DEFAULT_IF -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o \$DEFAULT_IF -j MASQUERADE

[Peer]
PublicKey = $K8S_PUBKEY
Endpoint = $K8S_PUBLIC_IP:51820
# 允許訪問的網段：K8s Pod CIDR (10.244.0.0/16), Service CIDR (10.96.0.0/12), VPN Tunnel (192.168.100.1/32)
AllowedIPs = 10.244.0.0/16, 10.96.0.0/12, 192.168.100.1/32
PersistentKeepalive = 25
EOF

# 設定權限
sudo chmod 600 /etc/wireguard/wg0.conf

# 5. 啟用 IP forwarding (使用 sysctl.d 避免汙染主檔)
echo "啟用核心轉發..."
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-wireguard.conf > /dev/null
sudo sysctl -p /etc/sysctl.d/99-wireguard.conf > /dev/null

# 6. 啟動服務 (修復：之前版本遺漏了這一步)
echo "啟動 WireGuard 服務..."
# 如果已經運行先停止，避免報錯
sudo wg-quick down wg0 2>/dev/null || true
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0

# 7. 驗證狀態
if sudo wg show wg0 > /dev/null; then
    echo "✅ AWS VPN Gateway 服務啟動成功"
    sudo wg show wg0
else
    echo "❌ 服務啟動失敗"
    exit 1
fi

echo "AWS VPN Gateway 設定完成"
EOFSSH

echo ""
echo "✅ AWS 端設定完成！VPN 通道應已建立。"
echo "現在您可以執行 ./scripts/test-vpn-connectivity.sh 進行測試。"
