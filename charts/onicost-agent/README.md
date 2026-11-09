# onicost-agent

Helm chart of the Onicost agent, which sends the inventory and the container usage of a Kubernetes cluster to Onicost. The agent is read-only by default. It acts only in two optional modes. In the [actions mode](https://github.com/onicost/onicost-helm-charts/blob/main/docs/security.md#actions-mode) of the Onicost scheduler, which `actions.enabled` turns on: with dedicated permissions, it switches workloads off and on at the times of the rules you activate, and each action is recorded in the scheduler journal. The [auto-resize mode](#auto-resize-mode), which `autoresize.enabled` turns on, lets it lower the requests of the pods Onicost validated, in place and at their creation, on Kubernetes 1.35 or later. Install, operations and security guides: [github.com/onicost/onicost-helm-charts](https://github.com/onicost/onicost-helm-charts#documentation).

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
| `actions.enabled` | `false` | `true`: actions mode of the Onicost scheduler. The ClusterRole grants `patch` on Deployments, StatefulSets and CronJobs, and `get`, `list`, `watch` and `patch` on HorizontalPodAutoscalers, no `update` and no scale subresource, so that the agent switches off and on the workloads of the rules activated in Onicost. `false`: read-only, the ClusterRole has no write rule. See [Security](https://github.com/onicost/onicost-helm-charts/blob/main/docs/security.md#actions-mode) |
| `autoresize.enabled` | `false` | `true`: [auto-resize mode](#auto-resize-mode), Kubernetes 1.35 or later. Adds `patch` on `pods/resize`, `create` on `pods/eviction` and `get`, `list`, `watch` on `verticalpodautoscalers` to the ClusterRole, a Role on the ConfigMap `onicost-autoresize-state` of the release namespace, and the admission webhook with its Service, its certificate Secret and, with `networkPolicy.enabled`, an ingress rule on `9443`. `false`: none of them is rendered. Independent of `actions.enabled` |
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

## Auto-resize mode

The auto-resize mode needs the chart 0.7.0 or later and Kubernetes 1.35 or later, for the API server and for the kubelets: it resizes pods in place, which is generally available from 1.35. On an older cluster, Onicost keeps the mode off and says why. It is off by default, and turning it on changes no pod by itself: the agent acts only on the workloads of the namespaces you label and activate in Onicost, with the values Onicost validated after the observation period.

```bash
helm upgrade onicost-agent oci://ghcr.io/onicost/charts/onicost-agent --version <version> \
  --namespace onicost --reset-then-reuse-values --set autoresize.enabled=true
kubectl label namespace <namespace> onicost.com/autoresize=enabled
```

The agent then lowers the requests of the running pods in place, one step at a time, a canary pod first, and watches them: on an OOM kill, restarts, throttling, failing probes or a resize refused, it puts the values of the pod template back and freezes the workload. The admission webhook gives a new pod (a rollout, a scale-up, a node lost) the last validated values of its workload, so that it does not start again from the values of its template. The Deployments and StatefulSets are never changed: Argo CD and Flux see no drift.

Rights added by the mode, and why:

| Rule | Why |
|---|---|
| `patch` on `pods/resize` (ClusterRole) | Resize the running pods in place, down, and back up on a roll back |
| `create` on `pods/eviction` (ClusterRole) | Evict a pod whose roll back in place stays refused or pending, through the Eviction API, which honours its PodDisruptionBudget. The pod is recreated with the values of its template |
| `get`, `list`, `watch` on `verticalpodautoscalers.autoscaling.k8s.io` (ClusterRole) | Leave alone the workloads a VerticalPodAutoscaler drives. Read only; without the CRD, nothing is read |
| `get`, `patch` on the ConfigMap `onicost-autoresize-state`, `create` on ConfigMaps (Role of the release namespace) | Keep the freezes, steps and canaries across restarts of the agent. RBAC cannot restrict `create` to a name, since the request is authorized before the object exists: the agent creates only this ConfigMap, in its own namespace |

The agent never updates nor deletes a pod, never writes a Deployment, a StatefulSet or a VerticalPodAutoscaler, and has no right on its MutatingWebhookConfiguration, which the chart installs. RBAC cannot restrict `pods/resize` and `pods/eviction` to some namespaces: the agent enforces the namespaces itself, and never acts in `kube-system`, `kube-public`, `kube-node-lease`, `argocd`, `flux-system`, its own namespace and `exclude.namespaces`.

The mode also renders:

- the Service `<release>-autoresize`, port `443` to the port `9443` of the agent;
- the MutatingWebhookConfiguration `<release>-autoresize`, called on the `CREATE` of pods only, in the namespaces labelled `onicost.com/autoresize=enabled` only, never the release namespace nor `kube-system` even labelled, with `failurePolicy: Ignore`, `timeoutSeconds: 2`, `sideEffects: None` and `reinvocationPolicy: Never`. The webhook never refuses a pod: when the agent is down, slow or in doubt, the pod is created with the values of its template, and only the gain is lost;
- the Secret `<release>-autoresize-tls`, with a certificate for `<release>-autoresize.<namespace>.svc` and its CA, generated by Helm for 10 years and kept across upgrades: the chart reads it back with `lookup`. To renew it, delete the Secret and upgrade; the agent reads the new one within two minutes. `helm template` and `--dry-run=client` cannot read it back and generate a new one at each render: with a tool that renders the chart that way, such as Argo CD, ignore the differences on the data of this Secret and on the `caBundle` of the MutatingWebhookConfiguration;
- with `networkPolicy.enabled`, an ingress rule on TCP `9443` from any source: the API server calls the webhook from an address the chart does not know, often outside the pod network.

To stop the mode:

1. Use the emergency stop of the Onicost app first, for the organization or the cluster: the workloads go back to the values of their templates, in place, and the webhook stops changing new pods. For one workload, annotate it `onicost.com/autoresize: ignore`.
2. Then turn the mode off with `--set autoresize.enabled=false`: it removes the rights, the Role, the webhook, its Service and its Secret.
3. When the mode was turned off before the restore, the agent can no longer put the values back: the pods keep their lowered values until they are recreated. Recreate them with `kubectl rollout restart deployment/<name> --namespace <namespace>`, or `statefulset/<name>`, for each workload of the journal of the app.
