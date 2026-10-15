# Install

## Prerequisites

- Kubernetes 1.22 or later, and `kubectl` with cluster-admin rights: the chart creates a ClusterRole.
- Helm 3.14 or later.
- Outbound HTTPS from the cluster to the Onicost endpoint, directly or through a proxy.

## Token

Each cluster has its own agent token, shown in the Onicost interface when you add the cluster or rotate its token. Store it in a Secret of the release namespace. The chart mounts it from there and never accepts the token as a value.

```bash
kubectl create namespace onicost
printf 'Agent token: ' && read -rs ONICOST_TOKEN && echo
printf '%s' "$ONICOST_TOKEN" | kubectl create secret generic onicost-agent-token \
  --namespace onicost --from-file=token=/dev/stdin
```

To rotate the token, write the new one to the same Secret, for example by adding `--dry-run=client -o yaml | kubectl apply -f -` to the `kubectl create secret` command. The agent picks it up within two minutes, without a restart.

Another Secret name or key: set `token.existingSecret` and `token.secretKey`.

## Endpoint

`endpoint` is required: the base URL of the Onicost ingestion gateway, without a trailing slash. For Onicost SaaS it is `https://ingest.onicost.com`.

```bash
helm upgrade --install onicost-agent oci://ghcr.io/onicost/charts/onicost-agent \
  --version <version> --namespace onicost --set endpoint=https://ingest.onicost.com
```

## Options

### Outbound proxy

```bash
--set proxy.url=http://proxy.internal:3128
```

The proxy is used only to reach the endpoint. The API server and the kubelets are reached directly. Credentials in the URL show in clear text in the pod spec: prefer a proxy that does not need them.

### Network policy

If the namespace denies traffic by default, the agent never becomes ready. Enable the chart's NetworkPolicy:

```bash
--set networkPolicy.enabled=true
```

It allows egress to the cluster DNS and to TCP 443, 6443 and 10250 (endpoint, API server, kubelets). Adapt it when needed:

- **API server on another port**: find it with `kubectl get endpointslices -n default -l kubernetes.io/service-name=kubernetes` and add it to `networkPolicy.egressPorts`.
- **Proxy**: add the proxy port to `networkPolicy.egressPorts`.
- **DNS other than CoreDNS in `kube-system`** (NodeLocal DNSCache, external resolver): `--set networkPolicy.dns.namespaceSelector=null --set networkPolicy.dns.podSelector=null` allows port 53 to any destination.
- **Destination allow-list**: `networkPolicy.egressCidrs` must then cover the API server, the node addresses and the endpoint. Leave it empty with Cilium, which does not match node addresses with `ipBlock` by default.

### Kubelet certificates

On some managed clusters, Scaleway Kapsule for one, the agent cannot verify the kubelet certificates. Set `kubelet.apiServerProxy=true` to scrape these kubelets through the API server. Read [Security](security.md#the-nodesproxy-option) first: it grants an extra permission.

## Check the agent

```bash
kubectl --namespace onicost get pods
kubectl --namespace onicost logs deployment/onicost-agent
```

The pod is `Running` and ready (`1/1`) within a minute. Ready means the inventory is synced and collection has started. At startup the log says whether the API server and the endpoint are reachable, and names any blocked flow. If something is wrong, see [Troubleshooting](operations.md#troubleshooting).
