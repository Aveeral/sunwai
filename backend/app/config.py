"""Settings, read from the .env file in the project root (never committed)."""
import os
from pathlib import Path

from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[2]          # the Sunwai folder
load_dotenv(ROOT / ".env")


class Settings:
    # The backend logs in as sunwai_app, which has NO privileges of its own.
    # Every request switches to a real role (SET LOCAL ROLE), see db.py.
    database_url: str = os.getenv(
        "DATABASE_URL", "postgresql://sunwai_app:sunwai_app_dev@localhost:5432/sunwai")

    # LLM. LLM_MODE: "auto" = OpenAI when a key is set, else the offline classifier
    #                "openai" / "offline" = force one of them
    openai_api_key: str = os.getenv("OPENAI_API_KEY", "").strip()
    openai_model: str = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
    llm_mode: str = os.getenv("LLM_MODE", "auto").lower()
    llm_cache_dir: Path = ROOT / "backend" / "llm_cache"

    # Signs the demo login tokens
    secret_key: str = os.getenv("SECRET_KEY", "sunwai-dev-secret-change-me")

    # How often the escalation job runs (seconds). 0 turns it off.
    scheduler_seconds: int = int(os.getenv("SCHEDULER_SECONDS", "300"))

    # where the website is served from (comma-separated); trailing "/" ignored
    cors_origins: list[str] = [o.strip().rstrip("/") for o in os.getenv(
        "CORS_ORIGINS", "http://localhost:5173,http://127.0.0.1:5173").split(",") if o.strip()]

    @property
    def use_openai(self) -> bool:
        if self.llm_mode == "offline":
            return False
        if self.llm_mode == "openai":
            return True
        return bool(self.openai_api_key) and self.openai_api_key != "sk-..."


settings = Settings()
