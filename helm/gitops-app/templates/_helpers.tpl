{{/*
helm/gitops-app/templates/_helpers.tpl
Reusable template helpers for the gitops-app chart.
*/}}

{{/* Chart name */}}
{{- define "gitops-app.name" -}}
{{- default .Chart.Name .Values.app.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Full release name */}}
{{- define "gitops-app.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.app.name }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/* Chart label */}}
{{- define "gitops-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Common labels applied to every resource */}}
{{- define "gitops-app.labels" -}}
helm.sh/chart: {{ include "gitops-app.chart" . }}
{{ include "gitops-app.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
environment: {{ .Values.app.environment }}
{{- end }}

{{/* Selector labels — used by Service and Deployment */}}
{{- define "gitops-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "gitops-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: {{ include "gitops-app.name" . }}
{{- end }}

{{/* ServiceAccount name */}}
{{- define "gitops-app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "gitops-app.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* Image reference — combines repository and tag */}}
{{- define "gitops-app.image" -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag }}
{{- end }}
