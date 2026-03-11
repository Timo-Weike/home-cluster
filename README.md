# Home Cluster GitOps Repository (Pi5 + Longhorn via Argo CD)

This repository contains a fully-documented GitOps scaffold for a home Kubernetes
cluster built on **Raspberry Pi 5** nodes with **Longhorn** distributed storage,
**Sealed Secrets** for safe secret management, and **Prometheus/Grafana monitoring**
— all managed by **Argo CD**.

The bootstrap script prepares OS-level storage and installs k3s and Argo CD only.
Argo CD then reconciles the three cluster components from this repository.

---

## Cluster components

| Component | Namespace | Purpose |
|---|---|---|
| [Longhorn](https://longhorn.io) | `longhorn-system` | Distributed block storage (PersistentVolumes) |
| [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) | `monitoring` | Prometheus, Grafana, Alertmanager, Node Exporter |
| [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) | `sealed-secrets` | Encrypt secrets for safe Git storage |

> **Removed from original scaffold:** MetalLB and Traefik.  
> K3s ships with its own servicelb (Klipper) and Traefik ingress by default,
> so those components are handled at the k3s layer rather than through Argo CD.
> Disable them at k3s install time if you prefer a fully GitOps-managed alternative.

---

## Repository layout

```
.
├── apps/
│   └── home-assistant/        # Example application (Longhorn PVC + Deployment)
├── cluster/
│   ├── root-app.yaml          # Argo CD App-of-Apps — points at cluster/components/
│   └── components/
│       ├── longhorn/
│       │   └── application.yaml
│       ├── monitoring/
│       │   └── application.yaml
│       └── sealed-secrets/
│           └── application.yaml
├── docs/
├── scripts/
│   └── bootstrap-pi.sh        # OS prep, k3s install, Argo CD install (master only)
└── README.md
```

---

## Workflow summary

1. Boot each Pi from NVMe (Ubuntu Server 24.04 64-bit).
2. Copy `scripts/bootstrap-pi.sh` to each Pi and `chmod +x` it.
3. **Master only:** run the bootstrap script. It will:
   - Partition and mount the NVMe data disk at `/var/lib/longhorn`
   - Install k3s (with the built-in servicelb and Traefik **disabled** — see note above)
   - Install Argo CD into the `argocd` namespace
   - Apply `cluster/root-app.yaml` to register the App-of-Apps
4. **Workers:** run the bootstrap script using the join token printed by the master.
5. Argo CD syncs the three components in order (sync waves):
   - Wave 0: `sealed-secrets` (must be ready before any encrypted secrets are used)
   - Wave 0: `longhorn` (storage must exist before stateful workloads)
   - Wave 1: `monitoring` (needs Longhorn PVCs for Prometheus and Grafana)

> Update `repoURL` in `cluster/root-app.yaml` to point at your own Git remote
> before running the bootstrap.

---

## Using Sealed Secrets

After the `sealed-secrets` controller is running, install `kubeseal` on your
workstation and encrypt a secret:

```bash
# Fetch the public cert from the controller
kubeseal --fetch-cert \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=sealed-secrets \
  > pub-cert.pem

# Seal a secret
kubectl create secret generic my-secret \
  --dry-run=client \
  --from-literal=password=hunter2 \
  -o yaml \
  | kubeseal --cert pub-cert.pem --format yaml > my-sealed-secret.yaml

# Commit my-sealed-secret.yaml — it is safe to push to a public repo
```

**Back up the controller's master key** immediately after the first install:

```bash
kubectl get secret -n sealed-secrets \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealed-secrets-master-key-backup.yaml
```

Store the backup somewhere **outside** this repository.

---

## Security note

This repository contains no credentials.
Supply cluster join tokens, DNS tokens, and Grafana passwords via SealedSecrets
or by editing the relevant Helm `valuesObject` blocks locally before pushing.

---

## License

See [LICENSE](LICENSE).