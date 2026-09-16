# subtx-generator Helm chart

> Part of the [**BSV Layered Multicast**](https://github.com/lightwebinc/bsv-multicast) open-source project — see the main repository for the full architecture, design docs, and BRC specifications.

Helm chart for [subtx-generator](https://github.com/lightwebinc/subtx-generator) — the BSV multicast load and control-frame tooling.

This repository packages templates, default values, JSON Schema validation, and CI workflows for the generator. The application source lives in [`subtx-generator`](https://github.com/lightwebinc/subtx-generator).

## Modes

The chart packages a single multi-binary image and selects the binary via `.Values.mode`:

| mode | Binary | Purpose |
|---|---|---|
| `subtx-gen` (default) | `/usr/local/bin/subtx-gen` | BRC-124/BRC-128 traffic generator |
| `send-anchor-frame` | `/usr/local/bin/send-anchor-frame` | BRC-134 anchor tx sender |
| `send-block-announce` | `/usr/local/bin/send-block-announce` | BRC-131 block + coinbase announcements (TCP) |
| `send-subtree-data` | `/usr/local/bin/send-subtree-data` | BRC-132 subtree data sender (TCP) |
| `send-subtree-push` | `/usr/local/bin/send-subtree-push` | BRC-143 subtree push → proxy lane 8726 |
| `send-block-push` | `/usr/local/bin/send-block-push` | BRC-144 block push → proxy lane 8727 |

The `send-subtree-push` / `send-block-push` binaries are packaged in images built from `v0.2.10` on — the chart's default image (`appVersion`) includes them, along with `tunnel-sink`. Only an older explicit `image.tag` pin lacks them.

The binaries are configured by **CLI flags**; the only environment variable they read is `LOG_FORMAT` (rendered from `logFormat`). The chart translates the matching `*Args` block from `values.yaml` into the container's `command` and `args`. Zero / empty values are omitted so the binary defaults apply. Boolean `false` is likewise omitted, so flags whose binary default is `true` (`sendBlockAnnounce.coinbase`, `sendSubtreePush.coinbasePlaceholder`) cannot be disabled through the chart.

## Install

```bash
# Continuous traffic generator (Deployment) — emits 1000 pps until killed
helm install gen oci://ghcr.io/lightwebinc/charts/subtx-generator \
  --version 0.3.4 -n bsv-mcast \
  --set mode=subtx-gen \
  --set args.addr=[fd20::20]:8725 \
  --set subtxGen.pps=1000 --set subtxGen.duration=0s

# Finite load test (Job) — send 10 anchor frames then exit
helm install anchor-test . -n bsv-mcast \
  --set mode=send-anchor-frame \
  --set workloadType=Job \
  --set args.addr=[fd20::20]:8725 \
  --set sendAnchorFrame.count=10
```

## Workload type

| `workloadType` | Use case |
|---|---|
| `Deployment` (default) | Long-running generators (`subtx-gen` with `duration=0`). |
| `Job` | Finite runs; pod terminates on completion. |

## Networking

The generator is a pure UDP/TCP client toward the proxy — no MLD join, no multicast receive. Default `networking.mode: pod` is appropriate for any CNI. `host` and `multus` are available for operators that need a specific source NIC.

## Values reference

See [`values.yaml`](values.yaml). The flags of the six packaged binaries are exposed under per-mode blocks (one exception: `subtx-gen -tcp`, the TCP submission lane, is not modelled — the chart's `subtx-gen` always submits over UDP, which the binary's own help text marks deprecated):

- `args` — shared flags (`addr`)
- `subtxGen` — full `subtx-gen` surface (frame version, payload format, gap injection, BRC-127 announce, txid corruption, direct-multicast SSM mode)
- `sendAnchorFrame` — BRC-134 sender
- `sendBlockAnnounce` — BRC-131 sender
- `sendSubtreeData` — BRC-132 sender
- `sendSubtreePush` — BRC-143 subtree push (proxy lane 8726)
- `sendBlockPush` — BRC-144 block push (proxy lane 8727)
- `logFormat` (`text`|`json`, schema-validated) → `LOG_FORMAT`: the generator now logs through `shard-common/logging`; set `json` to match the rest of the fleet. See the [Unified Logging Plan](https://github.com/lightwebinc/shard-common/blob/main/docs/logging.md).

### direct-multicast mode (subtxGen)

`subtxGen.mode` defaults to `unicast` (forward to proxy via `args.addr`).
Set `subtxGen.mode=direct-multicast` plus `subtxGen.bindSource`,
`subtxGen.egressIface`, `subtxGen.sourceMode`, `subtxGen.scope`, and
`subtxGen.egressPort` to bypass the proxy and emit `(S=bindSource, G)`
directly. The generator stamps SeqNum per-flow and HashKey =
XXH64(bindSource ∥ groupIdx ∥ subtreeID) so SSM listeners see
deterministic flows without a proxy in the loop. Operators MUST add
`bindSource` to the shard-manifest `publishers` list so receivers'
`(S,G)` joins include this generator. See the
[SSM Support Plan](https://github.com/lightwebinc/bsv-multicast/blob/main/DESIGN.md#source-specific-multicast-ssm).

## Release

Gated `release.yml` — `workflow_dispatch` with `confirm: RELEASE` and `production` Environment review.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
