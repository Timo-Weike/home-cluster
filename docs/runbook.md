# Runbook — Argo CD-managed Components (Longhorn prep included)

This runbook explains the sequence performed by the updated bootstrap script and the responsibilities of Argo CD.

## High-level process
- **Node prep (performed by bootstrap script on every node):**
  - Partition NVMe if needed and create `/var/lib/longhorn` on partition p3
  - Format and mount the partition, add /etc/fstab entry
  - Install OS-level prerequisites: smartmontools (optional), open-iscsi, nfs-common, etc.
  - Enable required kernel modules for block device management
- **k3s installation (performed by bootstrap):**
  - Install k3s server on master (Traefik disabled here to allow Helm-managed Traefik by Argo CD)
  - Install k3s agents on workers
- **Argo CD installation (performed by bootstrap on master):**
  - Install Argo CD only (so it can GitOps-manage cluster components)
  - Apply `cluster/argocd/root-app.yaml` to instruct Argo CD to sync `cluster/components/*`
- **Argo CD installs & manages:**
  - MetalLB (LoadBalancer)
  - Traefik (Ingress)
  - Longhorn (Storage)
  - Monitoring (Prometheus/Grafana)
  - Applications (Home Assistant, etc.)

## Notes & safety
- Partitioning is destructive. The script asks for explicit confirmation (type YES).
- The bootstrap script does not contain any secrets; add secrets (e.g., TLS, cloud credentials) to your Git repo or ArgoCD-managed secret store.
- Ensure your network's MetalLB IP range does not overlap DHCP assignments.
