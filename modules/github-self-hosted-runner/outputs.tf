output "terraform_node_public_ip" {
  value = aws_instance.terraform_node.public_ip
}
