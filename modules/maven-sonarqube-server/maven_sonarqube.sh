#!/bin/bash
set -euo pipefail

# ===== VERSIONS / VARS =====
MAVEN_VERSION="3.9.10"
SONARQUBE_VERSION="10.5.1.90531"
POSTGRES_USER="ddsonar"
POSTGRES_DB="ddsonarqube"
POSTGRES_PASSWORD="Team@123"
SONAR_USER="ddsonar"
SONAR_GROUP="ddsonar"
SONAR_DIR="/opt/sonarqube"
JAVA_PKG="openjdk-17-jdk"

trap 'echo " ERROR at line $LINENO"; exit 1' ERR

echo "=========================================="
echo "  Starting SonarQube & dependencies setup"
echo "=========================================="

echo "=== Updating system packages ==="
sudo apt-get update -y

echo "=== Installing base dependencies ==="
sudo apt-get install -y wget unzip curl zip gnupg lsb-release "$JAVA_PKG" tar

# ----- kubectl -----
install_kubectl() {
  if ! command -v kubectl &>/dev/null; then
    echo "Installing kubectl..."
    curl -fsSL -o kubectl "https://s3.us-west-2.amazonaws.com/amazon-eks/1.31.7/2025-04-17/bin/linux/amd64/kubectl"
    chmod +x ./kubectl
    sudo mv ./kubectl /usr/local/bin/kubectl
  else
    echo "kubectl already installed."
  fi
  echo "Verifying kubectl..."
  kubectl version --client
}

# ----- AWS CLI v2 -----
install_aws_cli() {
  if ! command -v aws &>/dev/null; then
    echo "Installing AWS CLI v2..."
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
    unzip -o awscliv2.zip
    sudo ./aws/install
    rm -rf awscliv2.zip aws
  else
    echo "AWS CLI already installed."
    aws --version
  fi
}

# ----- Maven -----
install_maven() {
  if ! command -v mvn &>/dev/null || [[ "$(mvn -version | grep 'Apache Maven')" != *"$MAVEN_VERSION"* ]]; then
    echo "Installing Maven $MAVEN_VERSION..."
    MAVEN_TAR="apache-maven-${MAVEN_VERSION}-bin.tar.gz"
    MAVEN_URL="https://dlcdn.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/${MAVEN_TAR}"
    wget -nv "$MAVEN_URL" -O "$MAVEN_TAR"
    sudo tar -xzf "$MAVEN_TAR" -C /opt
    sudo ln -sfn "/opt/apache-maven-${MAVEN_VERSION}" /opt/maven
    rm "$MAVEN_TAR"
    sudo tee /etc/profile.d/maven.sh >/dev/null <<'EOF'
export M2_HOME=/opt/maven
export PATH=$M2_HOME/bin:$PATH
EOF
    sudo chmod +x /etc/profile.d/maven.sh
    if ! grep -q "/etc/profile.d/maven.sh" ~/.bashrc; then
      echo 'if [ -f /etc/profile.d/maven.sh ]; then source /etc/profile.d/maven.sh; fi' >> ~/.bashrc
    fi
    # shellcheck disable=SC1091
    source /etc/profile.d/maven.sh
  else
    echo "Maven already installed."
  fi
  mvn -version
}

# ===== Kernel & user limits for Elasticsearch =====
echo "=== Configuring kernel & user limits for ES ==="
sudo tee /etc/sysctl.d/99-sonarqube.conf >/dev/null <<'EOF'
vm.max_map_count=262144
fs.file-max=65536
EOF
sudo sysctl --system

sudo tee /etc/security/limits.d/99-sonarqube.conf >/dev/null <<EOF
${SONAR_USER} soft nofile 65536
${SONAR_USER} hard nofile 65536
${SONAR_USER} soft nproc  4096
${SONAR_USER} hard nproc  4096
EOF

# ===== PostgreSQL =====
echo "=== Installing PostgreSQL ==="
if ! command -v psql &>/dev/null; then
  wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /usr/share/keyrings/postgresql.gpg
  echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
    | sudo tee /etc/apt/sources.list.d/pgdg.list
  sudo apt-get update -y
  sudo apt-get install -y postgresql postgresql-contrib
else
  echo "PostgreSQL already installed."
fi

echo "=== Configuring PostgreSQL user & DB ==="
sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${POSTGRES_USER}'" | grep -q 1 \
  || sudo -u postgres psql -c "CREATE USER ${POSTGRES_USER} WITH ENCRYPTED PASSWORD '${POSTGRES_PASSWORD}';"

sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${POSTGRES_DB}'" | grep -q 1 \
  || sudo -u postgres psql -c "CREATE DATABASE ${POSTGRES_DB} OWNER ${POSTGRES_USER};"

echo "GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_USER};" | sudo -u postgres psql

# ===== SonarQube install (if missing) =====
echo "=== Installing SonarQube (if needed) ==="
if [ ! -d "${SONAR_DIR}" ]; then
  wget -nv "https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-${SONARQUBE_VERSION}.zip"
  sudo unzip -o "sonarqube-${SONARQUBE_VERSION}.zip" -d /opt
  sudo mv "/opt/sonarqube-${SONARQUBE_VERSION}" "${SONAR_DIR}"
  rm "sonarqube-${SONARQUBE_VERSION}.zip"
else
  echo "SonarQube already present at ${SONAR_DIR}"
fi

echo "=== Creating ${SONAR_USER}:${SONAR_GROUP} and fixing ownership ==="
getent group "${SONAR_GROUP}" >/dev/null || sudo groupadd "${SONAR_GROUP}"
id -u "${SONAR_USER}" &>/dev/null || sudo useradd --system --gid "${SONAR_GROUP}" --home "${SONAR_DIR}" --shell /usr/sbin/nologin "${SONAR_USER}"

# Ensure required writable dirs exist and are owned by the service user
sudo install -d -o "${SONAR_USER}" -g "${SONAR_GROUP}" "${SONAR_DIR}/data" "${SONAR_DIR}/logs" "${SONAR_DIR}/temp"
sudo chown -R "${SONAR_USER}:${SONAR_GROUP}" "${SONAR_DIR}"
sudo chmod +x "${SONAR_DIR}/bin/linux-x86-64/sonar.sh"

# ===== SonarQube DB config =====
echo "=== Configuring SonarQube DB connection ==="
sudo tee "${SONAR_DIR}/conf/sonar.properties" >/dev/null <<EOF
sonar.jdbc.username=${POSTGRES_USER}
sonar.jdbc.password=${POSTGRES_PASSWORD}
sonar.jdbc.url=jdbc:postgresql://localhost:5432/${POSTGRES_DB}
# Optional: bind UI to all interfaces (comment out to keep 127.0.0.1)
#sonar.web.host=0.0.0.0
#sonar.web.port=9000
EOF
sudo chown "${SONAR_USER}:${SONAR_GROUP}" "${SONAR_DIR}/conf/sonar.properties"

# ===== systemd unit =====
echo "=== Creating systemd unit for SonarQube ==="
sudo tee /etc/systemd/system/sonar.service >/dev/null <<EOF
[Unit]
Description=SonarQube service
After=network.target

[Service]
Type=forking
User=${SONAR_USER}
Group=${SONAR_GROUP}
WorkingDirectory=${SONAR_DIR}
ExecStart=${SONAR_DIR}/bin/linux-x86-64/sonar.sh start
ExecStop=${SONAR_DIR}/bin/linux-x86-64/sonar.sh stop
LimitNOFILE=65536
LimitNPROC=4096
Restart=on-failure
RestartSec=10
SyslogIdentifier=sonarqube

[Install]
WantedBy=multi-user.target
EOF

echo "=== Reloading systemd & (re)starting service ==="
sudo systemctl daemon-reload
# In case a prior start-limit was hit:
sudo systemctl reset-failed sonar || true
sudo systemctl enable sonar
sudo systemctl restart sonar

echo "=== Status (one-shot) ==="
sudo systemctl --no-pager --full status sonar || true

echo "=== Tail logs (hint) ==="
echo "To watch live logs:"
echo "  journalctl -u sonar -f"
echo "Or:"
echo "  tail -n +1 -f ${SONAR_DIR}/logs/{sonar.log,es.log,web.log,ce.log}"

# ----- Optional tools -----
install_kubectl
install_aws_cli
install_maven

echo "ALL DONE! Access SonarQube at:  http://<server-ip>:9000"
echo "If you changed network exposure, ensure port 9000 is open in your firewall/SG."
