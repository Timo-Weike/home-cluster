
param (
    [string]
    $secretValue,
    [string]
    $namespace,
    [string]
    $secretName
)

# generate random secretValue when $secretValue is null or empty
if ([string]::IsNullOrEmpty($secretValue)) {
    $secretValue = [Guid]::NewGuid().ToString()
}

# Keycloak admin password
$tempFileName = "$env:TEMP\ks-value.txt"
[System.IO.File]::WriteAllText($tempFileName, $secretValue, [System.Text.Encoding]::UTF8)
kubeseal --raw --from-file="$tempFileName" `
  --namespace $namespace --name $secretName `
  --controller-namespace sealed-secrets `
  --sealed-secret-file "${secretName}-secret.yaml"

Remove-Item $tempFileName




# # Keycloak admin password
# $env:KUBESEAL_VALUE = 'xxx'
# [System.IO.File]::WriteAllText("$env:TEMP\ks-value.txt", $env:KUBESEAL_VALUE, [System.Text.Encoding]::UTF8)
# kubeseal --raw --from-file="$env:TEMP\ks-value.txt" `
#   --namespace keycloak --name keycloak-admin-secret `
#   --controller-namespace sealed-secrets `
#   --sealed-secret-file keycloak-admin-secret.yaml

# # Keycloak DB passwords (use same or different values)
# $env:KUBESEAL_VALUE = 'xxx'
# [System.IO.File]::WriteAllText("$env:TEMP\ks-value.txt", $env:KUBESEAL_VALUE, [System.Text.Encoding]::UTF8)
# kubeseal --raw --from-file="$env:TEMP\ks-value.txt" `
#   --namespace keycloak --name keycloak-db-secret `
#   --controller-namespace sealed-secrets `
#   --sealed-secret-file keycloak-db-secret.yaml

# # Wiki.js DB password (use same value for db-password, db-admin-password, DB_PASS)
# $env:KUBESEAL_VALUE = 'xxx'
# [System.IO.File]::WriteAllText("$env:TEMP\ks-value.txt", $env:KUBESEAL_VALUE, [System.Text.Encoding]::UTF8)
# kubeseal --raw --from-file="$env:TEMP\ks-value.txt" `
#   --namespace wikijs --name wikijs-db-secret `
#   --controller-namespace sealed-secrets `
#   --sealed-secret-file wikijs-db-secret.yaml