{{- define "subtx-generator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "subtx-generator.fullname" -}}
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

{{- define "subtx-generator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "subtx-generator.labels" -}}
helm.sh/chart: {{ include "subtx-generator.chart" . }}
{{ include "subtx-generator.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: bsv-multicast
app.kubernetes.io/component: {{ .Values.mode }}
{{- end -}}

{{- define "subtx-generator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "subtx-generator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "subtx-generator.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "subtx-generator.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "subtx-generator.multusAnnotation" -}}
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
emitFlag — render a single CLI flag, honoring zero/empty defaults.
Receives a dict with keys:
  name: the kebab-case flag (without leading dash)
  v:    the value (any type)
- bool true  → "-<name>"
- bool false → omitted
- empty string / "0s" → omitted
- string / number / duration → "-<name>=<value>"
- 0 numeric → omitted (binary default applies)
*/}}
{{- define "subtx-generator.emitFlag" -}}
{{- $name := .name -}}
{{- $v := .v -}}
{{- if kindIs "bool" $v -}}
{{- if $v }}
- {{ printf "-%s" $name }}
{{- end -}}
{{- else if kindIs "string" $v -}}
{{- if and (ne $v "") (ne $v "0s") }}
- {{ printf "-%s=%v" $name $v }}
{{- end -}}
{{- else -}}
{{- if and $v (ne (printf "%v" $v) "0") }}
- {{ printf "-%s=%v" $name $v }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Container args (rendered as a YAML list) for the selected mode.
Each (camelCase values key) → (kebab-case binary flag) mapping is explicit
to avoid relying on regex backreference behaviour across Sprig versions.
*/}}
{{- define "subtx-generator.args" -}}
{{/* Shared flags */}}
{{- include "subtx-generator.emitFlag" (dict "name" "addr" "v" .Values.args.addr) -}}
{{- if eq .Values.mode "subtx-gen" -}}
{{- $a := .Values.subtxGen -}}
{{- include "subtx-generator.emitFlag" (dict "name" "tcp"                   "v" $a.tcp) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "frame-version"         "v" $a.frameVersion) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "shard-bits"            "v" $a.shardBits) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "subtrees"              "v" $a.subtrees) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "subtree-seed"          "v" $a.subtreeSeed) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "pps"                   "v" $a.pps) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "duration"              "v" $a.duration) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "count"                 "v" $a.count) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "workers"               "v" $a.workers) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "payload-size"          "v" $a.payloadSize) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "payload-format"        "v" $a.payloadFormat) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "seq-start"             "v" $a.seqStart) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "seq-gap-every"         "v" $a.seqGapEvery) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "seq-gap-size"          "v" $a.seqGapSize) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "seq-gap-delay"         "v" $a.seqGapDelay) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "log-interval"          "v" $a.logInterval) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "print-subtrees"        "v" $a.printSubtrees) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "subtree-group"         "v" $a.subtreeGroup) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "announce-addr"         "v" $a.announceAddr) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "announce-interval"     "v" $a.announceInterval) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "announce-ttl"          "v" $a.announceTtl) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "announce-phase-size"   "v" $a.announcePhaseSize) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "announce-phase-interval" "v" $a.announcePhaseInterval) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "corrupt-txid-rate"     "v" $a.corruptTxidRate) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "mode"                  "v" $a.mode) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "bind-source"           "v" $a.bindSource) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "egress-iface"          "v" $a.egressIface) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "source-mode"           "v" $a.sourceMode) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "scope"                 "v" $a.scope) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "mc-group-id"           "v" $a.mcGroupId) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "egress-port"           "v" $a.egressPort) -}}
{{- else if eq .Values.mode "send-anchor-frame" -}}
{{- $a := .Values.sendAnchorFrame -}}
{{- include "subtx-generator.emitFlag" (dict "name" "count"        "v" $a.count) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "payload-size" "v" $a.payloadSize) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "interval"     "v" $a.interval) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "tcp"          "v" $a.tcp) -}}
{{- else if eq .Values.mode "send-block-announce" -}}
{{- $a := .Values.sendBlockAnnounce -}}
{{- include "subtx-generator.emitFlag" (dict "name" "blocks"   "v" $a.blocks) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "subtrees" "v" $a.subtrees) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "interval" "v" $a.interval) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "coinbase" "v" $a.coinbase) -}}
{{- else if eq .Values.mode "send-subtree-data" -}}
{{- $a := .Values.sendSubtreeData -}}
{{- include "subtx-generator.emitFlag" (dict "name" "frames"        "v" $a.frames) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "msg-type"      "v" $a.msgType) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "nodes"         "v" $a.nodes) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "payload-size"  "v" $a.payloadSize) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "subtree-count" "v" $a.subtreeCount) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "interval"      "v" $a.interval) -}}
{{- else if eq .Values.mode "send-subtree-push" -}}
{{- $a := .Values.sendSubtreePush -}}
{{- include "subtx-generator.emitFlag" (dict "name" "count"                "v" $a.count) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "interval"             "v" $a.interval) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "duration"             "v" $a.duration) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "nodes"                "v" $a.nodes) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "coinbase-placeholder" "v" $a.coinbasePlaceholder) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "seed"                 "v" $a.seed) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "log-hashes"           "v" $a.logHashes) -}}
{{- else if eq .Values.mode "send-block-push" -}}
{{- $a := .Values.sendBlockPush -}}
{{- include "subtx-generator.emitFlag" (dict "name" "count"         "v" $a.count) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "interval"      "v" $a.interval) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "duration"      "v" $a.duration) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "subtrees"      "v" $a.subtrees) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "coinbase-size" "v" $a.coinbaseSize) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "bump-size"     "v" $a.bumpSize) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "height-start"  "v" $a.heightStart) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "seed"          "v" $a.seed) -}}
{{- include "subtx-generator.emitFlag" (dict "name" "log-hashes"    "v" $a.logHashes) -}}
{{- end -}}
{{- end -}}

{{/*
Shared pod spec body.
*/}}
{{- define "subtx-generator.podSpec" -}}
serviceAccountName: {{ include "subtx-generator.serviceAccountName" . }}
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
{{- if eq .Values.workloadType "Job" }}
restartPolicy: OnFailure
{{- end }}
containers:
  - name: {{ .Chart.Name }}
    image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
    imagePullPolicy: {{ .Values.image.pullPolicy }}
    {{- with .Values.securityContext }}
    securityContext:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- /* Absolute path: the Dockerfile installs every binary into
           /usr/local/bin, and the distroless image has no shell to fall
           back on PATH resolution. */}}
    command: ["/usr/local/bin/{{ .Values.mode }}"]
    args:
      {{- include "subtx-generator.args" . | nindent 6 }}
    env:
      - name: LOG_FORMAT
        value: {{ .Values.logFormat | default "text" | quote }}
      {{- with .Values.extraEnv }}
      {{- toYaml . | nindent 6 }}
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
