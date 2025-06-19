#############################
# Fetch AWS Account ID and Region
#############################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

################################################################################
# EKS Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.30"

  cluster_endpoint_public_access = true

  create_kms_key              = false
  create_cloudwatch_log_group = false
  cluster_encryption_config   = {}

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnets
  control_plane_subnet_ids = var.private_subnets
  cluster_additional_security_group_ids = var.security_group_ids

  eks_managed_node_group_defaults = {
    instance_types = ["m5.xlarge", "m5.large", "t3.medium"]
    iam_role_additional_policies = {
      AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    }
  }

  eks_managed_node_groups = {
    node-group-01 = {
      min_size     = 1
      max_size     = 10
      desired_size = 1
    },
    node-group-02 = {
      min_size     = 1
      max_size     = 10
      desired_size = 1

      instance_types = ["t3.large"]
      capacity_type  = "SPOT"
    }
  }

  manage_aws_auth_configmap = true

  aws_auth_roles = [
    {
      rolearn  = var.rolearn
      username = "fusi"
      groups   = ["system:masters"]
    },
    {
      rolearn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/github-runner-ssm-role"
      username = "github-runner"
      groups   = ["system:masters"]
    }
  ]

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
