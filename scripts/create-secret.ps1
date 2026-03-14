
param (
    [string]
    $secretValue,
    [string]
    $namespace,
    [string]
    $secretName
)

# # Keycloak admin password
# $env:KUBESEAL_VALUE = $secretValue
# [System.IO.File]::WriteAllText("$env:TEMP\ks-value.txt", $env:KUBESEAL_VALUE, [System.Text.Encoding]::UTF8)
# kubeseal --raw --from-file="$env:TEMP\ks-value.txt" `
#   --namespace $namespace --name $secretName `
#   --controller-namespace sealed-secrets

# Keycloak admin password
$env:KUBESEAL_VALUE = 'xxx'
[System.IO.File]::WriteAllText("$env:TEMP\ks-value.txt", $env:KUBESEAL_VALUE, [System.Text.Encoding]::UTF8)
kubeseal --raw --from-file="$env:TEMP\ks-value.txt" `
  --namespace keycloak --name keycloak-admin-secret `
  --controller-namespace sealed-secrets `
  --sealed-secret-file keycloak-admin-secret.yaml

# Keycloak DB passwords (use same or different values)
$env:KUBESEAL_VALUE = 'xxx'
[System.IO.File]::WriteAllText("$env:TEMP\ks-value.txt", $env:KUBESEAL_VALUE, [System.Text.Encoding]::UTF8)
kubeseal --raw --from-file="$env:TEMP\ks-value.txt" `
  --namespace keycloak --name keycloak-db-secret `
  --controller-namespace sealed-secrets `
  --sealed-secret-file keycloak-db-secret.yaml

# Wiki.js DB password (use same value for db-password, db-admin-password, DB_PASS)
$env:KUBESEAL_VALUE = 'xxx'
[System.IO.File]::WriteAllText("$env:TEMP\ks-value.txt", $env:KUBESEAL_VALUE, [System.Text.Encoding]::UTF8)
kubeseal --raw --from-file="$env:TEMP\ks-value.txt" `
  --namespace wikijs --name wikijs-db-secret `
  --controller-namespace sealed-secrets `
  --sealed-secret-file wikijs-db-secret.yaml