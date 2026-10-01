resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "MyVPC" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = { Name = "Public-Subnet" }
}

resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"

  tags = { Name = "Private-Subnet" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "Cloud-IGW" }
}

resource "aws_route_table" "public-rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "Public-Route-Table" }
}
resource "aws_route_table_association" "public-rt" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public-rt.id
}

resource "aws_route_table" "private-rt" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "Private-Route-Table" }
}

resource "aws_route_table_association" "private-rt" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private-rt.id
}
resource "aws_security_group" "nat_sg" {
  name   = "nat-instance-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.2.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "nat-instance-sg" }
}
data "aws_ami" "amazon_linux" {
  most_recent = true

  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_instance" "nat_instance" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public.id
  source_dest_check           = false
  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.nat_sg.id
  ]

  user_data = <<-EOF
              #!/bin/bash

              echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-ip-forward.conf
              sysctl -p /etc/sysctl.d/99-ip-forward.conf

              IFACE=$(ip -o -4 route show to default | awk '{print $5}')

              iptables -t nat -A POSTROUTING -o $IFACE -j MASQUERADE

              dnf install -y iptables-services

              iptables-save > /etc/sysconfig/iptables

              systemctl enable --now iptables
              EOF

  tags = {
    Name = "linux-nat-router"
  }
}
resource "aws_route" "private_nat" {
route_table_id = aws_route_table.private-rt.id
destination_cidr_block = "0.0.0.0/0"

network_interface_id = aws_instance.nat_instance.primary_network_interface_id
}
