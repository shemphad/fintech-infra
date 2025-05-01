#!/bin/bash
set -euo pipefail

### 1) System update & upgrade
echo "Updating and upgrading system packages..."
sudo apt-get update -y
sudo apt-get upgrade -y

### 2) Docker cleanup & install
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
echo "Docker installation complete."

### 3) Install Java (OpenJDK 17)
echo "Installing OpenJDK 17..."
sudo apt-get install -y openjdk-17-jdk

### 4) Jenkins installation
echo "Adding Jenkins GPG key..."
curl -fsSL https://pkg.jenkins.io/debian/jenkins.io-2023.key \
  | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null

echo "Adding Jenkins APT repository..."
echo \
  "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian binary/" \
  | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

echo "Updating package index for Jenkins..."
sudo apt-get update -y

echo "Installing Jenkins..."
sudo apt-get install -y jenkins

echo "Enabling and starting Jenkins service..."
sudo systemctl enable jenkins
sudo systemctl start jenkins

### 5) Nginx & SSL reverse-proxy for Jenkins
echo "Installing Nginx..."
sudo apt-get install -y nginx

echo "Allowing Nginx through UFW..."
sudo ufw allow 'Nginx Full'

echo "Installing Certbot and the Nginx plugin..."
sudo apt-get install -y certbot python3-certbot-nginx

echo "Creating Nginx site for Jenkins..."
sudo tee /etc/nginx/sites-available/jenkins.conf > /dev/null <<'EOL'
server {
    listen 80;
    server_name jenkins.dominionsystem.org;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOL

echo "Enabling Jenkins Nginx config..."
sudo ln -sf /etc/nginx/sites-available/jenkins.conf /etc/nginx/sites-enabled/

echo "Testing Nginx configuration..."
sudo nginx -t

echo "Reloading Nginx..."
sudo systemctl reload nginx

echo "Obtaining Let’s Encrypt SSL certificate..."
sudo certbot --nginx \
  --non-interactive \
  --agree-tos \
  --email fusisoft@gmail.com \
  -d jenkins.dominionsystem.org

echo "Setting up daily cron for Certbot renewal..."
# This line ensures certbot renew runs quietly each day at midnight
sudo bash -c 'echo "0 0 * * * root certbot renew --quiet" >> /etc/crontab'

echo "Reloading Nginx to apply SSL..."
sudo systemctl restart nginx

echo "✅ Jenkins is now available at: https://jenkins.dominionsystem.org"
