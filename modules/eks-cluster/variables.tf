################################################################################
# General Variables from root module
################################################################################
variable "cluster_name" {
  type    = string
}

################################################################################
# Variables from other Modules
################################################################################

variable "vpc_id" {
  description = "VPC ID which EKS cluster is deployed in"
  type        = string
}

variable "private_subnets" {
  description = "VPC Private Subnets which EKS cluster is deployed in"
  type        = list(any)
}

variable "security_group_ids" {
  description = "Addtional Security Groups for EKS control plane"
  type        = list(any)
} 
################################################################################
# Variables defined using Environment Variables
################################################################################

variable "rolearn" {
  description = "Add admin role to the aws-auth configmap"
}

