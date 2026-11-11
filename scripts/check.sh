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

# Every option: CIDR allow-list, extra egress rules appended, ingress on the metrics port and on the webhook port.
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
    # Admission webhook of the auto-resize, called by the API server. Its source address is not known to the chart, and
    # is often outside the pod network (a managed control plane): any source. The webhook answers only over TLS.
    - ports:
        - port: 9443
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

# get on nodes/proxy, which opens the whole kubelet API, is granted only with kubelet.apiServerProxy.
clusterrole() {
  helm template onicost-agent "$chart" --show-only templates/clusterrole.yaml "$@"
}
if clusterrole "${endpoint[@]}" | grep -q 'nodes/proxy'; then
  echo 'nodes/proxy granted while kubelet.apiServerProxy is false' >&2
  exit 1
fi
same 'nodes/proxy rule' "$(cat <<'EOF'
  - apiGroups: [""]
    resources: [nodes/proxy]
    verbs: [get]
EOF
)" "$(clusterrole "${endpoint[@]}" --set kubelet.apiServerProxy=true | grep -B1 -A1 'nodes/proxy')"

# Without actions.enabled the ClusterRole is the read-only one of the chart 0.6.0, byte for byte but the version labels:
# get, list and watch on the inventory resources, HorizontalPodAutoscalers and PodDisruptionBudgets included, and get on
# nodes/metrics.
chart_yaml=$(helm show chart "$chart")
chart_version=$(sed -n 's/^version: *//p' <<< "$chart_yaml" | tr -d '"')
app_version=$(sed -n 's/^appVersion: *//p' <<< "$chart_yaml" | tr -d '"')
read_only_role=$(cat <<EOF
---
# Source: onicost-agent/templates/clusterrole.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: onicost-agent
  labels:
    app.kubernetes.io/name: onicost-agent
    app.kubernetes.io/instance: onicost-agent
    app.kubernetes.io/version: "$app_version"
    app.kubernetes.io/managed-by: Helm
    helm.sh/chart: onicost-agent-$chart_version
rules:
  - apiGroups: [""]
    resources: [nodes, pods, namespaces, persistentvolumes, persistentvolumeclaims]
    verbs: [get, list, watch]
  - apiGroups: [apps]
    resources: [deployments, replicasets, statefulsets, daemonsets]
    verbs: [get, list, watch]
  - apiGroups: [batch]
    resources: [jobs, cronjobs]
    verbs: [get, list, watch]
  - apiGroups: [autoscaling]
    resources: [horizontalpodautoscalers]
    verbs: [get, list, watch]
  - apiGroups: [policy]
    resources: [poddisruptionbudgets]
    verbs: [get, list, watch]
  - apiGroups: [""]
    resources: [nodes/metrics]
    verbs: [get]
EOF
)
same 'default ClusterRole' "$read_only_role" "$(clusterrole "${endpoint[@]}")"
same 'ClusterRole with actions.enabled=false' "$read_only_role" "$(clusterrole "${endpoint[@]}" --set actions.enabled=false)"

# actions.enabled adds the patch rules of the scheduler, and nothing else: no update, no scale subresource, no create,
# no delete, no Secret.
same 'ClusterRole with actions.enabled' "$read_only_role
$(cat <<'EOF'
  # Actions mode of the scheduler: patch replicas, suspend, minReplicas and annotations.
  - apiGroups: [apps]
    resources: [deployments, statefulsets]
    verbs: [patch]
  - apiGroups: [batch]
    resources: [cronjobs]
    verbs: [patch]
  - apiGroups: [autoscaling]
    resources: [horizontalpodautoscalers]
    verbs: [get, list, watch, patch]
EOF
)" "$(clusterrole "${endpoint[@]}" --set actions.enabled=true)"

# The read rules never carry a write verb, whatever the values.
for value in actions.enabled=false actions.enabled=true kubelet.apiServerProxy=true; do
  if clusterrole "${endpoint[@]}" --set "$value" | sed -n '/poddisruptionbudgets/,/verbs/p' | grep -Eq 'patch|update|create|delete'; then
    echo "poddisruptionbudgets granted more than get, list and watch with $value" >&2
    exit 1
  fi
done

# The agent learns the actions mode from ONICOST_ACTIONS_ENABLED and its own namespace, which it never touches,
# from the downward API.
actions_env() {
  helm template onicost-agent "$chart" --show-only templates/deployment.yaml "$@" \
    | sed -n '/- name: ONICOST_ACTIONS_ENABLED$/,/fieldPath:/p'
}
actions_env_want() {
  cat <<EOF
            - name: ONICOST_ACTIONS_ENABLED
              value: "$1"
            # Namespace of the agent, which the scheduler never touches.
            - name: ONICOST_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
EOF
}
same 'default actions variables' "$(actions_env_want false)" "$(actions_env "${endpoint[@]}")"
same 'actions variables with actions.enabled' "$(actions_env_want true)" "$(actions_env "${endpoint[@]}" --set actions.enabled=true)"

# Without autoresize.enabled, nothing of the auto-resize mode is rendered, whatever the other values: no pods/resize, no
# pods/eviction, no VerticalPodAutoscaler, no webhook, no Role of the state, no Secret or Service of the webhook, no port
# 9443 and no variable of the mode.
for args in "" "--set autoresize.enabled=false" "--set actions.enabled=true" "--set networkPolicy.enabled=true" "--set kubelet.apiServerProxy=true"; do
  # shellcheck disable=SC2086
  manifests=$(helm template onicost-agent "$chart" "${endpoint[@]}" $args)
  for word in pods/resize pods/eviction verticalpodautoscalers MutatingWebhookConfiguration '^kind: Role$' '^kind: RoleBinding$' \
    '^kind: Service$' 'kubernetes.io/tls' failurePolicy 9443 ONICOST_AUTORESIZE autoresize; do
    if grep -Eq "$word" <<< "$manifests"; then
      echo "'$word' rendered without autoresize.enabled ($args)" >&2
      exit 1
    fi
  done
done

# autoresize.enabled adds to the ClusterRole patch on pods/resize, create on pods/eviction and get, list and watch on the
# VerticalPodAutoscalers, and nothing else; with actions.enabled too, both sets of rules.
autoresize_rules=$(cat <<'EOF'
  # Auto-resize mode: resize the pods in place, lower and back up.
  - apiGroups: [""]
    resources: [pods/resize]
    verbs: [patch]
  # Auto-resize mode: evict a pod whose roll back in place stays refused, through the Eviction API, which honours its PodDisruptionBudget.
  - apiGroups: [""]
    resources: [pods/eviction]
    verbs: [create]
  # Auto-resize mode: find the workloads a VerticalPodAutoscaler drives, to leave them alone. Read only; nothing is created.
  - apiGroups: [autoscaling.k8s.io]
    resources: [verticalpodautoscalers]
    verbs: [get, list, watch]
EOF
)
same 'ClusterRole with autoresize.enabled' "$read_only_role
$autoresize_rules" "$(clusterrole "${endpoint[@]}" --set autoresize.enabled=true)"
same 'ClusterRole with actions.enabled and autoresize.enabled' "$(clusterrole "${endpoint[@]}" --set actions.enabled=true)
$autoresize_rules" "$(clusterrole "${endpoint[@]}" --set actions.enabled=true --set autoresize.enabled=true)"

# The Role of the state, in the release namespace only: get and patch on the state ConfigMap by name, create without a
# name, which RBAC cannot restrict; bound to the service account of the agent.
same 'Role of the auto-resize' "$(cat <<'EOF'
kind: Role
metadata:
  name: onicost-agent-autoresize
  namespace: onicost
rules:
  - apiGroups: [""]
    resources: [configmaps]
    resourceNames: [onicost-autoresize-state]
    verbs: [get, patch]
  - apiGroups: [""]
    resources: [configmaps]
    verbs: [create]
kind: RoleBinding
metadata:
  name: onicost-agent-autoresize
  namespace: onicost
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: onicost-agent-autoresize
subjects:
  - kind: ServiceAccount
    name: onicost-agent
    namespace: onicost
EOF
)" "$(helm template onicost-agent "$chart" "${endpoint[@]}" --namespace onicost --set autoresize.enabled=true \
  --show-only templates/autoresize-role.yaml | grep -Ev '^(---| *#|apiVersion:|  labels:|    (app.kubernetes.io|helm.sh)/)' | grep -v '^ *$')"

# The webhook never blocks a pod: failurePolicy Ignore, a 2 s timeout, no side effect, no reinvocation, the CREATE of
# pods only, in every namespace without a label to select it, but the release namespace, the namespaces the agent never
# touches and exclude.namespaces, each once. The caBundle is the CA of the Secret, which signed a certificate of
# <service>.<namespace>.svc.
webhook=$(helm template onicost-agent "$chart" "${endpoint[@]}" --namespace payments-ops --set autoresize.enabled=true \
  --set 'exclude.namespaces={monitoring,kube-system,payments-ops}' --show-only templates/autoresize-webhook.yaml)
same 'MutatingWebhookConfiguration' "$(cat <<'EOF'
webhooks:
  - name: pods.autoresize.onicost.com
    admissionReviewVersions: [v1]
    sideEffects: None
    # A webhook that fails or does not answer leaves the pod with the values of its template.
    failurePolicy: Ignore
    timeoutSeconds: 2
    reinvocationPolicy: Never
    matchPolicy: Equivalent
    clientConfig:
      service:
        name: onicost-agent-autoresize
        namespace: payments-ops
        path: /mutate-pods
        port: 443
    rules:
      - apiGroups: [""]
        apiVersions: [v1]
        operations: [CREATE]
        resources: [pods]
        scope: Namespaced
    # Every namespace but the agent's own, the ones the agent never touches and exclude.namespaces, which the API
    # server does not call the webhook for.
    namespaceSelector:
      matchExpressions:
        - key: kubernetes.io/metadata.name
          operator: NotIn
          values:
            - "payments-ops"
            - "kube-system"
            - "kube-public"
            - "kube-node-lease"
            - "argocd"
            - "flux-system"
            - "monitoring"
EOF
)" "$(sed -n '/^webhooks:/,$p' <<< "$webhook" | grep -v 'caBundle:')"
# No label selects the namespaces, whatever the values: no matchLabels in the namespaceSelector, with the default values
# and with those of values-all.yaml.
for args in "--set autoresize.enabled=true" "-f scripts/values-all.yaml"; do
  # shellcheck disable=SC2086
  selector=$(helm template onicost-agent "$chart" "${endpoint[@]}" $args --show-only templates/autoresize-webhook.yaml \
    | sed -n '/^    namespaceSelector:$/,$p')
  if [[ -z $selector ]] || grep -q 'matchLabels' <<< "$selector"; then
    echo "the namespaceSelector of the webhook selects labelled namespaces ($args)" >&2
    exit 1
  fi
done
same 'Service of the webhook' "$(cat <<'EOF'
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: onicost-agent
    app.kubernetes.io/instance: onicost-agent
  ports:
    - name: webhook
      port: 443
      targetPort: webhook
      protocol: TCP
EOF
)" "$(awk '/^kind: Service$/{s=1} s && /^spec:/{p=1} p && /^---/{exit} p' <<< "$webhook" | grep -v '^ *$')"
tls=$(mktemp -d)
trap 'rm -rf "$tls"' EXIT
secret_value() { sed -n "s/^  $1: //p" <<< "$webhook" | base64 --decode; }
secret_value tls.crt > "$tls/tls.crt"
secret_value ca.crt > "$tls/ca.crt"
secret_value tls.key > "$tls/tls.key"
if [[ $(sed -n 's/^      caBundle: //p' <<< "$webhook" | base64 --decode) != "$(cat "$tls/ca.crt")" ]]; then
  echo 'the caBundle of the webhook is not the CA of its Secret' >&2
  exit 1
fi
if ! grep -q '^type: kubernetes.io/tls$' <<< "$webhook" || ! openssl verify -CAfile "$tls/ca.crt" "$tls/tls.crt" > /dev/null; then
  echo 'the certificate of the webhook is not a TLS Secret signed by its CA' >&2
  exit 1
fi
if ! openssl x509 -in "$tls/tls.crt" -noout -text | grep -q 'DNS:onicost-agent-autoresize.payments-ops.svc'; then
  echo 'the certificate of the webhook does not name onicost-agent-autoresize.payments-ops.svc' >&2
  exit 1
fi
if [[ $(openssl x509 -in "$tls/tls.crt" -noout -pubkey) != "$(openssl pkey -in "$tls/tls.key" -pubout)" ]]; then
  echo 'the key of the webhook does not match its certificate' >&2
  exit 1
fi

# The agent runs in the mode: its variables, the port of the webhook, and the Secret of the certificate mounted read-only.
deployment() {
  helm template onicost-agent "$chart" --show-only templates/deployment.yaml "$@"
}
on=$(deployment "${endpoint[@]}" --set autoresize.enabled=true)
same 'auto-resize variables' "$(cat <<'EOF'
            - name: ONICOST_AUTORESIZE_ENABLED
              value: "true"
            - name: ONICOST_AUTORESIZE_WEBHOOK_ADDR
              value: ":9443"
            - name: ONICOST_AUTORESIZE_TLS_DIR
              value: "/etc/onicost/autoresize-tls"
EOF
)" "$(sed -n '/- name: ONICOST_AUTORESIZE_ENABLED$/,/autoresize-tls"$/p' <<< "$on")"
same 'auto-resize port' "$(cat <<'EOF'
            - name: webhook
              containerPort: 9443
              protocol: TCP
EOF
)" "$(grep -A2 -- '- name: webhook$' <<< "$on")"
same 'auto-resize certificate mount' "$(cat <<'EOF'
          volumeMounts:
            - name: token
              mountPath: /var/run/secrets/onicost
              readOnly: true
            # Certificate of the webhook, read again by the agent when the kubelet updates it.
            - name: autoresize-tls
              mountPath: /etc/onicost/autoresize-tls
              readOnly: true
EOF
)" "$(sed -n '/^          volumeMounts:$/,/^          livenessProbe:$/p' <<< "$on" | sed '$d')"
same 'auto-resize certificate volume' "$(cat <<'EOF'
        - name: autoresize-tls
          secret:
            secretName: "onicost-agent-autoresize-tls"
            defaultMode: 0440
            items:
              - key: tls.crt
                path: tls.crt
              - key: tls.key
                path: tls.key
EOF
)" "$(sed -n '/^        - name: autoresize-tls$/,$p' <<< "$on")"
# Without the mode, the Deployment is that of the chart without the mode, byte for byte.
same 'Deployment with autoresize.enabled=false' "$(deployment "${endpoint[@]}")" "$(deployment "${endpoint[@]}" --set autoresize.enabled=false)"

# The NetworkPolicy opens TCP 9443 in ingress from any source in the mode, the egress rules unchanged.
same 'NetworkPolicy with autoresize.enabled' "$(cat <<'EOF'
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
              k8s-app: kube-dns
    # API server, kubelets and gateway.
    - ports:
        - port: 443
          protocol: TCP
        - port: 6443
          protocol: TCP
        - port: 10250
          protocol: TCP
  ingress:
    # Admission webhook of the auto-resize, called by the API server. Its source address is not known to the chart, and
    # is often outside the pod network (a managed control plane): any source. The webhook answers only over TLS.
    - ports:
        - port: 9443
          protocol: TCP
EOF
)" "$(netpol "${endpoint[@]}" --set networkPolicy.enabled=true --set autoresize.enabled=true)"

refuses 'endpoint is required'
refuses 'endpoint is required' --set endpoint=
refuses schema --set endpoint=ingest.example.test
refuses schema "${endpoint[@]}" --set proxy.url=socks5://proxy:1080
refuses schema "${endpoint[@]}" --set unknown=1
refuses schema "${endpoint[@]}" --set token.value=x
refuses schema "${endpoint[@]}" --set token.existingSecrets=x
refuses schema "${endpoint[@]}" --set kubelet.insecureSkipVerfy=true
refuses schema "${endpoint[@]}" --set-string kubelet.apiServerProxy=true
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
refuses schema "${endpoint[@]}" --set actions=true
refuses schema "${endpoint[@]}" --set actions.enable=true
refuses schema "${endpoint[@]}" --set actions.enabled=null
refuses schema "${endpoint[@]}" --set-string actions.enabled=true
refuses schema "${endpoint[@]}" --set autoresize=true
refuses schema "${endpoint[@]}" --set autoresize.enable=true
refuses schema "${endpoint[@]}" --set autoresize.enabled=null
refuses schema "${endpoint[@]}" --set-string autoresize.enabled=true
