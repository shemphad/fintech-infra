output "terraform_node_public_ip" {
  value = aws_instance.eks_client_node.public_ip
}

output "eks_client_sg" {
  value = module.eks-client-node.eks_client_sg.id
}

output "eks_client_instance_profile" {
  description = "IAM instance profile assigned to EKS client node"
  value       = aws_iam_instance_profile.eks_client_ssm_profile.name
}

# (Optional) Output the private key for SSH access.
# Make sure to store this output securely.

# Optionally output the private key (sensitive)
output "eks_client_private_key" {
  value     = tls_private_key.eks_client_key.private_key_pem
  sensitive = true
}





