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
resource "aws_iam_role" "eks_client_ssm_role" {
  name = "eks-client-ssm-role"
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
resource "aws_iam_role_policy_attachment" "eks_client_ssm_policy_attach" {
  role       = aws_iam_role.eks_client_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Allow EKS client node to update kubeconfig and interact with EKS API
resource "aws_iam_policy" "eks_client_eks_access" {
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
resource "aws_iam_role_policy_attachment" "eks_client_eks_access_attach" {
  role       = aws_iam_role.eks_client_ssm_role.name
  policy_arn = aws_iam_policy.eks_client_eks_access.arn
}

# Create an instance profile for the EC2 instance to use the IAM Role
resource "aws_iam_instance_profile" "eks_client_ssm_profile" {
  name = "eks-client-ssm-profile"
  role = aws_iam_role.eks_client_ssm_role.name
}

#############################
# Updated EC2 Instance Resource
############################## Generate an RSA private ke

# EC2 instance using the generated key pair for SSH access
resource "aws_instance" "eks_client_node" {
  ami                    = local.final_ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.eks_client_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.eks_client_ssm_profile.name
  key_name               = aws_key_pair.eks_client_key.key_name
  tags                   = var.tags

  root_block_device {
    volume_size           = 15
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = var.user_data

  depends_on = [
    aws_iam_instance_profile.eks_client_ssm_profile
  ]
}

resource "aws_eip" "eks_client_eip" {
  instance = aws_instance.eks_client_node.id
  domain = "vpc"

  depends_on = [
    aws_instance.eks_client_node
  ]
}


#############################
# Security Group for EKS Client Node
#############################resource "aws_security_group" "eks_client_sg" {
  resource "aws_security_group" "eks_client_sg" {
  name        = "eks-client-sg"
  description = "Security group for EKS client instance with SSM access and SSH access"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
   }

   ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound rule to allow all traffic (needed for AWS API access)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
