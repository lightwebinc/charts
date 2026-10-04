# arcade-bridge Helm chart

> Part of the [**BSV Layered Multicast**](https://github.com/lightwebinc/bsv-multicast)
> open-source project. See the main repository for the full architecture, design docs, and BRC
> specifications.

Helm chart for [arcade-bridge](https://github.com/lightwebinc/arcade-bridge): the landing-tier
bridge that runs an **unmodified** Arcade v2 + merkle-service stack with a multicast delivery fabric
as its transport.

This repository packages templates, default values, JSON Schema validation, and CI workflows for
the bridge. The application source lives in
[`arcade-bridge`](https://github.com/lightwebinc/arcade-bridge).

The binary is configured by **CLI flags only** (no environment fallback, no config file), so the
Deployment renders `args:` from `.config` in [`values.yaml`](values.yaml). Empty / `0` / `"0s"` /
`false` values are omitted so the binary default applies; anything unmodelled goes in `extraArgs`.

## What it deploys

| Plane | Port (default) | Who dials it |
|---|---|---|
| subtree lane (BRC-143) | `9143` | the delivery side |
| block lane (BRC-144) | `9144` | the delivery side |
| retrieval plane | `9165` | **merkle-service**, fetching what was announced |
| facade (`POST /txs`) | `9166` | **Arcade's propagation** (only when enabled) |
| metrics / health | `9167` | Prometheus, kubelet |
| up-tunnel (out) | `8725` | this bridge to the fabric's open tx ingress |

Two independent halves:

```text
  feed   : fabric ==push==> lanes -> cache -> Kafka announce -> merkle-service
                                 \-> retrieval plane <- fetch <- merkle-service
  facade : Arcade -> POST /txs -> parse -> ensure EF -> hydrate
                                 -> one bare EF stream up-tunnel -> fabric ingress :8725
```

The feed makes merkle-service's ordinary announce-and-fetch pipeline local: the objects were
already pushed down the lanes, so the bridge announces `{hash, dataHubUrl}` pointing at its own
retrieval plane and the "fetch" never leaves the box. The facade serves the Teranode-shaped
`POST /txs` surface Arcade already speaks and forwards **one** copy of each transaction up the
tunnel; the fabric fans it out to every miner-tier consumer instead of Arcade's O(N) unicast.

Up to three Services, because the audiences differ: `<release>-arcade-bridge` carries the delivery
lanes plus metrics, `<release>-arcade-bridge-retrieval` is the merkle-service-facing fetch address,
and `<release>-arcade-bridge-facade` is Arcade's submit address (rendered only when the facade is
enabled). Service and container ports are **derived from the `config.*Listen` flags**, so a port
can never drift from what the process actually binds.

No ConfigMap: there is nothing to mount, the flags are the entire configuration surface.

Unlike teranode-bridge, there is no tx delivery lane, no submitter role, and no reverse
(blockchain) path here: an Arcade operator is a plain delivery consumer. Transactions go **up**
through the facade only.

## Install

> The chart references `ghcr.io/lightwebinc/arcade-bridge:<appVersion>`; `appVersion` always
> tracks a published image tag (see the contract note in [`Chart.yaml`](Chart.yaml)). The image is
> public.

```bash
# OCI registry: minimum viable feed (proof ingest through the fabric)
helm install bridge oci://ghcr.io/lightwebinc/charts/arcade-bridge \
  --version 0.1.1 -n bsv-mcast --create-namespace \
  --set config.advertise=http://192.0.2.10:9165 \
  --set config.kafka[0]=192.0.2.10:19092

# Or from a local clone: full landing tier, feed plus facade
helm install bridge . -n bsv-mcast -f examples/landing-tier.yaml \
  --set config.advertise=http://192.0.2.10:9165

# Sink: burn in a delivery slot with no stack at all
helm install burn-in . -n bsv-mcast -f examples/sink.yaml
```

`helm install` prints the exact URL that will be announced, the state of the facade, and a warning
for every required flag left empty. Read it.

## `config.advertise`: the one value that fails silently

`-advertise` is the base URL **merkle-service** dials to fetch an announced subtree or block.
Everything else in the ingest path can be verified by watching a counter; this one cannot, because
a wrong value breaks nothing that reports an error:

> announcements keep succeeding · fetches never arrive · retrieval traffic stays flat while the
> announce count climbs · no log line, no failed metric

Worse than silence: every failed fetch charges the bridge's **fetch-health breaker** entry in
merkle-service, keyed by `config.peerId`, so a wrong address actively penalises the peer it names.

Rules:

| Rule | Why |
|---|---|
| It is what **merkle-service's containers** can dial | Not necessarily what the bridge binds. Binding `[::]:9165` and advertising a routable address is the normal shape. Containers cannot dial loopback, and a v6-only address needs the container network to route v6. |
| **No API prefix** | The announced URL is `advertise` + `config.apiPrefix`. Putting `/api/v1` in both doubles the path and every fetch 404s; the chart **refuses to install** that. |
| No trailing slash | Trimmed anyway, but `//subtree/` is what a raw concatenation would produce. |
| Scheme required (`http://`, `https://`) | Schema-enforced: a bare `host:port` is not a URL merkle-service can dial. |
| Allowed by merkle-service's SSRF guard | Private fetch addresses (RFC1918/ULA) are refused unless its environment sets `DATAHUB_ALLOW_PRIVATE_IPS=true`. |

`config.hydrateAsset` is the mirror image and the easy thing to get backwards: it **does** carry
the asset service's own `/api/v1`, because the bridge dials it exactly as given.

## Modes

| `config.mode` | What runs | Required |
|---|---|---|
| `all` (default) | lanes + cache + retrieval plane + Kafka announce; plus the facade when `config.edgeIngress` is set | `advertise`, `kafka` |
| `sink` | lanes + cache + retrieval plane: receive, parse, count, serve | **nothing** |

`sink` is a first-class deployment, not a degraded one: the lanes still run and still enforce
framing, so it burns in a delivery slot before the Arcade stack attaches and separates
object-plane faults from stack-side ones. The chart drops the announce flags in that mode (a sink
that listed a `-kafka` would read like a bridge that lost its stack) but keeps the retrieval plane
and its Service, because the binary serves it unconditionally and `/readyz` requires it.

## The facade

Set `config.edgeIngress` (a failover list; with a dual-homed tunnel, the side-A and side-B slot
inners) and the bridge serves Arcade's own datahub submission surface on `config.facadeListen`.
Point Arcade at it by listing the facade Service (or the host address, under
`networking.mode: host`) in its `datahub_urls`. Arcade probes `GET /health` to restore a tripped
endpoint breaker; any HTTP response satisfies it.

The response contract is Teranode's failure-list grammar, so Arcade's per-transaction classifier
and retry reaper behave identically. EF submissions pass through byte for byte;
standard-serialized ones are hydrated from a fixed 256 MiB recent-submission cache with the
optional `config.hydrateAsset` fallback, and a parent nowhere to be found fails that one
transaction as `TX_MISSING_PARENT`, which Arcade already retries.

`config.kafka` and `config.edgeIngress` are YAML **lists** in values but render as **single
comma-joined flags** (`-kafka=a,b`, `-edge-ingress=a,b`): the binary splits on comma itself. This
differs from teranode-bridge-helm, whose binary takes repeated flags.

## Scaling: why `replicaCount` stays 1

The object cache is **in-process, and every announcement names this release's retrieval address**.
A pushed subtree lives only on the bridge that received it. Put N replicas behind one retrieval
Service and `(N-1)/N` of merkle-service's fetches land on a replica that never saw the object: an
honest `404`, and merkle-service's per-peer fetch-health breaker charges the announced
`config.peerId` for every one, penalising the whole set for the topology mistake. The chart warns
on `replicaCount > 1`.

Scale by adding **releases**, each with its own `config.advertise` and its own `peerId`. For the
same reason the chart ships **no HorizontalPodAutoscaler**: autoscaling would fragment the cache
under load, the moment it is least able to absorb a miss.

## Install-time refusals

The chart fails rather than render a manifest that produces a crashloop or a silent data fault:

| Condition | Why not a warning |
|---|---|
| `config.advertise` ends with `config.apiPrefix` | Doubled announce path. Nothing errors at runtime; every merkle-service fetch 404s and charges the fetch-health breaker. |
| `config.advertise` without an `http(s)://` scheme | Schema-enforced; a bare `host:port` is not a URL merkle-service can dial. |
| `config.edgeIngress` set with `config.mode: sink` | The facade never starts in sink mode, so the binary silently ignores it; Arcade would be pointed at a facade that does not exist. |
| `config.hydrateAsset` set with the facade off | Hydration only runs inside the facade; the binary silently ignores the value. |

Softer problems (empty `advertise`/`kafka` in `mode: all`, `replicaCount > 1`) surface as NOTES
warnings and a `helm.sh/chart-warnings` pod annotation.

## Values reference

See [`values.yaml`](values.yaml) for the full annotated reference. Every flag in
[`arcade-bridge/docs/configuration.md`](https://github.com/lightwebinc/arcade-bridge/blob/main/docs/configuration.md)
is reachable from `.config`.

### Flags whose zero value means something

Omission means "use the binary default", so a flag whose default is non-zero can never be turned
*off* by omitting it. Two are therefore rendered **unconditionally**:

| Key | Renders | Because |
|---|---|---|
| `config.statsEvery` | `-stats-every=<v>` | `"0s"` means *no periodic stats*; omitted it becomes the binary's `1m`. |
| `metrics.enabled: false` | `-metrics-addr=` | The only value that switches the listener off. Setting `config.metricsAddr: ""` would be omitted and the binary default `[::]:9167` would apply: metrics you thought you had disabled. |

`metrics.enabled: false` also removes `/healthz`, `/readyz` and both probes, which have nowhere
else to point.

### Observability

Series are `arcade_bridge_*`, covering the lanes, the cache, announce, the facade, and the
up-tunnel. The full catalogue is in the
[binary repo's configuration reference](https://github.com/lightwebinc/arcade-bridge/blob/main/docs/configuration.md#observability).

| Value | Effect |
| --- | --- |
| `metrics.serviceMonitor.enabled: true` | Scrapes `/metrics` on the metrics Service port. |
| `metrics.prometheusRule.enabled: true` | Installs the built-in alert set: announce failures (merkle-service not hearing about held objects), sustained lane handler errors, connections dropped on a framing fault, up-tunnel stalled (failures rising with sends flat: Arcade is seeing 503s), and missing parents (recent cache undersized or `hydrateAsset` unset). |

`/readyz` answers `200` only once **every** lane is bound and the retrieval plane is listening;
`/healthz` is always `200`. Readiness gates traffic steering; liveness asserts only that the
process is alive. Both probes live on the metrics listener.

### Networking

| `networking.mode` | Use |
|---|---|
| `pod` (default) | Ordinary CNI. Right when merkle-service, Arcade and the delivery side can all route to cluster Services. |
| `host` | `hostNetwork: true`; the pod binds node addresses. Right when the stack can only reach a node address, the common case for a landing tier in front of a LAN stack. Ports become **host** ports: one bridge per node, and the rollout defaults to `Recreate` (a rolling update cannot bind the same host ports twice). |

`networkPolicy` splits ingress by audience: `laneIngressFrom` (delivery side),
`retrievalIngressFrom` (merkle-service), `facadeIngressFrom` (Arcade), `metricsIngressFrom`
(Prometheus). It is fail-closed: enabling it with an empty list for a port admits no peers on it.
It is inert under `networking.mode: host`; restrict host traffic at the node firewall.

### Sizing

`resources` defaults assume the 1 GiB `config.cacheBytes` default. The process holds **one**
object cache of that size, plus a fixed **256 MiB** recent-submission cache whenever the facade is
on, so budget the memory limit for the sum and raise it together with `cacheBytes`.

Size `config.cacheTtl` (default `30m`) against merkle-service's **worst-case Kafka consumer lag**,
not retention: a fetch after expiry is an honest `404` that its stale-announcement grace then has
to excuse, and that `404` charges this bridge's fetch-health.

## Helm test

```bash
helm test bridge -n bsv-mcast
```

Probes `/healthz`, `/metrics` and `/readyz` on the metrics Service; `/readyz` answers `200` only
once every lane is bound and the retrieval plane is listening, the one check that distinguishes a
live bridge from a running process. With the facade enabled it also probes the facade Service's
`GET /health`, the route Arcade uses to restore a tripped endpoint breaker.

## Release

The `release.yml` workflow is gated. It runs only via `workflow_dispatch` with `confirm: RELEASE`.
Tag-based auto-release is intentionally disabled.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
