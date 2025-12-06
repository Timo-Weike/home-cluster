# Home Cluster GitOps Repository (Pi5 + Longhorn via Argo CD)

This repository contains a fully-documented GitOps scaffold for a home Kubernetes cluster built on **Raspberry Pi 5** nodes with **Longhorn** distributed storage **managed by Argo CD** and **Traefik** as the ingress controller. MetalLB is used for LoadBalancer IPs. The bootstrap script prepares the OS-level storage and installs k3s and Argo CD only; Argo CD then manages MetalLB, Longhorn, Traefik, and other cluster components.

**What you get (archive):**
- `scripts/bootstrap-pi.sh` — safe, documented bootstrap script (partitions, mounts, k3s install, OS prep for Longhorn, installs Argo CD on master only)
- `cluster/` — Argo CD-managed components (MetalLB, Longhorn, Traefik) under `components/`, plus `root-app.yaml` for Argo CD to apply
- `apps/` — example app (Home Assistant) with Longhorn PVC and Deployment
- `monitoring/` — guidance and values for Prometheus/Grafana
- Full, line-by-line documentation inside each file.

Security note: This repo does not contain credentials. You must supply cluster tokens and any DNS/API tokens where required.

---
## Workflow summary
1. Boot each Pi from NVMe (Ubuntu Server 24.04 64-bit) — no SD card needed.
2. Copy `scripts/bootstrap-pi.sh` to each Pi, `chmod +x`.
3. Run master bootstrap: it prepares disks, installs k3s, installs Argo CD and registers the `root-app` pointing at `cluster/components/`.
4. Run worker bootstrap on other Pis (using printed token).
5. Argo CD syncs: MetalLB, Traefik, Longhorn, Monitoring, Apps.

This repo assumes you will push it to your Git host and update `cluster/argocd/root-app.yaml` to point at the repo URL.
