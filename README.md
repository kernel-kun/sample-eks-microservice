# sample-eks-microservice

A tiny Python web application — plus the AWS Terraform infrastructure and the
GitHub Actions deployment pipeline behind it — that showcases the end-to-end
shape of running a small microservice on Amazon EKS.

The repo is split into three loosely coupled tracks. Each track owns its
artifacts and can be reviewed, applied, or torn down on its own:

- **`app/`** — Python FastAPI service modelled on the HTTP-only surface of
  [stefanprodan/podinfo](https://github.com/stefanprodan/podinfo): structured
  JSON logs, liveness/readiness probes, Prometheus metrics, graceful shutdown,
  pod metadata via the Kubernetes Downward API. Multi-stage Dockerfile,
  multi-arch image (`linux/amd64`, `linux/arm64`), Trivy scan in CI, published
  to GitHub Container Registry.
- **`infra/`** — Terraform that provisions a Well-Architected VPC (3 AZs,
  per-AZ NAT) and an EKS cluster (managed node group on AL2023, EKS Pod
  Identity, the standard add-ons), plus the IAM scaffolding the AWS Load
  Balancer Controller needs. Remote state in S3 with native locking.
- **`deploy/`** — Helm chart for the service (Deployment, Service, Ingress
  backed by an ALB, ServiceAccount, ServiceMonitor, Grafana dashboard
  ConfigMap), values for the upstream `aws-load-balancer-controller` and
  `kube-prometheus-stack` charts, and a single `workflow_dispatch` GitHub
  Actions workflow that installs everything in order and surfaces the public
  ALB URL in the run summary.

The intent is a reference small enough that every moving part can be read in
one sitting, but realistic enough that the same shape scales up: the service
ships through CI, the cluster comes from code, and the deploy is one click
away.

## What is in scope

- HTTP only, served through an internet-facing ALB. No TLS, no DNS.
- Logs and metrics. No tracing, no OpenTelemetry SDK.
- Single namespace (`default`) and a single deployment with fixed replicas.
- Static AWS credentials passed into `workflow_dispatch` — chosen because the
  AWS account is recreated each demo and we don't want to persist anything on
  the GitHub side.

## Repo layout

```
.
├── app/                            # Python service + Dockerfile
├── infra/                          # Terraform (VPC, EKS, IAM)
├── deploy/
│   ├── charts/microservice/        # Local helm chart for the service
│   ├── ingress-controller/         # Values for aws-load-balancer-controller
│   └── monitoring/                 # Values for kube-prometheus-stack
├── .github/workflows/              # build-image.yml, deploy.yml
├── Makefile                        # convenience wrappers
└── README.md
```

## Quickstart

### Microservice

```bash
make app-install     # create venv + install deps
make app-test        # run pytest
make app-run         # serve on http://127.0.0.1:8080
make image           # docker buildx --load -t sample-service:dev
```

Endpoints: `/`, `/healthz`, `/readyz`, `/metrics`. Configuration is via env
vars (see `app/README.md`). The container image is built, scanned with Trivy,
and pushed multi-arch to `ghcr.io/kernel-kun/sample-eks-microservice` by
`.github/workflows/build-image.yml` on every change under `app/**`.

### Infrastructure

_Coming with the infra track._

### Deploy

_Coming with the deploy track._

## Prerequisites

- `git`, `make`, `docker` (with `buildx`)
- `python` 3.12+ (for local app dev)
- `terraform` 1.9+, `aws` CLI v2 (for infra)
- `kubectl`, `helm` 3.x (for deploy)
