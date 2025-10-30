{{/* Chart base name */}}
{{- define "cliscale.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Release fullname */}}
{{- define "cliscale.fullname" -}}
{{- $name := default .Chart.Name .Values.fullnameOverride -}}
{{- $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Service fullname: <release>-<svc> */}}
{{- define "cliscale.fullnameFor" -}}
{{- $root := index . 0 -}}
{{- $svcName := index . 1 -}}
{{- printf "%s-%s" (include "cliscale.fullname" $root) $svcName | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Standard labels */}}
{{- define "cliscale.labelsFor" -}}
{{- $root := index . 0 -}}
{{- $svcName := index . 1 -}}
app.kubernetes.io/name: {{ include "cliscale.fullnameFor" (list $root $svcName) }}
app.kubernetes.io/instance: {{ $root.Release.Name }}
app.kubernetes.io/managed-by: {{ $root.Release.Service }}
helm.sh/chart: {{ printf "%s-%s" $root.Chart.Name $root.Chart.Version | quote }}
{{- end -}}

{{/* Selector labels */}}
{{- define "cliscale.selectorLabelsFor" -}}
{{- $root := index . 0 -}}
{{- $svcName := index . 1 -}}
app.kubernetes.io/name: {{ include "cliscale.fullnameFor" (list $root $svcName) }}
{{- end -}}
