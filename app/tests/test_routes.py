from fastapi.testclient import TestClient

from sample_service.main import create_app
from sample_service.routes import health


def _client() -> TestClient:
    app = create_app()
    return TestClient(app)


def test_root():
    with _client() as client:
        r = client.get("/")
        assert r.status_code == 200
        body = r.json()
        assert body["message"] == "Hello World!"
        assert "version" in body
        assert "hostname" in body


def test_healthz_always_200():
    with _client() as client:
        r = client.get("/healthz")
        assert r.status_code == 200
        assert r.json() == {"status": "ok"}


def test_readyz_lifecycle():
    with _client() as client:
        # lifespan startup flips state to READY
        r = client.get("/readyz")
        assert r.status_code == 200
        assert r.json() == {"status": "ready"}

        health.readiness.mark_draining()
        r = client.get("/readyz")
        assert r.status_code == 503
        assert r.json() == {"status": "draining"}


def test_metrics():
    with _client() as client:
        client.get("/")  # generate at least one observation
        r = client.get("/metrics")
        assert r.status_code == 200
        body = r.text
        assert "http_requests_total" in body
        assert "http_request_duration_seconds" in body
