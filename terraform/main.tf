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
    from_port    = 22
    to_port      = 22
    protocol      = "tcp"
    cidr_blocks = ["106.219.125.163/32"]
  }

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
resource "aws_key_pair" "project1-nat" {
  key_name   = "project1-nat"
  public_key = file("~/.ssh/project1-nat.pub")

  tags = { Name = "project1-nat" }
}

resource "aws_instance" "nat_instance" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public.id
  source_dest_check           = false
  associate_public_ip_address = true
  key_name                    = aws_key_pair.project1-nat.key_name


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
  route_table_id         = aws_route_table.private-rt.id
  destination_cidr_block = "0.0.0.0/0"

  network_interface_id = aws_instance.nat_instance.primary_network_interface_id
}
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = { Name = "nat-eip" }
}

resource "aws_eip_association" "nat_eip" {
  allocation_id = aws_eip.nat_eip.id
  instance_id   = aws_instance.nat_instance.id
}

resource "aws_security_group" "pvt_sg" {

name = "pvt-sg" 
vpc_id = aws_vpc.main.id

ingress { 
to_port = 22
from_port = 22
protocol = "tcp"
security_groups = [aws_security_group.nat_sg.id]
}

egress {
to_port = 0
from_port = 0
protocol = "-1"
cidr_blocks = ["0.0.0.0/0"]
}

tags = { Name = "pvt-sg"
}
}
resource "aws_instance" "pvt_compute" {
ami = data.aws_ami.amazon_linux.id
instance_type = "t3.micro"
subnet_id = aws_subnet.private.id
associate_public_ip_address = false

vpc_security_group_ids = [ aws_security_group.pvt_sg.id ]

key_name = aws_key_pair.project1-nat.key_name

tags = { Name = "private-compute" }
}

