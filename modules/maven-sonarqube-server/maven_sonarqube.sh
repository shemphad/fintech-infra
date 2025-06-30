#!/bin/bash
set -euxo pipefail

# Ensure system is up-to-date
sudo apt-get update -y

### 1) Install kubectl
echo "Installing kubectl..."
curl -fsSL -o kubectl https://s3.us-west-2.amazonaws.com/amazon-eks/1.31.7/2025-04-17/bin/linux/amd64/kubectl
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl
echo "Verifying kubectl..."
kubectl version --client

### 2) Install dependencies & AWS CLI
echo "Installing base dependencies..."
sudo apt-get install -y wget unzip curl zip gnupg lsb-release

echo "Installing AWS CLI v2..."
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip -o awscliv2.zip
sudo ./aws/install --update
rm -rf awscliv2.zip aws

### 3) Java 17 & Maven
echo "Installing OpenJDK 17..."
sudo apt-get install -y openjdk-17-jdk

echo "Installing Maven..."
MAVEN_VERSION=3.9.9
wget -q "https://dlcdn.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.zip"
sudo unzip -o apache-maven-${MAVEN_VERSION}-bin.zip -d /opt
sudo ln -sfn /opt/apache-maven-${MAVEN_VERSION} /opt/maven
rm apache-maven-${MAVEN_VERSION}-bin.zip

sudo tee /etc/profile.d/maven.sh > /dev/null <<EOF
export M2_HOME=/opt/maven
export PATH=\$M2_HOME/bin:\$PATH
EOF

sudo chmod +x /etc/profile.d/maven.sh
# Export for current shell to verify version
export M2_HOME=/opt/maven
export PATH=$M2_HOME/bin:$PATH

echo "Verifying Maven..."
mvn -version

### 4) Sysctl for Elasticsearch
echo "Configuring vm.max_map_count..."
sudo sysctl -w vm.max_map_count=262144
echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf

### 5) SonarQube
SONARQUBE_VERSION=10.5.1.90531
echo "Downloading SonarQube..."
wget -q "https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-${SONARQUBE_VERSION}.zip"
sudo unzip -o sonarqube-${SONARQUBE_VERSION}.zip -d /opt
sudo mv /opt/sonarqube-${SONARQUBE_VERSION} /opt/sonarqube
rm sonarqube-${SONARQUBE_VERSION}.zip

echo "Creating SonarQube user/group..."
sudo groupadd --force ddsonar
sudo useradd --system --gid ddsonar --home /opt/sonarqube --shell /bin/false ddsonar
sudo chown -R ddsonar:ddsonar /opt/sonarqube
sudo chmod +x /opt/sonarqube/bin/linux-x86-64/sonar.sh

### 6) PostgreSQL
echo "Installing PostgreSQL..."
wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /usr/share/keyrings/postgresql.gpg
echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list
sudo apt-get update -y
sudo apt-get install -y postgresql postgresql-contrib

echo "Configuring PostgreSQL DB and user..."
sudo -u postgres psql <<'EOF'
CREATE USER ddsonar WITH ENCRYPTED PASSWORD 'Team@123';
CREATE DATABASE ddsonarqube OWNER ddsonar;
GRANT ALL PRIVILEGES ON DATABASE ddsonarqube TO ddsonar;
EOF

echo "Configuring SonarQube database settings..."
sudo tee /opt/sonarqube/conf/sonar.properties > /dev/null <<'EOF'
sonar.jdbc.username=ddsonar
sonar.jdbc.password=Team@123
sonar.jdbc.url=jdbc:postgresql://localhost:5432/ddsonarqube
EOF

### 7) Systemd unit for SonarQube
echo "Creating systemd service for SonarQube..."
sudo tee /etc/systemd/system/sonar.service > /dev/null <<'EOF'
[Unit]
Description=SonarQube service
After=network.target

[Service]
Type=forking
ExecStart=/opt/sonarqube/bin/linux-x86-64/sonar.sh start
ExecStop=/opt/sonarqube/bin/linux-x86-64/sonar.sh stop
User=ddsonar
Group=ddsonar
Restart=always
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable sonar.service
sudo systemctl start sonar.service

echo "✅ Setup complete! SonarQube is running. Access it on port 9000."

### 8) Nginx & Certbot
apt-get install -y nginx certbot python3-certbot-nginx
ufw allow 'Nginx Full'

tee /etc/nginx/sites-available/sonarqube.conf > /dev/null <<'EOF'
server {
    listen 80;
    server_name sonarqube.dominionsystem.org;

    location / {
        proxy_pass http://localhost:9000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location ~ /.well-known/acme-challenge {
        allow all;
    }
}
EOF

ln -sf /etc/nginx/sites-available/sonarqube.conf /etc/nginx/sites-enabled/
nginx -t
systemctl reload nginx

echo "Obtaining SSL..."
certbot --nginx --non-interactive --agree-tos \
  --email fusisoft@gmail.com \
  -d sonarqube.dominionsystem.org

echo "0 0 * * * root certbot renew --quiet" >> /etc/crontab

systemctl reload nginx

echo "✅ Setup complete! https://sonarqube.dominionsystem.org"
