output "nat_private_ip" {
value = aws_instance.nat_instance.private_ip
}

output "nat_public_ip" {
value = aws_instance.nat_instance.public_ip
}

output "private_ec2_ip" {
value = aws_instance.pvt_compute.private_ip
}

