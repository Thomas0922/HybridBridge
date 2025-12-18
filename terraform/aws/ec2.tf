data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "vpn_gateway" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.vpn_gateway.id]
  key_name               = var.key_pair_name
  source_dest_check      = false

  user_data = <<-EOF
              #!/bin/bash
              set -e
              
               # 【新增】設定非互動模式，防止 apt-get upgrade 卡住
               export DEBIAN_FRONTEND=noninteractive
              
               # 檢查並等待鎖定釋放 (避免與其他更新衝突)
               while fuser /var/lib/dpkg/lock >/dev/null 2>&1 ; do sleep 1 ; done
               while fuser /var/lib/apt/lists/lock >/dev/null 2>&1 ; do sleep 1 ; done
            
               apt-get update
               # 加入參數以自動回答 "yes" 並保留舊設定
               apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
              
               apt-get install -y wireguard wireguard-tools
              
               echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
               echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
               sysctl -p
              
               apt-get install -y htop iotop iftop
              
               # 生成金鑰
               wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey
               chmod 600 /etc/wireguard/privatekey
              
               echo "VPN Gateway setup complete at $(date)" > /var/log/setup-complete.log
               EOF

   tags = {
     Name = "${var.project_name}-vpn-gateway"
     Role = "vpn-gateway"
   }
 }

resource "aws_instance" "test_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.private.id]
  key_name               = var.key_pair_name

  user_data = <<-EOF
              #!/bin/bash
              set -e
              
              apt-get update
            
              
              apt-get install -y nginx
              
              cat > /var/www/html/index.html <<HTML
              <!DOCTYPE html>
              <html>
              <head>
                <title>HybridBridge Test Server</title>
                <style>
                  body { font-family: Arial; margin: 40px; background: #f0f0f0; }
                  .container { background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
                  h1 { color: #333; }
                  .info { background: #e8f4f8; padding: 15px; border-radius: 5px; margin: 20px 0; }
                  .success { color: #27ae60; font-weight: bold; }
                </style>
              </head>
              <body>
                <div class="container">
                  <h1>🌉 HybridBridge Test Server</h1>
                  <p class="success">✓ Successfully connected to AWS Private Subnet!</p>
                  <div class="info">
                    <p><strong>Server Info:</strong></p>
                    <p>Hostname: $(hostname)</p>
                    <p>Private IP: $(hostname -I | awk '{print $1}')</p>
                    <p>Environment: AWS VPC Private Subnet</p>
                    <p>Time: $(date)</p>
                  </div>
                  <p><small>This server is only accessible through VPN tunnel</small></p>
                </div>
              </body>
              </html>
              HTML
              
              systemctl enable nginx
              systemctl start nginx
              
              echo "Test server setup complete at $(date)" > /var/log/setup-complete.log
              EOF

  tags = {
    Name = "${var.project_name}-test-server"
    Role = "test-server"
  }
}
