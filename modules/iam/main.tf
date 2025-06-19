provider "aws" {
  region = "us-east-2"
}

# IAM Role for GitHub Actions
resource "aws_iam_role" "github_actions_role" {
  name = "${var.environment}-GitHubActionsECR"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${var.aws_account_id}:oidc-provider/token.actions.githubusercontent.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:*/fintech-app:*"
          }
        }
      }
    ]
  })
}

# Use this Terraform configuration to create the GitHub Actions OIDC provider in AWS
resource "aws_iam_openid_connect_provider" "github_oidc" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1"  # ✅ GitHub's official OIDC thumbprint
  ]
}

# Attach ECR permissions to IAM Role
resource "aws_iam_policy" "github_ecr_policy" {
  name        = "${var.environment}-GitHubECRPolicy"
  description = "Permissions for GitHub Actions to push/pull from ECR"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:BatchGetImage"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:*"
      },
      # Allow GitHub Actions to assume the role correctly
      {
        Effect = "Allow"
        Action = "sts:TagSession"
        Resource = "*"
      }
    ]
  })
}


# Attach EKS permissions to IAM Role
resource "aws_iam_policy" "github_eks_policy" {
  name        = "${var.environment}-GitHubEKSPolicy"
  description = "Permissions for GitHub Actions to deploy to EKS"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:UpdateClusterConfig"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach Policies to Role
resource "aws_iam_role_policy_attachment" "attach_ecr" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = aws_iam_policy.github_ecr_policy.arn
}

resource "aws_iam_role_policy_attachment" "attach_eks" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = aws_iam_policy.github_eks_policy.arn
}


