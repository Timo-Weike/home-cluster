# postgres-stack

A thin wrapper chart that bundles:

| Component | Source | Purpose |
|-----------|--------|---------|
| **PostgreSQL 16** | Bitnami sub-chart (`bitnami/postgresql`) | Database server, StatefulSet + PVC |
| **pgAdmin 4** | Custom templates in this chart | Web admin UI, Deployment + PVC |

All database logic (StatefulSet, Services, Secrets, backup hooks) is delegated to the
battle-tested Bitnami chart. This chart only adds the pgAdmin UI on top.

---

## Repository layout

```
postgres-stack/
├── Chart.yaml            # declares bitnami/postgresql as a dependency
├── Chart.lock            # pinned dependency digest — commit this!
├── values.yaml           # defaults for both postgresql sub-chart and pgAdmin
├── argocd-application.yaml
└── templates/
    ├── _helpers.tpl
    ├── NOTES.txt
    ├── pgadmin-secret.yaml
    ├── pgadmin-servers-cm.yaml   # pre-seeds the postgres connection in pgAdmin
    ├── pgadmin-deployment.yaml
    ├── pgadmin-service.yaml
    ├── pgadmin-pvc.yaml
    └── pgadmin-ingress.yaml
```

---

## First-time setup

```bash
# 1. Resolve and lock dependencies (requires Helm 3)
helm dependency update charts/postgres-stack

# 2. Commit the generated lock file and downloaded chart tarball
git add charts/postgres-stack/Chart.lock charts/postgres-stack/charts/
git commit -m "chore: lock postgres-stack dependencies"
git push

# 3. Apply the Argo CD Application
kubectl apply -f charts/postgres-stack/argocd-application.yaml
```

> **Why commit `Chart.lock`?**  
> Argo CD renders the chart in an air-gapped context. Without the lock file (and
> optionally the `charts/` tarball), it cannot resolve the Bitnami dependency.
> Alternatively, enable the `--enable-helm-sync-on-the-fly` Argo CD flag, but
> committing the lock is simpler and more reliable.

---

## Secrets (production)

Use SealedSecrets (already in your cluster) to encrypt the passwords and commit them:

```bash
# PostgreSQL superuser password
echo -n 'your-pg-password' | kubeseal --raw \
  --namespace database --name postgres-credentials \
  --controller-namespace sealed-secrets

# pgAdmin login password
echo -n 'your-pgadmin-password' | kubeseal --raw \
  --namespace database --name pgadmin-credentials \
  --controller-namespace sealed-secrets
```

Then in your Argo CD values override:

```yaml
postgresql:
  auth:
    existingSecret: postgres-credentials
    secretKeys:
      adminPasswordKey: postgres-password
      userPasswordKey:  postgres-password

pgadmin:
  auth:
    existingSecret: pgadmin-credentials
    secretKey: pgadmin-password
```

---

## Connecting other apps to PostgreSQL

The Bitnami chart exposes PostgreSQL at:

```
<release-name>-postgresql.<namespace>.svc.cluster.local:5432
```

Example pod env:

```yaml
env:
  - name: DATABASE_HOST
    value: postgres-stack-postgresql.database.svc.cluster.local
  - name: DATABASE_PORT
    value: "5432"
  - name: DATABASE_NAME
    value: appdb
  - name: DATABASE_USER
    value: postgres
  - name: DATABASE_PASSWORD
    valueFrom:
      secretKeyRef:
        name: postgres-credentials
        key: postgres-password
```
