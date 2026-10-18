# Changelog

All notable changes to this repository are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.0] - 2026-10-18

### Added

- The read-only ClusterRole gains `get`, `list` and `watch` on `horizontalpodautoscalers` (`autoscaling`) and `poddisruptionbudgets` (`policy`), whatever `actions.enabled`: the agent 0.6.0 reads them for the recommendations of Onicost, never writes a PodDisruptionBudget, and patches the HorizontalPodAutoscalers in the actions mode only, as before. `scripts/check.sh` checks that the PodDisruptionBudget rule carries no write verb with `actions.enabled` false or true and with `kubelet.apiServerProxy`. `docs/security.md` lists the two rules and the new readings.

### Changed

- The chart deploys the agent 0.6.0, image `ghcr.io/onicost/onicost-agent:0.6.0`: it reads the cAdvisor and volume metrics of the kubelets (CFS throttling, OOM kills, memory peak, network, ephemeral storage, volume usage) with the existing `nodes/metrics` right, the pools, taints and allocatable of the nodes, the placement, resources, QoS class, HPA and PDB of the workloads, which the recommendations v2 of Onicost need. Without the new read rules, the agent sends the workloads without HPA and PDB and checks the rights again every 10 minutes. The values, the network flows and the actions mode do not change. Upgrading from 0.5.x keeps the values (`--reset-then-reuse-values`, with `--set actions.enabled=true` where it was set); the agents 0.5 still work with Onicost, with fewer recommendations.
- The chart description names the HPAs and PDBs and the network, throttling and volume usage.

## [0.5.1] - 2026-10-16

### Changed

- The chart deploys the agent 0.5.1, image `ghcr.io/onicost/onicost-agent:0.5.1`. It checks at start, then every 10 minutes, which permissions of the actions mode its service account lacks, with one `SelfSubjectAccessReview` per permission, and reports them in its heartbeat (`actionsMissingPermissions`), whatever the mode; Onicost shows them on the cluster page once the actions mode is on. Its inventory gives each Deployment, StatefulSet and CronJob the hints of the scheduler: opted out by the annotation `onicost.com/scheduler: ignore`, scaled by a HorizontalPodAutoscaler (known in the actions mode only), managed by Flux or Argo CD.
- No new permission and no change to the values or the templates: `SelfSubjectAccessReview` is granted to every authenticated identity by the default ClusterRole `system:basic-user`, and the ClusterRole of the chart is unchanged, read-only without `actions.enabled`. Upgrading from 0.5.0 keeps the values as they are (`--reset-then-reuse-values`, with `--set actions.enabled=true` where it was set); the agents 0.5.0 still work with Onicost.

## [0.5.0] - 2026-10-16

### Added

- `actions.enabled`, `false` by default: the actions mode of the Onicost scheduler. `true` adds to the ClusterRole `patch` on `deployments`, `statefulsets` and `cronjobs`, and `get`, `list`, `watch` and `patch` on `horizontalpodautoscalers`, and nothing else: no update, no scale subresource, no create, no delete, no Secret, ConfigMap or custom resource. `values.schema.json` accepts only a boolean.
- The Deployment sets `ONICOST_ACTIONS_ENABLED` from `actions.enabled`, and `ONICOST_NAMESPACE`, the namespace of the agent, which the scheduler never touches, from the downward API.
- `docs/security.md` describes the actions mode: what the agent does with these permissions, what it never does, how to leave the mode, and an optional ValidatingAdmissionPolicy (Kubernetes 1.30 or later) that rejects any other change by the agent. `docs/install.md` gives the `helm upgrade` command with `--set actions.enabled=true`.

### Changed

- The chart deploys the agent 0.5.0, image `ghcr.io/onicost/onicost-agent:0.5.0`: it reads the schedule of its cluster from the endpoint, reports the scheduler actions and says in its heartbeat whether the actions mode is on. In actions mode it switches off and on the workloads of the scheduler rules activated in Onicost; otherwise it changes nothing and reports `actions_disabled`.
- Upgrading from 0.4.x without `actions.enabled` keeps the read-only ClusterRole unchanged; the network flows are unchanged, the new routes are on the same endpoint.

## [0.4.1] - 2026-10-15

### Changed

- The chart and the agent image are published under `ghcr.io/onicost`: chart `oci://ghcr.io/onicost/charts/onicost-agent`, image `ghcr.io/onicost/onicost-agent:0.4.1`. No functional change in the chart or the agent.
- The documentation is rewritten: a short README, install, operations and security guides under `docs/`, and the chart README as the values reference.

## [0.4.0] - 2026-10-13

### Added

- The chart README has an upgrade note for 0.4.0: nothing changes in the values, the RBAC or the network flows.

### Changed

- The chart deploys the agent 0.4.0, image `onicost-agent:0.4.0`: it also sends the `ephemeral-storage` request of each container and, on an AWS Fargate node (label `eks.amazonaws.com/compute-type=fargate`), the size Fargate provisions for each pod, read from its `CapacityProvisioned` annotation, the only annotation the agent reads. No new permission: the agent reads the pods and the nodes it already watches, and the ClusterRole is unchanged.

## [0.3.0] - 2026-10-12

### Added

- The chart README has an upgrade note for 0.3.0: nothing changes in the values, the RBAC or the network flows.

### Changed

- The chart deploys the agent 0.3.0, image `onicost-agent:0.3.0`: it also sends the GPU capacity of the nodes (`status.capacity` and `status.allocatable`) and the GPU requests of the containers by resource, for the `nvidia.com/`, `amd.com/`, `gpu.intel.com/` and `habana.ai/` resources (`nvidia.com/gpu`, `nvidia.com/gpu.shared`, MIG slices). Nothing else to install on GPU nodes, and no new permission: the ClusterRole is unchanged.

## [0.2.2] - 2026-10-12

Never published: these changes ship with 0.3.0.

### Added

- `kubelet.apiServerProxy`, `false` by default: `true` adds `get` on `nodes/proxy` to the ClusterRole, which the agent 0.2.1 needs to scrape through the API server proxy a kubelet whose certificate fails the checks, as on Scaleway Kapsule. This permission opens the whole kubelet API of every node; the chart README says when to grant it. `values.schema.json` accepts only a boolean.

### Changed

- The chart still deploys the image `onicost-agent:0.2.1`.

## [0.2.1] - 2026-10-12

### Added

- Optional NetworkPolicy for the agent pod, for namespaces that deny traffic by default, where the agent otherwise never becomes ready: `networkPolicy.enabled`, `false` by default. It allows egress to the cluster DNS (`networkPolicy.dns`) and to the TCP ports of the API server, the kubelets and the gateway (`networkPolicy.egressPorts`, `443`, `6443` and `10250` by default), optionally restricted to `networkPolicy.egressCidrs`, appends `networkPolicy.extraEgress`, and allows ingress on the metrics port from `networkPolicy.metricsFrom`. `values.schema.json` rejects unknown keys in `networkPolicy` and `networkPolicy.dns`, ports outside `1`-`65535` and CIDRs without a prefix length.
- The chart README explains when to enable the NetworkPolicy, what the agent must reach and how to adapt the values.

### Changed

- The chart deploys the agent 0.2.1: a connectivity report at startup and explicit warnings when the API server, the kubelets or the gateway are unreachable (with the flow to open), a `/readyz` body that says why the agent is not ready, and kubelet certificates without IP SAN verified by the host name of the node (then, when the ClusterRole grants `get` on `nodes/proxy`, scraped through the API server proxy). OVHcloud MKS nodes are marked on-demand.
- The `release` workflow accepts a chart `version` that differs from its `appVersion`, for a change of the chart alone; a final chart version still cannot deploy a release candidate.

## [0.2.0] - 2026-10-10

### Added

- The chart README lists the metrics served on `/metrics`, with their type and meaning, and how to pass the `prometheus.io/*` pod annotations as strings for a Prometheus that discovers pods through them.
- The chart README states the bound of the send buffer (two hours and 64 MiB) and that the agent sets the soft memory limit of the Go runtime to 90% of the container memory limit.
- The chart README warns that credentials in `proxy.url` appear in clear text in the Deployment and pod specs, not only in the release values.

### Changed

- The chart deploys the image `onicost-agent:0.2.0` by default.
- `values.schema.json` rejects an `endpoint` or a `proxy.url` that is not an `http://` or `https://` URL, and an `endpoint` with credentials, a query or a fragment: such a value now fails `helm upgrade` instead of the agent at startup.
- `values.schema.json` rejects an empty `image.repository`.
- The install and pull commands of the READMEs use a `<version>` placeholder; the versions are listed in this CHANGELOG.

### Fixed

- The notes printed after an install or an upgrade name the deployed image tag, `image.tag` when it is set, instead of always the chart `appVersion`.
- `podLabels: null` is treated as empty instead of failing the rendering.

## [0.1.0] - 2026-10-06

### Added

- Chart `onicost-agent` version `0.1.0`, which deploys the image `onicost-agent:0.1.0` on Kubernetes 1.22 or later.
- Created objects: ServiceAccount, read-only ClusterRole, ClusterRoleBinding, and a single-replica Deployment with the `Recreate` strategy. The namespace and the token Secret are left to the install command.
- Secure defaults: pod at the `restricted` level of the Pod Security Standards (non-root user `65532`, read-only root filesystem, no capabilities, seccomp `RuntimeDefault`); read-only RBAC, with no access to Secrets or ConfigMaps; token read from an existing Secret, never from the values.
- Values: `endpoint` (required), `token.existingSecret`, `token.secretKey`, `kubelet.insecureSkipVerify`, `scrapeInterval`, `exclude.namespaces`, `exclude.labelKeys`, `proxy.url`, `image.repository`, `image.tag`, `image.pullPolicy`, `resources`, and the standard pod keys `imagePullSecrets`, `podAnnotations`, `podLabels`, `priorityClassName`, `nodeSelector`, `tolerations`, `affinity`. `values.schema.json` rejects any unknown key at the top level and in `token`, `kubelet`, `exclude`, `proxy`, `image` and the items of `imagePullSecrets`, as well as any value of the wrong type; `resources`, `affinity` and `tolerations` follow the Kubernetes objects and are not checked key by key.
- `/healthz` and `/readyz` probes and Prometheus metrics on `/metrics`, port `8080`.

[Unreleased]: https://github.com/onicost/onicost-helm-charts/compare/onicost-agent-0.6.0...HEAD
[0.6.0]: https://github.com/onicost/onicost-helm-charts/compare/onicost-agent-0.5.1...onicost-agent-0.6.0
[0.5.1]: https://github.com/onicost/onicost-helm-charts/compare/onicost-agent-0.5.0...onicost-agent-0.5.1
[0.5.0]: https://github.com/onicost/onicost-helm-charts/compare/onicost-agent-0.4.1...onicost-agent-0.5.0
[0.4.1]: https://github.com/onicost/onicost-helm-charts/compare/onicost-agent-0.4.0...onicost-agent-0.4.1
[0.4.0]: https://github.com/onicost/onicost-helm-charts/compare/onicost-agent-0.3.0...onicost-agent-0.4.0
[0.3.0]: https://github.com/onicost/onicost-helm-charts/compare/onicost-agent-0.2.1...onicost-agent-0.3.0
[0.2.1]: https://github.com/onicost/onicost-helm-charts/compare/onicost-agent-0.2.0...onicost-agent-0.2.1
[0.2.0]: https://github.com/onicost/onicost-helm-charts/compare/onicost-agent-0.1.0...onicost-agent-0.2.0
[0.1.0]: https://github.com/onicost/onicost-helm-charts/tree/onicost-agent-0.1.0
