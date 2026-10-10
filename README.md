# onicost-helm-charts

Public Helm charts of Onicost.

Onicost is a SaaS FinOps application: it computes the costs of Kubernetes clusters and suggests optimizations. The Onicost agent, installed in each monitored cluster, collects the cluster inventory and the CPU and memory usage of the containers from the kubelets, then pushes them to the Onicost ingestion gateway once a minute. It only has read permissions and accesses no Secret.

## Requirements

- Helm 3.14 or later (the CI uses Helm 4.3.0);
- a Kubernetes 1.22 or later cluster for the installation.

## Charts

| Chart | OCI reference | Documentation |
|---|---|---|
| `onicost-agent` | `oci://ghcr.io/samytsb/charts/onicost-agent` | [charts/onicost-agent/README.md](charts/onicost-agent/README.md) |

The full install command, which also creates the agent token Secret, is given by the Onicost interface. Its Helm part:

```bash
helm upgrade --install onicost-agent oci://ghcr.io/samytsb/charts/onicost-agent --version <version> \
  --namespace onicost --reset-then-reuse-values --set endpoint=<gateway URL>
```

Pull a given version of the chart (versions are listed in the [CHANGELOG](CHANGELOG.md)):

```bash
helm pull oci://ghcr.io/samytsb/charts/onicost-agent --version <version>
```

## Commands

```bash
# Lint the chart, render it and check the refusals of the schema
./scripts/check.sh

# Render the manifests locally
helm template onicost-agent charts/onicost-agent --set endpoint=https://ingest.example.test
```

## Layout

| Path | Content |
|---|---|
| `charts/onicost-agent/` | Onicost agent chart |
| `scripts/check.sh` | Checks of the chart: lint, rendering and refusals of the schema |
| `scripts/values-all.yaml` | Every optional value set, rendered by `scripts/check.sh` |
| `.github/workflows/ci.yml` | Runs `scripts/check.sh` on every push to `main` and every pull request |
| `.github/workflows/release.yml` | Publishes the chart to `ghcr.io` on every version tag |

## Release

Versions follow semantic versioning. The chart `version` and `appVersion` move together with the agent image: chart version `0.2.0` deploys the image `ghcr.io/samytsb/onicost-agent:0.2.0`.

To release a version:

1. Release the agent first: tag `v<version>` in onicost-agent, whose image package must be public.
2. Update `version` and `appVersion` in `charts/onicost-agent/Chart.yaml`, and the [CHANGELOG](CHANGELOG.md) (a release candidate `X.Y.Z-rc.N` needs no entry).
3. Push the tag `onicost-agent-<version>`.

The `release` workflow checks that the tag matches the chart, that the CHANGELOG has an entry for the version and that the image `ghcr.io/samytsb/onicost-agent:<version>` exists, runs `scripts/check.sh`, then packages the chart and pushes it to `oci://ghcr.io/samytsb/charts`, unless that version is already published.

## License

Apache License 2.0, see [LICENSE](LICENSE).
