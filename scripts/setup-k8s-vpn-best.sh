#!/bin/bash

set -e

echo "╔════════════════════════════════════════════════════╗"
echo "║     設定 K8s 端 WireGuard VPN                     ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

# 確認必要目錄存在
mkdir -p ~/hybridbridge/docs

# 【1】檢查並安裝 WireGuard
echo "【1/7】檢查 WireGuard..."
if ! command -v wg &> /dev/null; then
    echo "WireGuard 未安裝，開始安裝..."
    sudo apt-get update -qq
    sudo apt-get install -y wireguard wireguard-tools iptables
    echo "✅ WireGuard 已安裝"
else
    echo "✅ WireGuard 已安裝"
fi
echo ""

# 【2】生成 WireGuard 金鑰對
echo "【2/7】生成 WireGuard 金鑰對..."
if [ ! -f /etc/wireguard/privatekey ]; then
    echo "生成新金鑰..."
    sudo sh -c 'umask 077; wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey'
    echo "✅ 金鑰已生成"
else
    echo "⚠️  金鑰已存在，跳過生成"
fi

# 儲存 K8s 公鑰
sudo cat /etc/wireguard/publickey > ~/hybridbridge/docs/k8s-vpn-pubkey.txt
K8S_PUBKEY=$(cat ~/hybridbridge/docs/k8s-vpn-pubkey.txt)
echo "✅ K8s 公鑰: $K8S_PUBKEY"
echo ""

# 【3】獲取 AWS VPN Gateway IP
echo "【3/7】獲取 AWS VPN Gateway IP..."
cd ~/hybridbridge/terraform/aws

if [ ! -f "terraform.tfstate" ]; then
    echo "❌ 找不到 terraform.tfstate"
    echo "請先完成 AWS 基礎設施部署（terraform apply）"
    exit 1
fi

AWS_VPN_IP=$(terraform output -raw vpn_gateway_public_ip 2>/dev/null)
if [ -z "$AWS_VPN_IP" ]; then
    echo "❌ 無法獲取 AWS VPN Gateway IP"
    exit 1
fi

echo "✅ AWS VPN Gateway IP: $AWS_VPN_IP"
cd ~/hybridbridge
echo ""

# 【4】等待 AWS 實例並獲取公鑰
echo "【4/7】等待 AWS VPN Gateway 就緒並獲取公鑰..."
echo "這可能需要 1-3 分鐘..."

AWS_READY=false
for i in {1..30}; do
    if ssh -i ~/.ssh/hybridbridge-key \
           -o ConnectTimeout=5 \
           -o StrictHostKeyChecking=no \
           -o BatchMode=yes \
           ubuntu@$AWS_VPN_IP \
           "test -f /etc/wireguard/publickey" 2>/dev/null; then
        AWS_READY=true
        break
    fi
    
    if [ $i -eq 30 ]; then
        echo ""
        echo "❌ 等待超時（5 分鐘）"
        echo "請檢查："
        echo "  1. AWS EC2 實例是否正在運行"
        echo "  2. Security Group 是否允許 SSH (port 22)"
        echo "  3. SSH 金鑰是否正確"
        exit 1
    fi
    
    echo -n "."
    sleep 10
done

echo ""
if [ "$AWS_READY" = true ]; then
    echo "✅ AWS VPN Gateway 已就緒"
fi

# 獲取 AWS 公鑰
ssh -i ~/.ssh/hybridbridge-key \
    -o StrictHostKeyChecking=no \
    ubuntu@$AWS_VPN_IP \
    "sudo cat /etc/wireguard/publickey" > ~/hybridbridge/docs/aws-vpn-pubkey.txt

AWS_PUBKEY=$(cat ~/hybridbridge/docs/aws-vpn-pubkey.txt)
echo "✅ AWS 公鑰: $AWS_PUBKEY"
echo ""

# 【5】偵測網路介面
echo "【5/7】偵測網路介面..."
IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
if [ -z "$IFACE" ]; then
    echo "⚠️  無法自動偵測，使用預設值 eth0"
    IFACE="eth0"
else
    echo "✅ 偵測到網路介面: $IFACE"
fi
echo ""

# 【6】建立 WireGuard 配置
echo "【6/7】建立 WireGuard 配置..."
K8S_PRIVATE_KEY=$(sudo cat /etc/wireguard/privatekey)

sudo tee /etc/wireguard/wg0.conf > /dev/null <<EOF
[Interface]
PrivateKey = $K8S_PRIVATE_KEY
Address = 192.168.100.1/24
ListenPort = 51820

# 路由設定 - 讓流量到 AWS VPC 走 VPN
PostUp = ip route add 10.0.0.0/16 dev wg0 2>/dev/null || true

# 防火牆規則 - 允許 VPN 流量轉發
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT
PostUp = iptables -A FORWARD -o wg0 -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o $IFACE -j MASQUERADE

# 清理規則
PostDown = ip route del 10.0.0.0/16 dev wg0 2>/dev/null || true
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
PostDown = iptables -D FORWARD -o wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o $IFACE -j MASQUERADE

[Peer]
# AWS VPN Gateway
PublicKey = $AWS_PUBKEY
Endpoint = $AWS_VPN_IP:51820
AllowedIPs = 10.0.0.0/16, 192.168.100.2/32
PersistentKeepalive = 25
EOF

sudo chmod 600 /etc/wireguard/wg0.conf
echo "✅ 配置檔已建立: /etc/wireguard/wg0.conf"
echo ""

# 【7】啟用 IP forwarding
echo "【7/7】啟用 IP forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null

if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf > /dev/null
    echo "✅ IP forwarding 已啟用並持久化"
else
    echo "✅ IP forwarding 已啟用"
fi
echo ""

# 顯示配置摘要
echo "╔════════════════════════════════════════════════════╗"
echo "║          VPN 配置摘要                             ║"
echo "╠════════════════════════════════════════════════════╣"
echo "║ K8s VPN IP:        192.168.100.1                  ║"
echo "║ AWS VPN IP:        192.168.100.2                  ║"
echo "║ AWS Endpoint:      $AWS_VPN_IP:51820"
echo "║ 網路介面:         $IFACE"
echo "║ K8s 公鑰:          ${K8S_PUBKEY:0:32}...         ║"
echo "║ AWS 公鑰:          ${AWS_PUBKEY:0:32}...         ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

echo "╔════════════════════════════════════════════════════╗"
echo "║  ✅ K8s 端 VPN 設定完成！                         ║"
echo "╠════════════════════════════════════════════════════╣"
echo "║  下一步操作：                                      ║"
echo "║                                                    ║"
echo "║  1. 設定 AWS 端 VPN：                             ║"
echo "║     ./scripts/setup-aws-vpn.sh                    ║"
echo "║                                                    ║"
echo "║  2. 啟動 K8s 端 VPN：                             ║"
echo "║     sudo wg-quick up wg0                          ║"
echo "║     sudo systemctl enable wg-quick@wg0            ║"
echo "║                                                    ║"
echo "║  3. 啟動 AWS 端 VPN（在 setup-aws-vpn.sh 後）：   ║"
echo "║     ssh -i ~/.ssh/hybridbridge-key ubuntu@$AWS_VPN_IP  ║"
echo "║     sudo wg-quick up wg0                          ║"
echo "║     sudo systemctl enable wg-quick@wg0            ║"
echo "║                                                    ║"
echo "║  4. 測試 VPN 連線：                               ║"
echo "║     ./scripts/test-vpn-connectivity.sh            ║"
echo "╚════════════════════════════════════════════════════╝"
