# Changelog

All notable changes to this repository are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.1] - 2026-10-12

### Added

- Optional NetworkPolicy for the agent pod, for namespaces that deny traffic by default, where the agent otherwise never becomes ready: `networkPolicy.enabled`, `false` by default. It allows egress to the cluster DNS (`networkPolicy.dns`) and to the TCP ports of the API server, the kubelets and the gateway (`networkPolicy.egressPorts`, `443`, `6443` and `10250` by default), optionally restricted to `networkPolicy.egressCidrs`, appends `networkPolicy.extraEgress`, and allows ingress on the metrics port from `networkPolicy.metricsFrom`. `values.schema.json` rejects unknown keys in `networkPolicy` and `networkPolicy.dns`, ports outside `1`-`65535` and CIDRs without a prefix length.
- The chart README explains when to enable the NetworkPolicy, what the agent must reach and how to adapt the values.

### Changed

- The chart deploys the agent 0.2.1: a connectivity report at startup and explicit warnings when the API server, the kubelets or the gateway are unreachable (with the flow to open), a `/readyz` body that says why the agent is not ready, and kubelet certificates without IP SAN verified by the host name of the node (then, when the ClusterRole grants `get` on `nodes/proxy`, scraped through the API server proxy). OVHcloud MKS nodes are marked on-demand.

### Changed

- The chart still deploys the image `ghcr.io/samytsb/onicost-agent:0.2.0`.
- The `release` workflow accepts a chart `version` that differs from its `appVersion`, for a change of the chart alone; a final chart version still cannot deploy a release candidate.

## [0.2.0] - 2026-10-10

### Added

- The chart README lists the metrics served on `/metrics`, with their type and meaning, and how to pass the `prometheus.io/*` pod annotations as strings for a Prometheus that discovers pods through them.
- The chart README states the bound of the send buffer (two hours and 64 MiB) and that the agent sets the soft memory limit of the Go runtime to 90% of the container memory limit.
- The chart README warns that credentials in `proxy.url` appear in clear text in the Deployment and pod specs, not only in the release values.

### Changed

- The chart deploys the image `ghcr.io/samytsb/onicost-agent:0.2.0` by default.
- `values.schema.json` rejects an `endpoint` or a `proxy.url` that is not an `http://` or `https://` URL, and an `endpoint` with credentials, a query or a fragment: such a value now fails `helm upgrade` instead of the agent at startup.
- `values.schema.json` rejects an empty `image.repository`.
- The install and pull commands of the READMEs use a `<version>` placeholder; the versions are listed in this CHANGELOG.

### Fixed

- The notes printed after an install or an upgrade name the deployed image tag, `image.tag` when it is set, instead of always the chart `appVersion`.
- `podLabels: null` is treated as empty instead of failing the rendering.

## [0.1.0] - 2026-10-06

### Added

- Chart `onicost-agent` version `0.1.0`, which deploys the image `ghcr.io/samytsb/onicost-agent:0.1.0` on Kubernetes 1.22 or later.
- Created objects: ServiceAccount, read-only ClusterRole, ClusterRoleBinding, and a single-replica Deployment with the `Recreate` strategy. The namespace and the token Secret are left to the install command.
- Secure defaults: pod at the `restricted` level of the Pod Security Standards (non-root user `65532`, read-only root filesystem, no capabilities, seccomp `RuntimeDefault`); read-only RBAC, with no access to Secrets or ConfigMaps; token read from an existing Secret, never from the values.
- Values: `endpoint` (required), `token.existingSecret`, `token.secretKey`, `kubelet.insecureSkipVerify`, `scrapeInterval`, `exclude.namespaces`, `exclude.labelKeys`, `proxy.url`, `image.repository`, `image.tag`, `image.pullPolicy`, `resources`, and the standard pod keys `imagePullSecrets`, `podAnnotations`, `podLabels`, `priorityClassName`, `nodeSelector`, `tolerations`, `affinity`. `values.schema.json` rejects any unknown key at the top level and in `token`, `kubelet`, `exclude`, `proxy`, `image` and the items of `imagePullSecrets`, as well as any value of the wrong type; `resources`, `affinity` and `tolerations` follow the Kubernetes objects and are not checked key by key.
- `/healthz` and `/readyz` probes and Prometheus metrics on `/metrics`, port `8080`.

[Unreleased]: https://github.com/samytsb/onicost-helm-charts/compare/onicost-agent-0.2.1...HEAD
[0.2.1]: https://github.com/samytsb/onicost-helm-charts/compare/onicost-agent-0.2.0...onicost-agent-0.2.1
[0.2.0]: https://github.com/samytsb/onicost-helm-charts/compare/onicost-agent-0.1.0...onicost-agent-0.2.0
[0.1.0]: https://github.com/samytsb/onicost-helm-charts/tree/onicost-agent-0.1.0
