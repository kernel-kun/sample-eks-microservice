import socket

from fastapi import APIRouter

from sample_service.config import settings

router = APIRouter()


@router.get("/")
def root() -> dict[str, str]:
    return {
        "message": "Hello World!",
        "version": settings.app_version,
        "hostname": socket.gethostname(),
        "pod_name": settings.pod_name,
        "pod_ip": settings.pod_ip,
        "node_name": settings.node_name,
        "namespace": settings.pod_namespace,
    }
