# Onicost Helm charts

This repository holds the Helm chart of the Onicost agent. The agent runs in each Kubernetes cluster you monitor with [Onicost](https://onicost.com): it reads the cluster inventory and the container usage with read-only permissions and sends them to Onicost once a minute.

## Requirements

- Kubernetes 1.22 or later, and cluster-admin rights for the install
- Helm 3.14 or later
- The agent token of the cluster, shown in the Onicost interface when you add the cluster

## Install

```bash
kubectl create namespace onicost
printf 'Agent token: ' && read -rs ONICOST_TOKEN && echo
printf '%s' "$ONICOST_TOKEN" | kubectl create secret generic onicost-agent-token \
  --namespace onicost --from-file=token=/dev/stdin
helm upgrade --install onicost-agent oci://ghcr.io/onicost/charts/onicost-agent \
  --version <version> --namespace onicost --set endpoint=https://ingest.onicost.com
```

Replace `<version>` with the latest version in the [changelog](CHANGELOG.md). The Onicost interface gives the same command with the version filled in. The token never appears on a command line or in the Helm values.

## Upgrade

```bash
helm upgrade onicost-agent oci://ghcr.io/onicost/charts/onicost-agent \
  --version <version> --namespace onicost --reset-then-reuse-values
```

## Uninstall

```bash
helm uninstall onicost-agent --namespace onicost
kubectl delete namespace onicost
```

## Documentation

- [Install](docs/install.md): token, endpoint, proxy, network policy, checking the agent
- [Operations](docs/operations.md): upgrades, version pinning, metrics, logs, troubleshooting
- [Security](docs/security.md): permissions, collected data, image provenance, reporting a vulnerability
- [Values reference](charts/onicost-agent/README.md)

## Versioning

Chart versions follow [Semantic Versioning](https://semver.org). The chart `appVersion` is the tag of the agent image it deploys; a change to the chart alone bumps the chart version only.

## License

[Apache License 2.0](LICENSE)
