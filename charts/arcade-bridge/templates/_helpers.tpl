{{- define "arcade-bridge.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "arcade-bridge.fullname" -}}
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

{{- define "arcade-bridge.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "arcade-bridge.labels" -}}
helm.sh/chart: {{ include "arcade-bridge.chart" . }}
{{ include "arcade-bridge.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: bsv-multicast
app.kubernetes.io/component: {{ .Values.config.mode | default "all" }}
{{- end -}}

{{- define "arcade-bridge.selectorLabels" -}}
app.kubernetes.io/name: {{ include "arcade-bridge.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "arcade-bridge.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "arcade-bridge.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
port — the port a listen address binds, so containerPort/Service port can never
drift from the flag the process actually gets. Input is the raw listen string
("[::]:9143", "192.0.2.10:9165", ":9167"); output is the trailing number.
*/}}
{{- define "arcade-bridge.port" -}}
{{- $addr := . | toString -}}
{{- $p := regexFind "[0-9]+$" $addr -}}
{{- if not $p -}}
{{- fail (printf "arcade-bridge: cannot derive a port from listen address %q — it must end in :<port>" $addr) -}}
{{- end -}}
{{- $p -}}
{{- end -}}

{{/*
facadeEnabled — non-empty when the facade actually starts: edgeIngress set and
mode != sink, exactly the binary's own condition. Everything facade-shaped
(flags, containerPort, Service, NetworkPolicy rule) keys off this so the chart
never advertises a listener the process does not open.
*/}}
{{- define "arcade-bridge.facadeEnabled" -}}
{{- $c := .Values.config -}}
{{- if and (ne ($c.mode | default "all") "sink") $c.edgeIngress -}}true{{- end -}}
{{- end -}}

{{/*
apiPrefix / announceUrl — the URL merkle-service is told to fetch from, built
the same way the binary builds it: TrimRight(advertise, "/") + prefix. This is
the value that silently breaks proof ingest when wrong, so NOTES.txt prints it
and validate rejects the doubled form.
*/}}
{{- define "arcade-bridge.apiPrefix" -}}
{{- printf "/%s" (trimAll "/" (.Values.config.apiPrefix | default "/api/v1")) -}}
{{- end -}}

{{- define "arcade-bridge.announceUrl" -}}
{{- printf "%s%s" (trimSuffix "/" (.Values.config.advertise | default "")) (include "arcade-bridge.apiPrefix" .) -}}
{{- end -}}

{{/*
validate — install-time refusal for configurations that are wrong in a way the
running process would not tell you about (or would only tell you by exiting 2
into a crashloop). Warnings, not failures, live in NOTES.txt.
*/}}
{{- define "arcade-bridge.validate" -}}
{{- $c := .Values.config -}}
{{- $sink := eq ($c.mode | default "all") "sink" -}}
{{- $adv := trimSuffix "/" ($c.advertise | default "") -}}
{{- $prefix := include "arcade-bridge.apiPrefix" . -}}
{{- if and $adv (hasSuffix $prefix $adv) -}}
{{- fail (printf "arcade-bridge: config.advertise (%q) already ends with config.apiPrefix (%q). The announced URL is advertise + apiPrefix, so this announces %q — merkle-service's subtree and block fetches would 404 against a doubled path while every announcement kept succeeding, and every 404 charges this bridge's fetch-health breaker. Drop the prefix from config.advertise." $adv $prefix (printf "%s%s" $adv $prefix)) -}}
{{- end -}}
{{- if and $sink $c.edgeIngress -}}
{{- fail "arcade-bridge: config.edgeIngress is set with config.mode=sink. The facade never starts in sink mode (sink's whole point is touching nothing), so the binary would silently ignore it — Arcade would be pointed at a facade that does not exist. Either drop config.edgeIngress or set config.mode=all." -}}
{{- end -}}
{{- if and $c.hydrateAsset (not (include "arcade-bridge.facadeEnabled" .)) -}}
{{- fail "arcade-bridge: config.hydrateAsset is set but the facade is off (config.edgeIngress is empty or config.mode is sink). Hydration only runs inside the facade, so the binary would silently ignore this value. Set config.edgeIngress to enable the facade, or drop config.hydrateAsset." -}}
{{- end -}}
{{- end -}}

{{/*
flag — render one CLI flag from a values key.
  bool true            -> "-name"        (bare)
  bool false / null    -> omitted        (binary default applies)
  "" / "0s" / 0        -> omitted        (binary default applies)
  anything else        -> "-name=value"
Flags whose ZERO VALUE MEANS SOMETHING cannot go through here — omission would
silently restore the binary's non-zero default. Those are written out
unconditionally in .args below.
*/}}
{{- define "arcade-bridge.flag" -}}
{{- $name := .name -}}
{{- $v := .v -}}
{{- if kindIs "bool" $v -}}
{{- if $v }}
- {{ printf "-%s" $name | quote }}
{{- end -}}
{{- else if kindIs "string" $v -}}
{{- if and (ne $v "") (ne $v "0s") }}
- {{ printf "-%s=%s" $name $v | quote }}
{{- end -}}
{{- else -}}
{{- if and $v (ne (printf "%v" $v) "0") }}
- {{ printf "-%s=%d" $name (int64 $v) | quote }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
joinFlag — a list rendered as ONE comma-joined flag. The binary takes -kafka
and -edge-ingress as single comma-separated values and splits them itself
(unlike teranode-bridge, whose flags repeat), so the chart models them as YAML
lists for `--set config.kafka[0]=...` ergonomics and joins here.
*/}}
{{- define "arcade-bridge.joinFlag" -}}
{{- if .v }}
- {{ printf "-%s=%s" .name (join "," .v) | quote }}
{{- end -}}
{{- end -}}

{{- define "arcade-bridge.args" -}}
{{- $c := .Values.config -}}
{{- $sink := eq ($c.mode | default "all") "sink" -}}
{{- $facade := include "arcade-bridge.facadeEnabled" . -}}
{{/* Delivery lanes */}}
{{- include "arcade-bridge.flag" (dict "name" "subtree-listen" "v" $c.subtreeListen) -}}
{{- include "arcade-bridge.flag" (dict "name" "block-listen" "v" $c.blockListen) -}}
{{- include "arcade-bridge.flag" (dict "name" "max-object" "v" $c.maxObject) -}}
{{- /* Retrieval plane: runs in EVERY mode, sink included — the binary starts
       it unconditionally and /readyz requires it. */ -}}
{{- include "arcade-bridge.flag" (dict "name" "retrieval-listen" "v" $c.retrievalListen) -}}
{{- include "arcade-bridge.flag" (dict "name" "api-prefix" "v" $c.apiPrefix) -}}
{{- /* mode=sink announces nothing, so the announce flags are dropped outright:
       a sink that lists an -advertise or a -kafka reads like a bridge that
       lost its stack. */ -}}
{{- if not $sink -}}
{{/* Announce targets */}}
{{- include "arcade-bridge.flag" (dict "name" "advertise" "v" (trimSuffix "/" ($c.advertise | default ""))) -}}
{{- include "arcade-bridge.joinFlag" (dict "name" "kafka" "v" $c.kafka) -}}
{{- include "arcade-bridge.flag" (dict "name" "subtree-topic" "v" $c.subtreeTopic) -}}
{{- include "arcade-bridge.flag" (dict "name" "block-topic" "v" $c.blockTopic) -}}
{{- include "arcade-bridge.flag" (dict "name" "peer-id" "v" $c.peerId) -}}
{{- include "arcade-bridge.flag" (dict "name" "client-name" "v" $c.clientName) -}}
{{- end -}}
{{- /* Facade: only when it actually starts (edgeIngress set, mode != sink) so
       the arg vector never suggests a listener the process does not open. */ -}}
{{- if $facade -}}
{{- include "arcade-bridge.flag" (dict "name" "facade-listen" "v" $c.facadeListen) -}}
{{- include "arcade-bridge.joinFlag" (dict "name" "edge-ingress" "v" $c.edgeIngress) -}}
{{- include "arcade-bridge.flag" (dict "name" "edge-tx-port" "v" $c.edgeTxPort) -}}
{{- include "arcade-bridge.flag" (dict "name" "hydrate-asset" "v" $c.hydrateAsset) -}}
{{- end -}}
{{- /* Cache */ -}}
{{- include "arcade-bridge.flag" (dict "name" "cache-bytes" "v" $c.cacheBytes) -}}
{{- include "arcade-bridge.flag" (dict "name" "cache-ttl" "v" $c.cacheTtl) -}}
{{/* Process */}}
{{- include "arcade-bridge.flag" (dict "name" "mode" "v" $c.mode) -}}
{{- /* "0s" = periodic stats OFF; omission would restore the binary's 1m */ -}}
{{- $stats := "1m" -}}
{{- if and (not (kindIs "invalid" $c.statsEvery)) (ne ($c.statsEvery | toString) "") }}{{ $stats = ($c.statsEvery | toString) }}{{ end }}
- {{ printf "-stats-every=%s" $stats | quote }}
{{- /* metrics.enabled false => explicitly empty, the only value that turns the
       listener (and with it /healthz and /readyz) off */ -}}
{{- if .Values.metrics.enabled }}
- {{ printf "-metrics-addr=%s" ($c.metricsAddr | default "[::]:9167") | quote }}
{{- else }}
- "-metrics-addr="
{{- end }}
{{- range .Values.extraArgs }}
- {{ . | quote }}
{{- end -}}
{{- end -}}
