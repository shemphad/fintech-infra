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
    module.lb_role,                        # IAM role for service account
    kubernetes_service_account.service_account, # Service account resource
    module.eks,                             # Ensure EKS is up
    aws_eks_addon.coredns                   # Ensure addons are Active
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
      value = "aws-load-balancer-controller"
    },
    {
      name  = "clusterName"
      value = var.cluster_name
    }
  ]
}
