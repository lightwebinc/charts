# shard-listener Helm chart

> Part of the [**BSV Layered Multicast**](https://github.com/lightwebinc/bsv-multicast) open-source project — see the main repository for the full architecture, design docs, and BRC specifications.

Helm chart for [shard-listener](https://github.com/lightwebinc/shard-listener) — the IPv6 multicast shard subscriber in the BSV multicast transaction distribution pipeline.

This repository packages templates, default values, JSON Schema validation, and CI workflows for the listener. The application source lives in [`shard-listener`](https://github.com/lightwebinc/shard-listener).

## Install

> The chart references `ghcr.io/lightwebinc/shard-listener:<appVersion>` — `appVersion` always tracks a published image tag (see the contract note in [`Chart.yaml`](Chart.yaml)).

```bash
# DaemonSet over a labeled set of fabric nodes (recommended)
helm install listener oci://ghcr.io/lightwebinc/charts/shard-listener \
  --version 0.7.5 -n bsv-mcast --create-namespace \
  --set workloadType=DaemonSet \
  --set 'nodeSelector.bsv-mcast/role=listener' \
  --set config.retryEndpoints='[2001:db8::24]:9300\,[2001:db8::25]:9300\,[2001:db8::26]:9300'

# Single-replica Deployment
helm install listener . -n bsv-mcast --create-namespace \
  --set networking.mode=host
```

## Workload type

| `workloadType` | Use case |
|---|---|
| `Deployment` (default) | Small clusters, one or a few listener replicas; `replicaCount` controls quantity. |
| `DaemonSet` | One listener pod per labeled fabric node; recommended for production. |

## Networking modes

`multus` (default) and `host`, as in the proxy chart. `unicast` is schema-accepted but currently identical to running on the primary CNI only — the listener templates apply no unicast-specific handling. See [multicast-kube-infra](https://github.com/lightwebinc/multicast-kube-infra).

## Important constraint — `NUM_WORKERS=1`

The Linux kernel delivers each multicast datagram to **all** sockets in a SO_REUSEPORT group with no load balancing. Multiple listener workers cause N-fold frame duplication. The chart hardcodes `NUM_WORKERS=1` in the rendered Deployment regardless of `config.numWorkers`, and `values.schema.json` rejects any value other than `1`.

## Values reference

### Pod defaults (v0.3.2+)

The chart ships hardened pod-level defaults: `resources` requests/limits (per node when running as a DaemonSet), a nonroot `podSecurityContext` (uid 65532, seccomp `RuntimeDefault`), and `terminationGracePeriodSeconds: 30` — keep it `>= config.drainTimeout` so in-flight NACK recovery completes on shutdown. The default `workloadType: Deployment` is single-node/test-only; production needs `DaemonSet` plus a fabric `nodeSelector` (see the warning in [`values.yaml`](values.yaml)).

See [`values.yaml`](values.yaml). Most flags accepted by the listener binary are exposed under `.config` — the NACK tail-probe family (`-nack-backoff-base`, `-nack-tail-probe*`, `-nack-max-flows`, `-nack-max-forward-jump`), `-rebucket-relay` and `-retry-tee` (`RETRY_TEE`, receive-side mirror to a co-resident retry-endpoint `-tee-listen`) are settable via `extraEnv` (all honoured by the default appVersion; on an older `image.tag` pin `-nack-tail-probe*` requires ≥ 1.15.0, `-rebucket-relay` ≥ 1.10.1 and `-retry-tee` ≥ 1.24.1) — including:

- `config.mode` — P3b role split (`collapsed`|`receiver`|`delivery`; requires appVersion ≥ 1.6.9) and `config.deliveryAddrs` — receiver-mode delivery fan-out target set (requires appVersion ≥ 1.7.0)
- Multicast egress / domain bridging (BRC-128)
- Block header egress — BRC-135 frames emitted from BRC-131 announcements (unicast + multicast)
- Block control-plane PoW gate: `config.requireBlockPow` (default `true`) + `config.minPowBits` (see below)
- BRC-127 subtree group subscriptions
- BRC-132 subtree data caching
- Cross-listener TxID dedup via a modular cache backend (see below)
- Sender allow/deny CIDR lists
- Beacon-driven retry endpoint discovery (BRC-126)
- SSM (RFC 4607) opt-in: `config.sourceMode=ssm` + per-control-group bootstrap source lists
- Unified logging: `config.logFormat` (`text`|`json`) → `LOG_FORMAT`, `config.logLevel` → `LOG_LEVEL`, `config.traceSampling` (`0`–`1`) → `TRACE_SAMPLING` (schema-validated). Set `logFormat: json` for fleet aggregation; level is runtime-togglable via `POST /loglevel` + SIGHUP. See the [Unified Logging Plan](https://github.com/lightwebinc/shard-common/blob/main/docs/logging.md).

### Block PoW gate (default ON)

| Key | Env var | Default | Notes |
|-----|---------|---------|-------|
| `config.requireBlockPow` | `REQUIRE_BLOCK_POW` | `true` | Gate BRC-131 block announces on real header proof-of-work and drop any deprecated standalone BRC-133 coinbase frame (counted as `coinbase_legacy`; the coinbase rides inline in the block) before fan-out. Announces arriving over multicast bypass the local proxy, so the edge re-validates. **BRC-135 header egress is fed downstream of this gate** — disabling it also stops validating what the header lane emits. Binary default is `true` since image 1.16.0 — satisfied by the default appVersion (older pins default `false`; the env is rendered unconditionally, so the chart value governs either way). |
| `config.minPowBits` | `MIN_POW_BITS` | `"0"` | Difficulty floor in Bitcoin compact nBits. `"0"` = header self-consistency only. mainnet/testnet `"0x1d00ffff"`, devnet `"0x207fffff"`. |

Both env vars are rendered **unconditionally**, so `requireBlockPow: false` really
turns the gate off — with a conditional (omit-when-false) rendering the binary's
`true` default would silently win. `minPowBits` hex MUST carry the `0x` prefix: a
bare `"1d00ffff"` is parsed as decimal and the listener refuses to start
(`values.schema.json` rejects it at install time).

### Dedup cache backend

The egress dedup gate and the courtesy ingress mark each use the modular
`shard-common/cache` backend, selected independently:

- **Egress:** `config.egressDedupBackend` (`redis`|`aerospike`|`memory`|`none`;
  empty infers `redis` when `egressDedupRedisAddr` is set, else `none`). For
  aerospike set `config.egressDedupAerospikeHosts` (+ `…Namespace`, `…Set`).
- **Ingress mark:** the `config.ingressSet*` equivalents. `ingressSetPrefix`
  MUST match the proxy chart's `config.txidDedup.prefix`.

Aerospike namespaces must be provisioned on the cluster; TTL floor is 1s. When
passing comma-separated `…AerospikeHosts` via `--set`, escape the commas or use
a values file. See
[`shard-common/docs/cache-backend.md`](https://github.com/lightwebinc/shard-common/blob/main/docs/cache-backend.md).

### SSM (Source-Specific Multicast)

`config.sourceMode` defaults to `ssm`; `asm` remains a lab/dev fallback
(RFC 8815 deprecates inter-domain ASM). With `ssm`, supply at least one
of `config.ssmBootstrap.{manifest,beacon,subtreeAnnounce}` (DNS names
or IPv6 literals — headless-Service names are the production pattern).
Each list renders to its own `SSM_BOOTSTRAP_*` env var and is resolved
via `shard-common/bootstrap.Resolver` (fail-closed startup; last-good
retention on transient refresh failures). `config.ssmPublishersStatic`
is a lab/CI escape hatch for the data-plane source list; production
must use manifest-driven discovery. The fail-closed check lives in the
binary, not in chart validation: at startup the listener refuses to run
with `sourceMode=ssm` and no bootstrap or static list, so an install
without one CrashLoops until sources are set. See the
[SSM Support Plan](https://github.com/lightwebinc/bsv-multicast/blob/main/DESIGN.md#source-specific-multicast-ssm)
for fabric prerequisites (PIM-SSM, MLDv2, raised `mld_max_msf`).

On a collapsed node (proxy and listener co-located), set
`config.localSource` to the co-located proxy's `BIND_SOURCE`. That source
is dropped from every roster-driven `(S,G)` join; joining the node's own
source on the PIM interface would install an `iif==oif` mroute and loop
originated frames until hop-limit death. When set, this listener does not
receive own-node frames via multicast — mirror locally where own-source
completeness matters.

### BRC-139 auto-shard-config (opt-in)

`config.autoShardConfig` exposes the BRC-139 manifest consumer. Off by
default; manual `config.shardBits`/`sourceMode`/`shardInclude` always win.
When `enabled: true` the listener decodes manifests off its beacon socket
and adopts `ShardBits`/`SourceMode` once `pilotQuorum` distinct
authoritative announcers agree for the hysteresis window. With
`shardIncludeFromManifest: true` it additionally joins pilot groups at
runtime (`union(shardInclude, pilot groups)`).

| Key | Env var | Default | Notes |
|-----|---------|---------|-------|
| `enabled` | `MANIFEST_CONSUMER_ENABLED` | `false` | master switch |
| `bootstrap` | `MANIFEST_BOOTSTRAP` | `optional` | `required` fails closed: no data-plane bind until quorum |
| `pilotQuorum` | `PILOT_QUORUM` | `2` | min distinct authoritative announcers |
| `pilotHysteresis` | `PILOT_HYSTERESIS` | `0s` | `0s` ⇒ 2 × AnnounceInterval |
| `shardIncludeFromManifest` | `SHARD_INCLUDE_FROM_MANIFEST` | `false` | additive auto-join to pilot groups |
| `liveResharding` | `LIVE_RESHARDING` | `false` | bridging vs restart-on-adopt |
| `bridgingWindow` | `BRIDGING_WINDOW` | `0s` | `0s` ⇒ honour pilot `TransitionEpoch` |

See the [Automatic Shard Configuration Plan](https://github.com/lightwebinc/bsv-multicast/blob/main/DESIGN.md#automatic-shard-configuration).

## Helm test

```bash
helm test listener -n bsv-mcast
```

## Release

`release.yml` is gated — `workflow_dispatch` with `confirm: RELEASE` and a `production` GitHub Environment review.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
