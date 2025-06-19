#############################
# Fetch AWS Account ID and Region
#############################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

################################################################################
# EKS Cluster
################################################################################

# module "eks" {
#   source  = "terraform-aws-modules/eks/aws"
#   version = "~> 19.0"

#   cluster_name    = var.cluster_name
#   cluster_version = "1.30"

#   cluster_endpoint_public_access = true

#   create_kms_key              = false
#   create_cloudwatch_log_group = false
#   cluster_encryption_config   = {}

#   cluster_addons = {
#     coredns = {
#       most_recent = true
#     }
#     kube-proxy = {
#       most_recent = true
#     }
#     vpc-cni = {
#       most_recent = true
#     }
#     aws-ebs-csi-driver = {
#       most_recent = true
#     }
#   }

#   vpc_id                   = var.vpc_id
#   subnet_ids               = var.private_subnets
#   control_plane_subnet_ids = var.private_subnets
#   cluster_additional_security_group_ids = var.security_group_ids

#   eks_managed_node_group_defaults = {
#     instance_types = ["m5.xlarge", "m5.large", "t3.medium"]
#     iam_role_additional_policies = {
#       AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
#     }
#   }

#   eks_managed_node_groups = {
#     node-group-01 = {
#       min_size     = 1
#       max_size     = 10
#       desired_size = 1
#     },
#     node-group-02 = {
#       min_size     = 1
#       max_size     = 10
#       desired_size = 1

#       instance_types = ["t3.large"]
#       capacity_type  = "SPOT"
#     }
#   }
#########################################
# EKS v1.31
#########################################
module   "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.31"

  bootstrap_self_managed_addons = false
  cluster_addons = {
    coredns                = {
      most_recent = true
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
    kube-proxy             = {
      most_recent = true
    }
    vpc-cni                = {
      most_recent = true
    }
  }

  # Optional
  cluster_endpoint_public_access = true

  # Optional: Adds the current caller identity as an administrator via cluster access entry
  enable_cluster_creator_admin_permissions = true

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnets
  control_plane_subnet_ids = var.private_subnets
  cluster_additional_security_group_ids = var.security_group_ids

  # EKS Managed Node Group(s)
  eks_managed_node_group_defaults = {
    instance_types = ["m6i.large", "m5.large", "m5n.large", "m5zn.large"]
  }

  eks_managed_node_groups = {
    example = {
      # Starting on 1.30, AL2023 is the default AMI type for EKS managed node groups
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["m5.xlarge"]

      min_size     = 2
      max_size     = 10
      desired_size = 2
    }
  }

  # tags = {
  #   Environment = "dev"
  #   Terraform   = "true"
  # }


#########################################
# configmap
#########################################
  # manage_aws_auth_configmap = true

  # aws_auth_roles = [
  #   {
  #     rolearn  = var.rolearn
  #     username = "fusi"
  #     groups   = ["system:masters"]
  #   },
  #   {
  #     rolearn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/github-runner-ssm-role"
  #     username = "github-runner"
  #     groups   = ["system:masters"]
  #   }
  # ]
  tags = {
    env       = "dev"
    terraform = "true"
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
      app = "webapp"
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

resource "kubernetes_namespace" "fintech-dev" {
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
