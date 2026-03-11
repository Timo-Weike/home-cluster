#!/usr/bin/env bash
# =============================================================================
# bootstrap-thinkcentre.sh
#
# k3s HA bootstrap for Lenovo ThinkCentre nodes running Ubuntu Server 24.04.
#
# Topology:
#   • 2 control-plane (master) nodes with embedded etcd
#   • Optional additional worker nodes
#   • API server is reached via the fixed IP of the FIRST master
#
# Usage:
#   On the FIRST master:
#     sudo ./bootstrap-thinkcentre.sh master-init
#
#   On the SECOND master (after the first is ready):
#     sudo K3S_TOKEN=<token> MASTER1_IP=<ip> ./bootstrap-thinkcentre.sh master-join
#
#   On each worker node:
#     sudo K3S_TOKEN=<token> MASTER1_IP=<ip> ./bootstrap-thinkcentre.sh worker
#
# After running master-init the token and join command are printed and also
# saved to /root/k3s-join-info.txt on the first master.
# =============================================================================

set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── Configuration — edit these before running ─────────────────────────────────

# Kubernetes version to install (leave empty for latest stable)
K3S_VERSION="${K3S_VERSION:-}"

# The IP address of the FIRST master node.
# Workers and the second master use this to join the cluster.
# If running master-init, this is auto-detected; set it explicitly if the node
# has multiple NICs.
MASTER1_IP="${MASTER1_IP:-}"

# Cluster token — auto-generated on master-init; must be passed in for every
# other role.
K3S_TOKEN="${K3S_TOKEN:-}"

# Argo CD version (tag from https://github.com/argoproj/argo-cd/releases)
ARGOCD_VERSION="${ARGOCD_VERSION:-v2.11.3}"

# Git URL of this repository — used when registering the root-app with Argo CD.
REPO_URL="${REPO_URL:-https://github.com/Timo-Weike/home-cluster.git}"

# Path to the root-app manifest inside the repo.
ROOT_APP_PATH="${ROOT_APP_PATH:-cluster/root-app.yaml}"

# =============================================================================
# Sanity checks
# =============================================================================

[[ $EUID -eq 0 ]] || die "Run this script as root (sudo)."

ROLE="${1:-}"
[[ -n "$ROLE" ]] || die "Usage: $0 <master-init|master-join|worker>"
[[ "$ROLE" =~ ^(master-init|master-join|worker)$ ]] \
  || die "Unknown role '$ROLE'. Must be master-init, master-join, or worker."

# =============================================================================
# Step 1 — System preparation (all roles)
# =============================================================================

system_prep() {
  info "=== System preparation ==="

  info "Setting hostname..."
  HOSTNAME_INPUT=""
  read -rp "Enter a hostname for this node (e.g. thinkcentre-01): " HOSTNAME_INPUT
  [[ -n "$HOSTNAME_INPUT" ]] || die "Hostname cannot be empty."
  hostnamectl set-hostname "$HOSTNAME_INPUT"
  # Ensure the hostname resolves locally
  if ! grep -q "$HOSTNAME_INPUT" /etc/hosts; then
    echo "127.0.1.1  $HOSTNAME_INPUT" >> /etc/hosts
  fi
  success "Hostname set to $HOSTNAME_INPUT"

  info "Updating package lists and upgrading installed packages..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get upgrade -y -qq
  apt-get install -y -qq \
    curl wget git jq open-iscsi nfs-common \
    apt-transport-https ca-certificates gnupg lsb-release
  success "Packages up to date."

  info "Enabling and starting open-iscsi (required by Longhorn)..."
  systemctl enable --now iscsid
  success "iSCSI daemon running."

  info "Loading required kernel modules..."
  modprobe iscsi_tcp 2>/dev/null || warn "iscsi_tcp module not available — may be built-in."
  # Persist across reboots
  cat > /etc/modules-load.d/k3s.conf <<EOF
iscsi_tcp
EOF

  info "Disabling swap (Kubernetes requirement)..."
  swapoff -a
  sed -i '/\bswap\b/s/^/#/' /etc/fstab
  success "Swap disabled."

  info "Adjusting sysctl settings for Kubernetes networking..."
  cat > /etc/sysctl.d/99-k3s.conf <<EOF
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
vm.overcommit_memory                = 1
kernel.panic                        = 10
kernel.panic_on_oops                = 1
EOF
  sysctl --system -q
  success "Sysctl tuning applied."
}

# =============================================================================
# Step 2a — Install k3s: first master (cluster init)
# =============================================================================

install_master_init() {
  info "=== Installing k3s — FIRST master (cluster init) ==="

  # Auto-detect primary IP if not set
  if [[ -z "$MASTER1_IP" ]]; then
    MASTER1_IP=$(ip route get 1.1.1.1 | awk '{print $7; exit}')
    info "Auto-detected node IP: $MASTER1_IP"
  fi

  # Generate a random token if not provided
  if [[ -z "$K3S_TOKEN" ]]; then
    K3S_TOKEN=$(openssl rand -hex 32)
    info "Generated cluster token."
  fi

  local install_flags=(
    # Embedded etcd HA mode
    "--cluster-init"
    # Advertise the fixed IP so joining nodes can reach the API server
    "--advertise-address=${MASTER1_IP}"
    "--tls-san=${MASTER1_IP}"
    # Disable components managed via Argo CD / not needed
    "--disable=traefik"
    "--disable=servicelb"
    # Write kubeconfig with broader permissions so non-root users can read it
    "--write-kubeconfig-mode=0644"
  )

  local version_flag=""
  [[ -n "$K3S_VERSION" ]] && version_flag="INSTALL_K3S_VERSION=${K3S_VERSION}"

  info "Running k3s installer..."
  eval "K3S_TOKEN=${K3S_TOKEN} ${version_flag} \
    curl -sfL https://get.k3s.io | sh -s - server ${install_flags[*]}"

  info "Waiting for k3s to become ready (up to 120 s)..."
  local deadline=$(( $(date +%s) + 120 ))
  until kubectl get nodes &>/dev/null; do
    (( $(date +%s) < deadline )) || die "k3s did not become ready in time."
    sleep 4
  done
  success "k3s control-plane is up."

  # Save join info for the operator
  cat > /root/k3s-join-info.txt <<EOF
# Generated by bootstrap-thinkcentre.sh on $(date)
MASTER1_IP=${MASTER1_IP}
K3S_TOKEN=${K3S_TOKEN}

# Join the SECOND master:
#   sudo K3S_TOKEN=${K3S_TOKEN} MASTER1_IP=${MASTER1_IP} ./bootstrap-thinkcentre.sh master-join
#
# Join a worker:
#   sudo K3S_TOKEN=${K3S_TOKEN} MASTER1_IP=${MASTER1_IP} ./bootstrap-thinkcentre.sh worker
EOF
  chmod 600 /root/k3s-join-info.txt

  echo ""
  success "============================================================"
  success " First master ready.  Join info saved to /root/k3s-join-info.txt"
  success "   MASTER1_IP : ${MASTER1_IP}"
  success "   K3S_TOKEN  : ${K3S_TOKEN}"
  success "============================================================"
  echo ""
}

# =============================================================================
# Step 2b — Install k3s: second (or additional) master
# =============================================================================

install_master_join() {
  info "=== Installing k3s — additional master (joining HA cluster) ==="

  [[ -n "$K3S_TOKEN" ]]  || die "K3S_TOKEN must be set. See /root/k3s-join-info.txt on the first master."
  [[ -n "$MASTER1_IP" ]] || die "MASTER1_IP must be set."

  local install_flags=(
    "--server=https://${MASTER1_IP}:6443"
    "--advertise-address=$(ip route get 1.1.1.1 | awk '{print $7; exit}')"
    "--tls-san=${MASTER1_IP}"
    "--disable=traefik"
    "--disable=servicelb"
    "--write-kubeconfig-mode=0644"
  )

  local version_flag=""
  [[ -n "$K3S_VERSION" ]] && version_flag="INSTALL_K3S_VERSION=${K3S_VERSION}"

  eval "K3S_TOKEN=${K3S_TOKEN} ${version_flag} \
    curl -sfL https://get.k3s.io | sh -s - server ${install_flags[*]}"

  info "Waiting for node to appear in cluster..."
  sleep 10
  kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get nodes || true
  success "Second master joined the cluster."
}

# =============================================================================
# Step 2c — Install k3s: worker node
# =============================================================================

install_worker() {
  info "=== Installing k3s — worker node ==="

  [[ -n "$K3S_TOKEN" ]]  || die "K3S_TOKEN must be set. See /root/k3s-join-info.txt on the first master."
  [[ -n "$MASTER1_IP" ]] || die "MASTER1_IP must be set."

  local version_flag=""
  [[ -n "$K3S_VERSION" ]] && version_flag="INSTALL_K3S_VERSION=${K3S_VERSION}"

  eval "K3S_TOKEN=${K3S_TOKEN} K3S_URL=https://${MASTER1_IP}:6443 ${version_flag} \
    curl -sfL https://get.k3s.io | sh -"

  success "Worker node installed and joined the cluster."
}

# =============================================================================
# Step 3 — Install Argo CD (master-init only)
# =============================================================================

install_argocd() {
  info "=== Installing Argo CD ${ARGOCD_VERSION} ==="

  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

  kubectl apply -n argocd \
    -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

  info "Waiting for Argo CD server deployment to be ready (up to 300 s)..."
  kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
  success "Argo CD is running."

  # Retrieve the initial admin password
  local initial_password
  initial_password=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d)

  echo ""
  success "============================================================"
  success " Argo CD initial admin password: ${initial_password}"
  success " Access the UI:  kubectl port-forward svc/argocd-server -n argocd 8080:443"
  success "                 then open https://localhost:8080"
  warn   " Change this password immediately after first login!"
  success "============================================================"
  echo ""

  # Append to join info file
  cat >> /root/k3s-join-info.txt <<EOF

# Argo CD initial admin password: ${initial_password}
# (change with: argocd account update-password)
EOF
}

# =============================================================================
# Step 4 — Apply root-app (master-init only)
# =============================================================================

apply_root_app() {
  info "=== Applying Argo CD root-app ==="

  # The root-app manifest lives in the Git repo.  We download it directly from
  # the configured REPO_URL so the cluster immediately begins reconciling.
  local raw_url
  raw_url=$(echo "$REPO_URL" \
    | sed 's|github.com|raw.githubusercontent.com|' \
    | sed 's|\.git$||')
  raw_url="${raw_url}/main/${ROOT_APP_PATH}"

  info "Fetching root-app from: ${raw_url}"
  if curl -sfL "$raw_url" | kubectl apply -f -; then
    success "root-app applied — Argo CD will now sync longhorn, monitoring, and sealed-secrets."
  else
    warn "Could not fetch root-app from Git. Apply it manually once the cluster has network access:"
    warn "  kubectl apply -f ${ROOT_APP_PATH}"
  fi
}

# =============================================================================
# Main
# =============================================================================

system_prep

case "$ROLE" in
  master-init)
    install_master_init
    install_argocd
    apply_root_app
    ;;
  master-join)
    install_master_join
    ;;
  worker)
    install_worker
    ;;
esac

echo ""
success "=== bootstrap-thinkcentre.sh complete (role: ${ROLE}) ==="
echo ""
info "Next steps:"
case "$ROLE" in
  master-init)
    echo "  1. Copy K3S_TOKEN and MASTER1_IP from /root/k3s-join-info.txt"
    echo "  2. Run this script with 'master-join' on the second ThinkCentre"
    echo "  3. Optionally run with 'worker' on any additional nodes"
    echo "  4. Watch Argo CD sync:  kubectl get applications -n argocd -w"
    ;;
  master-join)
    echo "  1. Verify cluster:  kubectl get nodes  (run on first master)"
    echo "  2. Optionally run with 'worker' on any additional nodes"
    ;;
  worker)
    echo "  1. Verify node appeared:  kubectl get nodes  (run on a master)"
    ;;
esac
echo ""