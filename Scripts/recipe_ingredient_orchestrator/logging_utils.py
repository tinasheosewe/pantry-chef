from __future__ import annotations

import logging
from logging.handlers import RotatingFileHandler
from pathlib import Path


DEFAULT_LOG_FORMAT = "%(asctime)s %(levelname)s [%(name)s] %(message)s"
PACKAGE_LOGGER_NAME = "recipe_ingredient_orchestrator"


package_logger = logging.getLogger(PACKAGE_LOGGER_NAME)
if not package_logger.handlers:
    package_logger.addHandler(logging.NullHandler())


def setup_logging(output_root: Path, level_name: str) -> Path:
    log_dir = output_root / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / "orchestrator.log"

    root_logger = logging.getLogger(PACKAGE_LOGGER_NAME)
    level = _logging_level(level_name)

    if getattr(root_logger, "_orchestrator_logging_configured", False):
        root_logger.setLevel(level)
        for handler in root_logger.handlers:
            handler.setLevel(level)
        return log_path

    root_logger.setLevel(level)
    root_logger.propagate = False

    formatter = logging.Formatter(DEFAULT_LOG_FORMAT)

    stream_handler = logging.StreamHandler()
    stream_handler.setLevel(level)
    stream_handler.setFormatter(formatter)

    file_handler = RotatingFileHandler(
        log_path,
        maxBytes=2 * 1024 * 1024,
        backupCount=5,
        encoding="utf-8",
    )
    file_handler.setLevel(level)
    file_handler.setFormatter(formatter)

    root_logger.handlers.clear()
    root_logger.addHandler(stream_handler)
    root_logger.addHandler(file_handler)
    root_logger._orchestrator_logging_configured = True  # type: ignore[attr-defined]
    return log_path


def get_logger(name: str) -> logging.Logger:
    return logging.getLogger(f"{PACKAGE_LOGGER_NAME}.{name}")


def _logging_level(level_name: str) -> int:
    normalized = level_name.strip().upper()
    return {
        "CRITICAL": logging.CRITICAL,
        "ERROR": logging.ERROR,
        "WARNING": logging.WARNING,
        "INFO": logging.INFO,
        "DEBUG": logging.DEBUG,
    }.get(normalized, logging.INFO)