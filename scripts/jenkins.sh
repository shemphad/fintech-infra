#!/bin/bash -xe
# Fix common Jenkins startup failures on Amazon Linux 2/2023

# 0) If we just kept failing, clear the systemd failed state
sudo systemctl reset-failed jenkins || true

# 1) Ensure Java 17 is present and default
if ! command -v java >/dev/null 2>&1; then
  if command -v dnf >/dev/null 2>&1; then
    sudo dnf -y install java-17-amazon-corretto-headless
  else
    sudo yum -y install java-17-amazon-corretto-headless
  fi
fi

# 2) Compute JAVA_HOME and persist it for Jenkins (some AL2023 images need this)
JAVA_BIN="$(readlink -f "$(command -v java)")" || true
JAVA_HOME_GUESS="$(dirname "$(dirname "$JAVA_BIN")")"
if [ -n "$JAVA_HOME_GUESS" ] && [ -x "$JAVA_HOME_GUESS/bin/java" ]; then
  if ! grep -q '^JAVA_HOME=' /etc/sysconfig/jenkins 2>/dev/null; then
    echo "JAVA_HOME=\"$JAVA_HOME_GUESS\"" | sudo tee -a /etc/sysconfig/jenkins >/dev/null
  else
    sudo sed -i "s|^JAVA_HOME=.*|JAVA_HOME=\"$JAVA_HOME_GUESS\"|" /etc/sysconfig/jenkins
  fi
fi

# 3) Make sure Jenkins directories belong to 'jenkins' user
for d in /var/lib/jenkins /var/log/jenkins /var/cache/jenkins; do
  if [ -d "$d" ]; then
    sudo chown -R jenkins:jenkins "$d"
  fi
done

# 4) If port 8080 is busy, switch Jenkins to 8081
if sudo ss -ltnp | grep -q ':8080 '; then
  if grep -q '^JENKINS_PORT=' /etc/sysconfig/jenkins 2>/dev/null; then
    sudo sed -i 's/^JENKINS_PORT=.*/JENKINS_PORT="8081"/' /etc/sysconfig/jenkins
  else
    echo 'JENKINS_PORT="8081"' | sudo tee -a /etc/sysconfig/jenkins >/dev/null
  fi
fi

# 5) Reload unit and start
sudo systemctl daemon-reload
sudo systemctl enable jenkins
sudo systemctl start jenkins

# 6) Show quick status + last logs to confirm
sleep 5
sudo systemctl status jenkins --no-pager || true
sudo tail -n 200 /var/log/jenkins/jenkins.log || true
