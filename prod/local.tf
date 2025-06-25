# Fetch latest Ubuntu 20.04 AMI if ami_id not explicitly provided
data "aws_ami" "ubuntu_latest" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# EKS cluster data source (used for IRSA OIDC derivation)
data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

# Local values
locals {
  final_ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu_latest[0].id

  eks_oidc_provider = replace(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")

  common_tags = merge(var.tags, {
    env_name = var.env_name
  })
}
