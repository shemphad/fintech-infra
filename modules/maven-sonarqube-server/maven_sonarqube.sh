#!/bin/bash
set -euo pipefail

# ===== VARIABLES =====
MAVEN_VERSION="3.9.10"
SONARQUBE_VERSION="10.5.1.90531"
POSTGRES_USER="ddsonar"
POSTGRES_DB="ddsonarqube"
POSTGRES_PASSWORD="Team@123"
export DEBIAN_FRONTEND=noninteractive

# ===== BETTER TRAP FOR DEBUGGING =====
trap 'echo " ERROR at line $LINENO"; exit 1' ERR

echo "=========================================="
echo "  Starting SonarQube & dependencies setup"
echo "  Target: Ubuntu 20.04 (focal)"
echo "=========================================="

# ===== UPDATE SYSTEM =====
echo "=== Updating system packages ==="
sudo apt-get update -y

# ===== INSTALL BASE PACKAGES =====
echo "=== Installing base dependencies ==="
sudo apt-get install -y wget unzip curl zip gnupg lsb-release openjdk-17-jdk tar ca-certificates procps

# ===== INSTALL kubectl =====
install_kubectl() {
  if ! command -v kubectl &>/dev/null; then
    echo "Installing kubectl..."
    curl -fsSL -o kubectl "https://s3.us-west-2.amazonaws.com/amazon-eks/1.31.7/2025-04-17/bin/linux/amd64/kubectl"
    chmod +x ./kubectl
    sudo mv ./kubectl /usr/local/bin/kubectl
  else
    echo " kubectl already installed."
  fi
  echo "Verifying kubectl..."
  kubectl version --client
}

# ===== INSTALL AWS CLI =====
install_aws_cli() {
  if ! command -v aws &>/dev/null; then
    echo "Installing AWS CLI v2..."
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
    unzip -o awscliv2.zip
    sudo ./aws/install
    rm -rf awscliv2.zip aws
  else
    echo " AWS CLI already installed."
    aws --version
  fi
}

# ===== INSTALL MAVEN =====
install_maven() {
  if ! command -v mvn &>/dev/null || [[ "$(mvn -version 2>/dev/null | grep 'Apache Maven' || true)" != *"$MAVEN_VERSION"* ]]; then
    echo "Installing Maven $MAVEN_VERSION..."

    sudo mkdir -p /opt

    MAVEN_TAR="apache-maven-${MAVEN_VERSION}-bin.tar.gz"
    MAVEN_BASE_URLS=(
      "https://archive.apache.org/dist/maven/maven-3"
      "https://downloads.apache.org/maven/maven-3"
      "https://dlcdn.apache.org/maven/maven-3"
    )

    rm -f "$MAVEN_TAR"
    ok=0
    for base in "${MAVEN_BASE_URLS[@]}"; do
      url="${base}/${MAVEN_VERSION}/binaries/${MAVEN_TAR}"
      echo "  -> Trying $url"
      if curl -fsI "$url" >/dev/null; then
        wget -nv "$url" -O "$MAVEN_TAR"
        ok=1
        break
      fi
    done

    if [[ "$ok" -ne 1 || ! -s "$MAVEN_TAR" ]]; then
      echo "Failed to download Maven $MAVEN_VERSION from known mirrors."
      exit 1
    fi

    echo "Extracting Maven..."
    sudo tar -xzf "$MAVEN_TAR" -C /opt
    sudo ln -sfn "/opt/apache-maven-${MAVEN_VERSION}" /opt/maven
    rm -f "$MAVEN_TAR"

    echo "Configuring Maven environment..."
    sudo tee /etc/profile.d/maven.sh >/dev/null <<'EOF'
export M2_HOME=/opt/maven
export PATH=$M2_HOME/bin:$PATH
EOF
    sudo chmod +x /etc/profile.d/maven.sh

    # Add for future shells; ignore if already present
    grep -q "/etc/profile.d/maven.sh" ~/.bashrc || \
      echo 'if [ -f /etc/profile.d/maven.sh ]; then source /etc/profile.d/maven.sh; fi' >> ~/.bashrc

    # Apply for current non-login shell without failing the script
    source /etc/profile.d/maven.sh || true
  else
    echo "Maven already installed."
  fi

  echo "Verifying Maven..."
  mvn -version
}


# ===== SYSCTL CONFIG FOR ELASTICSEARCH =====
echo "Configuring vm.max_map_count..."
sudo sysctl -w vm.max_map_count=262144
grep -q "vm.max_map_count=262144" /etc/sysctl.conf || echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf >/dev/null

# Apply login limits for SonarQube (Elasticsearch needs these)
echo "Configuring limits for SonarQube..."
sudo tee /etc/security/limits.d/sonarqube.conf >/dev/null <<'EOF'
ddsonar   -   nofile   65536
ddsonar   -   nproc    4096
EOF

# ===== INSTALL POSTGRESQL =====
echo "=== Installing PostgreSQL ==="
if ! command -v psql &>/dev/null; then
  # Prefer PGDG over HTTPS; fall back to Ubuntu stock if update fails
  sudo rm -f /etc/apt/sources.list.d/pgdg.list /usr/share/keyrings/postgresql.gpg || true
  sudo install -m 0755 -d /usr/share/keyrings
  curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
  | sudo gpg --dearmor -o /usr/share/keyrings/postgresql.gpg

  echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
  | sudo tee /etc/apt/sources.list.d/pgdg.list >/dev/null

  if ! sudo apt-get update -y; then
    echo "PGDG unavailable; falling back to Ubuntu stock PostgreSQL..."
    sudo rm -f /etc/apt/sources.list.d/pgdg.list
    sudo apt-get update -y
  fi

  sudo apt-get install -y postgresql postgresql-contrib
else
  echo "PostgreSQL already installed."
fi

# Ensure service is enabled/running
sudo systemctl enable --now postgresql

# Ensure localhost password auth is allowed (avoid 'peer' auth surprises)
PG_HBA="$(sudo -u postgres psql -tAc "SHOW hba_file;")"
if ! sudo grep -Eq '^[[:space:]]*host[[:space:]]+all[[:space:]]+all[[:space:]]+127\.0\.0\.1/32[[:space:]]+(md5|scram-sha-256)' "$PG_HBA"; then
  echo "Adding localhost md5 to $PG_HBA"
  sudo sed -i '1ihost    all             all             127.0.0.1/32            md5' "$PG_HBA"
  sudo systemctl restart postgresql
fi

echo "Configuring PostgreSQL user and DB..."
sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${POSTGRES_USER}'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE USER ${POSTGRES_USER} WITH ENCRYPTED PASSWORD '${POSTGRES_PASSWORD}';"

sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${POSTGRES_DB}'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE DATABASE ${POSTGRES_DB} OWNER ${POSTGRES_USER};"

echo "GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_USER};" | sudo -u postgres psql

# ===== INSTALL SONARQUBE =====
echo "=== Installing SonarQube ==="
sudo mkdir -p /opt/sonarqube
if [ ! -x "/opt/sonarqube/bin/linux-x86-64/sonar.sh" ]; then
  echo "Downloading SonarQube..."
  wget -nv "https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-${SONARQUBE_VERSION}.zip"
  sudo unzip -o "sonarqube-${SONARQUBE_VERSION}.zip" -d /opt
  sudo rm -rf /opt/sonarqube/*
  sudo mv "/opt/sonarqube-${SONARQUBE_VERSION}/"* /opt/sonarqube/
  sudo rm -rf "/opt/sonarqube-${SONARQUBE_VERSION}" "sonarqube-${SONARQUBE_VERSION}.zip"
else
  echo "SonarQube already present in /opt/sonarqube"
fi

echo "Creating SonarQube user/group..."
getent group ddsonar >/dev/null || sudo groupadd ddsonar
id -u ddsonar &>/dev/null || sudo useradd --system --gid ddsonar --home /opt/sonarqube --shell /bin/false ddsonar
sudo chown -R ddsonar:ddsonar /opt/sonarqube
sudo chmod +x /opt/sonarqube/bin/linux-x86-64/sonar.sh

echo "Configuring SonarQube DB connection..."
sudo tee /opt/sonarqube/conf/sonar.properties > /dev/null <<EOF
sonar.jdbc.username=${POSTGRES_USER}
sonar.jdbc.password=${POSTGRES_PASSWORD}
sonar.jdbc.url=jdbc:postgresql://localhost:5432/${POSTGRES_DB}
EOF

# ===== CREATE SYSTEMD SERVICE =====
echo "=== Creating systemd unit for SonarQube ==="
sudo tee /etc/systemd/system/sonar.service > /dev/null <<'EOF'
[Unit]
Description=SonarQube service
After=network.target postgresql.service

[Service]
Type=forking
ExecStart=/opt/sonarqube/bin/linux-x86-64/sonar.sh start
ExecStop=/opt/sonarqube/bin/linux-x86-64/sonar.sh stop
User=ddsonar
Group=ddsonar
Restart=always
LimitNOFILE=65536
LimitNPROC=4096
# Ensure PAM applies limits to the service
PAMName=login

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable sonar.service
sudo systemctl restart sonar.service

echo "SonarQube is starting. Access it at:  http://<your-server-ip>:9000"

# ===== CALL OPTIONAL TOOLS =====
install_kubectl
install_aws_cli
install_maven

echo "ALL DONE! SonarQube setup completed successfully."
echo "If the service exits on first boot, re-login (to apply limits) and run: sudo systemctl restart sonar"
echo "Open a new SSH session or run: source ~/.bashrc"
echo "Test Maven: mvn -version"
