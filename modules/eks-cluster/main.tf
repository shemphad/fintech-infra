data "aws_eks_cluster_auth" "main" {
  name = var.cluster_name
}

data "aws_caller_identity" "current" {}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.main.token
  alias                  = "eks"
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.31"

  enable_cluster_creator_admin_permissions = true
  cluster_endpoint_public_access           = true

  # ✅ Updated: Enable add-on bootstrap via Terraform
  bootstrap_self_managed_addons = true

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnets
  control_plane_subnet_ids = var.private_subnets
  cluster_additional_security_group_ids = var.security_group_ids

  create_cloudwatch_log_group = true
  cluster_enabled_log_types   = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent              = true
      service_account_role_arn = var.cni_role_arn  # ✅ ensure this is passed correctly
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
  }

  eks_managed_node_group_defaults = {
    ami_type       = "AL2023_x86_64_STANDARD"
    instance_types = ["t2.medium"]
    min_size       = 1
    max_size       = 10
    desired_size   = 1
    iam_role_additional_policies = {
      AmazonEKS_CNI_Policy = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    }
  }

  eks_managed_node_groups = {
    eks-node-group-2 = {
      # Uses the defaults
    }
  }

  access_entries = {
    fusi = {
      kubernetes_groups = ["eks-admins"]
      principal_arn     = "arn:aws:iam::999568710647:user/fusi"

      policy_associations = [
        {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      ]
    }

    github_runner = {
      kubernetes_groups = ["eks-admins"]
      principal_arn     = "arn:aws:iam::999568710647:role/github-runner-ssm-role"

      policy_associations = [
        {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      ]
    }
  }

  tags = local.common_tags
}

# ✅ Bind eks-admins group to cluster-admin role
resource "kubernetes_cluster_role_binding" "eks_admins_binding" {
  provider = kubernetes.eks

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
}

################################################################################
# Kubernetes Namespaces
################################################################################

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
}
