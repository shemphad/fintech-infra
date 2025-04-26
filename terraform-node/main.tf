resource "aws_instance" "terraform_node" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  user_data     = file("${path.module}/terraform.sh")

  tags = {
    Name = "terraform-node"
  }
}