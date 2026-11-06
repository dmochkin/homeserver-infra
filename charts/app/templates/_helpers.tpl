{{- define "app.labels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "app.selectorLabels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "app.image" -}}
{{ required "image.repository is set by the deploy script" .Values.image.repository }}:{{ required "image.tag is set by the deploy script" .Values.image.tag }}
{{- end }}

{{/* Pod settings shared by the app and its scheduled jobs. */}}
{{- define "app.podSecurity" -}}
securityContext:
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault
  # The standard container profile plus signals between Ubuntu 26.04's stacked labels
  # (installed by homeserver-infra roles/k3s). Needed by Go programs and anything that signals its own processes.
  appArmorProfile:
    type: Localhost
    localhostProfile: homeserver-container
{{- end }}

{{- define "app.containerSecurity" -}}
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
{{- end }}

{{- define "app.env" -}}
{{- with .Values.env }}
env:
  {{- range $name, $value := . }}
  - name: {{ $name }}
    value: {{ $value | toString | quote }}
  {{- end }}
{{- end }}
{{- with .Values.envSecret }}
envFrom:
  - secretRef:
      name: {{ . }}
{{- end }}
{{- end }}
