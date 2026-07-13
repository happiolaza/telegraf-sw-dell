{{- define "telegraf-site.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "telegraf-site.fullname" -}}
{{- printf "telegraf-%s" .Values.site.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "telegraf-site.labels" -}}
app.kubernetes.io/name: {{ include "telegraf-site.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/component: telegraf-snmp
app.kubernetes.io/part-of: switch-monitoring
site: {{ .Values.site.name }}
environment: {{ .Values.site.environment | default "production" }}
{{- end }}

{{- define "telegraf-site.selectorLabels" -}}
app.kubernetes.io/name: {{ include "telegraf-site.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
site: {{ .Values.site.name }}
{{- end }}
