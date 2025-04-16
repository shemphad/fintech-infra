# Generate an RSA private key
resource "tls_private_key" "eks_client_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create a random suffix to ensure uniqueness (optional)
resource "random_id" "eks_client_key_suffix" {
  byte_length = 4
}

# Register the public key with AWS as an EC2 key pair
resource "aws_key_pair" "eks_client_key" {
  key_name   = "eks-client-key-${random_id.eks_client_key_suffix.hex}"
  public_key = tls_private_key.eks_client_key.public_key_openssh
}


