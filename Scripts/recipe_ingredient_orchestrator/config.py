from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class OrchestratorConfig:
    openai_api_key: str | None
    openai_api_key_source: str | None
    generation_model: str
    planner_model: str
    review_model: str
    ambiguity_model: str
    ingredient_model: str
    base_url: str
    timeout_seconds: int
    max_retries: int
    max_dish_attempts: int
    max_resolution_cycles: int
    max_concurrency: int
    requests_per_minute: int
    auto_accept_score: float
    auto_accept_margin: float
    log_level: str
    output_root: Path
    accepted_root: Path

    @classmethod
    def from_env(cls, base_dir: Path | None = None) -> "OrchestratorConfig":
        resolved_base_dir = (base_dir or Path(__file__).resolve().parent).resolve()
        project_root = resolved_base_dir.parents[1]
        openai_api_key, openai_api_key_source = _resolve_openai_api_key(project_root)
        generation_model = _gpt_model_env("ORCHESTRATOR_OPENAI_MODEL", "gpt-4o")
        planner_model = _gpt_model_env("ORCHESTRATOR_PLANNER_MODEL", "gpt-4o-mini")
        review_model = _gpt_model_env("ORCHESTRATOR_REVIEW_MODEL", "gpt-4o-mini")
        ambiguity_model = _gpt_model_env("ORCHESTRATOR_AMBIGUITY_MODEL", "gpt-4o-mini")
        ingredient_model = _gpt_model_env("ORCHESTRATOR_INGREDIENT_MODEL", "gpt-4o-mini")
        return cls(
            openai_api_key=openai_api_key,
            openai_api_key_source=openai_api_key_source,
            generation_model=generation_model,
            planner_model=planner_model,
            review_model=review_model,
            ambiguity_model=ambiguity_model,
            ingredient_model=ingredient_model,
            base_url=os.environ.get("ORCHESTRATOR_OPENAI_BASE_URL", "https://api.openai.com/v1"),
            timeout_seconds=int(os.environ.get("ORCHESTRATOR_TIMEOUT_SECONDS", "90")),
            max_retries=int(os.environ.get("ORCHESTRATOR_MAX_RETRIES", "3")),
            max_dish_attempts=max(1, int(os.environ.get("ORCHESTRATOR_MAX_DISH_ATTEMPTS", "3"))),
            max_resolution_cycles=max(1, int(os.environ.get("ORCHESTRATOR_MAX_RESOLUTION_CYCLES", "2"))),
            max_concurrency=max(1, int(os.environ.get("ORCHESTRATOR_MAX_CONCURRENCY", "3"))),
            requests_per_minute=max(1, int(os.environ.get("ORCHESTRATOR_REQUESTS_PER_MINUTE", "30"))),
            auto_accept_score=float(os.environ.get("ORCHESTRATOR_AUTO_ACCEPT_SCORE", "0.92")),
            auto_accept_margin=float(os.environ.get("ORCHESTRATOR_AUTO_ACCEPT_MARGIN", "0.12")),
            log_level=os.environ.get("ORCHESTRATOR_LOG_LEVEL", "INFO").strip().upper() or "INFO",
            output_root=Path(os.environ.get("ORCHESTRATOR_OUTPUT_ROOT", str(resolved_base_dir / "runtime"))).resolve(),
            accepted_root=_accepted_root_env(resolved_base_dir),
        )

    def require_openai_api_key(self) -> None:
        if not self.openai_api_key:
            raise RuntimeError(
                "OPENAI_API_KEY is required for production mode. Use --demo to run the local mock path."
            )

    def require_request_planning_support(self) -> None:
        if not self.openai_api_key:
            raise RuntimeError(
                "OPENAI_API_KEY is required for request planning. Request-based entry points do not support heuristic fallback."
            )


def _optional_env(key: str) -> str | None:
    value = os.environ.get(key)
    if value is None:
        return None
    cleaned = value.strip()
    return cleaned or None


def _gpt_model_env(key: str, default: str) -> str:
    value = _optional_env(key) or default
    if not value.startswith("gpt-"):
        raise RuntimeError(f"{key} must reference a GPT-family model. Received '{value}'.")
    return value


def _accepted_root_env(resolved_base_dir: Path) -> Path:
    configured = (
        _optional_env("ORCHESTRATOR_ACCEPTED_ROOT")
        or _optional_env("ORCHESTRATOR_APPROVED_ROOT")
        or str(resolved_base_dir / "accepted")
    )
    return Path(configured).resolve()


def _resolve_openai_api_key(project_root: Path) -> tuple[str | None, str | None]:
    env_value = _optional_env("OPENAI_API_KEY")
    if env_value is not None:
        return env_value, "environment"

    secrets_path = project_root / "Config" / "Secrets.xcconfig"
    if not secrets_path.exists():
        return None, None

    values = _read_xcconfig_values(secrets_path)
    resolved = values.get("OPENAI_API_KEY")
    if resolved is None:
        return None, None

    value, source_path = resolved
    cleaned = _clean_config_value(value)
    if cleaned is None or _looks_like_placeholder(cleaned):
        return None, None

    return cleaned, f"xcconfig:{source_path.relative_to(project_root).as_posix()}"


def _read_xcconfig_values(
    path: Path,
    seen: set[Path] | None = None,
) -> dict[str, tuple[str, Path]]:
    resolved_path = path.resolve()
    if seen is None:
        seen = set()
    if resolved_path in seen or not resolved_path.exists():
        return {}

    seen.add(resolved_path)
    values: dict[str, tuple[str, Path]] = {}

    for raw_line in resolved_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.partition("//")[0].strip()
        if not line:
            continue

        include_target = _parse_include_target(line)
        if include_target is not None:
            include_path = (resolved_path.parent / include_target).resolve()
            values.update(_read_xcconfig_values(include_path, seen=seen))
            continue

        if "=" not in line:
            continue

        key, value = line.split("=", 1)
        values[key.strip()] = (value.strip(), resolved_path)

    return values


def _clean_config_value(value: str) -> str | None:
    cleaned = value.strip().strip('"').strip()
    return cleaned or None


def _parse_include_target(line: str) -> str | None:
    if not line.startswith("#include"):
        return None

    remainder = line[len("#include"):].strip()
    if remainder.startswith("?"):
        remainder = remainder[1:].strip()
    if len(remainder) < 2 or not remainder.startswith('"') or not remainder.endswith('"'):
        return None
    target = remainder[1:-1].strip()
    return target or None


def _looks_like_placeholder(value: str) -> bool:
    return value.startswith("$(") or value.startswith("YOUR_") or value.startswith("__MISSING_CONFIG__")