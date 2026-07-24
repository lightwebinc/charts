{{- define "shard-manifest.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "shard-manifest.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "shard-manifest.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "shard-manifest.labels" -}}
helm.sh/chart: {{ include "shard-manifest.chart" . }}
{{ include "shard-manifest.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: bsv-multicast
app.kubernetes.io/component: manifest
{{- end -}}

{{- define "shard-manifest.selectorLabels" -}}
app.kubernetes.io/name: {{ include "shard-manifest.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "shard-manifest.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "shard-manifest.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "shard-manifest.multusAnnotation" -}}
{{- if eq .Values.networking.mode "multus" -}}
k8s.v1.cni.cncf.io/networks: |
  [{
    "name": {{ .Values.networking.multus.networkName | quote }},
    "namespace": {{ .Values.networking.multus.namespace | quote }},
    {{- if .Values.networking.multus.fabricIPv6 }}
    "ips": [ {{ .Values.networking.multus.fabricIPv6 | quote }} ],
    {{- end }}
    "interface": {{ .Values.networking.multus.interface | quote }}
  }]
{{- end -}}
{{- end -}}

{{/*
Container env list. Each entry maps to a manifest daemon environment
variable; empty / zero values are emitted so the daemon falls back to its
hard-coded default.
*/}}
{{- define "shard-manifest.env" -}}
- name: SHARD_BITS
  value: {{ .Values.manifest.shardBits | quote }}
- name: JOINED_GROUPS
  value: {{ .Values.manifest.joinedGroups | quote }}
{{- if .Values.manifest.domains }}
- name: DOMAINS
  value: {{ join "," .Values.manifest.domains | quote }}
{{- end }}
- name: BITMAP
  value: {{ .Values.manifest.bitmap | quote }}
- name: ROLE_HINT
  value: {{ .Values.manifest.roleHint | quote }}
- name: GENERATION_ID
  value: {{ .Values.manifest.generationId | quote }}
- name: AUTHORITATIVE
  value: {{ .Values.manifest.authoritative | quote }}
- name: MANIFEST_SCOPE
  value: {{ .Values.manifest.scope | quote }}
- name: PORT
  value: {{ .Values.manifest.port | quote }}
- name: MC_GROUP_ID
  value: {{ .Values.manifest.mcGroupId | quote }}
- name: SOURCE_MODE
  value: {{ .Values.manifest.sourceMode | default "asm" | quote }}
{{- if .Values.manifest.publishers }}
- name: PUBLISHERS
  value: {{ join "," .Values.manifest.publishers | quote }}
{{- end }}
{{- if .Values.manifest.publishersRefresh }}
- name: PUBLISHERS_REFRESH
  value: {{ .Values.manifest.publishersRefresh | quote }}
{{- end }}
- name: IFACE
  value: {{ .Values.manifest.iface | quote }}
- name: ANNOUNCE_INTERVAL
  value: {{ .Values.manifest.announceInterval | quote }}
- name: TTL
  value: {{ .Values.manifest.ttl | quote }}
- name: METRICS_ADDR
  value: {{ .Values.metrics.addr | quote }}
- name: OTLP_ENDPOINT
  value: {{ .Values.otlp.endpoint | quote }}
- name: OTLP_INTERVAL
  value: {{ .Values.otlp.interval | quote }}
- name: DEBUG
  value: {{ .Values.manifest.debug | quote }}
- name: LOG_FORMAT
  value: {{ .Values.manifest.logFormat | quote }}
- name: LOG_LEVEL
  value: {{ .Values.manifest.logLevel | quote }}
{{- if .Values.manifest.traceSampling }}
- name: TRACE_SAMPLING
  value: {{ .Values.manifest.traceSampling | quote }}
{{- end }}
- name: INSTANCE_ID
  value: {{ default "" .Values.manifest.instanceId | quote }}
{{- end -}}

{{- define "shard-manifest.podSpec" -}}
serviceAccountName: {{ include "shard-manifest.serviceAccountName" . }}
{{- with .Values.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- if eq .Values.networking.mode "host" }}
hostNetwork: true
dnsPolicy: {{ .Values.networking.host.dnsPolicy }}
{{- end }}
{{- with .Values.priorityClassName }}
priorityClassName: {{ . }}
{{- end }}
{{- with .Values.podSecurityContext }}
securityContext:
  {{- toYaml . | nindent 2 }}
{{- end }}
containers:
  - name: {{ .Chart.Name }}
    image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
    imagePullPolicy: {{ .Values.image.pullPolicy }}
    {{- with .Values.securityContext }}
    securityContext:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    ports:
      - name: metrics
        containerPort: {{ .Values.metrics.port }}
        protocol: TCP
    env:
      {{- include "shard-manifest.env" . | nindent 6 }}
      {{- with .Values.extraEnv }}
      {{- toYaml . | nindent 6 }}
      {{- end }}
    {{- if .Values.probes.liveness.enabled }}
    livenessProbe:
      httpGet:
        path: /healthz
        port: metrics
      initialDelaySeconds: {{ .Values.probes.liveness.initialDelaySeconds }}
      periodSeconds: {{ .Values.probes.liveness.periodSeconds }}
      timeoutSeconds: {{ .Values.probes.liveness.timeoutSeconds }}
      failureThreshold: {{ .Values.probes.liveness.failureThreshold }}
    {{- end }}
    {{- if .Values.probes.readiness.enabled }}
    readinessProbe:
      httpGet:
        path: /readyz
        port: metrics
      initialDelaySeconds: {{ .Values.probes.readiness.initialDelaySeconds }}
      periodSeconds: {{ .Values.probes.readiness.periodSeconds }}
      timeoutSeconds: {{ .Values.probes.readiness.timeoutSeconds }}
      failureThreshold: {{ .Values.probes.readiness.failureThreshold }}
    {{- end }}
    {{- with .Values.resources }}
    resources:
      {{- toYaml . | nindent 6 }}
    {{- end }}
{{- with .Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.topologySpreadConstraints }}
topologySpreadConstraints:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}
