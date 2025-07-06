################################################################################
# Service Account for IRSA
################################################################################

resource "kubernetes_service_account" "service_account" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.lb_controller.arn
    }
  }
}

################################################################################
# IAM Role for Service Account (IRSA)
################################################################################

resource "aws_iam_role" "lb_controller" {
  name = "${var.cluster_name}-aws-load-balancer-controller"

  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_arn, "arn:aws:iam::", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

# Attach AWS managed policy for ALB Controller
resource "aws_iam_role_policy_attachment" "lb_controller_attach" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = "arn:aws:iam::aws:policy/ELBIngressControllerPolicy" # Use your custom policy if needed
}

################################################################################
# Helm Release: AWS Load Balancer Controller
################################################################################

resource "helm_release" "lb" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  create_namespace = true

  depends_on = [
    kubernetes_service_account.service_account,
    aws_iam_role.lb_controller
  ]

  set = [
    {
      name  = "region"
      value = var.main_region
    },
    {
      name  = "vpcId"
      value = var.vpc_id
    },
    {
      name  = "image.repository"
      value = "602401143452.dkr.ecr.${var.main_region}.amazonaws.com/amazon/aws-load-balancer-controller"
    },
    {
      name  = "serviceAccount.create"
      value = "false"
    },
    {
      name  = "serviceAccount.name"
      value = kubernetes_service_account.service_account.metadata[0].name
    },
    {
      name  = "clusterName"
      value = var.cluster_name
    }
  ]
}
