#############################
# Fetch AWS Account ID
#############################
data "aws_caller_identity" "current" {}

#############################
# Fetch Latest Ubuntu AMI
#############################
data "aws_ami" "ubuntu_latest" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["099720109477"]  # Canonical's Ubuntu Owner ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  final_ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu_latest[0].id
}

#############################
# IAM Role for EKS Client Node
#############################
resource "aws_iam_role" "github_runner_ssm_role" {
  name = "github-runner-ssm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      }
    ]
  })
}

# Attach SSM Agent Policy to allow AWS Session Manager functionality
resource "aws_iam_role_policy_attachment" "github_runner_ssm_policy_attach" {
  role       = aws_iam_role.github_runner_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Allow EKS client node to update kubeconfig and interact with EKS API
resource "aws_iam_policy" "github_runner_eks_access" {
  name        = "EKSClientEKSAccessPolicy"
  description = "Allows EKS client instance to access and update EKS kubeconfig"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:ListNodegroups",
          "eks:DescribeNodegroup",
          "eks:UpdateClusterConfig",
          "eks:UpdateKubeconfig" # Added permission for updating kubeconfig
        ],
        Effect   = "Allow",
        Resource = "arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"
      }
    ]
  })
}

# Attach policy to IAM role
resource "aws_iam_role_policy_attachment" "github_runner_eks_access_attach" {
  role       = aws_iam_role.github_runner_ssm_role.name
  policy_arn = aws_iam_policy.github_runner_eks_access.arn
}

# Create an instance profile for the EC2 instance to use the IAM Role
resource "aws_iam_instance_profile" "github_runner_ssm_profile" {
  name = "github-runner-ssm-profile"
  role = aws_iam_role.github_runner_ssm_role.name
}


resource "aws_instance" "github-self-hosted-runner" {
  ami           = var.ami_id
  iam_instance_profile   = aws_iam_instance_profile.github_runner_ssm_profile.name
  instance_type = var.instance_type
  key_name      = var.key_name
  user_data     = file("${path.module}/terraform.sh")
  vpc_security_group_ids      = [var.security_group_id]
  subnet_id                   = var.subnet_id

  tags = {
    Name = "self-hosted-runner"
  }
}