#!/usr/bin/env bash
#
# bootstrap-pi.sh  (ArgoCD-managed components edition)
#
# Purpose:
#  - Prepare NVMe (create p3 partition for Longhorn if missing)
#  - Mount /var/lib/longhorn on p3
#  - Install OS-level prerequisites for storage (open-iscsi, nfs-common, smartmontools)
#  - Install k3s server (master) or agent (worker). Traefik disabled in k3s install.
#  - On master: install Helm and Argo CD only (Argo CD will then manage MetalLB, Traefik, Longhorn, monitoring)
#
# Important design decision:
#  - Longhorn requires host-level disk prep which Argo CD cannot do. The script prepares disks before Argo CD sync.
#
# Usage examples:
#  Master:
#    sudo ./bootstrap-pi.sh --mode master --hostname pi-master --metallb-cidr 192.168.10.200-192.168.10.250 --argocd-ip 192.168.10.220 --repo https://github.com/you/home-cluster.git
#
#  Worker:
#    sudo ./bootstrap-pi.sh --mode worker --hostname pi-node2 --master-ip 192.168.10.10 --token K10...
#
set -euo pipefail
IFS=$'\n\t'

NVME_DEVICE="/dev/nvme0n1"
BOOT_PART="${NVME_DEVICE}p1"
ROOT_PART="${NVME_DEVICE}p2"
LONGHORN_PART="${NVME_DEVICE}p3"

MODE=""
MASTER_IP=""
K3S_TOKEN=""
METALLB_CIDR="192.168.8.50-192.168.11.254"
ARGOCD_IP="192.168.8.50"
REPO_URL=""

function usage() {
  cat <<EOF
Usage: sudo $0 --mode master|worker [--master-ip IP --token TOKEN] [--metallb-cidr CIDR] [--argocd-ip IP]
Example master:
  sudo $0 --mode master --hostname pi-master --metallb-cidr 192.168.10.200-192.168.10.250 --argocd-ip 192.168.10.220 --repo https://github.com/you/home-cluster.git
Example worker (after master prints token):
  sudo $0 --mode worker --hostname pi-node2 --master-ip 192.168.10.10 --token K10...
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2;;
    --master-ip) MASTER_IP="$2"; shift 2;;
    --token) K3S_TOKEN="$2"; shift 2;;
    --metallb-cidr) METALLB_CIDR="$2"; shift 2;;
    --argocd-ip) ARGOCD_IP="$2"; shift 2;;
    --repo) REPO_URL="$2"; shift 2;;
    -h|--help) usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

if [[ $(id -u) -ne 0 ]]; then
  echo "Please run as root: sudo $0 ..." >&2; exit 2
fi
if [[ -z "$MODE" ]]; then usage; fi
if [[ "$MODE" == "worker" ]] && [[ -z "$MASTER_IP" || -z "$K3S_TOKEN" ]]; then echo "Worker requires --master-ip and --token"; exit 3; fi

# Ensure NVMe exists
if [ ! -b "$NVME_DEVICE" ]; then
  echo "ERROR: $NVME_DEVICE not found. Attach NVMe and ensure the device exists." >&2; exit 4
fi

# Partition p3 if missing. The script asks explicit confirmation before destructive actions.
if lsblk -o NAME | grep -q "${NVME_DEVICE##*/}p3"; then
  echo "Detected existing p3 partition on ${NVME_DEVICE}. Skipping partition creation."
else
  echo "No p3 partition detected on ${NVME_DEVICE}. This operation will partition the device and destroy existing data on it."
  read -p "Type YES to continue and repartition ${NVME_DEVICE}: " CONFIRM
  if [[ "$CONFIRM" != "YES" ]]; then echo "Aborted by user."; exit 5; fi

  parted --script "$NVME_DEVICE" mklabel gpt
  parted --script "$NVME_DEVICE" mkpart primary 1MiB 513MiB
  parted --script "$NVME_DEVICE" mkpart primary 513MiB 30%
  parted --script "$NVME_DEVICE" mkpart primary 30% 100%
  partprobe "$NVME_DEVICE"
  sleep 1

  mkfs.vfat -F32 -n BOOT "${BOOT_PART}" || true
  mkfs.ext4 -F -L rootfs "${ROOT_PART}" || true
  mkfs.ext4 -F -L longhorn "${LONGHORN_PART}" || true
  echo "Partitioning and formatting complete."
fi

# Mount /var/lib/longhorn
mkdir -p /var/lib/longhorn
if ! mountpoint -q /var/lib/longhorn; then
  echo "Mounting $LONGHORN_PART -> /var/lib/longhorn"
  grep -q "$LONGHORN_PART" /etc/fstab || echo "$LONGHORN_PART /var/lib/longhorn ext4 defaults 0 0" >> /etc/fstab
  mount -a || true
fi

# Install OS prerequisites
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates jq udev open-iscsi nfs-common smartmontools

# Load kernel modules useful for block management
modprobe dm_mod || true
modprobe dm_thin_pool || true
modprobe dm_snapshot || true
modprobe iscsi_tcp || true

# Install k3s (disable k3s's embedded Traefik so Traefik is managed by Argo CD)
if [[ "$MODE" == "master" ]]; then
  echo "Installing k3s server (Traefik disabled)..."
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='--write-kubeconfig-mode 644 --disable traefik' sh -
  echo "k3s server installed."
  K3S_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)
  echo "k3s token: $K3S_TOKEN"
else
  echo "Installing k3s agent to join https://$MASTER_IP:6443 ..."
  curl -sfL https://get.k3s.io | K3S_URL="https://$MASTER_IP:6443" K3S_TOKEN="$K3S_TOKEN" sh -
  echo "k3s agent installed."
fi

# On master: install Helm and Argo CD only (Argo will manage components)
if [[ "$MODE" == "master" ]]; then
  echo "Installing Helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

  # Wait for kube API
  echo "Waiting for kube API..."
  until kubectl get nodes >/dev/null 2>&1; do sleep 2; done

  # Install Argo CD via Helm (simple install)
  echo "Installing Argo CD..."
  kubectl create namespace argocd || true
  helm repo add argo https://argoproj.github.io/argo-helm
  helm repo update
  helm upgrade --install argocd argo/argo-cd -n argocd --set server.service.type=LoadBalancer --set server.service.loadBalancerIP=${ARGOCD_IP} || true

  # Apply root application pointing to cluster/components
  if [[ -z "$REPO_URL" ]]; then
    echo "Note: No --repo specified. The root app will reference the default placeholder; edit cluster/argocd/root-app.yaml to set your repo URL."
  fi
  kubectl apply -f ./cluster/argocd/root-app.yaml >/dev/null 2>&1 || true
  echo "Master bootstrap complete. Argo CD installed. Update cluster/argocd/root-app.yaml with your repo URL and apply it via kubectl or import it in Argo CD UI."

  echo "Worker join token: $K3S_TOKEN"
  echo "Run workers with: sudo ./bootstrap-pi.sh --mode worker --hostname <name> --master-ip <master-ip> --token $K3S_TOKEN --repo ${REPO_URL}"
fi

echo "Bootstrap finished for $HOSTNAME ($MODE). Reboot recommended."
