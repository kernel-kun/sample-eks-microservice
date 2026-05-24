from enum import Enum

from fastapi import APIRouter
from fastapi.responses import JSONResponse

router = APIRouter()


class State(str, Enum):
    STARTING = "starting"
    READY = "ready"
    DRAINING = "draining"


class Readiness:
    def __init__(self) -> None:
        self.state: State = State.STARTING

    def mark_ready(self) -> None:
        self.state = State.READY

    def mark_draining(self) -> None:
        self.state = State.DRAINING

    def is_ready(self) -> bool:
        return self.state is State.READY


readiness = Readiness()


@router.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/readyz")
def readyz() -> JSONResponse:
    if readiness.is_ready():
        return JSONResponse({"status": "ready"})
    return JSONResponse({"status": readiness.state.value}, status_code=503)
