from pydantic_settings import BaseSettings, SettingsConfigDict

from sample_service import __version__


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    port: int = 8080
    log_level: str = "INFO"
    app_version: str = __version__

    pod_name: str = ""
    pod_ip: str = ""
    node_name: str = ""
    pod_namespace: str = ""

    shutdown_drain_seconds: float = 5.0


settings = Settings()
