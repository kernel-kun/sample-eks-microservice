# deploy

The Kubernetes side of the repo. Three Helm releases land on the cluster:

1. **`aws-load-balancer-controller`** (`kube-system`) — turns Ingress objects
   into AWS ALBs.
2. **`kube-prometheus-stack`** (`monitoring`) — Prometheus operator, Prometheus,
   Grafana, plus the kiwigrid sidecar that auto-discovers dashboard ConfigMaps.
3. **`microservice`** (`app`) — our FastAPI service, its Service, the ALB
   Ingress, the ServiceMonitor that points Prometheus at `/metrics`, and the
   ConfigMap that ships the Grafana dashboard.

The same install runs from CI (`workflow_dispatch`) or from your laptop
(`make deploy-local`).

## Layout

```
deploy/
├── charts/microservice/                # Local Helm chart
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── dashboards/microservice.json    # Grafana dashboard JSON, embedded in CM
│   └── templates/                      # SA, Deployment, Service, Ingress, SM, CM, NOTES
├── ingress-controller/values.yaml      # values for eks/aws-load-balancer-controller
├── monitoring/values.yaml              # values for prometheus-community/kube-prometheus-stack
└── README.md
```

## Pinned versions

| Component                       | Chart version | App version |
| ------------------------------- | ------------- | ----------- |
| aws-load-balancer-controller    | 1.14.0        | v2.14.1     |
| kube-prometheus-stack           | 85.3.0        | (mixed)     |
| microservice (this chart)       | 0.1.0         | 0.1.0       |

Pinning the upstream charts is what keeps a "deploy now" run reproducible —
the rest of the workflow doesn't need to think about minor-version drift.

## Run from GitHub Actions

The `deploy` workflow has six `workflow_dispatch` inputs:

| Input                   | Purpose                                                    |
| ----------------------- | ---------------------------------------------------------- |
| `aws_region`            | Region the EKS cluster lives in (default `us-east-1`)      |
| `cluster_name`          | EKS cluster name (default `sample-eks` from `infra/`)      |
| `image_tag`             | Microservice image tag — `latest`, or a `sha-…` from CI    |
| `aws_access_key_id`     | Access key (masked at runtime)                             |
| `aws_secret_access_key` | Secret (masked at runtime)                                 |
| `aws_session_token`     | Session token (masked; leave blank for long-lived IAM creds) |

Static creds rather than OIDC because the lab account is recreated per demo;
nothing about it is worth wiring an identity provider for. The first step
masks the values via `::add-mask::` before any other action sees them. The
session token is optional — required for STS / lab creds, not needed for
plain IAM user keys.

The job:

1. Configures AWS CLI with the masked creds.
2. Updates kubeconfig against the named cluster.
3. Adds the `eks` and `prometheus-community` Helm repos.
4. Discovers the cluster's VPC ID (needed by the ALB controller).
5. Installs the three releases in order, each with `--wait`.
6. Polls for the ALB hostname (5 min budget — provisioning takes 90–180 s).
7. Smoke-tests `/healthz` against the hostname (10 min budget — target
   registration lags hostname assignment).
8. Writes the URL and curl examples to `$GITHUB_STEP_SUMMARY`.

If any step fails, the summary still renders with whatever it had at the
point of failure.

## Run locally

```bash
make chart-lint                                        # helm lint + template render
make deploy-local CLUSTER_NAME=sample-eks AWS_REGION=us-east-1
```

`deploy-local` mirrors the workflow but uses your current kube context. The
VPC ID and ALB controller role ARN are auto-discovered from `CLUSTER_NAME`
(via `aws eks describe-cluster` and `aws iam get-role`). Override `VPC_ID=...`
on the command line if you ever need to pin one explicitly.

## Microservice chart values

The chart is intentionally small. The values that matter day-to-day:

- `image.repository` / `image.tag` — defaults to
  `ghcr.io/kernel-kun/sample-eks-microservice:latest`. Override `tag` to pin
  a specific build.
- `replicaCount` — 2 by default, enough to survive a node roll.
- `resources` — 50m/64Mi requested, 200m/128Mi limits. Idle service is well
  under requests.
- `ingress.*` — ALB annotations for `internet-facing`, `target-type: ip`,
  HTTP-only listener on port 80, healthcheck path `/healthz`.
- `monitoring.serviceMonitor.labels.release` — must match the Helm release
  name of `kube-prometheus-stack` (`monitoring`). The operator's default
  selector is `release: <release-name>`.
- `monitoring.dashboard.enabled` — toggle the Grafana dashboard ConfigMap.

The AWS Load Balancer Controller chart (`deploy/ingress-controller/values.yaml`)
gets its IAM role from the `alb_controller_role_arn` Terraform output via an
`eks.amazonaws.com/role-arn` annotation on the ServiceAccount. Both
`make deploy-local` and the deploy workflow discover the role ARN at install
time and pass it through `--set` — the values file itself doesn't hardcode
anything account-scoped.

Everything is wired through Downward API so the app's `pydantic-settings`
config picks up `POD_NAME`, `POD_IP`, `POD_NAMESPACE`, `NODE_NAME`. The pod
runs under the Restricted Pod Security Standard: non-root, read-only root
filesystem, all capabilities dropped, RuntimeDefault seccomp.

## Verifying

```bash
kubectl get pods -A                                    # all three releases
kubectl get ingress -n app microservice                # wait for HOSTS column
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
# then http://localhost:3000  (admin / admin)  → Dashboards → microservice
```

The dashboard panels expect Prometheus metrics from the `microservice` job
(matched via `job=~".*microservice.*"`). If the panels stay blank, check
that the ServiceMonitor was discovered:

```bash
kubectl get servicemonitor -A
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090
# then http://localhost:9090/targets — look for the `app/microservice` target.
```

## Common pitfalls

- ALB hostname empty for minutes — normal, provisioning takes 90 to 180
  seconds. The workflow's poll loop already accounts for this.
- Grafana dashboard missing — the sidecar only watches ConfigMaps with the
  label `grafana_dashboard: "1"`. Confirm with
  `kubectl get cm -A -l grafana_dashboard=1`.
- ServiceMonitor not picked up — either the `release: monitoring` label is
  wrong (must match the kube-prometheus-stack release name), or the operator
  is configured with namespace selectors that exclude `app`. Our values keep
  the selectors permissive.
- Health check fails after the ALB hostname appears — ALB target group
  registration lags hostname propagation. Give it another minute; the
  workflow already retries `/healthz` for 5 minutes.
- ALB controller can't fetch AWS creds — the controller role uses IRSA, so
  the chart's ServiceAccount must carry the `eks.amazonaws.com/role-arn`
  annotation. Both deploy paths set it via `--set` from the
  `alb_controller_role_arn` Terraform output; if you ever install the chart
  directly, do the same. Verify with
  `kubectl -n kube-system get sa aws-load-balancer-controller -o yaml`.
- Helm release stuck in `pending-install` after a Ctrl+C —
  `make deploy-local` auto-recovers (uninstalls then reinstalls). For an
  ad-hoc fix: `helm uninstall <release> -n <ns>` then re-run.
