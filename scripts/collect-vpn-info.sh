#!/bin/bash

echo "=== VPN 設定資訊匯總 ==="
echo ""

# K8s 端資訊
echo "【K8s 端】"
echo "K8s 公網 IP: $(cat ~/hybridbridge/docs/my-public-ip.txt)"
echo "K8s 私網 IP: 192.168.93.130"
echo "K8s VPN IP: 192.168.100.1"
echo "K8s 公鑰: $(cat ~/hybridbridge/docs/k8s-vpn-pubkey.txt)"
echo "K8s 私鑰路徑: /etc/wireguard/privatekey"
echo ""

# AWS 端資訊
cd ~/hybridbridge/terraform/aws
echo "【AWS 端】"
echo "AWS VPN Gateway 公網 IP: $(terraform output -raw vpn_gateway_public_ip)"
echo "AWS VPN Gateway 私網 IP: $(terraform output -raw vpn_gateway_private_ip)"
echo "AWS VPN IP: 192.168.100.2"
echo "AWS 公鑰: $(cat ~/hybridbridge/docs/aws-vpn-pubkey.txt)"
echo "AWS 私鑰路徑: /etc/wireguard/privatekey (在 AWS 機器上)"
echo ""

# 網路範圍
echo "【網路範圍】"
echo "VPN Tunnel: 192.168.100.0/24"
echo "AWS VPC: 10.0.0.0/16"
echo "K8s Pod CIDR: 10.244.0.0/16"
echo "K8s Service CIDR: 10.96.0.0/12"
cd ~/hybridbridge
