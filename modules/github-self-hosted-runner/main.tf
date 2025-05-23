resource "aws_instance" "terraform_node" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  user_data     = file("${path.module}/terraform.sh")
  vpc_security_group_ids      = [var.security_group_id]
  subnet_id                   = var.subnet_id

  tags = {
    Name = "self-hosted-runner"
  }
}