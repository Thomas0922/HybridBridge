output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_id" {
  description = "Public Subnet ID"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "Private Subnet ID"
  value       = aws_subnet.private.id
}

output "vpn_gateway_public_ip" {
  description = "VPN Gateway public IP"
  value       = aws_instance.vpn_gateway.public_ip
}

output "vpn_gateway_private_ip" {
  description = "VPN Gateway private IP"
  value       = aws_instance.vpn_gateway.private_ip
}

output "test_server_private_ip" {
  description = "Test Server private IP"
  value       = aws_instance.test_server.private_ip
}

output "nat_gateway_ip" {
  description = "NAT Gateway public IP"
  value       = aws_eip.nat.public_ip
}

output "ssh_to_vpn_gateway" {
  description = "SSH command to VPN gateway"
  value       = "ssh -i ~/.ssh/hybridbridge-key ubuntu@${aws_instance.vpn_gateway.public_ip}"
}

output "vpn_gateway_public_key_command" {
  description = "Command to get VPN gateway WireGuard public key"
  value       = "ssh -i ~/.ssh/hybridbridge-key ubuntu@${aws_instance.vpn_gateway.public_ip} 'sudo cat /etc/wireguard/publickey'"
}

output "test_server_url" {
  description = "Test server URL (accessible via VPN)"
  value       = "http://${aws_instance.test_server.private_ip}"
}
