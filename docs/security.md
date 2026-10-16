# Security

## Permissions

The agent's ClusterRole is read-only by default:

| API group | Resources | Verbs |
|---|---|---|
| `""` (core) | `nodes`, `pods`, `namespaces`, `persistentvolumes`, `persistentvolumeclaims` | `get`, `list`, `watch` |
| `apps` | `deployments`, `replicasets`, `statefulsets`, `daemonsets` | `get`, `list`, `watch` |
| `batch` | `jobs`, `cronjobs` | `get`, `list`, `watch` |
| `""` (core) | `nodes/metrics` | `get` |
| `""` (core) | `nodes/proxy` | `get`, only with `kubelet.apiServerProxy=true` |

No access to Secrets or ConfigMaps, and no write permission unless you enable the [actions mode](#actions-mode). The kubelet mounts the token from its Secret: the agent reads no Secret through the API.

The pod meets the `restricted` Pod Security Standard: non-root user `65532`, read-only root filesystem, all capabilities dropped, no privilege escalation, seccomp `RuntimeDefault`.

## What is collected

Sent to Onicost:

- the inventory: nodes (capacity, allocatable, GPU resources, labels), namespaces and workloads with their labels, pods with the requests and limits of their containers, PersistentVolumes and PersistentVolumeClaims;
- the usage: CPU and memory of each container, read from the kubelet resource metrics and aggregated per minute;
- on AWS Fargate nodes only, the size Fargate provisioned for each pod, parsed from its `CapacityProvisioned` annotation;
- for the scheduler, in every mode: each action or skipped action, with its rule, its workload (`namespace/kind/name`), its reason, a short detail and the original values; and, in each heartbeat, whether the actions mode is on.

The agent also reads from Onicost the schedule of its cluster: the windows, exceptions and wake-ups of the active scheduler rules, and the namespaces and labels they target.

Not collected: Secrets, ConfigMaps, pod annotations other than the Fargate one, logs, and application data or traffic.

To send less, `exclude.namespaces` drops everything from the listed namespaces, and `exclude.labelKeys` removes the listed label keys before sending.

## Actions mode

The Onicost scheduler switches workloads off and on at the times of the rules you activate in Onicost, for example outside office hours. The agent reads the schedule of its cluster in every mode, but acts only when the chart is installed with `actions.enabled=true`. Without it, the agent changes nothing and reports, once per window and per workload, that it lacks the permissions (`actions_disabled`); the cluster page in Onicost shows the command that enables the mode (see [Install](install.md#actions-mode)).

`actions.enabled=true` adds these rules to the ClusterRole, and nothing else:

| API group | Resources | Verbs |
|---|---|---|
| `apps` | `deployments`, `statefulsets` | `patch` |
| `batch` | `cronjobs` | `patch` |
| `autoscaling` | `horizontalpodautoscalers` | `get`, `list`, `watch`, `patch` |

The agent writes only with JSON merge patches on the objects themselves: never `update`, never the `scale` subresource. It reads the Deployments, StatefulSets and CronJobs with the read-only rules, and watches the HorizontalPodAutoscalers in this mode only.

During a stop window of an active rule, the agent:

- sets `spec.replicas` of a Deployment or a StatefulSet to 0, or to 1 when a HorizontalPodAutoscaler drives it, after setting `spec.minReplicas: 1` on that HorizontalPodAutoscaler, which cannot scale to zero;
- sets `spec.suspend: true` on a CronJob;
- first writes the original values (replicas, `minReplicas`, `suspend`, rule, time) to the annotation `onicost.com/scheduler-restore` of the object and of its HorizontalPodAutoscaler. At the end of the window it restores exactly these values and removes the annotation. The annotation is the agent's only memory: `kubectl get -o yaml` shows what was changed and how to undo it;
- on an object managed by Flux, sets `kustomize.toolkit.fluxcd.io/reconcile: disabled` or `helm.toolkit.fluxcd.io/driftDetection: disabled` for the duration of the window, so that Flux does not bring the replicas back. Nothing changes in Git. On an object managed by Argo CD, or by another controller, whose replicas come back, the agent gives up for the rest of the window and reports it.

The agent never:

- creates or deletes an object, changes Pods, Nodes, custom resources or Argo CD Applications, or reads Secrets or ConfigMaps;
- acts on a rule that is not active in Onicost, or on the schedule of another cluster: the endpoint serves only the schedule of the cluster of the token;
- touches the namespaces `kube-system`, `kube-public`, `kube-node-lease`, `argocd`, `flux-system` and its own namespace, or a workload annotated `onicost.com/scheduler: ignore`.

Kubernetes RBAC cannot restrict a verb to some fields or to some namespaces of a ClusterRole: `patch` allows any change to the Deployments, StatefulSets, CronJobs and HorizontalPodAutoscalers of every namespace. The agent writes only the fields and annotations above, and it enforces the excluded namespaces itself. Each action is reported to Onicost and shown in the scheduler journal. To have the API server enforce the fields too, see [Optional hardening](#optional-hardening).

To leave the actions mode, pause or delete the rules in Onicost and wait for the workloads to come back on, then upgrade with `--set actions.enabled=false`. Without the permissions, the agent cannot restore an object it switched off: the `onicost.com/scheduler-restore` annotation keeps the values to restore by hand.

### Optional hardening

On Kubernetes 1.30 or later, a ValidatingAdmissionPolicy can make the API server reject any other change by the agent. It is optional: the agent already writes only the fields above. The policy below rejects a change by the agent to a Deployment, a StatefulSet or a CronJob other than `spec.replicas`, `spec.suspend` and `metadata.annotations`, and to a HorizontalPodAutoscaler other than `spec.minReplicas` and `metadata.annotations`. It ignores `metadata.generation`, `metadata.resourceVersion` and `metadata.managedFields`, which the API server maintains itself.

It matches the ServiceAccount of the agent, `system:serviceaccount:<namespace>:<release>`: replace `onicost` and `onicost-agent` with the namespace and the name of your release. It checks fields only, in every namespace: the agent enforces the excluded namespaces itself.

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: onicost-agent-actions
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: [apps]
        apiVersions: ["*"]
        operations: [UPDATE]
        resources: [deployments, statefulsets]
      - apiGroups: [batch]
        apiVersions: ["*"]
        operations: [UPDATE]
        resources: [cronjobs]
      - apiGroups: [autoscaling]
        apiVersions: ["*"]
        operations: [UPDATE]
        resources: [horizontalpodautoscalers]
  matchConditions:
    - name: onicost-agent
      expression: "request.userInfo.username == 'system:serviceaccount:onicost:onicost-agent'"
  variables:
    - name: allowedSpec
      expression: "request.resource.resource == 'horizontalpodautoscalers' ? ['minReplicas'] : ['replicas', 'suspend']"
    - name: allowedMetadata
      expression: "['annotations', 'generation', 'managedFields', 'resourceVersion']"
    - name: spec
      expression: "dyn(object.spec)"
    - name: oldSpec
      expression: "dyn(oldObject.spec)"
    - name: metadata
      expression: "dyn(object.metadata)"
    - name: oldMetadata
      expression: "dyn(oldObject.metadata)"
  validations:
    - expression: >-
        variables.spec.all(k, k in variables.allowedSpec || (k in variables.oldSpec && variables.spec[k] == variables.oldSpec[k]))
        && variables.oldSpec.all(k, k in variables.allowedSpec || k in variables.spec)
      message: "the Onicost agent may change only spec.replicas, spec.suspend, or spec.minReplicas of a HorizontalPodAutoscaler"
    - expression: >-
        variables.metadata.all(k, k in variables.allowedMetadata || (k in variables.oldMetadata && variables.metadata[k] == variables.oldMetadata[k]))
        && variables.oldMetadata.all(k, k in variables.allowedMetadata || k in variables.metadata)
      message: "the Onicost agent may change only metadata.annotations"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: onicost-agent-actions
spec:
  policyName: onicost-agent-actions
  validationActions: [Deny]
```

Apply it with `kubectl apply -f`, after the upgrade with `actions.enabled=true`. A patch it rejects fails with the message of the policy, and the agent reports the action as failed.

## The nodes/proxy option

Some managed clusters, Scaleway Kapsule for one, serve kubelet certificates that the agent cannot verify. With `kubelet.apiServerProxy=true`, the agent scrapes these kubelets through the API server (`GET /api/v1/nodes/<node>/proxy/metrics/resource`), which needs `get` on `nodes/proxy`. That permission opens the whole kubelet API of every node, pod logs included, not only its metrics. Grant it only when the logs show kubelet errors with `errorClass: tls_verification`.

`kubelet.insecureSkipVerify=true` avoids the permission but skips the kubelet certificate check: the agent's service account token is then sent to whatever answers on the node addresses. Use it only on a trusted node network.

## Image provenance

The chart deploys `ghcr.io/onicost/onicost-agent`, tagged with the chart `appVersion`. Onicost builds it from a tagged release, for `linux/amd64` and `linux/arm64`, on the `gcr.io/distroless/static-debian13:nonroot` base. To pin the exact image, set `image.tag` to `<version>@sha256:<digest>`.

The chart itself is published to `oci://ghcr.io/onicost/charts/onicost-agent` by the [release workflow](../.github/workflows/release.yml) of this repository, from the tag `onicost-agent-<version>`.

## Report a vulnerability

E-mail contact@onicost.com with the affected version and the steps to reproduce. Do not open a public issue.
