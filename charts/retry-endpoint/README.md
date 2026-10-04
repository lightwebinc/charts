# retry-endpoint Helm chart

> Part of the [**BSV Layered Multicast**](https://github.com/lightwebinc/bsv-multicast) open-source project — see the main repository for the full architecture, design docs, and BRC specifications.

Helm chart for [retry-endpoint](https://github.com/lightwebinc/retry-endpoint) — the BSV multicast retry endpoint that caches frames and retransmits them on NACK.

This repository packages templates, default values, JSON Schema validation, and CI workflows for the retry endpoint. The application source lives in [`retry-endpoint`](https://github.com/lightwebinc/retry-endpoint).

## Install

> The chart references `ghcr.io/lightwebinc/retry-endpoint:<appVersion>` — `appVersion` always tracks a published image tag (see the contract note in [`Chart.yaml`](Chart.yaml)).

```bash
helm install retry-node-1 oci://ghcr.io/lightwebinc/charts/retry-endpoint \
  --version 0.5.3 -n bsv-mcast --create-namespace \
  --set config.nackAddr=2001:db8::24 \
  --set 'nodeSelector.bsv-mcast/node=retry-1'
```

## Critical configuration

### `config.nackAddr` is effectively required

The retry endpoint advertises its NACK listen address via the BRC-126 beacon. Listeners filter ACK/MISS responses by source IPv6, so the advertised address must equal the address the kernel selects for outgoing replies.

Without `config.nackAddr` the binary attempts to auto-detect from the egress interface, which may resolve to a SLAAC address that listeners don't trust. The chart emits a `helm.sh/chart-warnings` pod annotation when `nackAddr` is empty.

In `multus` mode, set `config.nackAddr` to the per-pod fabric IPv6 from `networking.multus.fabricIPv6` (no CIDR mask).

### `config.egressIface` vs `config.mcIface`

The receive iface (`config.mcIface` → `MC_IFACE`, where the endpoint joins the multicast group) and the retransmission **egress** iface (`config.egressIface` → comma-separated NIC list) now default **separately**. On a single-NIC node both stay `eth0`; on a collapsed/multi-NIC edge the retransmit may leave a different interface than the one it receives on, so set `config.egressIface` explicitly rather than assuming it tracks `mcIface`.

### Cache backend (optional)

The frame cache uses the modular `shard-common/cache` backend. Select it with
`config.cacheBackend`:

| Value | Storage | Keys to set | Notes |
|-------|---------|-------------|-------|
| `memory` (default) | in-process | — | per-pod, lost on restart; set `config.redisAddr` to add cross-instance dedup only |
| `redis` | Redis/Valkey/Dragonfly | `config.redisAddr=<host>:6379` | shared frames + dedup |
| `aerospike` | Aerospike Community Edition | `config.aerospikeHosts=<h:3000,…>`, `config.aerospikeNamespace`, `config.aerospikeSet` | auto-sharded; namespace must be provisioned; **TTL floor 1s** |

This chart **does not** bundle a Redis or Aerospike subchart — install the
backend separately (e.g. `bitnami/redis`, or an Aerospike CE StatefulSet). See
[`shard-common/docs/cache-backend.md`](https://github.com/lightwebinc/shard-common/blob/main/docs/cache-backend.md).

## Networking modes

Same as the other charts — `multus` (default), `host`, `unicast` (reserved).

### Collapsed node (hostNetwork)

On a collapsed node — one that runs the multicast routing stack and a co-resident listener — the retry endpoint runs as a `hostNetwork` pod, serving BRC-126 NACK retransmission over the host fabric. Tolerate the data-plane taint and pin with a `nodeSelector` as needed. Worked example: [`examples/collapsed-node.yaml`](examples/collapsed-node.yaml).

```sh
helm install retry-node-1 . -f examples/collapsed-node.yaml \
  --set config.nackAddr=<pod fabric IPv6>
```

`config.nackAddr` stays required (see above); on a multi-NIC edge also set `config.egressIface` to the retransmission NIC when it differs from `config.mcIface`. Note that `config.egressHoplimit` is currently a **no-op** (the binary does not read `EGRESS_HOPLIMIT`) — raise the multicast hop limit at the host level if retransmits must cross a mesh/tunnel hop.

## Values reference

### Pod defaults (v0.2.3+)

The chart ships hardened pod-level defaults: `resources` requests/limits (size memory to your resend window) and a nonroot `podSecurityContext` (uid 65532, seccomp `RuntimeDefault`, matching the distroless image).

See [`values.yaml`](values.yaml). Most flags accepted by the binary are exposed under `.config` — `-rl-sender-rate`/`-rl-sender-window`, `-tee-listen` (`TEE_LISTEN`, loopback frame mirror from a co-resident proxy/listener `-retry-tee`) and `-mc-join-enabled` (`MC_JOIN_ENABLED`, `false` = tee-only ingest, requires `TEE_LISTEN`) are settable via `extraEnv` (all read by the default appVersion; the tee pair needs image ≥ 1.10.1) — including:

- Per-FrameVer cache TTLs (tx / block / subtree / anchor)
- All five rate-limit tiers (IP / sender / sequence / chain / group), plus the opt-in THROTTLED backoff reply: `config.rlThrottleResponse` → `RL_THROTTLE_RESPONSE`
- BRC-126 beacon: tier, preference, interval, scope, flags
- ACK/MISS response suppression
- BRC-132 subtree data caching
- OpenTelemetry OTLP push
- Unified logging: `config.logFormat` (`text`|`json`) → `LOG_FORMAT`, `config.logLevel` → `LOG_LEVEL`, `config.traceSampling` (`0`–`1`) → `TRACE_SAMPLING` (schema-validated); runtime `/loglevel` + SIGHUP. See the [Unified Logging Plan](https://github.com/lightwebinc/shard-common/blob/main/docs/logging.md).
- SSM (RFC 4607) opt-in: `config.sourceMode=ssm` + `config.bindSource` + per-control-group bootstrap
- NACK proxying (cross-domain recovery) opt-in: `config.proxyEnabled=true` + `config.upstreamRetryEndpoints` (recovers cache misses from an upstream endpoint and re-serves this domain). See [BRC-126](https://github.com/lightwebinc/bsv-multicast/blob/main/docs/brc-126-retransmission-protocol.md).

### SSM (Source-Specific Multicast)

`config.sourceMode` defaults to `ssm` (`asm` is the lab/dev fallback). The
binary fails closed at startup under `ssm` until at least one bootstrap
source is configured. When `ssm`:

- `config.bindSource` MUST be the per-pod IPv6 from your
  Multus static IPAM (or Whereabouts, if installed) allocation. The beacon emit socket binds it via
  `net.DialUDP(laddr=...)` so SSM listeners can pre-declare this
  retry-endpoint in their `ssmBootstrap.beacon`. Each replica MUST
  hold a distinct address — anycast / ECMP-shared sources break
  PIM-SSM RPF.
- `config.ssmBootstrap.{manifest,beacon,subtreeAnnounce}` (DNS names
  or IPv6 literals) supply the source lists for the matching control
  groups when retry-endpoint joins them. Resolved via
  `shard-common/bootstrap.Resolver` (fail-closed startup).
- `config.ssmPublishersStatic` is a lab/CI escape hatch for the
  data-plane source list; production uses manifest-driven discovery.

See the [SSM Support Plan](https://github.com/lightwebinc/bsv-multicast/blob/main/DESIGN.md#source-specific-multicast-ssm)
for fabric prerequisites (PIM-SSM, MLDv2, raised `mld_max_msf`).

## Helm test

```bash
helm test retry-node-1 -n bsv-mcast
```

## Release

Gated `release.yml` — `workflow_dispatch` with `confirm: RELEASE` and `production` Environment review.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
