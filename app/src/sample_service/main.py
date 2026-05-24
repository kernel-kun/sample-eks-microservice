import asyncio
import signal
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI
from loguru import logger

from sample_service.config import settings
from sample_service.logging import configure_logging
from sample_service.metrics import PrometheusMiddleware, metrics_response
from sample_service.routes import health, root


@asynccontextmanager
async def lifespan(_: FastAPI):
    configure_logging()
    logger.info("startup", version=settings.app_version, port=settings.port)
    health.readiness.mark_ready()
    try:
        yield
    finally:
        logger.info("shutdown signal received, draining")
        health.readiness.mark_draining()
        await asyncio.sleep(settings.shutdown_drain_seconds)
        logger.info("drain complete, exiting")


def create_app() -> FastAPI:
    app = FastAPI(lifespan=lifespan)
    app.add_middleware(PrometheusMiddleware)
    app.include_router(root.router)
    app.include_router(health.router)
    app.add_route("/metrics", metrics_response)
    return app


app = create_app()


def run() -> None:
    config = uvicorn.Config(
        app,
        host="0.0.0.0",
        port=settings.port,
        log_config=None,
        access_log=False,
    )
    server = uvicorn.Server(config)

    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    def _request_shutdown(signame: str) -> None:
        logger.info("signal received", signal=signame)
        server.should_exit = True

    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, _request_shutdown, sig.name)

    loop.run_until_complete(server.serve())


if __name__ == "__main__":
    run()
