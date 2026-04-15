# keycloak — custom Helm chart

Wraps [codecentric/keycloakx](https://github.com/codecentric/helm-charts/tree/master/charts/keycloakx)
and [bitnami/postgresql](https://github.com/bitnami/charts/tree/main/bitnami/postgresql)
into a single, GitOps-ready chart.  No plaintext credentials are stored anywhere.

## Directory layout

```
cluster/components/keycloak/
├── chart/                   ← this Helm chart
│   ├── Chart.yaml
│   ├── Chart.lock           ← MUST be committed after `helm dependency update`
│   ├── values.yaml
│   └── templates/
│       └── _helpers.tpl
├── more/                    ← plain manifests applied alongside the chart
│   ├── keycloak-admin-secret.yaml   ← SealedSecret (admin password)
│   └── keycloak-db-secret.yaml      ← SealedSecret (DB passwords)
└── keycloak-app.yaml        ← Argo CD Application
```

## First-time setup

### 1. Seal the secrets

```powershell
# Admin password
$env:KUBESEAL_VALUE = 'your-admin-password'
[System.IO.File]::WriteAllText("$env:TEMP\ks.txt", $env:KUBESEAL_VALUE, [System.Text.Encoding]::UTF8)
kubeseal --raw --from-file="$env:TEMP\ks.txt" `
  --namespace keycloak --name keycloak-admin-secret `
  --controller-namespace sealed-secrets
# → paste output as admin-password in more/keycloak-admin-secret.yaml

# DB user password  (used by Keycloak and as postgresql userPasswordKey)
$env:KUBESEAL_VALUE = 'your-db-password'
[System.IO.File]::WriteAllText("$env:TEMP\ks.txt", $env:KUBESEAL_VALUE, [System.Text.Encoding]::UTF8)
kubeseal --raw --from-file="$env:TEMP\ks.txt" `
  --namespace keycloak --name keycloak-db-secret `
  --controller-namespace sealed-secrets
# → paste output as db-password in more/keycloak-db-secret.yaml

# DB admin (postgres superuser) password
$env:KUBESEAL_VALUE = 'your-db-admin-password'
[System.IO.File]::WriteAllText("$env:TEMP\ks.txt", $env:KUBESEAL_VALUE, [System.Text.Encoding]::UTF8)
kubeseal --raw --from-file="$env:TEMP\ks.txt" `
  --namespace keycloak --name keycloak-db-secret `
  --controller-namespace sealed-secrets
# → paste output as db-admin-password in more/keycloak-db-secret.yaml
```

### 2. Lock the chart dependencies

```bash
cd cluster/components/keycloak/chart
helm dependency update    # downloads charts/ and writes Chart.lock
git add Chart.lock charts/
git commit -m "chore(keycloak): lock helm dependencies"
```

`Chart.lock` must be committed so Argo CD can render the chart without
live registry access.

### 3. Apply the Argo CD Application

```bash
kubectl apply -f cluster/components/keycloak/keycloak-app.yaml
```

Argo CD will pick it up and sync both sources.

## Accessing Keycloak

Keycloak is exposed on NodePort **30781**:

```
http://<any-node-ip>:30781
```

Admin console: `http://<node>:30781/admin` — log in with `admin` and the
password you sealed in step 1.

## Upgrading

* **Keycloak version**: bump `appVersion` in `Chart.yaml` and `image.tag` in
  `values.yaml`, then push.  Argo CD will rolling-restart the StatefulSet.
* **Chart dependency versions**: update the `version` constraints in
  `Chart.yaml`, re-run `helm dependency update`, commit `Chart.lock`.
