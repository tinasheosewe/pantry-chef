from __future__ import annotations

from collections import deque
import json
import time
from dataclasses import dataclass, field
from threading import Lock
from urllib import error, request

from .config import OrchestratorConfig
from .logging_utils import get_logger


class OpenAIRequestError(RuntimeError):
    pass


logger = get_logger("openai_client")


class RequestRateLimiter:
    def __init__(self, requests_per_minute: int) -> None:
        self._requests_per_minute = max(1, requests_per_minute)
        self._timestamps: deque[float] = deque()
        self._lock = Lock()

    def wait_for_slot(self) -> None:
        while True:
            now = time.monotonic()
            with self._lock:
                while self._timestamps and now - self._timestamps[0] >= 60.0:
                    self._timestamps.popleft()

                if len(self._timestamps) < self._requests_per_minute:
                    self._timestamps.append(now)
                    return

                sleep_seconds = max(0.05, 60.0 - (now - self._timestamps[0]))

            time.sleep(sleep_seconds)


@dataclass
class OpenAIChatClient:
    config: OrchestratorConfig
    _rate_limiter: RequestRateLimiter = field(init=False, repr=False)

    def __post_init__(self) -> None:
        self._rate_limiter = RequestRateLimiter(self.config.requests_per_minute)

    def complete_json(
        self,
        system_prompt: str,
        user_prompt: str,
        schema: dict,
        schema_name: str,
        temperature: float,
        model: str | None = None,
    ) -> dict:
        selected_model = model or self.config.generation_model
        logger.info("Submitting structured request schema=%s model=%s", schema_name, selected_model)
        payload = {
            "model": selected_model,
            "temperature": temperature,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            "response_format": {
                "type": "json_schema",
                "json_schema": {
                    "name": schema_name,
                    "strict": True,
                    "schema": schema,
                },
            },
        }

        last_error: Exception | None = None
        for attempt in range(self.config.max_retries + 1):
            try:
                logger.debug("Waiting for rate-limit slot schema=%s attempt=%s", schema_name, attempt + 1)
                self._rate_limiter.wait_for_slot()
                response = self._submit(payload)
                logger.info("Structured request succeeded schema=%s attempt=%s", schema_name, attempt + 1)
                return response
            except error.HTTPError as exc:
                if not _is_retryable_http_error(exc):
                    logger.error("Structured request failed without retry schema=%s http=%s", schema_name, exc.code)
                    raise OpenAIRequestError(_http_error_message(exc)) from exc
                last_error = OpenAIRequestError(_http_error_message(exc))
                if attempt >= self.config.max_retries:
                    break
                logger.warning("Retrying structured request schema=%s http=%s attempt=%s", schema_name, exc.code, attempt + 1)
                time.sleep(max(_retry_after_seconds(exc), min(8.0, 1.5 ** attempt)))
            except (error.URLError, TimeoutError, ValueError) as exc:
                last_error = exc
                if attempt >= self.config.max_retries:
                    break
                logger.warning("Retrying structured request schema=%s error=%s attempt=%s", schema_name, type(exc).__name__, attempt + 1)
                time.sleep(min(8.0, 1.5 ** attempt))

        logger.error("Structured request exhausted retries schema=%s error=%s", schema_name, last_error)
        raise OpenAIRequestError(f"OpenAI request failed after retries: {last_error}")

    def _submit(self, payload: dict) -> dict:
        url = f"{self.config.base_url.rstrip('/')}/chat/completions"
        http_request = request.Request(
            url,
            method="POST",
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {self.config.openai_api_key}",
                "Content-Type": "application/json",
            },
        )

        with request.urlopen(http_request, timeout=self.config.timeout_seconds) as response:
            payload = json.loads(response.read().decode("utf-8"))

        message = payload["choices"][0]["message"]
        content = message.get("content")
        if isinstance(content, list):
            text = "".join(part.get("text", "") for part in content if isinstance(part, dict))
        else:
            text = content or ""

        cleaned = text.strip()
        if not cleaned:
            raise ValueError("OpenAI returned empty content for a structured response.")
        return json.loads(cleaned)


def _is_retryable_http_error(exc: error.HTTPError) -> bool:
    return exc.code in {408, 409, 429, 500, 502, 503, 504}


def _retry_after_seconds(exc: error.HTTPError) -> float:
    retry_after = exc.headers.get("Retry-After") if exc.headers else None
    if retry_after is None:
        return 0.0

    try:
        return max(0.0, float(retry_after))
    except ValueError:
        return 0.0


def _http_error_message(exc: error.HTTPError) -> str:
    details = ""
    try:
        body = exc.read().decode("utf-8", errors="replace").strip()
    except Exception:
        body = ""

    if body:
        try:
            payload = json.loads(body)
            message = payload.get("error", {}).get("message")
            if isinstance(message, str) and message.strip():
                details = f": {message.strip()}"
            else:
                details = f": {body}"
        except json.JSONDecodeError:
            details = f": {body}"

    return f"OpenAI request failed with HTTP {exc.code}{details}"