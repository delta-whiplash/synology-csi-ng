{{/* Fullname helpers (standard helm pattern) */}}
{{- define "synology-csi-talos-ng.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "synology-csi-talos-ng.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- printf "%s" $name }}
{{- end }}
{{- end }}

{{- define "synology-csi-talos-ng.labels" -}}
app.kubernetes.io/name: {{ include "synology-csi-talos-ng.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "synology-csi-talos-ng.driverImage" -}}
{{- $d := .Values.driver -}}
{{- if $d.digest -}}
{{ $d.image }}@{{ $d.digest }}
{{- else -}}
{{ $d.image }}:{{ $d.tag | default .Chart.AppVersion }}
{{- end -}}
{{- end }}

{{/* Container hardening: everything that runs in userland without host
access runs non-root with dropped caps. NOT applied to the node plugin
(privileged by CSI design — device nodes, mounts, chroot). */}}
{{- define "synology-csi-talos-ng.hardenedSecurityContext" -}}
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 65534
  runAsGroup: 65534
  seccompProfile:
    type: RuntimeDefault
{{- end }}
