################################################################################
# General Variables from Root Module
################################################################################

variable "main_region" {
  description = "AWS Region where resources will be deployed"
  type        = string
  default     = "us-east-2"
}

variable "env_name" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

################################################################################
# Variables from Other Modules
################################################################################

variable "vpc_id" {
  description = "VPC ID where Load Balancers will be deployed"
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC Provider ARN used for IRSA"
  type        = string
}
