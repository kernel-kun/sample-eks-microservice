# sample-eks-microservice

A small Python HTTP service, the AWS infrastructure to run it on, and the deploy
pipeline that wires the two together. Three independent tracks under one repo:

- **`app/`** — Python FastAPI service with health probes, structured logs, and
  Prometheus metrics.
- **`infra/`** — Terraform that provisions a VPC, an EKS cluster, and the IAM
  scaffolding for in-cluster controllers.
- **`deploy/`** — Helm chart for the service plus values for the upstream
  monitoring and ingress charts. Driven by a single GitHub Actions workflow.

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

> Quickstart sections are filled in by each track as it lands.

### Microservice

_Coming with the microservice track._

### Infrastructure

_Coming with the infra track._

### Deploy

_Coming with the deploy track._

## Prerequisites

- `git`, `make`, `docker` (with `buildx`)
- `python` 3.12+ (for local app dev)
- `terraform` 1.9+, `aws` CLI v2 (for infra)
- `kubectl`, `helm` 3.x (for deploy)
