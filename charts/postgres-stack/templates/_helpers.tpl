{{/*
Fully-qualified release name, truncated to 63 chars.
*/}}
{{- define "postgres-stack.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
pgAdmin selector labels.
*/}}
{{- define "postgres-stack.pgadmin.selectorLabels" -}}
app.kubernetes.io/name: pgadmin
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Name of the Secret that holds the pgAdmin password.
*/}}
{{- define "postgres-stack.pgadmin.secretName" -}}
{{- if .Values.pgadmin.auth.existingSecret }}
{{- .Values.pgadmin.auth.existingSecret }}
{{- else }}
{{- include "postgres-stack.fullname" . }}-pgadmin
{{- end }}
{{- end }}

{{/*
In-cluster DNS name of the Bitnami PostgreSQL primary service.
The Bitnami chart creates:  <release>-postgresql.<namespace>.svc.cluster.local
*/}}
{{- define "postgres-stack.postgres.host" -}}
{{- printf "%s-postgresql.%s.svc.cluster.local" (include "postgres-stack.fullname" .) .Release.Namespace }}
{{- end }}

{{/*
PostgreSQL port (sourced from sub-chart values).
*/}}
{{- define "postgres-stack.postgres.port" -}}
{{- .Values.postgresql.service.ports.postgresql | default 5432 }}
{{- end }}

{{/*
Name of the Secret that the Bitnami sub-chart creates (or the existingSecret).
*/}}
{{- define "postgres-stack.postgres.secretName" -}}
{{- if .Values.postgresql.auth.existingSecret }}
{{- .Values.postgresql.auth.existingSecret }}
{{- else }}
{{- include "postgres-stack.fullname" . }}-postgresql
{{- end }}
{{- end }}

{{/*
Key inside the postgres secret that holds the superuser password.
*/}}
{{- define "postgres-stack.postgres.secretKey" -}}
{{- if .Values.postgresql.auth.existingSecret }}
{{- .Values.postgresql.auth.secretKeys.adminPasswordKey | default "postgres-password" }}
{{- else }}
postgres-password
{{- end }}
{{- end }}
