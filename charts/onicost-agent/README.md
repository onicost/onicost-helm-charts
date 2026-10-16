# onicost-agent

Helm chart of the Onicost agent, which sends the inventory and the container usage of a Kubernetes cluster to Onicost. The agent is read-only by default; `actions.enabled` lets it switch workloads off and on for the Onicost scheduler. Install, operations and security guides: [github.com/onicost/onicost-helm-charts](https://github.com/onicost/onicost-helm-charts#documentation).

```bash
helm upgrade --install onicost-agent oci://ghcr.io/onicost/charts/onicost-agent \
  --version <version> --namespace onicost --set endpoint=https://ingest.onicost.com
```

The token Secret must exist first, see the [install guide](https://github.com/onicost/onicost-helm-charts/blob/main/docs/install.md#token).

## Values

The schema refuses unknown keys and wrong types, so a misspelled key fails the install or the upgrade.

| Key | Default | Description |
|---|---|---|
| `endpoint` | `""` | Required. Base URL of the Onicost ingestion gateway, `http://` or `https://`, without a trailing `/` |
| `token.existingSecret` | `onicost-agent-token` | Existing Secret of the release namespace that holds the agent token |
| `token.secretKey` | `token` | Key of the token in that Secret |
| `kubelet.insecureSkipVerify` | `false` | `true`: kubelet certificates are not verified. Last resort, on a trusted node network |
| `kubelet.apiServerProxy` | `false` | `true`: grants `get` on `nodes/proxy` to scrape, through the API server, the kubelets whose certificate fails verification (Scaleway Kapsule). Opens the whole kubelet API of every node |
| `actions.enabled` | `false` | `true`: actions mode of the Onicost scheduler. The ClusterRole grants `patch` and `update` on Deployments, StatefulSets and CronJobs, `get`, `patch` and `update` on `deployments/scale` and `statefulsets/scale`, and `get`, `list`, `watch`, `patch` and `update` on HorizontalPodAutoscalers, so that the agent switches off and on the workloads of the rules activated in Onicost. `false`: read-only, the ClusterRole has no write rule. See [Security](https://github.com/onicost/onicost-helm-charts/blob/main/docs/security.md#actions-mode) |
| `scrapeInterval` | `30s` | Interval between two kubelet scrapes: `10s`, `15s`, `20s`, `30s` or `60s` |
| `exclude.namespaces` | `[]` | Namespaces of which nothing is sent |
| `exclude.labelKeys` | `[]` | Label keys removed before sending. Keep the GPU node labels (such as `nvidia.com/gpu.product`) and `eks.amazonaws.com/compute-type`: Onicost prices GPU and Fargate nodes from them |
| `proxy.url` | `""` | Outgoing HTTP proxy, `http://` or `https://`, used only to reach the gateway. Empty: direct connection |
| `image.repository` | `ghcr.io/onicost/onicost-agent` | Agent image |
| `image.tag` | `""` | Empty: the chart `appVersion` |
| `image.pullPolicy` | `IfNotPresent` | `Always`, `IfNotPresent` or `Never` |
| `resources` | requests `50m` CPU and `64Mi`, limit `256Mi` | Container resources. The memory limit covers the send buffer (two hours, 64 MiB at most) |
| `imagePullSecrets` | `[]` | Pull Secrets, as `{name: <Secret>}` |
| `podAnnotations` | `{}` | Pod annotations, string values |
| `podLabels` | `{}` | Extra pod labels, string values. Cannot override the chart labels |
| `priorityClassName` | `""` | PriorityClass of the pod |
| `nodeSelector` | `{}` | Node selector of the pod |
| `tolerations` | `[]` | Pod tolerations |
| `affinity` | `{}` | Pod affinity |
| `networkPolicy.enabled` | `false` | `true`: creates a NetworkPolicy that allows the agent's egress, for namespaces that deny traffic by default |
| `networkPolicy.dns.namespaceSelector` | `kubernetes.io/metadata.name: kube-system` | Namespace of the cluster DNS. `null`: every namespace |
| `networkPolicy.dns.podSelector` | `k8s-app: kube-dns` | Cluster DNS pods. `null`: every pod; both `null`: port 53 to any destination |
| `networkPolicy.egressPorts` | `[443, 6443, 10250]` | TCP ports the agent reaches: gateway, API server, kubelets |
| `networkPolicy.egressCidrs` | `[]` | CIDRs the egress ports are restricted to. Empty: any destination |
| `networkPolicy.extraEgress` | `[]` | Extra egress rules, appended as-is |
| `networkPolicy.metricsFrom` | `[]` | Peers allowed to reach the metrics port `8080`. Empty: no ingress rule |

Lists on the command line: `--set 'exclude.namespaces={kube-system,monitoring}'`. Helm merges maps with the defaults: set a key to `null` to remove it.
