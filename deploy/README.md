# deploy

Three Helm releases land on the cluster, in order:

1. **`aws-load-balancer-controller`** in `kube-system` — turns Ingress
   objects into AWS ALBs. ServiceAccount carries the
   `eks.amazonaws.com/role-arn` annotation so the controller can assume the
   IRSA role created by `infra/`.
2. **`kube-prometheus-stack`** in `monitoring` — Prometheus operator,
   Prometheus, Grafana, plus the kiwigrid sidecar that auto-loads dashboard
   ConfigMaps.
3. **`microservice`** in `app` — Deployment, Service, Ingress, ServiceMonitor,
   Grafana dashboard ConfigMap.

The same install runs from CI (`deploy.yml`, `workflow_dispatch`) and from
your laptop (`make deploy-local`). Workflow inputs and what the job does
are documented in the root `README.md`.

## Pinned versions

| Component                       | Chart version | App version |
| ------------------------------- | ------------- | ----------- |
| aws-load-balancer-controller    | 1.14.0        | v2.14.1     |
| kube-prometheus-stack           | 85.3.0        | mixed       |
| microservice (this chart)       | 0.1.0         | 0.1.0       |

If you bump `aws-load-balancer-controller`, refresh
`infra/policies/alb-controller.json` from the matching upstream tag.

## Run locally

```bash
make chart-lint                            # helm lint + template render
make deploy-local                          # installs all three releases
```

`deploy-local` defaults to `CLUSTER_NAME=sample-eks` and `AWS_REGION=us-east-1`,
auto-discovers the VPC ID + ALB controller role ARN from the cluster, and
auto-recovers releases stuck in `pending-install` / `pending-upgrade` /
`pending-rollback`. Override `CLUSTER_NAME=…` / `AWS_REGION=…` / `VPC_ID=…`
on the command line if needed.

## Microservice chart values that matter

| Value                                       | Default                                            | Notes                                       |
| ------------------------------------------- | -------------------------------------------------- | ------------------------------------------- |
| `image.repository` / `image.tag`            | `ghcr.io/kernel-kun/sample-eks-microservice:latest`| Override `tag` to pin a build                |
| `replicaCount`                              | `2`                                                | Enough to survive a node roll                |
| `resources`                                 | 50m/64Mi req, 200m/128Mi lim                       | Idle service is well under requests          |
| `ingress.*`                                 | internet-facing ALB, target-type `ip`, healthcheck `/healthz` | HTTP-only listener on port 80     |
| `monitoring.serviceMonitor.labels.release`  | `monitoring`                                       | Must match the kube-prometheus-stack release name |
| `monitoring.dashboard.enabled`              | `true`                                             | Toggles the Grafana dashboard ConfigMap      |

The ALB controller's role ARN is wired in at install time (by `make deploy-local`
and the workflow alike) — the values file under `deploy/ingress-controller/`
doesn't hardcode anything account-scoped.

## Verifying

```bash
kubectl get pods -A
kubectl get ingress -n app microservice
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
# http://localhost:3000  (admin / admin)  → Dashboards → microservice
```

If the dashboard panels stay blank, the ServiceMonitor may not have been
discovered. Check the Prometheus targets page:

```bash
kubectl get servicemonitor -A
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090
# http://localhost:9090/targets — look for app/microservice
```
