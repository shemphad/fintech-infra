#!/bin/bash
# Run the sed command to eliminate hidden characters if needed:
# sed -i 's/\r$//' sonar.sh
set -euo pipefail

# ===== VERSIONS / VARS (Configuration) =====
MAVEN_VERSION="3.9.10"
SONARQUBE_VERSION="10.5.1.90531"
POSTGRES_USER="ddsonar"
POSTGRES_DB="ddsonarqube"
POSTGRES_PASSWORD="Team@123"
SONAR_USER="ddsonar"
SONAR_GROUP="ddsonar"
SONAR_DIR="/opt/sonarqube"
JAVA_PKG="openjdk-17-jdk"
KUBECTL_URL="https://s3.us-west-2.amazonaws.com/amazon-eks/1.31.7/2025-04-17/bin/linux/amd64/kubectl"

# --- Error Handling ---
trap 'echo " 🛑 ERROR at line $LINENO. Exiting." >&2; exit 1' ERR

# --- Helper Functions ---

source_maven_env() {
    if [ -f "/etc/profile.d/maven.sh" ]; then
        # shellcheck disable=SC1091
        source /etc/profile.d/maven.sh
    fi
}

install_kubectl() {
    echo "--- Installing kubectl ---"
    if ! command -v kubectl &>/dev/null; then
        sudo curl -fsSL -o /usr/local/bin/kubectl "$KUBECTL_URL"
        sudo chmod +x /usr/local/bin/kubectl
    else
        echo "kubectl already installed."
    fi
    kubectl version --client || true
}

install_aws_cli() {
    echo "--- Installing AWS CLI v2 ---"
    if ! command -v aws &>/dev/null; then
        local AWS_TEMP_DIR
        AWS_TEMP_DIR=$(mktemp -d)
        local AWS_ZIP="${AWS_TEMP_DIR}/awscliv2.zip"

        curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$AWS_ZIP"
        unzip -q "$AWS_ZIP" -d "$AWS_TEMP_DIR"

        sudo "${AWS_TEMP_DIR}/aws/install"
        rm -rf "$AWS_TEMP_DIR"
    else
        echo "AWS CLI already installed."
        aws --version
    fi
}

install_maven() {
    echo "--- Installing Maven ${MAVEN_VERSION} ---"
    if ! command -v mvn &>/dev/null || ! mvn -version 2>/dev/null | grep -q "Apache Maven ${MAVEN_VERSION}"; then
        local MAVEN_URL="https://dlcdn.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz"
        local TEMP_MAVEN_TAR
        TEMP_MAVEN_TAR=$(mktemp)

        wget -nv "$MAVEN_URL" -O "$TEMP_MAVEN_TAR"
        sudo tar -xzf "$TEMP_MAVEN_TAR" -C /opt
        sudo ln -sfn "/opt/apache-maven-${MAVEN_VERSION}" /opt/maven
        rm "$TEMP_MAVEN_TAR"

        sudo tee /etc/profile.d/maven.sh >/dev/null <<'EOF'
export M2_HOME=/opt/maven
export PATH=$M2_HOME/bin:$PATH
EOF
        sudo chmod +x /etc/profile.d/maven.sh
        source_maven_env
    else
        echo "Maven already installed and at the correct version."
    fi
    mvn -version
}

# ----------------- MAIN EXECUTION -----------------
echo "=========================================="
echo " 🚀 Starting SonarQube & dependencies setup"
echo "=========================================="

## Purge problematic PostgreSQL PGDG repository entry
echo "=== Purging problematic PostgreSQL PGDG repository entry ==="
if grep -rL "focal-pgdg" /etc/apt/ --include "*.list" &>/dev/null; then
    find /etc/apt/ -type f -name "*.list" -exec sudo grep -l "focal-pgdg" {} \; | while read -r FILE; do
        echo "Found and removing repository file: $FILE"
        sudo rm -f "$FILE"
    done
fi
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

echo "=== Updating system packages and installing base dependencies ==="
sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y wget unzip curl zip gnupg lsb-release "$JAVA_PKG" tar

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
${SONAR_USER} soft nproc 4096
${SONAR_USER} hard nproc 4096
EOF

# ===== PostgreSQL Installation =====
echo "=== Installing PostgreSQL ==="
if ! command -v psql &>/dev/null; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql postgresql-contrib
else
    echo "PostgreSQL already installed."
fi

echo "=== Configuring PostgreSQL user & DB ==="
sudo -u postgres psql -c "CREATE USER ${POSTGRES_USER} WITH ENCRYPTED PASSWORD '${POSTGRES_PASSWORD}'" || \
sudo -u postgres psql -c "ALTER USER ${POSTGRES_USER} WITH ENCRYPTED PASSWORD '${POSTGRES_PASSWORD}'"

sudo -u postgres psql -c "CREATE DATABASE ${POSTGRES_DB} OWNER ${POSTGRES_USER}" || true
echo "GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_USER};" | sudo -u postgres psql

sudo systemctl restart postgresql

# ===== SonarQube install =====
echo "=== Installing SonarQube ==="
if [ ! -d "${SONAR_DIR}" ]; then
    SONAR_ZIP_TEMP=$(mktemp)
    wget -nv "https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-${SONARQUBE_VERSION}.zip" -O "${SONAR_ZIP_TEMP}"
    sudo unzip -q "${SONAR_ZIP_TEMP}" -d /opt
    sudo mv "/opt/sonarqube-${SONARQUBE_VERSION}" "${SONAR_DIR}"
    rm "${SONAR_ZIP_TEMP}"
else
    echo "SonarQube already present at ${SONAR_DIR}"
fi

# Create user/group and set ownership
getent group "${SONAR_GROUP}" >/dev/null || sudo groupadd --system "${SONAR_GROUP}"
id -u "${SONAR_USER}" &>/dev/null || sudo useradd --system --gid "${SONAR_GROUP}" --home "${SONAR_DIR}" --shell /usr/sbin/nologin "${SONAR_USER}"

sudo install -d -o "${SONAR_USER}" -g "${SONAR_GROUP}" "${SONAR_DIR}/data" "${SONAR_DIR}/logs" "${SONAR_DIR}/temp"
sudo chown -R "${SONAR_USER}:${SONAR_GROUP}" "${SONAR_DIR}"
sudo chmod +x "${SONAR_DIR}/bin/linux-x86-64/sonar.sh"

# Configure DB connection
echo "=== Configuring SonarQube DB connection ==="
sudo tee "${SONAR_DIR}/conf/sonar.properties" >/dev/null <<EOF
sonar.jdbc.username=${POSTGRES_USER}
sonar.jdbc.password=${POSTGRES_PASSWORD}
sonar.jdbc.url=jdbc:postgresql://localhost:5432/${POSTGRES_DB}
# sonar.web.host=0.0.0.0
# sonar.web.port=9000
EOF
sudo chown "${SONAR_USER}:${SONAR_GROUP}" "${SONAR_DIR}/conf/sonar.properties"

# ===== systemd unit =====
echo "=== Creating systemd unit for SonarQube ==="
sudo tee /etc/systemd/system/sonar.service >/dev/null <<EOF
[Unit]
Description=SonarQube service
After=network.target postgresql.service
Wants=postgresql.service

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

sudo systemctl daemon-reload
sudo systemctl reset-failed sonar || true
sudo systemctl enable sonar
sudo systemctl restart sonar

sudo systemctl --no-pager --full status sonar || true

echo "To watch live logs: journalctl -u sonar -f"

# ----- Optional tools -----
install_kubectl
install_aws_cli
install_maven

echo " "
echo "=========================================================================="
echo "✅ ALL DONE! Access SonarQube at: http://<server-ip>:9000"
echo "NOTE: Default login is admin/admin. Change this immediately!"
echo "=========================================================================="
