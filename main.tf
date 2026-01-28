provider "aws" {
  region = "ap-south-1" 
}

# 0. Generate SSH Key Pair
resource "tls_private_key" "n8n_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "n8n_key_pair" {
  key_name   = "nayapay-n8n-key"
  public_key = tls_private_key.n8n_key.public_key_openssh
}

# Save private key locally for SSH access
resource "local_file" "private_key" {
  content         = tls_private_key.n8n_key.private_key_pem
  filename        = "${path.module}/nayapay-n8n-key.pem"
  file_permission = "0400"
}

# 1. Security Group Logic
resource "aws_security_group" "n8n_sg" {
  name        = "n8n-access-rules"
  description = "Security group for n8n automation server"

  # SSH Access (So you can fix things from your laptop)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # For high security, use your specific IP
  }

  # n8n Web Interface and Webhook Port
  ingress {
    from_port   = 5678
    to_port     = 5678
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  # Outbound Traffic (Crucial for Gemini API and Docker updates)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # Allow all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 2. EC2 Instance Definition
resource "aws_instance" "n8n_server" {
  ami           = "ami-019715e0d74f695be" # Ubuntu 24.04 LTS
  instance_type = "t3.micro"             # Free Tier
  key_name      = aws_key_pair.n8n_key_pair.key_name

  vpc_security_group_ids = [aws_security_group.n8n_sg.id]

  # Automated Setup Script
  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install docker.io -y
              sudo systemctl start docker
              sudo systemctl enable docker
              # Create n8n data directory with correct permissions (node user UID=1000)
              sudo mkdir -p /home/ubuntu/.n8n
              sudo chown -R 1000:1000 /home/ubuntu/.n8n
              # Running n8n with restart policy so it stays up
              sudo docker run -d \
                --name n8n \
                --restart always \
                -p 5678:5678 \
                -e N8N_SECURE_COOKIE=false \
                -v /home/ubuntu/.n8n:/home/node/.n8n \
                n8nio/n8n
              EOF

  tags = {
    Name = "NayaPay-Automation-Server"
    Environment = "Production"
  }
}

# 3. Output the IP (So you don't have to look it up in the console)
output "n8n_public_ip" {
  value = aws_instance.n8n_server.public_ip
}

output "ssh_command" {
  value = "ssh -i ${path.module}/nayapay-n8n-key.pem ubuntu@${aws_instance.n8n_server.public_ip}"
}

output "n8n_url" {
  value = "http://${aws_instance.n8n_server.public_ip}:5678"
}