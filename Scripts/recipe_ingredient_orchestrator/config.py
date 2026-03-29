"""Configuration loaded from environment variables with xcconfig fallback."""

from __future__ import annotations

import logging
import os
import re
from pathlib import Path
from typing import Optional

from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings

logger = logging.getLogger(__name__)

_PROJECT_ROOT = Path(__file__).resolve().parents[2]


def _read_xcconfig_key(key: str) -> Optional[str]:
    """Read a value from the Xcode config files (LocalSecrets first, then Secrets)."""
    for filename in ("LocalSecrets.xcconfig", "Secrets.xcconfig"):
        path = _PROJECT_ROOT / "Config" / filename
        if not path.exists():
            continue
        for line in path.read_text().splitlines():
            line = line.strip()
            if line.startswith("//") or "=" not in line:
                continue
            k, _, v = line.partition("=")
            k, v = k.strip(), v.strip()
            if k == key and v and not v.startswith("$("):
                return v
    return None


class Settings(BaseSettings):
    """All orchestrator settings. Environment variables take precedence."""

    openai_api_key: str = ""
    model: str = Field(default="gpt-4o", alias="ORCHESTRATOR_MODEL")
    review_model: str = Field(default="gpt-4o-mini", alias="ORCHESTRATOR_REVIEW_MODEL")
    enrichment_model: str = Field(default="gpt-4o-mini", alias="ORCHESTRATOR_ENRICHMENT_MODEL")
    planner_model: str = Field(default="gpt-4o-mini", alias="ORCHESTRATOR_PLANNER_MODEL")
    max_concurrency: int = Field(default=5, ge=1, alias="ORCHESTRATOR_MAX_CONCURRENCY")
    ingredient_batch_size: int = Field(default=25, ge=1, alias="ORCHESTRATOR_INGREDIENT_BATCH_SIZE")
    recipe_batch_size: int = Field(default=10, ge=1, alias="ORCHESTRATOR_RECIPE_BATCH_SIZE")
    max_retries: int = Field(default=3, ge=1, alias="ORCHESTRATOR_MAX_RETRIES")
    output_dir: str = Field(
        default="Scripts/recipe_ingredient_orchestrator/output",
        alias="ORCHESTRATOR_OUTPUT_DIR",
    )
    log_level: str = Field(default="INFO", alias="ORCHESTRATOR_LOG_LEVEL")

    model_config = {"env_prefix": "", "populate_by_name": True}

    @model_validator(mode="after")
    def resolve_api_key(self) -> "Settings":
        if not self.openai_api_key:
            self.openai_api_key = os.environ.get("OPENAI_API_KEY", "")
        if not self.openai_api_key:
            self.openai_api_key = _read_xcconfig_key("OPENAI_API_KEY") or ""
        return self

    @field_validator("log_level")
    @classmethod
    def validate_log_level(cls, v: str) -> str:
        v = v.upper()
        if v not in ("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"):
            raise ValueError(f"Invalid log level: {v}")
        return v

    @property
    def resolved_output_dir(self) -> Path:
        p = Path(self.output_dir)
        if not p.is_absolute():
            p = _PROJECT_ROOT / p
        return p


def configure_logging(settings: Settings) -> None:
    """Set up root logger for the orchestrator."""
    level = getattr(logging, settings.log_level)
    fmt = "%(asctime)s [%(levelname)s] %(name)s: %(message)s"
    logging.basicConfig(level=level, format=fmt, force=True)
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("openai").setLevel(logging.WARNING)
