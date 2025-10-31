##############################################
# EKS Data + Auth
##############################################

data "aws_eks_cluster_auth" "main" {
  name = module.eks.cluster_name
}

data "aws_caller_identity" "current" {}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

locals {
  common_tags = {
    Environment = "Prod"
    ManagedBy   = "Terraform"
    Project     = "EKS-Cluster"
  }
}

##############################################
# IAM Roles (FIX: These roles were missing definitions)
##############################################

# Role for general EKS cluster administration access (referenced by the 'general' entry)
resource "aws_iam_role" "eks_access_role" {
  name = "eks-access-role"
  
  # NOTE: The Principal MUST match the entity that will assume this role (e.g., a specific User ARN, another role, or an OIDC provider).
  # We use the current account ARN as a placeholder for simplicity.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          AWS = data.aws_caller_identity.current.arn 
        }
      },
    ]
  })
  tags = local.common_tags
}

# Role for a GitHub Runner or CI/CD system (referenced by the 'github_runner' entry)
resource "aws_iam_role" "github_runner_ssm_role" {
  name = "github-runner-ssm-role"
  
  # NOTE: The Principal MUST match the entity that will assume this role (e.g., an OIDC provider for GitHub Actions).
  # We use the current account ARN as a placeholder for simplicity.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          AWS = data.aws_caller_identity.current.arn 
        }
      },
    ]
  })
  tags = local.common_tags
}


##############################################
# EKS Control Plane + Node Groups + Add-ons
##############################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name             = var.cluster_name
  cluster_version          = "1.32"

  enable_cluster_creator_admin_permissions = true
  cluster_endpoint_public_access           = true

  # ✅ Let Terraform manage add-ons
  bootstrap_self_managed_addons = true

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnets
  control_plane_subnet_ids = var.private_subnets

  cluster_additional_security_group_ids = var.security_group_ids

  # ✅ Enable CloudWatch logging
  create_cloudwatch_log_group = true
  cluster_enabled_log_types   = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  ##############################################
  # Core Add-ons (Always include vpc-cni)
  ##############################################
  cluster_addons = {
    vpc-cni = {
      most_recent              = true
      service_account_role_arn = var.cni_role_arn
      resolve_conflicts        = "OVERWRITE"
    }

    coredns = {
      most_recent     = true
      resolve_conflicts = "OVERWRITE"
    }

    kube-proxy = {
      most_recent     = true
      resolve_conflicts = "OVERWRITE"
    }

    eks-pod-identity-agent = {
      most_recent     = true
      resolve_conflicts = "OVERWRITE"
    }

    aws-ebs-csi-driver = {
      most_recent     = true
      resolve_conflicts = "OVERWRITE"
    }
  }

  ##############################################
  # Managed Node Groups - Best Practice
  ##############################################
  eks_managed_node_group_defaults = {
    ami_type        = "AL2023_x86_64_STANDARD"
    instance_types  = ["t3.medium"]

    min_size      = 3
    max_size      = 5
    desired_size  = 3

    iam_role_additional_policies = {
      AmazonEKSWorkerNodePolicy          = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
      AmazonEKS_CNI_Policy               = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
      AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
      AmazonEC2FullAccess                = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
    }
  }

  eks_managed_node_groups = {
    eks-node-group-1 = {
      # Uses all defaults
    }
  }

  ##############################################
  # Access entries (IAM Identity Center or user/role mapping)
  ##############################################
  access_entries = {
    general = {
      kubernetes_groups = ["eks-admins"]
      # FIX: Reference the newly created IAM Role ARN
      principal_arn = aws_iam_role.eks_access_role.arn 
      policy_associations = [
        {
          policy_arn  = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      ]
    }

    github_runner = {
      kubernetes_groups = ["eks-admins"]
      # FIX: Use the ARN reference for robustness
      principal_arn     = aws_iam_role.github_runner_ssm_role.arn
      policy_associations = [
        {
          policy_arn  = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      ]
    }
  }

  tags = local.common_tags
}

##############################################
# RBAC Bindings with depends_on
##############################################

resource "kubernetes_cluster_role_binding" "platform_admins_binding" {
  metadata {
    name = "platform-admins-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "Group"
    name      = "platform-admins"
    api_group = "rbac.authorization.k8s.io"
  }

  depends_on = [module.eks]
}

resource "kubernetes_cluster_role_binding" "eks_admins_binding" {
  metadata {
    name = "eks-admins-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "Group"
    name      = "eks-admins"
    api_group = "rbac.authorization.k8s.io"
  }

  depends_on = [module.eks]
}

##############################################
# Kubernetes Namespaces with depends_on
##############################################

resource "kubernetes_namespace" "fintech" {
  metadata {
    name = "fintech"
    annotations = {
      name = "fintech"
    }
    labels = {
      app = "fintech"
    }
  }

  depends_on = [module.eks]
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    annotations = {
      name = "monitoring"
    }
    labels = {
      app = "monitoring"
    }
  }

  depends_on = [module.eks]
}

resource "kubernetes_namespace" "fintech_dev" {
  metadata {
    name = "fintech-dev"
    annotations = {
      name = "fintech-dev"
    }
    labels = {
      app = "fintech-dev"
    }
  }

  depends_on = [module.eks]
}
