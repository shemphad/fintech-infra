#!/bin/bash
# Install Terraform
echo "Installing java packages........"
sudo apt-get update -y
sudo apt-get install openjdk-21-jdk -y

#Installing aws cli
sudo apt-get install unzip -y
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

#Installing teraform packages
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common

#Install the HashiCorp GPG key.
wget -O- https://apt.releases.hashicorp.com/gpg | \
gpg --dearmor | \
sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null

#Add the official HashiCorp repository to your system. The lsb_release -cs command finds the distribution release codename for your current system, such as buster, groovy, or sid.
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
sudo tee /etc/apt/sources.list.d/hashicorp.list

#Installing terraform binary
sudo apt update -y
sudo apt-get install terraform -y

#Installing kubectl client
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.27.12/2024-04-19/bin/linux/amd64/kubectl
chmod +x ./kubectl
mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$HOME/bin:$PATH 


### Docker cleanup & install
echo "Removing older Docker versions if installed..."
sudo apt-get remove -y docker docker-engine docker.io containerd runc || true

echo "Installing Docker dependencies..."
sudo apt-get install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg \
  lsb-release

echo "Adding Docker’s official GPG key..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "Configuring Docker stable repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "Updating package index for Docker..."
sudo apt-get update -y

echo "Installing Docker Engine..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

echo "Enabling and starting Docker service..."
sudo systemctl enable docker
sudo systemctl start docker

echo "Adding current user ($USER) to the Docker group..."
sudo usermod -aG docker "$USER"
newgrp docker
echo "Docker installation complete."

# Install Maven prerequisites
sudo apt update
sudo apt install -y wget tar git openjdk-17-jdk

# Define Maven version
MAVEN_VERSION=3.9.6
MAVEN_DIR=/opt/maven
MAVEN_ARCHIVE=apache-maven-$MAVEN_VERSION-bin.tar.gz

# Download and extract Maven
wget https://downloads.apache.org/maven/maven-3/$MAVEN_VERSION/binaries/$MAVEN_ARCHIVE -P /tmp
sudo mkdir -p $MAVEN_DIR
sudo tar -xzf /tmp/$MAVEN_ARCHIVE -C $MAVEN_DIR
sudo ln -s $MAVEN_DIR/apache-maven-$MAVEN_VERSION /opt/maven/latest

# Set environment variables
echo "export M2_HOME=/opt/maven/latest" | sudo tee /etc/profile.d/maven.sh
echo "export PATH=\$M2_HOME/bin:\$PATH" | sudo tee -a /etc/profile.d/maven.sh

# Apply env vars immediately
source /etc/profile.d/maven.sh





