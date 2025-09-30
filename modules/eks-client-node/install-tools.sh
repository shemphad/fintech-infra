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

#--- dynamic EKS kubeconfig update -----------------------------------------
# Strategy:
# 1) REGION: AWS_REGION/AWS_DEFAULT_REGION -> IMDSv2 -> AWS config -> us-east-1
# 2) CLUSTER: EKS_CLUSTER_NAME -> CLUSTER_PATTERN match -> single cluster -> newest cluster

discover_region() {
  if [[ -n "${AWS_REGION:-}" ]]; then echo "$AWS_REGION"; return; fi
  if [[ -n "${AWS_DEFAULT_REGION:-}" ]]; then echo "$AWS_DEFAULT_REGION"; return; fi

  # IMDSv2 (with IMDSv1 fallback)
  local token az
  token="$(curl -sS -m 2 -X PUT 'http://169.254.169.254/latest/api/token' \
            -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' || true)"
  if [[ -n "$token" ]]; then
    az="$(curl -sS -m 2 -H "X-aws-ec2-metadata-token: $token" \
          'http://169.254.169.254/latest/meta-data/placement/availability-zone' || true)"
  else
    az="$(curl -sS -m 2 'http://169.254.169.254/latest/meta-data/placement/availability-zone' || true)"
  fi
  if [[ -n "$az" ]]; then echo "${az::-1}"; return; fi

  local cfg_region
  cfg_region="$(aws configure get region 2>/dev/null || true)"
  if [[ -n "$cfg_region" ]]; then echo "$cfg_region"; return; fi

  echo "us-east-1"
}

discover_cluster() {
  local region="$1"
  local clusters
  # list-clusters returns names; use text to avoid jq dependency
  clusters=($(aws eks list-clusters --region "$region" --output text 2>/dev/null || true))

  # Explicit name override
  if [[ -n "${EKS_CLUSTER_NAME:-}" ]]; then
    echo "$EKS_CLUSTER_NAME"
    return 0
  fi

  # Optional pattern preference (case-insensitive substring)
  if [[ -n "${CLUSTER_PATTERN:-}" && "${#clusters[@]}" -gt 0 ]]; then
    local c lc patt
    patt="$(tr '[:upper:]' '[:lower:]' <<<"$CLUSTER_PATTERN")"
    for c in "${clusters[@]}"; do
      lc="$(tr '[:upper:]' '[:lower:]' <<<"$c")"
      if [[ "$lc" == *"$patt"* ]]; then
        echo "$c"
        return 0
      fi
    done
  fi

  # If exactly one cluster, use it
  if [[ "${#clusters[@]}" -eq 1 ]]; then
    echo "${clusters[0]}"
    return 0
  fi

  # If multiple, pick the newest by createdAt
  if [[ "${#clusters[@]}" -gt 1 ]]; then
    local newest="" newest_ts=0 c ts
    for c in "${clusters[@]}"; do
      ts="$(aws eks describe-cluster --region "$region" --name "$c" \
            --query 'cluster.createdAt' --output text 2>/dev/null || true)"
      # convert to epoch seconds (Ubuntu date can parse ISO8601)
      if [[ -n "$ts" ]]; then
        ts="$(date -d "$ts" +%s 2>/dev/null || echo 0)"
      else
        ts=0
      fi
      if (( ts > newest_ts )); then
        newest_ts="$ts"
        newest="$c"
      fi
    done
    if [[ -n "$newest" ]]; then
      echo "$newest"
      return 0
    fi
  fi

  # Nothing found
  echo ""
}

configure_kube() {
  local region cluster
  region="$(discover_region)"
  cluster="$(discover_cluster "$region")"

  if [[ -z "$cluster" ]]; then
    echo "Error: No EKS clusters found in region '$region' (or no permissions)."
    echo "Tip: set EKS_CLUSTER_NAME or CLUSTER_PATTERN, or export AWS_REGION/AWS_DEFAULT_REGION."
    return 1
  fi

  mkdir -p ~/.kube
  echo "Updating kubeconfig for cluster '$cluster' in region '$region'..."
  aws eks update-kubeconfig --region "$region" --name "$cluster"

  # Optional: echo the current context
  kubectl config current-context || true
}

configure_kube

