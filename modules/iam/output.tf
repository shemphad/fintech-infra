output "cni_role_arn" {
  description = "IAM Role ARN for EKS CNI"
  value       = aws_iam_role.cni_role.arn
}
