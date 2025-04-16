variable "aws_account_id" {
  description = "AWS Account ID"
  default     = "992382750832"
}

variable "repositories" {
  description = "List of ECR repositories to create"
  type        = list(string)
  default     = ["payload-app"]
}

variable "tags" {
  description = "Common tags for the cluster resources"
  type        = map(string)
  default     = {
    env       = "dev",
    terraform = "true"
  }
}

