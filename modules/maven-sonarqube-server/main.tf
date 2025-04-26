# provider "aws" {
#   region = var.region
# }

resource "aws_instance" "sonarqube" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  vpc_security_group_ids      = [var.security_group_id]
  subnet_id                   = var.subnet_id
  associate_public_ip_address = true
  user_data                   = file("${path.module}/maven_sonarqube.sh")
  tags = {
    Name = "Maven-Sonarqube-Server"
  }
}

# resource "aws_db_instance" "postgresql" {
#   identifier             = "sonarqube-postgresql"
#   allocated_storage      = 20
#   engine                 = "postgres"
#   engine_version         = "16"
#   instance_class         = "db.t3.micro"
#   db_name                = var.db_name
#   username               = var.db_username
#   password               = var.db_password
#   parameter_group_name   = "default.postgres16"
#   skip_final_snapshot    = true
#   publicly_accessible    = true
#   vpc_security_group_ids = var.db_security_group_id
#   db_subnet_group_name   = var.db_subnet_group
# }
