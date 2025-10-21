variable "ami_id" {
  description = "The AMI ID for the Terraform node. Leave empty to automatically fetch the latest Ubuntu AMI."
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "The instance type for the Terraform node"
  type        = string
  default     = "t3.medium"
}


variable "aws_region" {
  description = "The AWS region to deploy resources"
  type        = string
  default     = "us-east-2"
}

variable "vpc_id" {
  description = "The VPC ID where the EKS client instance will be deployed"
  type        = string
}

variable "vpc_security_group_ids" {
  description = "List of Security Group IDs assigned to the EKS client node"
  type        = list(string)
}

variable "subnet_id" {
  description = "The subnet ID where the EKS client node will be deployed"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}


variable "user_data" {
  description = "User data script for EKS client node"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags for the cluster resources"
  type        = map(string)
  default = {
    env       = "dev",
    terraform = "true"
  }
}

variable "key_name" {
  description = "Name of the SSH key pair to use for EC2 instance access."
  type        = string
}




