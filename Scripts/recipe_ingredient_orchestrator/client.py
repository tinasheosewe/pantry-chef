"""Async OpenAI client wrapper with structured outputs, retry, and concurrency."""

from __future__ import annotations

import asyncio
import logging
from typing import TypeVar

from openai import AsyncOpenAI, BadRequestError, APIStatusError
from pydantic import BaseModel

from .config import Settings

logger = logging.getLogger(__name__)

T = TypeVar("T", bound=BaseModel)

_TRANSIENT_CODES = {400, 429, 500, 502, 503}
_MAX_TRANSIENT_RETRIES = 3
_BASE_BACKOFF = 5.0


class LLMClient:
    """Thin async wrapper around the OpenAI SDK.

    All callers get typed Pydantic objects back — never raw dicts.
    Concurrency is bounded by the shared semaphore.
    """

    def __init__(self, settings: Settings) -> None:
        self._client = AsyncOpenAI(
            api_key=settings.openai_api_key,
            max_retries=settings.max_retries,
        )
        self._semaphore = asyncio.Semaphore(settings.max_concurrency)

    async def generate(
        self,
        *,
        messages: list[dict[str, str]],
        response_model: type[T],
        model: str,
        temperature: float = 0.7,
    ) -> T:
        """Send a chat completion and parse the response into a Pydantic model."""
        async with self._semaphore:
            logger.debug("LLM request: model=%s schema=%s", model, response_model.__name__)
            last_err: Exception | None = None
            for attempt in range(1, _MAX_TRANSIENT_RETRIES + 1):
                try:
                    response = await self._client.beta.chat.completions.parse(
                        model=model,
                        messages=messages,  # type: ignore[arg-type]
                        response_format=response_model,
                        temperature=temperature,
                    )
                    parsed = response.choices[0].message.parsed
                    if parsed is None:
                        refusal = response.choices[0].message.refusal
                        raise RuntimeError(f"LLM refused: {refusal}")
                    logger.debug("LLM response parsed: %s", response_model.__name__)
                    return parsed
                except APIStatusError as exc:
                    if exc.status_code not in _TRANSIENT_CODES:
                        raise
                    last_err = exc
                    wait = _BASE_BACKOFF * (2 ** (attempt - 1))
                    logger.warning(
                        "Transient API error %d (attempt %d/%d), retrying in %.0fs: %s",
                        exc.status_code, attempt, _MAX_TRANSIENT_RETRIES, wait, exc.message,
                    )
                    await asyncio.sleep(wait)
            raise last_err  # type: ignore[misc]

    async def close(self) -> None:
        await self._client.close()
