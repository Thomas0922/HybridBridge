#!/bin/bash

set -e

# 收集資訊
K8S_PUBKEY=$(cat ~/hybridbridge/docs/k8s-vpn-pubkey.txt)
K8S_PUBLIC_IP=$(cat ~/hybridbridge/docs/my-public-ip.txt)
AWS_VPN_IP=$(cd ~/hybridbridge/terraform/aws && terraform output -raw vpn_gateway_public_ip)

echo "=== 設定 AWS VPN Gateway ==="
echo "K8s 公鑰: $K8S_PUBKEY"
echo "K8s 公網 IP: $K8S_PUBLIC_IP"
echo "AWS VPN IP: $AWS_VPN_IP"
echo ""

# SSH 到 AWS 並建立設定
ssh -i ~/.ssh/hybridbridge-key ubuntu@$AWS_VPN_IP << EOFSSH
# 讀取 AWS 私鑰
AWS_PRIVATE_KEY=\$(sudo cat /etc/wireguard/privatekey)

# 建立設定檔
sudo tee /etc/wireguard/wg0.conf > /dev/null <<EOF
[Interface]
PrivateKey = \$AWS_PRIVATE_KEY
Address = 192.168.100.2/24
ListenPort = 51820

PostUp = iptables -A FORWARD -i wg0 -j ACCEPT
PostUp = iptables -A FORWARD -o wg0 -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o ens5 -j MASQUERADE

PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
PostDown = iptables -D FORWARD -o wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o ens5 -j MASQUERADE

[Peer]
PublicKey = $K8S_PUBKEY
Endpoint = $K8S_PUBLIC_IP:51820
AllowedIPs = 10.244.0.0/16, 10.96.0.0/12, 192.168.100.1/32
PersistentKeepalive = 25
EOF

# 設定權限
sudo chmod 600 /etc/wireguard/wg0.conf

# 啟用 IP forwarding
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

echo "✅ AWS VPN Gateway 設定完成"
EOFSSH

echo ""
echo "✅ AWS 端設定完成！"
