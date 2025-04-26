#!/bin/bash
set -euo pipefail

### 1) kubectl client
echo "Installing kubectl..."
curl -fsSL -o kubectl \
  https://s3.us-west-2.amazonaws.com/amazon-eks/1.27.12/2024-04-19/bin/linux/amd64/kubectl
chmod +x kubectl
mkdir -p "$HOME/bin"
mv kubectl "$HOME/bin/"
export PATH="$HOME/bin:$PATH"

### 2) Dependencies & AWS CLI
echo "Updating apt and installing dependencies..."
sudo apt-get update -y
sudo apt-get install -y wget unzip

echo "Installing AWS CLI..."
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip -o awscliv2.zip
sudo ./aws/install
rm -rf awscliv2.zip aws

### 3) Java 17 (Corretto) & Maven
echo "Installing OpenJDK 17..."
sudo apt-get install -y openjdk-17-jdk

echo "Installing Maven 3.9.9..."
LATEST_MAVEN_VERSION=3.9.9
wget -q "https://dlcdn.apache.org/maven/maven-3/${LATEST_MAVEN_VERSION}/binaries/apache-maven-${LATEST_MAVEN_VERSION}-bin.zip"
sudo unzip -o apache-maven-${LATEST_MAVEN_VERSION}-bin.zip -d /opt
sudo ln -sfn /opt/apache-maven-${LATEST_MAVEN_VERSION} /opt/maven
rm apache-maven-${LATEST_MAVEN_VERSION}-bin.zip

echo "Configuring Maven environment variables..."
sudo tee /etc/profile.d/maven.sh > /dev/null <<'EOF'
export M2_HOME=/opt/maven
export PATH=$M2_HOME/bin:$PATH
EOF
source /etc/profile.d/maven.sh

echo "Verifying Maven:"
mvn -version

### 4) SonarQube 10.5.1 setup
SONARQUBE_VERSION=10.5.1.90531
echo "Downloading SonarQube ${SONARQUBE_VERSION}..."
wget -q "https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-${SONARQUBE_VERSION}.zip"
sudo unzip -o sonarqube-${SONARQUBE_VERSION}.zip -d /opt
sudo mv /opt/sonarqube-${SONARQUBE_VERSION} /opt/sonarqube
rm sonarqube-${SONARQUBE_VERSION}.zip

echo "Creating ddsonar user and group..."
sudo groupadd --force ddsonar
sudo useradd --system --gid ddsonar --home /opt/sonarqube --shell /bin/false ddsonar
sudo chown -R ddsonar:ddsonar /opt/sonarqube
sudo chmod +x /opt/sonarqube/bin/linux-x86-64/sonar.sh

### 5) PostgreSQL installation & DB setup
echo "Installing PostgreSQL..."
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" \
  > /etc/apt/sources.list.d/pgdg.list'
wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt-get update -y
sudo apt-get install -y postgresql postgresql-contrib

echo "Configuring PostgreSQL user & database..."
sudo -u postgres psql <<'EOF'
CREATE USER ddsonar WITH ENCRYPTED PASSWORD 'Team@123';
CREATE DATABASE ddsonarqube OWNER ddsonar;
GRANT ALL PRIVILEGES ON DATABASE ddsonarqube TO ddsonar;
EOF

### 6) Configure SonarQube to use PostgreSQL
echo "Writing sonar.properties..."
sudo tee /opt/sonarqube/conf/sonar.properties > /dev/null <<'EOF'
sonar.jdbc.username=ddsonar
sonar.jdbc.password=Team@123
sonar.jdbc.url=jdbc:postgresql://localhost:5432/ddsonarqube
EOF

### 7) Systemd service for SonarQube
echo "Creating systemd unit for SonarQube..."
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

### 8) Nginx & Let's Encrypt SSL
echo "Installing Nginx & Certbot..."
sudo apt-get install -y nginx certbot python3-certbot-nginx
sudo ufw allow 'Nginx Full'

echo "Configuring Nginx reverse proxy for SonarQube..."
sudo tee /etc/nginx/sites-available/sonarqube.conf > /dev/null <<'EOF'
server {
    listen 80;
    server_name sonarqube.dominionsystem.org;

    location / {
        proxy_pass http://localhost:9000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location ~ /.well-known/acme-challenge {
        allow all;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/sonarqube.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

echo "Obtaining SSL certificate for sonarqube.dominionsystem.org..."
sudo certbot --nginx --non-interactive --agree-tos \
  --email fusisoft@gmail.com \
  -d sonarqube.dominionsystem.org

echo "Scheduling daily certificate renewal..."
sudo bash -c 'echo "0 0 * * * root certbot renew --quiet" >> /etc/crontab'

sudo systemctl reload nginx

echo "✅ Setup complete! Access SonarQube at: https://sonarqube.dominionsystem.org"
