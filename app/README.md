# sample-service

Small FastAPI HTTP service. Mirrors podinfo's HTTP-only surface (health probes,
structured JSON logs, Prometheus metrics) without the rest of podinfo's surface
area.

## Endpoints

| Path        | Purpose                                               |
|-------------|-------------------------------------------------------|
| `GET /`     | Hello World + pod metadata (hostname, pod name, etc.) |
| `GET /healthz` | Liveness — always 200 once the process is up      |
| `GET /readyz`  | Readiness — 200 when ready, 503 during drain      |
| `GET /metrics` | Prometheus exposition format                       |

## Configuration

All knobs are environment variables (`pydantic-settings`):

| Var | Default | Notes |
|-----|---------|-------|
| `PORT` | `8080` | uvicorn bind port |
| `LOG_LEVEL` | `INFO` | loguru level (`DEBUG`, `INFO`, `WARNING`, ...) |
| `APP_VERSION` | `0.1.0` | reported in `GET /` |
| `POD_NAME` / `POD_IP` / `NODE_NAME` / `POD_NAMESPACE` | `""` | injected via Kubernetes Downward API in cluster |
| `SHUTDOWN_DRAIN_SECONDS` | `5` | sleep after `SIGTERM` while readiness reports 503 |

## Local dev

```bash
make app-install        # one-time: create .venv, install deps
make app-test           # run pytest
make app-run            # serve on http://127.0.0.1:8080
```

## Container

```bash
make image                       # docker buildx build --load -t sample-service:dev app/
docker run --rm -p 8080:8080 sample-service:dev
```

The image is multi-stage on `python:3.12-slim`, runs as a non-root user
(uid 1000), and exposes 8080. Multi-arch (`linux/amd64`, `linux/arm64`) builds
are pushed to `ghcr.io/kernel-kun/sample-eks-microservice` by
`.github/workflows/build-image.yml`.

## Layout

```
app/
├── pyproject.toml
├── Dockerfile
├── .dockerignore
├── src/sample_service/
│   ├── __init__.py
│   ├── config.py        # pydantic-settings
│   ├── logging.py       # loguru → JSON to stdout, intercept stdlib
│   ├── metrics.py       # Counter + Histogram + ASGI middleware
│   ├── main.py          # app factory, lifespan, signal handlers
│   └── routes/
│       ├── root.py      # GET /
│       └── health.py    # /healthz, /readyz, shared readiness state
└── tests/test_routes.py
```
