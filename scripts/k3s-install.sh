#!/usr/bin/env bash

DEBIAN_FRONTEND=noninteractive
apt update
apt upgrade -y
apt install -y curl ca-certificates jq udev open-iscsi nfs-common smartmontools

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

# k3s token: K109f2c35ce6e4d68723e0a66a76d80cb5c73e247fea56a05030a5fb7536cbfb03a::server:1487dae33b8890e83dc85b378a85dd30



# On master: install Helm and Argo CD only (Argo will manage components)
if [[ "$MODE" == "master" ]]; then
  echo "Installing Helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

  # Wait for kube API
  echo "Waiting for kube API..."
  until kubectl get nodes >/dev/null 2>&1; do sleep 2; done

  
  ARGOCD_IP="192.168.8.50"

  # Install Argo CD via Helm (simple install)
  echo "Installing Argo CD..."
  kubectl create namespace argocd || true
  helm repo add argo https://argoproj.github.io/argo-helm
  helm repo update
  helm upgrade --install argocd argo/argo-cd -n argocd --set server.service.type=LoadBalancer --set server.service.loadBalancerIP=${ARGOCD_IP} || true

  # Apply root application pointing to cluster/components
  kubectl apply -f ./cluster/argocd/root-app.yaml >/dev/null 2>&1 || true
  echo "Master bootstrap complete. Argo CD installed. Update cluster/argocd/root-app.yaml with your repo URL and apply it via kubectl or import it in Argo CD UI."

  echo "Worker join token: $K3S_TOKEN"
  echo "Run workers with: sudo ./bootstrap-pi.sh --mode worker --hostname <name> --master-ip <master-ip> --token $K3S_TOKEN"
fi


echo "Bootstrap finished for $HOSTNAME ($MODE). Reboot recommended."

