{{/*
Expand the name of the chart.
*/}}
{{- define "pihole.unbound.name" -}}
{{- default "unbound" .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "pihole.unbound.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}-unbound
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}-unbound
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}-unbound
{{- end }}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "pihole.unbound.labels" -}}
helm.sh/chart: {{ include "pihole.chart" . }}
{{ include "pihole.unbound.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "pihole.unbound.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pihole.unbound.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
