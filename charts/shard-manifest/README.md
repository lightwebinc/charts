# shard-manifest Helm chart

> Part of the [**BSV Layered Multicast**](https://github.com/lightwebinc/bsv-multicast) open-source project — see the main repository for the full architecture, design docs, and BRC specifications.

Helm chart for [`shard-manifest`](https://github.com/lightwebinc/shard-manifest)
— the BRC-139 Shard Manifest Announcement Daemon.

The daemon periodically multicasts a small datagram to the IPv6 beacon
group (`FF0X::B:FFFD`) advertising the local participant's `shard_bits`
configuration and the set of shard groups it has joined. It is purely
informational and does not subscribe to or interpret data-plane traffic.

## Quick start

```bash
helm install my-manifest oci://ghcr.io/lightwebinc/charts/shard-manifest \
  --version 0.3.3 \
  --namespace bsv-mcast --create-namespace \
  --set manifest.shardBits=4 \
  --set manifest.joinedGroups=all \
  --set manifest.roleHint=proxy \
  --set 'manifest.publishers={shard-proxy-headless.svc.cluster.local}'
```

The default `manifest.sourceMode=ssm` requires a non-empty
`manifest.publishers` (the chart fails the install otherwise). For a
lab install without publishers, set `--set manifest.sourceMode=asm`
instead.

## Networking

The chart supports three networking modes:

| `networking.mode` | Use when                                                        |
| ----------------- | --------------------------------------------------------------- |
| `pod` (default)   | Cluster CNI provides IPv6 multicast egress to the beacon group. |
| `host`            | Pin to nodes with the fabric NIC; uses host network namespace.  |
| `multus`          | Attach a NetworkAttachmentDefinition for the fabric NIC.        |

When using `multus`, set `manifest.iface` explicitly to the secondary
interface name (default `net1`).

## Probes

| Endpoint   | Probe       | Default port |
| ---------- | ----------- | ------------ |
| `/healthz` | liveness    | 9091         |
| `/readyz`  | readiness   | 9091         |
| `/metrics` | scrape only | 9091         |

`/readyz` returns 200 once a manifest has been sent within
`2 × manifest.announceInterval` and 503 otherwise (starting / draining /
stale).

## Prometheus

Set `metrics.serviceMonitor.enabled=true` to render a `ServiceMonitor`
(requires the prometheus-operator CRD).

## Values

See [`values.yaml`](values.yaml) for all options, validated against
[`values.schema.json`](values.schema.json).

`manifest.domains` (BRC-148 per-domain plane descriptors → `DOMAINS` env)
requires image >= 0.3.0 — satisfied by the default `appVersion`; an older
`image.tag` pin ignores `DOMAINS`.

### Logging & tracing

`manifest.logFormat` (`json` default for this daemon | `text`) → `LOG_FORMAT`,
`manifest.logLevel` (`info`) → `LOG_LEVEL`, and `manifest.traceSampling` (`0`)
→ `TRACE_SAMPLING`, all schema-validated. The level is runtime-togglable via
`POST /loglevel` and SIGHUP; `traceSampling > 0` (with `otlp.endpoint`) enables
control-plane traces. See the
[Unified Logging Plan](https://github.com/lightwebinc/shard-common/blob/main/docs/logging.md).

### SSM (Source-Specific Multicast)

`manifest.sourceMode` defaults to `ssm` (`asm` is the lab fallback). When `ssm`:

- `manifest.publishers` MUST be a non-empty list of IPv6 literals
  and/or DNS names — typically a headless-Service name fronting the
  shard-proxy pods. Resolved via `shard-common/bootstrap.Resolver`
  and emitted as the `Flags.SourcesValid` payload union (BRC-139
  bit 4). `manifest.publishersRefresh` (default `30s`) sets the DNS
  re-resolve interval; last-good AAAAs are retained on transient
  failures.
- Every emitted manifest sets `Flags.SourceModeSSM` (BRC-139 bit 3)
  so listeners switch their data-plane address derivation to the
  `FF3x::/32` SSM prefix.
- The shard-manifest pod's own per-pod IPv6 (Multus + Whereabouts)
  is what receivers pass to the listener's `-ssm-bootstrap-manifest`
  flag (helm: `config.ssmBootstrap.manifest`) to `(S,G)`-join the
  manifest group under Posture C.

See the [SSM Support Plan](https://github.com/lightwebinc/bsv-multicast/blob/main/DESIGN.md#source-specific-multicast-ssm)
for fabric prerequisites.

### Pilot mode & live re-sharding

`manifest.pilotOnly` marks the announcement as a pilot manifest
(`Flags.PilotOnly` — desired fleet state, implies authoritative), and
`manifest.successor.*` emits the BRC-139 Successor block announcing a
re-shard generation transition. Both depend on consumer-side settings:
pilot replicas must meet the consumers' `-pilot-quorum` (default 2),
and consumers act on the Successor block only with `-live-resharding`
enabled. See the
[Pilot mode](https://github.com/lightwebinc/shard-manifest/blob/main/docs/configuration.md#pilot-mode-brc-139-auto-shard-config)
and
[Live re-sharding](https://github.com/lightwebinc/shard-manifest/blob/main/docs/configuration.md#live-re-sharding-brc-139-successor-block)
sections of the shard-manifest configuration docs.

## License

Apache 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
