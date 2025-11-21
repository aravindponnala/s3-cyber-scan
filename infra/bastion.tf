resource "aws_instance" "bastion" {
  ami                    = "ami-0c02fb55956c7d316"  # Amazon Linux 2 in us-east-1
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  associate_public_ip_address = true
  key_name               = var.ec2_key_name

  tags = {
    Name = "scanner-bastion"
  }
}
