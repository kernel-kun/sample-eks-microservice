# app

FastAPI service. Health probes, structured JSON logs, Prometheus metrics,
graceful shutdown, pod metadata via the Downward API.

The image is built and scanned by `.github/workflows/build-image.yml` and
published to `ghcr.io/<owner>/sample-eks-microservice`. Cloud-native design
notes (probes, signals, PSS) live in the root `README.md`.

## Endpoints

| Path           | Purpose                                              |
| -------------- | ---------------------------------------------------- |
| `GET /`        | Hello + pod metadata (hostname, pod, node, version)  |
| `GET /healthz` | Liveness — 200 once the process is up                |
| `GET /readyz`  | Readiness — 200 ready, 503 during shutdown drain     |
| `GET /metrics` | Prometheus exposition format                          |

## Configuration

All knobs are environment variables (`pydantic-settings`):

| Var                                                      | Default | Notes                                        |
| -------------------------------------------------------- | ------- | -------------------------------------------- |
| `PORT`                                                   | `8080`  | uvicorn bind port                            |
| `LOG_LEVEL`                                              | `INFO`  | `DEBUG`, `INFO`, `WARNING`, ...              |
| `APP_VERSION`                                            | `0.1.0` | reported in `GET /`                          |
| `POD_NAME` / `POD_IP` / `POD_NAMESPACE` / `NODE_NAME`    | `""`    | injected via Downward API in cluster         |
| `SHUTDOWN_DRAIN_SECONDS`                                 | `5`     | sleep after `SIGTERM` while readiness is 503 |

## Local dev

```bash
make app-install        # one-time: create .venv, install deps
make app-test           # pytest
make app-run            # uvicorn on http://127.0.0.1:8080
make image              # docker buildx --load -t sample-service:dev app/
docker run --rm -p 8080:8080 sample-service:dev
```
