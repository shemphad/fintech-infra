variable "aws_account_id" {
  description = "AWS Account ID"
  default     = "992382750832"
}

variable "tags" {
  description = "Common tags for the cluster resources"
  type        = map(string)
  default     = {
    terraform = "true"
  }
}

variable "aws_region" {
  description = "AWS Region"
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment where resources are deployed"
  
}