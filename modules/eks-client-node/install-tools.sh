#!/bin/bash
set -euo pipefail

# Jump Box bootstrap: Terraform 0.13.3, AWS CLI v2, kubectl 1.13.3
# Target OS: Ubuntu 20.04 (Focal)
# Arch: amd64

export DEBIAN_FRONTEND=noninteractive

TERRAFORM_VERSION="0.13.3"
KUBECTL_VERSION="v1.13.3"

#--- helpers ---------------------------------------------------------------
log() { echo -e "\n=== $* ==="; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1
}

#--- base deps -------------------------------------------------------------
log "Updating apt and installing base dependencies"
sudo apt-get update -y
sudo apt-get install -y curl unzip wget ca-certificates bash-completion gnupg lsb-release

#--- Terraform 0.13.3 -----------------------------------------------------
install_terraform() {
  local target_ver="$TERRAFORM_VERSION"
  local tf_bin="/usr/local/bin/terraform"

  if require_cmd terraform; then
    local cur
    cur="$(terraform version | head -n1 | awk '{print $2}' | sed 's/v//')"
    if [[ "$cur" == "$target_ver" ]]; then
      log "Terraform $target_ver already installed"
      return 0
    else
      log "Terraform present ($cur) -> replacing with $target_ver"
    fi
  else
    log "Installing Terraform $target_ver"
  fi

  local zip="terraform_${target_ver}_linux_amd64.zip"
  local url="https://releases.hashicorp.com/terraform/${target_ver}/${zip}"

  rm -f "/tmp/${zip}"
  curl -fsSL "$url" -o "/tmp/${zip}"

  sudo unzip -o "/tmp/${zip}" -d /usr/local/bin
  sudo chmod 0755 "$tf_bin"

  rm -f "/tmp/${zip}"

  log "Terraform installed: $(terraform version | head -n1)"
}

#--- AWS CLI v2 ------------------------------------------------------------
install_awscli() {
  if require_cmd aws; then
    log "AWS CLI already installed: $(aws --version 2>&1)"
    return 0
  fi

  log "Installing AWS CLI v2"
  pushd /tmp >/dev/null
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
  unzip -q -o awscliv2.zip
  sudo ./aws/install
  rm -rf aws awscliv2.zip
  popd >/dev/null

  log "AWS CLI installed: $(aws --version 2>&1)"
}

#--- kubectl v1.13.3 -------------------------------------------------------
install_kubectl() {
  local target_ver="$KUBECTL_VERSION"
  local kbin="/usr/local/bin/kubectl"

  if require_cmd kubectl; then
    local cur
    cur="$(kubectl version --client --short 2>/dev/null | awk '{print $3}')"
    if [[ "$cur" == "$target_ver" ]]; then
      log "kubectl $target_ver already installed"
      return 0
    else
      log "kubectl present ($cur) -> replacing with $target_ver"
    fi
  else
    log "Installing kubectl $target_ver"
  fi

  # Old but still downloadable path style for historical versions
  local url="https://dl.k8s.io/release/${target_ver}/bin/linux/amd64/kubectl"

  curl -fsSL "$url" -o /tmp/kubectl
  sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
  rm -f /tmp/kubectl

  # bash completion (if desired)
  if [[ -d /etc/bash_completion.d ]]; then
    kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl >/dev/null
  fi

  log "kubectl installed: $(kubectl version --client --short)"
}

#--- run installs ----------------------------------------------------------
install_terraform
install_awscli
install_kubectl

log "All set! Versions:"
terraform version | head -n1
aws --version
kubectl version --client --short
