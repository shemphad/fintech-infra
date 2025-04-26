resource "aws_instance" "jenkins_server" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  vpc_security_group_ids      = [var.security_group_id]
  subnet_id                   = var.subnet_id
  user_data     = file("${path.module}/jenkins.sh")

  tags = {
    Name = "jenkins-server"
  }
}
