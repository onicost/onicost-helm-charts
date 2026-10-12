#!/usr/bin/env bash
# Checks of the onicost-agent chart, run by the ci and release workflows: lint, rendering and schema refusals.
set -euo pipefail

chart=charts/onicost-agent
endpoint=(--set endpoint=https://ingest.example.test)

# refuses WANT ARGS...: helm template with ARGS must fail with an error that contains WANT.
refuses() {
  local want=$1 err
  shift
  if err=$(helm template onicost-agent "$chart" "$@" 2>&1 > /dev/null); then
    echo "accepted: $*" >&2
    exit 1
  fi
  if [[ $err != *"$want"* ]]; then
    echo "refused without '$want': $*: $err" >&2
    exit 1
  fi
}

helm lint "$chart" --strict
helm template onicost-agent "$chart" "${endpoint[@]}" > /dev/null

# Every optional value set: each optional branch is rendered, and podLabels never change the selector labels.
helm lint "$chart" --strict -f scripts/values-all.yaml
manifests=$(helm template onicost-agent "$chart" -f scripts/values-all.yaml)
if grep -q 'app.kubernetes.io/name: other' <<< "$manifests"; then
  echo 'podLabels override the selector labels' >&2
  exit 1
fi

# podLabels may be null.
helm template onicost-agent "$chart" "${endpoint[@]}" --set podLabels=null > /dev/null
helm template onicost-agent "$chart" "${endpoint[@]}" --set-json podLabels=null > /dev/null

# The notes name the image tag that is deployed.
notes=$(helm install onicost-agent "$chart" --dry-run=client "${endpoint[@]}" --set image.tag=9.9.9)
if [[ $notes != *'Onicost agent 9.9.9 is installed'* ]]; then
  echo 'NOTES.txt does not name the deployed image tag' >&2
  exit 1
fi

# The NetworkPolicy is rendered only when enabled.
if helm template onicost-agent "$chart" "${endpoint[@]}" | grep -q '^kind: NetworkPolicy$'; then
  echo 'NetworkPolicy rendered while networkPolicy.enabled is false' >&2
  exit 1
fi

# netpol ARGS...: spec of the NetworkPolicy rendered with ARGS.
netpol() {
  helm template onicost-agent "$chart" --show-only templates/networkpolicy.yaml "$@" | sed -n '/^spec:/,$p'
}

# same NAME WANT GOT: fails with a diff when GOT is not WANT.
same() {
  if [[ $3 != "$2" ]]; then
    echo "unexpected $1:" >&2
    diff <(echo "$2") <(echo "$3") >&2 || true
    exit 1
  fi
}

# Default: egress to the cluster DNS and to the TCP ports at any address, no ingress rule.
same 'default NetworkPolicy' "$(cat <<'EOF'
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: onicost-agent
      app.kubernetes.io/instance: onicost-agent
  policyTypes:
    - Egress
  egress:
    # Cluster DNS.
    - ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
      to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
    # API server, kubelets and gateway.
    - ports:
        - port: 443
          protocol: TCP
        - port: 6443
          protocol: TCP
        - port: 10250
          protocol: TCP
EOF
)" "$(netpol "${endpoint[@]}" --set networkPolicy.enabled=true)"

# Every option: CIDR allow-list, extra egress rules appended, ingress on the metrics port.
same 'NetworkPolicy of values-all.yaml' "$(cat <<'EOF'
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: onicost-agent
      app.kubernetes.io/instance: onicost-agent
  policyTypes:
    - Egress
    - Ingress
  egress:
    # Cluster DNS.
    - ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
      to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: coredns
    # API server, kubelets and gateway.
    - ports:
        - port: 443
          protocol: TCP
        - port: 6443
          protocol: TCP
        - port: 10250
          protocol: TCP
        - port: 3128
          protocol: TCP
      to:
        - ipBlock:
            cidr: "10.0.0.0/8"
        - ipBlock:
            cidr: "192.0.2.10/32"
    - ports:
      - port: 53
        protocol: UDP
      to:
      - ipBlock:
          cidr: 169.254.20.10/32
  ingress:
    # Metrics.
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
          podSelector:
            matchLabels:
              app.kubernetes.io/name: prometheus
      ports:
        - port: http
          protocol: TCP
EOF
)" "$(netpol -f scripts/values-all.yaml)"

# Both DNS selectors cleared: port 53 to any destination. One empty selector matches everything, in any namespace.
policy=$(netpol "${endpoint[@]}" --set networkPolicy.enabled=true \
  --set networkPolicy.dns.namespaceSelector=null --set networkPolicy.dns.podSelector=null)
if grep -Eq '^ *(- )?to:' <<< "$policy"; then
  echo 'DNS rule restricted although both DNS selectors are empty' >&2
  exit 1
fi
policy=$(netpol "${endpoint[@]}" --set networkPolicy.enabled=true --set 'networkPolicy.dns.namespaceSelector.kubernetes\.io/metadata\.name=null')
if ! grep -q '^        - namespaceSelector: {}$' <<< "$policy"; then
  echo 'empty DNS namespace selector does not match every namespace' >&2
  exit 1
fi

# No egress port: no port rule, which would otherwise allow every port.
policy=$(netpol "${endpoint[@]}" --set networkPolicy.enabled=true --set-json 'networkPolicy.egressPorts=[]')
if grep -q 'API server' <<< "$policy"; then
  echo 'port rule rendered without egress ports' >&2
  exit 1
fi

refuses 'endpoint is required'
refuses 'endpoint is required' --set endpoint=
refuses schema --set endpoint=ingest.example.test
refuses schema "${endpoint[@]}" --set proxy.url=socks5://proxy:1080
refuses schema "${endpoint[@]}" --set unknown=1
refuses schema "${endpoint[@]}" --set token.value=x
refuses schema "${endpoint[@]}" --set token.existingSecrets=x
refuses schema "${endpoint[@]}" --set kubelet.insecureSkipVerfy=true
refuses schema "${endpoint[@]}" --set 'exclude.namespace={a}'
refuses schema "${endpoint[@]}" --set proxy.uri=x
refuses schema "${endpoint[@]}" --set image.tags=x
refuses schema "${endpoint[@]}" --set scrapeInterval=45s
refuses schema "${endpoint[@]}" --set image.pullPolicy=Sometimes
refuses schema "${endpoint[@]}" --set token.existingSecret=
refuses schema "${endpoint[@]}" --set token.secretKey=
refuses schema "${endpoint[@]}" --set image.repository=
refuses schema "${endpoint[@]}" --set networkPolicy.enable=true
refuses schema "${endpoint[@]}" --set networkPolicy.dns.namespace=x
refuses schema "${endpoint[@]}" --set 'networkPolicy.egressPorts={0}'
refuses schema "${endpoint[@]}" --set 'networkPolicy.egressPorts={65536}'
refuses schema "${endpoint[@]}" --set 'networkPolicy.egressCidrs={10.0.0.0}'
refuses schema "${endpoint[@]}" --set-json 'networkPolicy.metricsFrom=["x"]'
