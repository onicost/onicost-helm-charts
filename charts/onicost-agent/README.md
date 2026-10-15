# Onicost agent Helm chart

The Onicost agent observes the cluster it runs in, collects the CPU and memory usage from the kubelets, the GPU capacity of the nodes and the size of AWS Fargate pods, and pushes the inventory and the samples to the Onicost ingestion gateway, once a minute.

The chart is published in OCI format: `oci://ghcr.io/onicost/charts/onicost-agent`.

Its objects carry the release name (`onicost-agent` with the install command). The ServiceAccount, the Deployment and the optional NetworkPolicy are created in the release namespace, the ClusterRole and the ClusterRoleBinding at the cluster level:

| Object | Role |
|---|---|
| ServiceAccount `onicost-agent` | Identity of the agent |
| ClusterRole `onicost-agent` | Read-only (`get`, `list`, `watch`) on nodes, pods, namespaces, `apps` and `batch` controllers, PVs and PVCs; `get` on `nodes/metrics`, and on `nodes/proxy` only with `kubelet.apiServerProxy=true`. No access to Secrets or ConfigMaps, no write permission |
| ClusterRoleBinding `onicost-agent` | Binds the ClusterRole to the ServiceAccount |
| Deployment `onicost-agent` | One replica, `Recreate` strategy, non-root container (`65532`), read-only root filesystem, no capabilities, seccomp `RuntimeDefault`: `restricted` level of the Pod Security Standards |
| NetworkPolicy `onicost-agent` | Only with `networkPolicy.enabled=true`: the egress the agent needs in a namespace that denies traffic by default, see [Network policies](#network-policies) |

The chart creates neither the namespace nor the token Secret, and accepts no token value.

## Installation

The full install command, with the token, is given by the Onicost interface, when a cluster is created and at each rotation of its token. It prompts for the token without echoing it, creates the `onicost` namespace and the `onicost-agent-token` Secret with server-side apply (the token goes through the standard input of `kubectl`, never through a command line or the values), then installs or upgrades the release:

```bash
helm upgrade --install onicost-agent oci://ghcr.io/onicost/charts/onicost-agent --version <version> \
  --namespace onicost --reset-then-reuse-values --set endpoint=<gateway URL>
```

Requirements: bash or zsh, Kubernetes and `kubectl` 1.22 or later, Helm 3.14 or later (for `--reset-then-reuse-values`), cluster administrator permissions.

## Upgrade

To move to another chart version, rerun only the `helm` part of the command with the new `--version` value. To change an option without touching the token, likewise rerun the `helm` part, followed by the option.

`--reset-then-reuse-values` starts from the default values of the requested chart version and keeps the options given before. To remove an option, set it back to its default value: `--set kubelet.insecureSkipVerify=false`, `--set-json 'exclude.namespaces=[]'` or `--set proxy.url=`.

### Upgrade to 0.4.0

Chart 0.4.0 deploys the agent 0.4.0, which also sends the `ephemeral-storage` request of each container and, on the AWS Fargate nodes of an EKS cluster, the size Fargate provisions for each pod, read from the `CapacityProvisioned` annotation of the pod: Onicost prices a Fargate pod on that size, and leaves it unpriced with an older agent. It is the only annotation the agent reads, on the pods of a Fargate node only, and it is never sent as is. The values, the RBAC and the network flows do not change:

```bash
helm upgrade onicost-agent oci://ghcr.io/onicost/charts/onicost-agent --version 0.4.0 \
  --namespace onicost --reset-then-reuse-values
```

Onicost recognises a Fargate node by its `eks.amazonaws.com/compute-type` label, or by its `fargate-ip-` name: keep this label out of `exclude.labelKeys`. The agent reads it on the node whatever `exclude.labelKeys` says, since the exclusion only applies to what is sent.

### Upgrade to 0.3.0

Chart 0.3.0 deploys the agent 0.3.0, which also sends the GPU capacity of the nodes and the GPU requests of the containers, by resource (`nvidia.com/gpu`, `nvidia.com/gpu.shared`, `nvidia.com/mig-*`, `amd.com/gpu`, `gpu.intel.com/*`, `habana.ai/*`). The values, the RBAC and the network flows do not change, and nothing has to be installed on the GPU nodes besides their usual device plugin:

```bash
helm upgrade onicost-agent oci://ghcr.io/onicost/charts/onicost-agent --version 0.3.0 \
  --namespace onicost --reset-then-reuse-values
```

Onicost reads the GPU model and memory from the node labels (NVIDIA GPU Feature Discovery, GKE, EKS, Karpenter, AKS) and from the instance type: keep these labels out of `exclude.labelKeys`.

## Values

`values.schema.json` rejects any unknown key at the top level and in `token`, `kubelet`, `exclude`, `proxy`, `image`, `networkPolicy`, `networkPolicy.dns` and the items of `imagePullSecrets`, as well as any value of the wrong type: a typo in these keys makes `helm upgrade` fail without changing the release. `resources`, `affinity` and the items of `tolerations`, `networkPolicy.extraEgress` and `networkPolicy.metricsFrom` follow the Kubernetes objects and are not checked key by key.

| Key | Default | Meaning |
|---|---|---|
| `endpoint` | `""` | Required: rendering fails when it is empty. Base URL of the gateway (`http://` or `https://`), without a trailing `/`; the agent appends `/v1/ingest/usage` and `/v1/ingest/inventory` to it |
| `token.existingSecret` | `onicost-agent-token` | Existing Secret of the release namespace that holds the token. Not empty |
| `token.secretKey` | `token` | Key of the token in that Secret, mounted as the file `token`. Not empty |
| `kubelet.insecureSkipVerify` | `false` | `false`: the certificate of each kubelet is verified with the cluster authority. `true`: no verification, for kubelets with self-signed certificates |
| `kubelet.apiServerProxy` | `false` | `true`: the ClusterRole grants `get` on `nodes/proxy`, so that a kubelet whose certificate fails the checks, neither valid for the node address or name nor signed by the cluster authority, is scraped through the API server proxy, as on Scaleway Kapsule. See [Security](#security) |
| `scrapeInterval` | `30s` | Interval between two scrapes of a kubelet: `10s`, `15s`, `20s`, `30s` or `60s` |
| `exclude.namespaces` | `[]` | Exact names of the namespaces of which nothing is sent: neither the namespace, nor its workloads, nor the usage of its containers, nor its PVCs and their PVs |
| `exclude.labelKeys` | `[]` | Exact label keys removed before sending (nodes, namespaces, workloads) |
| `proxy.url` | `""` | Outgoing HTTP proxy (`http://` or `https://`), used only to reach the gateway. Empty: direct connection |
| `image.repository` | `ghcr.io/onicost/onicost-agent` | Image repository. Not empty |
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
| `networkPolicy.enabled` | `false` | `true`: creates a NetworkPolicy for the agent pod, see [Network policies](#network-policies) |
| `networkPolicy.dns.namespaceSelector` | `kubernetes.io/metadata.name: kube-system` | Labels of the namespace of the cluster DNS pods. Empty or `null`: every namespace |
| `networkPolicy.dns.podSelector` | `k8s-app: kube-dns` | Labels of the cluster DNS pods. Empty or `null`: every pod. Both selectors empty: port `53` to any destination |
| `networkPolicy.egressPorts` | `[443, 6443, 10250]` | TCP ports allowed in egress: API server, kubelets and gateway. Empty: no such rule |
| `networkPolicy.egressCidrs` | `[]` | CIDRs the egress ports are restricted to. Empty: any destination |
| `networkPolicy.extraEgress` | `[]` | `NetworkPolicyEgressRule` objects appended as-is to the egress rules |
| `networkPolicy.metricsFrom` | `[]` | `NetworkPolicyPeer` objects allowed to reach the port `http` (`8080`). Empty: no ingress rule, and the policy does not restrict ingress |

The `global` key is accepted, for use as a subchart, and is not read.

Lists on the command line: `--set 'exclude.namespaces={kube-system,monitoring}'`.

## Security

- The pod meets the `restricted` level of the Pod Security Standards: it is admitted in a namespace that enforces this level (`pod-security.kubernetes.io/enforce=restricted`).
- RBAC permissions are read-only: no write permission, no access to Secrets or ConfigMaps. `GET /version` is already allowed by the `system:public-info-viewer` role.
- **Kubelets through the API server.** When a kubelet certificate fails the checks, the agent scrapes that kubelet through the API server proxy, `GET /api/v1/nodes/<node>/proxy/metrics/resource`, which needs `get` on `nodes/proxy`. The chart grants it only with `--set kubelet.apiServerProxy=true`: this permission opens the whole kubelet API of every node, not only its metrics, such as the logs of every pod. Without it, the agent logs that the API server refused to proxy the kubelet and that node is not scraped. `kubelet.insecureSkipVerify=true` is the other way out, without the permission but without checking the kubelet certificates.
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

## Network policies

In a namespace that denies traffic by default, typically with a `default-deny-all` NetworkPolicy that Kyverno or a similar policy engine generates in every namespace, the agent reaches nothing: its inventory caches never sync, `/readyz` keeps answering `503` and the pod stays not ready. With `networkPolicy.enabled=true`, the chart creates a NetworkPolicy, named after the release, that selects the agent pod and allows the traffic it needs:

| Destination | Port | Values |
|---|---|---|
| Cluster DNS | UDP and TCP `53` | `networkPolicy.dns` |
| Kubernetes API server | TCP `6443`, or `443` on some clouds | `networkPolicy.egressPorts`, `networkPolicy.egressCidrs` |
| Kubelets, on the node addresses | TCP `10250` | `networkPolicy.egressPorts`, `networkPolicy.egressCidrs` |
| Ingestion gateway | TCP `443` | `networkPolicy.egressPorts`, `networkPolicy.egressCidrs` |

```bash
helm upgrade --install onicost-agent oci://ghcr.io/onicost/charts/onicost-agent --version <version> \
  --namespace onicost --reset-then-reuse-values --set endpoint=<gateway URL> --set networkPolicy.enabled=true
```

NetworkPolicies are additive: this one allows these flows for the agent pod alone, on top of the other policies of the namespace, a default deny included. It isolates the pod in egress only, and in ingress as well when `networkPolicy.metricsFrom` is set. The probes come from the kubelet of the node and need no rule.

- **API server.** Most network plugins apply the policies after the translation of the `kubernetes` Service: the allowed port is that of its endpoints, `6443` on many clusters, not the port `443` of the Service. The endpoints: `kubectl get endpointslices --namespace default --selector kubernetes.io/service-name=kubernetes`. Add their port to `egressPorts` when it is neither `443` nor `6443`.
- **Kubelets.** The agent reads the port published by each node, `10250` by default: `kubectl get nodes -o jsonpath='{.items[*].status.daemonEndpoints.kubeletEndpoint.Port}'`.
- **DNS.** The defaults match CoreDNS (`k8s-app: kube-dns` in `kube-system`). Helm merges these maps with the defaults: to replace a label, set the default one to `null`: `--set networkPolicy.dns.podSelector.k8s-app=null --set networkPolicy.dns.podSelector.app=coredns`. With NodeLocal DNSCache or a resolver outside the cluster, clear both selectors, which allows port `53` to any destination: `--set networkPolicy.dns.namespaceSelector=null --set networkPolicy.dns.podSelector=null`.
- **Proxy.** With `proxy.url`, the agent reaches the proxy instead of the gateway: add the port of the proxy to `egressPorts`.
- **Address allow-list.** `egressCidrs` restricts the ports to these ranges, which must then cover the endpoints of the API server, the node addresses and the gateway, or the proxy: `--set 'networkPolicy.egressCidrs={10.0.0.0/8,203.0.113.10/32}'`. Some network plugins do not match the node addresses with an `ipBlock` by default, Cilium for one: keep `egressCidrs` empty with them.
- **Other flows.** `extraEgress` appends egress rules as they are written, for example to a destination these rules do not cover.
- **Metrics.** To let a Prometheus of another namespace scrape `/metrics`: `--set-json 'networkPolicy.metricsFrom=[{"namespaceSelector":{"matchLabels":{"kubernetes.io/metadata.name":"monitoring"}}}]'`.

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
