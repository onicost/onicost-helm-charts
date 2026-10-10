# Onicost agent Helm chart

The Onicost agent observes the cluster it runs in, collects the CPU and memory usage from the kubelets and pushes the inventory and the samples to the Onicost ingestion gateway, once a minute.

The chart is published in OCI format: `oci://ghcr.io/samytsb/charts/onicost-agent`.

Its objects carry the release name (`onicost-agent` with the install command). The ServiceAccount and the Deployment are created in the release namespace, the ClusterRole and the ClusterRoleBinding at the cluster level:

| Object | Role |
|---|---|
| ServiceAccount `onicost-agent` | Identity of the agent |
| ClusterRole `onicost-agent` | Read-only (`get`, `list`, `watch`) on nodes, pods, namespaces, `apps` and `batch` controllers, PVs and PVCs; `get` on `nodes/metrics`. No access to Secrets or ConfigMaps, no write permission |
| ClusterRoleBinding `onicost-agent` | Binds the ClusterRole to the ServiceAccount |
| Deployment `onicost-agent` | One replica, `Recreate` strategy, non-root container (`65532`), read-only root filesystem, no capabilities, seccomp `RuntimeDefault`: `restricted` level of the Pod Security Standards |

The chart creates neither the namespace nor the token Secret, and accepts no token value.

## Installation

The full install command, with the token, is given by the Onicost interface, when a cluster is created and at each rotation of its token. It prompts for the token without echoing it, creates the `onicost` namespace and the `onicost-agent-token` Secret with server-side apply (the token goes through the standard input of `kubectl`, never through a command line or the values), then installs or upgrades the release:

```bash
helm upgrade --install onicost-agent oci://ghcr.io/samytsb/charts/onicost-agent --version <version> \
  --namespace onicost --reset-then-reuse-values --set endpoint=<gateway URL>
```

Requirements: bash or zsh, Kubernetes and `kubectl` 1.22 or later, Helm 3.14 or later (for `--reset-then-reuse-values`), cluster administrator permissions.

## Upgrade

To move to another chart version, rerun only the `helm` part of the command with the new `--version` value. To change an option without touching the token, likewise rerun the `helm` part, followed by the option.

`--reset-then-reuse-values` starts from the default values of the requested chart version and keeps the options given before. To remove an option, set it back to its default value: `--set kubelet.insecureSkipVerify=false`, `--set-json 'exclude.namespaces=[]'` or `--set proxy.url=`.

## Values

`values.schema.json` rejects any unknown key at the top level and in `token`, `kubelet`, `exclude`, `proxy`, `image` and the items of `imagePullSecrets`, as well as any value of the wrong type: a typo in these keys makes `helm upgrade` fail without changing the release. `resources`, `affinity` and the items of `tolerations` follow the Kubernetes objects and are not checked key by key.

| Key | Default | Meaning |
|---|---|---|
| `endpoint` | `""` | Required: rendering fails when it is empty. Base URL of the gateway (`http://` or `https://`), without a trailing `/`; the agent appends `/v1/ingest/usage` and `/v1/ingest/inventory` to it |
| `token.existingSecret` | `onicost-agent-token` | Existing Secret of the release namespace that holds the token. Not empty |
| `token.secretKey` | `token` | Key of the token in that Secret, mounted as the file `token`. Not empty |
| `kubelet.insecureSkipVerify` | `false` | `false`: the certificate of each kubelet is verified with the cluster authority. `true`: no verification, for kubelets with self-signed certificates |
| `scrapeInterval` | `30s` | Interval between two scrapes of a kubelet: `10s`, `15s`, `20s`, `30s` or `60s` |
| `exclude.namespaces` | `[]` | Exact names of the namespaces of which nothing is sent: neither the namespace, nor its workloads, nor the usage of its containers, nor its PVCs and their PVs |
| `exclude.labelKeys` | `[]` | Exact label keys removed before sending (nodes, namespaces, workloads) |
| `proxy.url` | `""` | Outgoing HTTP proxy (`http://` or `https://`), used only to reach the gateway. Empty: direct connection |
| `image.repository` | `ghcr.io/samytsb/onicost-agent` | Image repository. Not empty |
| `image.tag` | `""` | Empty: the chart `appVersion` |
| `image.pullPolicy` | `IfNotPresent` | `Always`, `IfNotPresent` or `Never` |
| `resources` | requests `cpu: 50m`, `memory: 64Mi`; limits `memory: 256Mi` | Container resources. No CPU limit; the memory limit covers the send buffer (at most two hours and 64 MiB), and the agent sets the soft memory limit of the Go runtime to 90% of it |
| `imagePullSecrets` | `[]` | List of `{name: <Secret>}` objects |
| `podAnnotations` | `{}` | Pod annotations, string values |
| `podLabels` | `{}` | Labels added to the pod, string values. Cannot override the chart labels, including the selector labels |
| `priorityClassName` | `""` | PriorityClass of the pod. Empty: none |
| `nodeSelector` | `{}` | Node selector of the pod, string values |
| `tolerations` | `[]` | Pod tolerations |
| `affinity` | `{}` | Pod affinity |

The `global` key is accepted, for use as a subchart, and is not read.

Lists on the command line: `--set 'exclude.namespaces={kube-system,monitoring}'`.

## Security

- The pod meets the `restricted` level of the Pod Security Standards: it is admitted in a namespace that enforces this level (`pod-security.kubernetes.io/enforce=restricted`).
- RBAC permissions are read-only: no write permission, no access to Secrets or ConfigMaps. `GET /version` is already allowed by the `system:public-info-viewer` role.
- The token is mounted from its Secret by the kubelet: the agent reads no Secret through the API, and the token appears neither in the values nor in the release manifest.
- **Proxy with credentials.** Credentials in `proxy.url` (`http://user:password@proxy:3128`) are accepted, but they stay in clear text in the release values: `helm get values` shows them, and the Helm release Secret contains them. The chart also renders `proxy.url` as the plain value of the `ONICOST_PROXY_URL` variable, so the credentials appear in the Deployment and pod specs (`kubectl get deployment -o yaml`, `kubectl describe pod`), readable by anyone with `get` on pods or deployments in the namespace, a wider audience than the release Secret. When that is not acceptable, use a proxy without credentials in the URL, or control access at the network level. The agent does not write the credentials to its logs.

## Probes and metrics

Port `8080`, named `http`, serves:

- `/healthz`: the process responds;
- `/readyz`: `200` once the inventory caches are synced and collection has started, `503` before that and during shutdown;
- `/metrics`: metrics in the Prometheus text format:
  - `onicost_agent_build_info`: gauge, `1`, with the label `version`;
  - `onicost_agent_ready`: gauge, `1` once the inventory caches are synced, `0` before and during shutdown;
  - `onicost_agent_buffered_batches`: gauge, batches waiting to be sent;
  - `onicost_agent_accepted_batches_total`: counter, batches accepted by the gateway;
  - `onicost_agent_dropped_batches_total`: counter, batches refused by the gateway, too old or beyond the buffer bound;
  - `onicost_agent_scrape_errors_total`: counter, failed kubelet scrapes.

The chart creates no Service. For a Prometheus that discovers pods through the `prometheus.io/*` annotations, pass them as strings: `--set-string 'podAnnotations.prometheus\.io/scrape=true' --set-string 'podAnnotations.prometheus\.io/port=8080'`. With `--set`, `true` and `8080` become a boolean and a number, which the schema refuses.

As long as the token Secret does not exist, the pod stays in `ContainerCreating` (`FailedMount` event). A new token written to the Secret reaches the mounted file within one to two minutes, without restarting the pod.

## Troubleshooting

```bash
kubectl --namespace onicost get pods
kubectl --namespace onicost logs deployment/onicost-agent
```

## Uninstall

```bash
helm uninstall onicost-agent --namespace onicost && kubectl delete namespace onicost
```

`helm uninstall` also deletes the ClusterRole and the ClusterRoleBinding; deleting the namespace deletes the token Secret.
