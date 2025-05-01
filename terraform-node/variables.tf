variable "ami_id" {
  description = "The AMI ID for the Terraform node"
  type        = string
  default     = "ami-03c983f9003cb9cd1"
}

variable "instance_type" {
  description = "The instance type for the Terraform node"
  type        = string
  default     = "t2.medium"
}

variable "key_name" {
  description = "The key name for the Jenkins server"
  type        = string
  default     = "DevOps_Train2024"
}

variable "main-region" {
  description = "The AWS region to deploy resources"
  type        = string
  default     = "us-west-2"
}
