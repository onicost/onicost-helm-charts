# Security

## Permissions

The agent's ClusterRole is read-only:

| API group | Resources | Verbs |
|---|---|---|
| `""` (core) | `nodes`, `pods`, `namespaces`, `persistentvolumes`, `persistentvolumeclaims` | `get`, `list`, `watch` |
| `apps` | `deployments`, `replicasets`, `statefulsets`, `daemonsets` | `get`, `list`, `watch` |
| `batch` | `jobs`, `cronjobs` | `get`, `list`, `watch` |
| `""` (core) | `nodes/metrics` | `get` |
| `""` (core) | `nodes/proxy` | `get`, only with `kubelet.apiServerProxy=true` |

No access to Secrets or ConfigMaps, and no write permission. The kubelet mounts the token from its Secret: the agent reads no Secret through the API.

The pod meets the `restricted` Pod Security Standard: non-root user `65532`, read-only root filesystem, all capabilities dropped, no privilege escalation, seccomp `RuntimeDefault`.

## What is collected

Sent to Onicost:

- the inventory: nodes (capacity, allocatable, GPU resources, labels), namespaces and workloads with their labels, pods with the requests and limits of their containers, PersistentVolumes and PersistentVolumeClaims;
- the usage: CPU and memory of each container, read from the kubelet resource metrics and aggregated per minute;
- on AWS Fargate nodes only, the size Fargate provisioned for each pod, parsed from its `CapacityProvisioned` annotation.

Not collected: Secrets, ConfigMaps, pod annotations other than the Fargate one, logs, and application data or traffic.

To send less, `exclude.namespaces` drops everything from the listed namespaces, and `exclude.labelKeys` removes the listed label keys before sending.

## The nodes/proxy option

Some managed clusters, Scaleway Kapsule for one, serve kubelet certificates that the agent cannot verify. With `kubelet.apiServerProxy=true`, the agent scrapes these kubelets through the API server (`GET /api/v1/nodes/<node>/proxy/metrics/resource`), which needs `get` on `nodes/proxy`. That permission opens the whole kubelet API of every node, pod logs included, not only its metrics. Grant it only when the logs show kubelet errors with `errorClass: tls_verification`.

`kubelet.insecureSkipVerify=true` avoids the permission but skips the kubelet certificate check: the agent's service account token is then sent to whatever answers on the node addresses. Use it only on a trusted node network.

## Image provenance

The chart deploys `ghcr.io/onicost/onicost-agent`, tagged with the chart `appVersion`. Onicost builds it from a tagged release, for `linux/amd64` and `linux/arm64`, on the `gcr.io/distroless/static-debian13:nonroot` base. To pin the exact image, set `image.tag` to `<version>@sha256:<digest>`.

The chart itself is published to `oci://ghcr.io/onicost/charts/onicost-agent` by the [release workflow](../.github/workflows/release.yml) of this repository, from the tag `onicost-agent-<version>`.

## Report a vulnerability

E-mail security@onicost.com with the affected version and the steps to reproduce. Do not open a public issue.
