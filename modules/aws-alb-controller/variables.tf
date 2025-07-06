################################################################################
# General Variables
################################################################################

variable "main_region" {
  description = "AWS Region for deployment"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the EKS cluster"
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC Provider ARN for IRSA"
  type        = string
}
