# charts

Helm charts for the lightwebinc multicast services, published to
`oci://ghcr.io/lightwebinc/charts`:

| chart | what it deploys |
|---|---|
| [arcade-bridge](charts/arcade-bridge) | the Arcade bridge |
| [retry-endpoint](charts/retry-endpoint) | the NACK retransmission endpoint |
| [shard-listener](charts/shard-listener) | the multicast shard listener |
| [shard-manifest](charts/shard-manifest) | the shard manifest service |
| [shard-proxy](charts/shard-proxy) | the multicast shard proxy |
| [subtx-generator](charts/subtx-generator) | the test traffic generator |
| [teranode-bridge](charts/teranode-bridge) | the Teranode bridge |

Install a released chart straight from the registry:

```bash
helm install <release> oci://ghcr.io/lightwebinc/charts/<chart> --version <version>
```

Each chart is versioned independently; its README documents its values.

## Testing

`lint.yml` lints and renders every chart a change touches: the defaults, each
render scenario in `charts/<chart>/ci/*.yaml` (with `.expect` assertions), each
`examples/*.yaml`, and every `ci/reject/*.yaml`, which must fail to render.
A chart's lint inputs are in `charts/<chart>/ci/lint-inputs.json`.

## Releasing

Bump the chart's `version` (and `appVersion`, which must name a published
image) in `Chart.yaml`, then run the `release` workflow with the chart name and
`RELEASE` as the confirmation. `dry-run` packages without pushing.

## License

Apache 2.0, see [LICENSE](LICENSE).
