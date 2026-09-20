{{- define "shard-listener.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "shard-listener.fullname" -}}
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

{{- define "shard-listener.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "shard-listener.labels" -}}
helm.sh/chart: {{ include "shard-listener.chart" . }}
{{ include "shard-listener.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: bsv-multicast
{{- end -}}

{{- define "shard-listener.selectorLabels" -}}
app.kubernetes.io/name: {{ include "shard-listener.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "shard-listener.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "shard-listener.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "shard-listener.multusAnnotation" -}}
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

{{- define "shard-listener.multicastIf" -}}
{{- if eq .Values.networking.mode "multus" -}}
{{- .Values.networking.multus.interface -}}
{{- else -}}
{{- .Values.config.multicastIf -}}
{{- end -}}
{{- end -}}

{{/*
Container env. NUM_WORKERS is forced to 1 by the chart; the value is not
sourced from .Values.config.numWorkers (which the schema already restricts to 1)
to defend against schema bypass.
*/}}
{{- define "shard-listener.env" -}}
- name: MULTICAST_IF
  value: {{ include "shard-listener.multicastIf" . | quote }}
- name: LISTEN_PORT
  value: {{ .Values.config.listenPort | quote }}
- name: SHARD_BITS
  value: {{ .Values.config.shardBits | quote }}
- name: MC_SCOPE
  value: {{ .Values.config.mcScope | quote }}
- name: MC_GROUP_ID
  value: {{ .Values.config.mcGroupId | quote }}
- name: SOURCE_MODE
  value: {{ .Values.config.sourceMode | default "asm" | quote }}
- name: LISTENER_MODE
  value: {{ .Values.config.mode | default "collapsed" | quote }}
{{- with .Values.config.ssmBootstrap }}
{{- if .manifest }}
- name: SSM_BOOTSTRAP_MANIFEST
  value: {{ join "," .manifest | quote }}
{{- end }}
{{- if .beacon }}
- name: SSM_BOOTSTRAP_BEACON
  value: {{ join "," .beacon | quote }}
{{- end }}
{{- if .subtreeAnnounce }}
- name: SSM_BOOTSTRAP_SUBTREE_ANNOUNCE
  value: {{ join "," .subtreeAnnounce | quote }}
{{- end }}
{{- end }}
{{- if .Values.config.ssmPublishersStatic }}
- name: SSM_PUBLISHERS_STATIC
  value: {{ join "," .Values.config.ssmPublishersStatic | quote }}
{{- end }}
{{- if .Values.config.ssmBootstrapRefresh }}
- name: SSM_BOOTSTRAP_REFRESH
  value: {{ .Values.config.ssmBootstrapRefresh | quote }}
{{- end }}
{{- if .Values.config.localSource }}
- name: LOCAL_SOURCE
  value: {{ .Values.config.localSource | quote }}
{{- end }}
- name: SHARD_INCLUDE
  value: {{ .Values.config.shardInclude | quote }}
- name: SUBTREE_INCLUDE
  value: {{ .Values.config.subtreeInclude | quote }}
- name: SUBTREE_EXCLUDE
  value: {{ .Values.config.subtreeExclude | quote }}
- name: BEEF_TOPICS
  value: {{ .Values.config.beefTopics | default "" | quote }}
- name: BEEF_GROUPS
  value: {{ .Values.config.beefGroups | default "" | quote }}
- name: BEEF_SHARD_BITS
  {{- /* int (not default): Go-template default treats 0 as empty, so
         `| default 4` silently widened an explicit 0 (single group) to 4. */}}
  value: {{ .Values.config.beefShardBits | int | quote }}
- name: BEEF_MAX_OBJECT_BYTES
  value: {{ .Values.config.beefMaxObjectBytes | default 1048576 | int64 | quote }}
- name: BEEF_VERSIONS
  value: {{ .Values.config.beefVersions | default "" | quote }}
- name: BEEF_VERIFY_CONTENT
  value: {{ .Values.config.beefVerifyContent | default false | quote }}
- name: EGRESS_ADDR
  value: {{ .Values.config.egressAddr | quote }}
{{- if .Values.config.deliveryAddrs }}
- name: DELIVERY_ADDRS
  value: {{ join "," .Values.config.deliveryAddrs | quote }}
{{- end }}
- name: EGRESS_PROTO
  value: {{ .Values.config.egressProto | quote }}
- name: STRIP_HEADER
  value: {{ .Values.config.stripHeader | quote }}
- name: MC_EGRESS_ENABLED
  value: {{ .Values.config.mcEgressEnabled | quote }}
{{- if .Values.config.mcEgressEnabled }}
- name: MC_EGRESS_IFACE
  value: {{ .Values.config.mcEgressIface | quote }}
- name: MC_EGRESS_PORT
  value: {{ .Values.config.mcEgressPort | quote }}
- name: MC_EGRESS_SCOPE
  value: {{ .Values.config.mcEgressScope | quote }}
- name: MC_EGRESS_GROUP_ID
  value: {{ .Values.config.mcEgressGroupId | quote }}
- name: MC_EGRESS_HOPLIMIT
  value: {{ .Values.config.mcEgressHopLimit | quote }}
{{- end }}
- name: HEADER_EGRESS_ENABLED
  value: {{ .Values.config.headerEgressEnabled | quote }}
{{- if .Values.config.headerEgressEnabled }}
- name: HEADER_EGRESS_ADDR
  value: {{ .Values.config.headerEgressAddr | quote }}
- name: HEADER_EGRESS_PROTO
  value: {{ .Values.config.headerEgressProto | quote }}
{{- end }}
- name: HEADER_MC_EGRESS_ENABLED
  value: {{ .Values.config.headerMcEgressEnabled | quote }}
{{- if .Values.config.headerMcEgressEnabled }}
- name: HEADER_MC_EGRESS_IFACE
  value: {{ .Values.config.headerMcEgressIface | quote }}
- name: HEADER_MC_EGRESS_PORT
  value: {{ .Values.config.headerMcEgressPort | quote }}
- name: HEADER_MC_EGRESS_SCOPE
  value: {{ .Values.config.headerMcEgressScope | quote }}
- name: HEADER_MC_EGRESS_GROUP_ID
  value: {{ .Values.config.headerMcEgressGroupId | quote }}
- name: HEADER_MC_EGRESS_HOPLIMIT
  value: {{ .Values.config.headerMcEgressHopLimit | quote }}
{{- end }}
- name: RETRY_ENDPOINTS
  value: {{ .Values.config.retryEndpoints | quote }}
- name: NACK_JITTER_MAX
  value: {{ .Values.config.nackJitterMax | quote }}
- name: NACK_BACKOFF_MAX
  value: {{ .Values.config.nackBackoffMax | quote }}
- name: NACK_MAX_RETRIES
  value: {{ .Values.config.nackMaxRetries | quote }}
- name: NACK_GAP_TTL
  value: {{ .Values.config.nackGapTtl | quote }}
- name: BEACON_ENABLED
  value: {{ .Values.config.beaconEnabled | quote }}
- name: BEACON_PORT
  value: {{ .Values.config.beaconPort | quote }}
- name: BEACON_SCOPE
  value: {{ .Values.config.beaconScope | quote }}
{{- if .Values.config.subtreeGroups }}
- name: SUBTREE_GROUPS
  value: {{ .Values.config.subtreeGroups | quote }}
{{- end }}
- name: SUBTREE_GROUP_DEFAULT_TTL
  value: {{ .Values.config.subtreeGroupDefaultTtl | quote }}
- name: ANNOUNCE_SCOPE
  value: {{ .Values.config.announceScope | quote }}
{{- if .Values.config.senderInclude }}
- name: SENDER_INCLUDE
  value: {{ .Values.config.senderInclude | quote }}
{{- end }}
{{- if .Values.config.senderExclude }}
- name: SENDER_EXCLUDE
  value: {{ .Values.config.senderExclude | quote }}
{{- end }}
- name: SUBTREE_DATA_ENABLED
  value: {{ .Values.config.subtreeDataEnabled | quote }}
- name: EGRESS_DEDUP_CAP
  value: {{ .Values.config.egressDedupCap | quote }}
- name: EGRESS_DEDUP_TTL
  value: {{ .Values.config.egressDedupTtl | quote }}
{{- if .Values.config.txidDedupAddr }}
# DEPRECATED — emit only when operator explicitly sets the alias.
- name: TXID_DEDUP_ADDR
  value: {{ .Values.config.txidDedupAddr | quote }}
{{- if .Values.config.txidDedupPrefix }}
- name: TXID_DEDUP_PREFIX
  value: {{ .Values.config.txidDedupPrefix | quote }}
{{- end }}
{{- if .Values.config.txidDedupTtl }}
- name: TXID_DEDUP_TTL
  value: {{ .Values.config.txidDedupTtl | quote }}
{{- end }}
{{- end }}
{{- if .Values.config.deploymentId }}
- name: DEPLOYMENT_ID
  value: {{ .Values.config.deploymentId | quote }}
{{- end }}
{{- if .Values.config.nodeId }}
- name: NODE_ID
  value: {{ .Values.config.nodeId | quote }}
{{- end }}
{{- if .Values.config.egressDedupBackend }}
- name: EGRESS_DEDUP_BACKEND
  value: {{ .Values.config.egressDedupBackend | quote }}
{{- end }}
- name: EGRESS_DEDUP_REDIS_ADDR
  value: {{ .Values.config.egressDedupRedisAddr | quote }}
{{- if .Values.config.egressDedupAerospikeHosts }}
- name: EGRESS_DEDUP_AEROSPIKE_HOSTS
  value: {{ .Values.config.egressDedupAerospikeHosts | quote }}
- name: EGRESS_DEDUP_AEROSPIKE_NAMESPACE
  value: {{ .Values.config.egressDedupAerospikeNamespace | quote }}
- name: EGRESS_DEDUP_AEROSPIKE_SET
  value: {{ .Values.config.egressDedupAerospikeSet | quote }}
{{- end }}
- name: EGRESS_DEDUP_PREFIX
  value: {{ .Values.config.egressDedupPrefix | quote }}
- name: EGRESS_DEDUP_TTL_REDIS
  value: {{ .Values.config.egressDedupTtlRedis | quote }}
- name: EGRESS_DEDUP_LOCAL_CAP
  value: {{ .Values.config.egressDedupLocalCap | int64 | quote }}
{{- if or .Values.config.ingressSetRedisAddr .Values.config.ingressSetAerospikeHosts (.Values.config.ingressSetBackend | default "" | ne "") }}
{{- if .Values.config.ingressSetBackend }}
- name: INGRESS_SET_BACKEND
  value: {{ .Values.config.ingressSetBackend | quote }}
{{- end }}
{{- if .Values.config.ingressSetRedisAddr }}
- name: INGRESS_SET_REDIS_ADDR
  value: {{ .Values.config.ingressSetRedisAddr | quote }}
{{- end }}
{{- if .Values.config.ingressSetAerospikeHosts }}
- name: INGRESS_SET_AEROSPIKE_HOSTS
  value: {{ .Values.config.ingressSetAerospikeHosts | quote }}
- name: INGRESS_SET_AEROSPIKE_NAMESPACE
  value: {{ .Values.config.ingressSetAerospikeNamespace | quote }}
- name: INGRESS_SET_AEROSPIKE_SET
  value: {{ .Values.config.ingressSetAerospikeSet | quote }}
{{- end }}
- name: INGRESS_SET_PREFIX
  value: {{ .Values.config.ingressSetPrefix | quote }}
- name: INGRESS_SET_TTL
  value: {{ .Values.config.ingressSetTtl | quote }}
- name: INGRESS_SET_LOCAL_CAP
  value: {{ .Values.config.ingressSetLocalCap | int64 | quote }}
{{- end }}
# NUM_WORKERS is intentionally hardcoded to 1 by the chart.
# See values.yaml comment and the SO_REUSEPORT multicast notes.
- name: NUM_WORKERS
  value: "1"
- name: VERIFY_PAYLOAD_HASH
  value: {{ .Values.config.verifyPayloadHash | quote }}
# Block control-plane gate. Binary default is TRUE, so these are emitted
# UNCONDITIONALLY — an omitted var would leave `requireBlockPow: false` a
# silent no-op. An empty value falls back to the binary default.
- name: REQUIRE_BLOCK_POW
  value: {{ if kindIs "bool" .Values.config.requireBlockPow }}{{ .Values.config.requireBlockPow | quote }}{{ else }}"true"{{ end }}
- name: MIN_POW_BITS
  value: {{ .Values.config.minPowBits | default "0" | quote }}
- name: DRAIN_TIMEOUT
  value: {{ .Values.config.drainTimeout | quote }}
- name: DEBUG
  value: {{ .Values.config.debug | quote }}
- name: LOG_FORMAT
  value: {{ .Values.config.logFormat | quote }}
- name: LOG_LEVEL
  value: {{ .Values.config.logLevel | quote }}
{{- if .Values.config.traceSampling }}
- name: TRACE_SAMPLING
  value: {{ .Values.config.traceSampling | quote }}
{{- end }}
- name: METRICS_ADDR
  value: {{ .Values.config.metricsAddr | quote }}
{{- if .Values.config.instanceId }}
- name: INSTANCE_ID
  value: {{ .Values.config.instanceId | quote }}
{{- end }}
{{- if .Values.config.otlpEndpoint }}
- name: OTLP_ENDPOINT
  value: {{ .Values.config.otlpEndpoint | quote }}
- name: OTLP_INTERVAL
  value: {{ .Values.config.otlpInterval | quote }}
{{- end }}
{{- if .Values.config.autoShardConfig }}
- name: MANIFEST_CONSUMER_ENABLED
  value: {{ .Values.config.autoShardConfig.enabled | quote }}
- name: MANIFEST_BOOTSTRAP
  value: {{ .Values.config.autoShardConfig.bootstrap | quote }}
- name: PILOT_QUORUM
  value: {{ .Values.config.autoShardConfig.pilotQuorum | quote }}
- name: PILOT_HYSTERESIS
  value: {{ .Values.config.autoShardConfig.pilotHysteresis | quote }}
- name: SHARD_INCLUDE_FROM_MANIFEST
  value: {{ .Values.config.autoShardConfig.shardIncludeFromManifest | quote }}
- name: LIVE_RESHARDING
  value: {{ .Values.config.autoShardConfig.liveResharding | quote }}
- name: BRIDGING_WINDOW
  value: {{ .Values.config.autoShardConfig.bridgingWindow | quote }}
{{- end }}
{{- with .Values.extraEnv }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Shared pod spec body so deployment.yaml and daemonset.yaml stay in sync.
*/}}
{{- define "shard-listener.podSpec" -}}
serviceAccountName: {{ include "shard-listener.serviceAccountName" . }}
{{- with .Values.terminationGracePeriodSeconds }}
terminationGracePeriodSeconds: {{ . }}
{{- end }}
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
    env:
      {{- include "shard-listener.env" . | nindent 6 }}
    ports:
      - name: udp-mcast
        containerPort: {{ .Values.config.listenPort }}
        protocol: UDP
      - name: nack
        containerPort: {{ .Values.config.beaconPort }}
        protocol: UDP
      - name: metrics
        containerPort: {{ .Values.service.metricsPort }}
        protocol: TCP
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
