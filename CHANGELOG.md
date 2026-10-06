# Changelog

All notable changes to this repository are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-10-06

### Added

- Chart `onicost-agent` version `0.1.0`, which deploys the image `ghcr.io/samytsb/onicost-agent:0.1.0` on Kubernetes 1.22 or later.
- Created objects: ServiceAccount, read-only ClusterRole, ClusterRoleBinding, and a single-replica Deployment with the `Recreate` strategy. The namespace and the token Secret are left to the install command.
- Secure defaults: pod at the `restricted` level of the Pod Security Standards (non-root user `65532`, read-only root filesystem, no capabilities, seccomp `RuntimeDefault`); read-only RBAC, with no access to Secrets or ConfigMaps; token read from an existing Secret, never from the values.
- Values: `endpoint` (required), `token.existingSecret`, `token.secretKey`, `kubelet.insecureSkipVerify`, `scrapeInterval`, `exclude.namespaces`, `exclude.labelKeys`, `proxy.url`, `image.repository`, `image.tag`, `image.pullPolicy`, `resources`, and the standard pod keys `imagePullSecrets`, `podAnnotations`, `podLabels`, `priorityClassName`, `nodeSelector`, `tolerations`, `affinity`. `values.schema.json` rejects any unknown key at the top level and in `token`, `kubelet`, `exclude`, `proxy`, `image` and the items of `imagePullSecrets`, as well as any value of the wrong type; `resources`, `affinity` and `tolerations` follow the Kubernetes objects and are not checked key by key.
- `/healthz` and `/readyz` probes and Prometheus metrics on `/metrics`, port `8080`.

[0.1.0]: https://github.com/samytsb/onicost-helm-charts/tree/onicost-agent-0.1.0
