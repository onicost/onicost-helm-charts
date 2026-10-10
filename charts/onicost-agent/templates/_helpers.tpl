{{/*
Name of every object of the chart: the name of the release.
*/}}
{{- define "onicost-agent.fullname" -}}
{{- .Release.Name -}}
{{- end -}}

{{/*
Value of the helm.sh/chart label.
*/}}
{{- define "onicost-agent.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Selector of the Deployment.
*/}}
{{- define "onicost-agent.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Labels of every object.
*/}}
{{- define "onicost-agent.labels" -}}
{{ include "onicost-agent.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ include "onicost-agent.chart" . }}
{{- end -}}

{{/*
Labels of the pod: podLabels, then the labels of every object, which win so
that podLabels can never change the selector.
*/}}
{{- define "onicost-agent.podLabels" -}}
{{- $labels := include "onicost-agent.labels" . | fromYaml -}}
{{- toYaml (merge $labels (.Values.podLabels | default dict)) -}}
{{- end -}}
