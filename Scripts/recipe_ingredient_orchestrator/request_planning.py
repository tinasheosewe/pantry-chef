from __future__ import annotations

import json
from dataclasses import dataclass, replace

from .corpus import RecipeCorpusIndex, normalize_text
from .logging_utils import get_logger
from .models import CampaignSpec, DishSpec
from .openai_client import OpenAIChatClient, OpenAIRequestError
from .prompts import (
    APP_CUISINES,
    APP_MEAL_TYPES,
    exact_dish_brief_messages,
    exact_dish_brief_schema,
    request_intent_messages,
    request_intent_schema,
)


logger = get_logger("request_planning")


@dataclass(frozen=True)
class RequestIntent:
    raw_request: str
    desired_count: int
    cuisine: str | None
    meal_type: str | None
    exact_title: str | None


class RequestPlanningService:
    def __init__(self, corpus_index: RecipeCorpusIndex, client: OpenAIChatClient, planning_model: str | None = None) -> None:
        self._corpus_index = corpus_index
        self._client = client
        self._planning_model = planning_model

    def plan(self, request_text: str) -> CampaignSpec:
        logger.info("Planning request text=%s", request_text)
        intent = self._interpret_request_with_openai(request_text)
        logger.info(
            "Request interpreted desired_count=%s cuisine=%s meal_type=%s exact_title=%s",
            intent.desired_count,
            intent.cuisine,
            intent.meal_type,
            intent.exact_title,
        )

        if intent.exact_title is not None:
            duplicate_reason = self._corpus_index.duplicate_reason_for_title(intent.exact_title)
            if duplicate_reason is not None:
                logger.warning("Rejecting exact-title request title=%s reason=%s", intent.exact_title, duplicate_reason)
                raise RuntimeError(duplicate_reason)

            unique = self._ensure_unique_campaign(
                CampaignSpec(name=campaign_name_for_intent(intent), dishes=[self._build_exact_dish_spec(intent)]),
                intent,
            )
            if len(unique.dishes) != 1:
                raise RuntimeError(f"Unable to plan a unique recipe brief for request '{request_text}'.")
            logger.info("Exact-title request planned campaign=%s", unique.campaign_id)
            return unique

        for attempt_number in range(1, 4):
            logger.info("Planning campaign attempt=%s desired_count=%s", attempt_number, intent.desired_count)
            candidate = self._plan_with_openai(intent)
            unique = self._ensure_unique_campaign(candidate, intent)
            if len(unique.dishes) == intent.desired_count:
                logger.info("Campaign planning succeeded campaign=%s dish_count=%s", unique.campaign_id, len(unique.dishes))
                return unique
            logger.warning(
                "Campaign planning attempt=%s produced %s unique dishes out of %s",
                attempt_number,
                len(unique.dishes),
                intent.desired_count,
            )

        raise RuntimeError(
            f"Unable to plan {intent.desired_count} unique recipe briefs from request '{request_text}'."
        )

    def _interpret_request_with_openai(self, request_text: str) -> RequestIntent:
        system_prompt, user_prompt = request_intent_messages(request_text)
        payload = self._client.complete_json(
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            schema=request_intent_schema(),
            schema_name="request_intent",
            temperature=0.0,
            model=self._planning_model,
        )
        desired_count = max(1, int(payload.get("desired_count", 1)))
        cuisine = _enum_or_none(payload.get("cuisine"), APP_CUISINES)
        meal_type = _enum_or_none(payload.get("meal_type"), APP_MEAL_TYPES)
        exact_title = _normalized_exact_title(_optional_string(payload.get("exact_title")))
        if desired_count != 1:
            exact_title = None

        return RequestIntent(
            raw_request=_collapse_whitespace(request_text),
            desired_count=desired_count,
            cuisine=cuisine,
            meal_type=meal_type,
            exact_title=exact_title,
        )

    def _build_exact_dish_spec(self, intent: RequestIntent) -> DishSpec:
        if intent.exact_title is None:
            raise RuntimeError("Exact dish brief requested without an exact title.")
        try:
            return self._build_exact_dish_spec_with_openai(intent)
        except (OpenAIRequestError, TypeError, ValueError, KeyError) as exc:
            logger.exception("Exact-dish planning failed title=%s", intent.exact_title)
            raise RuntimeError(
                f"Unable to build an exact-dish brief for '{intent.exact_title}' without model confirmation."
            ) from exc

    def _build_exact_dish_spec_with_openai(self, intent: RequestIntent) -> DishSpec:
        awareness_context = self._corpus_index.awareness_context_for_spec(
            DishSpec(
                title=intent.exact_title or intent.raw_request,
                cuisine=intent.cuisine,
                meal_type=intent.meal_type,
            )
        )
        system_prompt, user_prompt = exact_dish_brief_messages(
            intent.raw_request,
            intent.exact_title or intent.raw_request,
            awareness_context=awareness_context,
        )
        payload = self._client.complete_json(
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            schema=exact_dish_brief_schema(),
            schema_name="exact_dish_brief",
            temperature=0.2,
            model=self._planning_model,
        )
        return DishSpec(
            title=intent.exact_title or _required_string(payload, "title"),
            cuisine=_enum_or_none(payload.get("cuisine"), APP_CUISINES) or intent.cuisine,
            meal_type=_enum_or_none(payload.get("meal_type"), APP_MEAL_TYPES) or intent.meal_type,
            servings=max(1, int(payload.get("servings", 4))),
            pantry_focus=_clean_string_list(payload.get("pantry_focus"), limit=8),
            goals=_clean_string_list(payload.get("goals"), limit=6) or ["original recipe", "user requested"],
            notes=_optional_string(payload.get("notes")) or f"Planned from natural language request: {intent.raw_request}",
        )

    def _plan_with_openai(self, intent: RequestIntent) -> CampaignSpec:
        proposal_count = _proposal_count_for(intent.desired_count)
        system_prompt = (
            "You turn a user recipe-generation request into a PantryChef campaign plan. "
            "Produce distinct, non-duplicate dish briefs that do not overlap existing recipes. "
            "Use only the supplied app-valid cuisine and meal type values."
        )
        user_prompt = json.dumps(
            {
                "request": intent.raw_request,
                "desired_count": intent.desired_count,
                "detected_constraints": {
                    "cuisine": intent.cuisine,
                    "meal_type": intent.meal_type,
                    "exact_title": intent.exact_title,
                    "proposal_count": proposal_count,
                },
                "allowed_cuisines": APP_CUISINES,
                "allowed_meal_types": APP_MEAL_TYPES,
                "existing_titles": self._corpus_index.awareness_context_for_spec(
                    DishSpec(
                        title=intent.exact_title or intent.raw_request,
                        cuisine=intent.cuisine,
                        meal_type=intent.meal_type,
                    )
                )["avoid_titles"],
                "known_ingredients": self._corpus_index.awareness_context_for_spec(
                    DishSpec(
                        title=intent.exact_title or intent.raw_request,
                        cuisine=intent.cuisine,
                        meal_type=intent.meal_type,
                    )
                )["known_ingredients"],
            },
            indent=2,
            sort_keys=True,
        )

        payload = self._client.complete_json(
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            schema=request_planning_schema(intent.desired_count),
            schema_name="campaign_plan",
            temperature=0.5,
            model=self._planning_model,
        )

        dishes = [
            DishSpec(
                title=_required_string(dish, "title"),
                cuisine=_enum_or_none(dish.get("cuisine"), APP_CUISINES) or intent.cuisine,
                meal_type=_enum_or_none(dish.get("meal_type"), APP_MEAL_TYPES) or intent.meal_type,
                servings=max(1, int(dish.get("servings", 4))),
                goals=_clean_string_list(dish.get("goals")),
                pantry_focus=_clean_string_list(dish.get("pantry_focus")),
                notes=_optional_string(dish.get("notes")),
            )
            for dish in payload.get("dishes", [])
        ]
        return CampaignSpec(name=_optional_string(payload.get("name")) or campaign_name_for_intent(intent), dishes=dishes)

    def _ensure_unique_campaign(self, candidate: CampaignSpec, intent: RequestIntent) -> CampaignSpec:
        unique_dishes: list[DishSpec] = []
        seen_titles: set[str] = set()

        for dish in candidate.dishes:
            duplicate_reason = self._corpus_index.duplicate_reason_for_title(dish.title)
            if duplicate_reason is not None:
                logger.warning("Dropping duplicate planned dish title=%s reason=%s", dish.title, duplicate_reason)
                continue

            peer_duplicate_reason = _peer_duplicate_reason(dish, unique_dishes)
            if peer_duplicate_reason is not None:
                logger.warning("Dropping near-duplicate planned dish title=%s reason=%s", dish.title, peer_duplicate_reason)
                continue

            normalized_title = normalize_text(dish.title)
            if normalized_title in seen_titles:
                logger.warning("Dropping repeated planned title=%s", dish.title)
                continue

            seen_titles.add(normalized_title)
            unique_dishes.append(dish)

            if len(unique_dishes) == intent.desired_count:
                break

        peer_titles = [dish.title for dish in unique_dishes]
        unique_dishes = [
            replace(dish, avoid_titles=sorted(title for title in peer_titles if normalize_text(title) != normalize_text(dish.title)))
            for dish in unique_dishes
        ]
        return CampaignSpec(
            name=candidate.name or campaign_name_for_intent(intent),
            dishes=unique_dishes,
            max_concurrency=candidate.max_concurrency,
            campaign_id=candidate.campaign_id,
            created_at=candidate.created_at,
        )


def campaign_name_for_intent(intent: RequestIntent) -> str:
    if intent.exact_title:
        return f"request-{normalize_text(intent.exact_title).replace(' ', '-') or 'recipe'}"
    base = normalize_text(intent.cuisine or intent.raw_request).replace(" ", "-") or "recipes"
    return f"request-{base}-{intent.desired_count}"


def request_planning_schema(desired_count: int) -> dict:
    proposal_count = _proposal_count_for(desired_count)
    return {
        "type": "object",
        "required": ["name", "dishes"],
        "properties": {
            "name": {"type": ["string", "null"]},
            "dishes": {
                "type": "array",
                "minItems": 1,
                "maxItems": proposal_count,
                "items": {
                    "type": "object",
                    "required": ["title", "cuisine", "meal_type", "servings", "goals", "pantry_focus", "notes"],
                    "properties": {
                        "title": {"type": "string"},
                        "cuisine": {"type": ["string", "null"], "enum": APP_CUISINES + [None]},
                        "meal_type": {"type": ["string", "null"], "enum": APP_MEAL_TYPES + [None]},
                        "servings": {"type": "integer", "minimum": 1, "maximum": 12},
                        "goals": {"type": "array", "items": {"type": "string"}},
                        "pantry_focus": {"type": "array", "items": {"type": "string"}},
                        "notes": {"type": ["string", "null"]},
                    },
                    "additionalProperties": False,
                },
            },
        },
        "additionalProperties": False,
    }


def _proposal_count_for(desired_count: int) -> int:
    return min(50, max(desired_count, desired_count * 2, desired_count + 4))


def _peer_duplicate_reason(candidate: DishSpec, existing: list[DishSpec]) -> str | None:
    candidate_title_tokens = set(normalize_text(candidate.title).split())
    candidate_focus_tokens = {
        token
        for value in [*candidate.pantry_focus, *(candidate.goals or [])]
        for token in normalize_text(value).split()
        if token
    }

    for peer in existing:
        title_overlap = _jaccard(candidate_title_tokens, set(normalize_text(peer.title).split()))
        focus_overlap = _jaccard(
            candidate_focus_tokens,
            {
                token
                for value in [*peer.pantry_focus, *(peer.goals or [])]
                for token in normalize_text(value).split()
                if token
            },
        )
        if title_overlap >= 0.7:
            return f"title overlap with peer dish '{peer.title}' is too high"
        if title_overlap >= 0.45 and focus_overlap >= 0.5:
            return f"title and pantry overlap with peer dish '{peer.title}' is too high"
    return None


def _jaccard(left: set[str], right: set[str]) -> float:
    if not left or not right:
        return 0.0
    return len(left & right) / len(left | right)
def _collapse_whitespace(value: str) -> str:
    return " ".join(value.strip().split())


def _optional_string(value: object) -> str | None:
    if value is None:
        return None
    cleaned = str(value).strip()
    return cleaned or None


def _required_string(payload: dict, key: str) -> str:
    value = _optional_string(payload.get(key))
    if value is None:
        raise ValueError(f"Missing required field: {key}")
    return value


def _enum_or_none(value: object, allowed_values: list[str]) -> str | None:
    cleaned = _optional_string(value)
    if cleaned is None:
        return None
    return cleaned if cleaned in allowed_values else None


def _clean_string_list(values: object, limit: int | None = None) -> list[str]:
    if not isinstance(values, list):
        return []
    cleaned: list[str] = []
    seen: set[str] = set()
    for value in values:
        item = _optional_string(value)
        if item is None:
            continue
        normalized = normalize_text(item)
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        cleaned.append(item)
        if limit is not None and len(cleaned) >= limit:
            break
    return cleaned


def _normalized_exact_title(value: str | None) -> str | None:
    if value is None:
        return None
    if value.lower() == value:
        return value.title()
    return value