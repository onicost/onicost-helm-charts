# Operations

## Upgrade

```bash
helm upgrade onicost-agent oci://ghcr.io/onicost/charts/onicost-agent \
  --version <version> --namespace onicost --reset-then-reuse-values
```

`--reset-then-reuse-values` starts from the defaults of the new chart version and keeps the options you set before. To drop an option, set it back to its default, for example `--set proxy.url=`. To change an option without upgrading, run the same command with the current version and the option. Read the [changelog](../CHANGELOG.md) before upgrading.

## Pin a version

Always pass `--version`. Each chart version deploys the agent image of its `appVersion`; `image.tag` overrides it, which you should rarely need. To see what runs:

```bash
helm list --namespace onicost
```

## Uninstall

```bash
helm uninstall onicost-agent --namespace onicost
kubectl delete namespace onicost
```

`helm uninstall` also deletes the ClusterRole and the ClusterRoleBinding. Deleting the namespace deletes the token Secret. In [actions mode](security.md#actions-mode), pause or delete the scheduler rules in Onicost and wait for the workloads to come back on before uninstalling.

## Metrics

Port `8080`, named `http`, serves `/healthz`, `/readyz` and `/metrics` in the Prometheus format. The chart creates no Service.

| Metric | Type | Meaning |
|---|---|---|
| `onicost_agent_ready` | gauge | `1` once the inventory is synced |
| `onicost_agent_dependency_up` | gauge | `1` when the dependency of the `dependency` label (`kubernetes_api`, `kubelet`, `gateway`) answered |
| `onicost_agent_buffered_batches` | gauge | Batches waiting to be sent |
| `onicost_agent_accepted_batches_total` | counter | Batches accepted by Onicost |
| `onicost_agent_dropped_batches_total` | counter | Batches refused, too old or beyond the buffer bound |
| `onicost_agent_scrape_errors_total` | counter | Failed kubelet scrapes |
| `onicost_agent_build_info` | gauge | `1`, with the agent `version` label |

For a Prometheus that discovers pods by annotation, pass the annotations as strings, since the schema refuses booleans and numbers:

```bash
--set-string 'podAnnotations.prometheus\.io/scrape=true' --set-string 'podAnnotations.prometheus\.io/port=8080'
```

In a namespace with `networkPolicy.enabled=true`, also allow Prometheus with `networkPolicy.metricsFrom`.

## Logs

```bash
kubectl --namespace onicost logs deployment/onicost-agent
```

Warnings name the blocked flow and carry an `errorClass` (`dns`, `timeout`, `connection_refused`, `tls_verification`, `http_status`...). The agent never logs its token.

## Troubleshooting

1. **Pod stuck in `ContainerCreating`.** The token Secret is missing: `kubectl --namespace onicost get secret onicost-agent-token`. Create it as in [Install](install.md#token).
2. **Pod running but never ready.** The agent cannot reach the API server, usually because of a default-deny NetworkPolicy. Look for `kubernetes api unreachable` in the logs and enable the [network policy](install.md#network-policy).
3. **No data in Onicost.** Look for `gateway unreachable` or a `401` in the logs. Check the endpoint and the proxy with `helm get values onicost-agent --namespace onicost`, and that the Secret holds the current token. For kubelet errors with `errorClass: tls_verification`, see [Kubelet certificates](install.md#kubelet-certificates).
