output "terraform_node_public_ip" {
  value = aws_instance.github-self-hosted-runner.public_ip
}
