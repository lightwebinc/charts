{{- define "retry-endpoint.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "retry-endpoint.fullname" -}}
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

{{- define "retry-endpoint.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "retry-endpoint.labels" -}}
helm.sh/chart: {{ include "retry-endpoint.chart" . }}
{{ include "retry-endpoint.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: bsv-multicast
{{- end -}}

{{- define "retry-endpoint.selectorLabels" -}}
app.kubernetes.io/name: {{ include "retry-endpoint.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "retry-endpoint.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "retry-endpoint.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "retry-endpoint.multusAnnotation" -}}
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

{{- define "retry-endpoint.iface" -}}
{{- if eq .Values.networking.mode "multus" -}}
{{- .Values.networking.multus.interface -}}
{{- else -}}
{{- .Values.config.mcIface -}}
{{- end -}}
{{- end -}}

{{- define "retry-endpoint.env" -}}
- name: MC_IFACE
  value: {{ include "retry-endpoint.iface" . | quote }}
- name: EGRESS_IFACE
  value: {{ .Values.config.egressIface | default (include "retry-endpoint.iface" .) | quote }}
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
{{- if .Values.config.bindSource }}
- name: BIND_SOURCE
  value: {{ .Values.config.bindSource | quote }}
{{- end }}
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
- name: EGRESS_PORT
  value: {{ .Values.config.egressPort | quote }}
{{- if kindIs "bool" .Values.config.egressMulticastLoop }}
- name: EGRESS_MULTICAST_LOOP
  value: {{ .Values.config.egressMulticastLoop | quote }}
{{- end }}
{{- if .Values.config.egressHoplimit }}
- name: EGRESS_HOPLIMIT
  value: {{ .Values.config.egressHoplimit | quote }}
{{- end }}
- name: DEDUP_WINDOW
  value: {{ .Values.config.dedupWindow | quote }}
{{- if .Values.config.proxyEnabled }}
- name: PROXY_ENABLED
  value: "true"
- name: UPSTREAM_RETRY_ENDPOINTS
  value: {{ join "," .Values.config.upstreamRetryEndpoints | quote }}
- name: PROXY_TIMEOUT
  value: {{ .Values.config.proxyTimeout | quote }}
- name: PROXY_MAX_ENDPOINTS
  value: {{ .Values.config.proxyMaxEndpoints | quote }}
- name: PROXY_DEDUP_WINDOW
  value: {{ .Values.config.proxyDedupWindow | quote }}
- name: PROXY_WORKERS
  value: {{ .Values.config.proxyWorkers | quote }}
- name: PROXY_QUEUE
  value: {{ .Values.config.proxyQueue | quote }}
{{- end }}
- name: NACK_PORT
  value: {{ .Values.config.nackPort | quote }}
{{- if .Values.config.nackAddr }}
- name: NACK_ADDR
  value: {{ .Values.config.nackAddr | quote }}
{{- end }}
- name: NACK_WORKERS
  value: {{ .Values.config.nackWorkers | quote }}
- name: CACHE_BACKEND
  value: {{ .Values.config.cacheBackend | quote }}
{{- if .Values.config.redisAddr }}
- name: REDIS_ADDR
  value: {{ .Values.config.redisAddr | quote }}
{{- end }}
{{- if .Values.config.aerospikeHosts }}
- name: AEROSPIKE_HOSTS
  value: {{ .Values.config.aerospikeHosts | quote }}
- name: AEROSPIKE_NAMESPACE
  value: {{ .Values.config.aerospikeNamespace | quote }}
- name: AEROSPIKE_SET
  value: {{ .Values.config.aerospikeSet | quote }}
{{- end }}
- name: CACHE_DIAL_TIMEOUT
  value: {{ .Values.config.cacheDialTimeout | quote }}
- name: CACHE_OP_TIMEOUT
  value: {{ .Values.config.cacheOpTimeout | quote }}
- name: CACHE_TTL
  value: {{ .Values.config.cacheTtl | quote }}
- name: CACHE_TTL_TX
  value: {{ .Values.config.cacheTtlTx | quote }}
- name: CACHE_TTL_BLOCK
  value: {{ .Values.config.cacheTtlBlock | quote }}
- name: CACHE_TTL_SUBTREE
  value: {{ .Values.config.cacheTtlSubtree | quote }}
- name: CACHE_TTL_BEEF
  value: {{ .Values.config.cacheTtlBeef | default "60s" | quote }}
- name: BEEF_ENABLED
  value: {{ .Values.config.beefEnabled | default false | quote }}
- name: BEEF_SHARD_BITS
  {{- /* int (not default): Go-template default treats 0 as empty, so
         `| default 4` silently widened an explicit 0 (single group) to 4. */}}
  value: {{ .Values.config.beefShardBits | int | quote }}
- name: CACHE_TTL_ANCHOR
  value: {{ .Values.config.cacheTtlAnchor | quote }}
- name: CACHE_MAX_KEYS
  value: {{ .Values.config.cacheMaxKeys | quote }}
- name: RL_IP_RATE
  value: {{ .Values.config.rlIpRate | quote }}
- name: RL_IP_BURST
  value: {{ .Values.config.rlIpBurst | quote }}
- name: RL_CHAIN_RATE
  value: {{ .Values.config.rlChainRate | quote }}
- name: RL_CHAIN_WINDOW
  value: {{ .Values.config.rlChainWindow | quote }}
- name: RL_SEQUENCE_MAX
  value: {{ .Values.config.rlSequenceMax | quote }}
- name: RL_SEQUENCE_WINDOW
  value: {{ .Values.config.rlSequenceWindow | quote }}
- name: RL_GROUP_RATE
  value: {{ .Values.config.rlGroupRate | quote }}
- name: RL_GROUP_BURST
  value: {{ .Values.config.rlGroupBurst | quote }}
- name: RL_THROTTLE_RESPONSE
  value: {{ .Values.config.rlThrottleResponse | default false | quote }}
- name: BEACON_ENABLED
  value: {{ .Values.config.beaconEnabled | quote }}
- name: BEACON_TIER
  value: {{ .Values.config.beaconTier | quote }}
- name: BEACON_PREFERENCE
  value: {{ .Values.config.beaconPreference | quote }}
- name: BEACON_INTERVAL
  value: {{ .Values.config.beaconInterval | quote }}
- name: BEACON_SCOPE
  value: {{ .Values.config.beaconScope | quote }}
- name: BEACON_FLAGS_UNICAST
  value: {{ .Values.config.beaconFlagsUnicast | quote }}
- name: BEACON_FLAGS_MULTICAST
  value: {{ .Values.config.beaconFlagsMulticast | quote }}
- name: BEACON_FLAGS_DRAINING
  value: {{ .Values.config.beaconFlagsDraining | quote }}
- name: SUPPRESS_ACK
  value: {{ .Values.config.suppressAck | quote }}
- name: SUPPRESS_MISS
  value: {{ .Values.config.suppressMiss | quote }}
- name: SUBTREE_DATA_ENABLED
  value: {{ .Values.config.subtreeDataEnabled | quote }}
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
{{- with .Values.extraEnv }}
{{ toYaml . }}
{{- end }}
{{- end -}}
