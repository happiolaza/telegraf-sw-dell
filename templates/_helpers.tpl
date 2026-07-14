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
{{- if .Values.site.vendor }}
vendor: {{ .Values.site.vendor }}
{{- end }}
environment: {{ .Values.site.environment | default "production" }}
{{- end }}

{{- define "telegraf-site.selectorLabels" -}}
app.kubernetes.io/name: {{ include "telegraf-site.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
site: {{ .Values.site.name }}
{{- end }}

{{- define "telegraf-site.prometheusPort" -}}
{{- .Values.telegraf.output.prometheusPort | default 9273 | int }}
{{- end }}

{{- define "telegraf-site.mibMountPath" -}}
/usr/share/snmp/mibs
{{- end }}

{{- define "telegraf-site.configMountPath" -}}
/etc/telegraf/telegraf.conf
{{- end }}
