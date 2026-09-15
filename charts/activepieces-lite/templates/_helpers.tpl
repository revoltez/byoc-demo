{{- define "ap.name" -}}
{{- printf "ap-%s" .Values.client.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "ap.labels" -}}
app.kubernetes.io/name: activepieces-lite
app.kubernetes.io/instance: {{ .Values.client.name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
demo/client: {{ .Values.client.name }}
demo/lane: {{ .Values.lane }}
{{- end -}}

{{- define "ap.selectorLabels" -}}
app.kubernetes.io/name: activepieces-lite
app.kubernetes.io/instance: {{ .Values.client.name }}
{{- end -}}

{{- define "ap.frontendUrl" -}}
{{- if .Values.frontendUrl -}}
{{ .Values.frontendUrl }}
{{- else if .Values.ingress.host -}}
http://{{ .Values.ingress.host }}
{{- else -}}
http://localhost:8080
{{- end -}}
{{- end -}}
