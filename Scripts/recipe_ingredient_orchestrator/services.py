from __future__ import annotations

from dataclasses import asdict
import json
from pathlib import Path
from threading import Lock
from typing import Protocol

from .catalog_alignment import CatalogAlignmentService
from .corpus import RecipeCorpusIndex, normalize_text
from .openai_client import OpenAIChatClient
from .models import (
    CatalogEntry,
    DishSpec,
    FacetDefinition,
    FacetSelection,
    FreshnessRange,
    IngredientCandidate,
    IngredientEnrichmentDecision,
    IngredientEnrichmentReport,
    IngredientMention,
    IngredientReference,
    IngredientStorage,
    RecipeCandidate,
    RecipeIngredientInput,
    RecipeReviewReport,
    RecipeStepInput,
    ReviewIssue,
    ResolvedRecipeArtifact,
    ResolutionRecord,
    ValidationReport,
    make_identifier,
    slugify,
)
from .prompts import (
    ambiguity_resolution_messages,
    ambiguity_resolution_schema,
    ingredient_enrichment_messages,
    ingredient_enrichment_schema,
    recipe_review_messages,
    recipe_review_schema,
    recipe_generation_messages,
    recipe_generation_schema,
)


_catalog_alignment_service = CatalogAlignmentService()

class RecipeGenerator(Protocol):
    def generate(self, spec: DishSpec, revision_feedback: list[str] | None = None) -> RecipeCandidate: ...


class IngredientCatalog(Protocol):
    def search(self, mention: IngredientMention, limit: int = 5) -> list[IngredientCandidate]: ...

    def upsert_entries(self, entries: list[CatalogEntry]) -> list[CatalogEntry]: ...


class AmbiguityResolver(Protocol):
    def resolve(
        self,
        spec: DishSpec,
        recipe: RecipeCandidate,
        mention: IngredientMention,
        candidates: list[IngredientCandidate],
    ) -> ResolutionRecord: ...


class RecipeReviewer(Protocol):
    def review(
        self,
        spec: DishSpec,
        candidate: RecipeCandidate,
        artifact: ResolvedRecipeArtifact,
        validation: ValidationReport,
        attempt_number: int,
    ) -> RecipeReviewReport: ...


class IngredientEnricher(Protocol):
    def enrich(
        self,
        spec: DishSpec,
        recipe: RecipeCandidate,
        unresolved_mentions: list[IngredientMention],
    ) -> IngredientEnrichmentReport: ...


class DuplicateRecipeError(RuntimeError):
    pass


class StaticRecipeGenerator:
    def __init__(self, candidate: RecipeCandidate) -> None:
        self._candidate = candidate

    def generate(self, spec: DishSpec, revision_feedback: list[str] | None = None) -> RecipeCandidate:
        return RecipeCandidate(
            title=self._candidate.title or spec.title,
            description=self._candidate.description,
            ingredients=self._candidate.ingredients,
            steps=self._candidate.steps,
            servings=self._candidate.servings or spec.servings,
            prep_time_minutes=self._candidate.prep_time_minutes,
            cook_time_minutes=self._candidate.cook_time_minutes,
            difficulty=self._candidate.difficulty,
            dietary_tags=list(self._candidate.dietary_tags),
            meal_type=self._candidate.meal_type or spec.meal_type,
            cuisine=self._candidate.cuisine or spec.cuisine,
            source=self._candidate.source,
        )


class DemoRecipeGenerator:
    def generate(self, spec: DishSpec, revision_feedback: list[str] | None = None) -> RecipeCandidate:
        pantry_focus = [value for value in spec.pantry_focus if value.strip()][:5]
        ingredient_names = pantry_focus or ["chicken", "garlic", "olive oil", "salt"]
        generated_ingredients = [
            RecipeIngredientInput(
                name=name,
                quantity=1,
                unit="piece",
                category="Produce",
            )
            for name in ingredient_names
        ]
        return RecipeCandidate(
            title=spec.title,
            description="Deterministic demo recipe candidate.",
            ingredients=generated_ingredients,
            steps=[
                RecipeStepInput(step_number=1, instruction="Prepare the pantry-focus ingredients and season them evenly.", estimated_duration_seconds=180),
                RecipeStepInput(step_number=2, instruction="Cook the main ingredients using a realistic technique for the dish style.", estimated_duration_seconds=900),
                RecipeStepInput(step_number=3, instruction="Finish the dish, adjust seasoning, and serve.", estimated_duration_seconds=180),
            ],
            servings=spec.servings,
            prep_time_minutes=15,
            cook_time_minutes=45,
            difficulty=2,
            meal_type=spec.meal_type or "Dinner",
            cuisine=spec.cuisine or "Other",
        )


class MutableIngredientCatalog:
    def __init__(
        self,
        entries: list[CatalogEntry],
        minimum_score: float = 0.45,
        storage_dir: Path | None = None,
    ) -> None:
        self._minimum_score = minimum_score
        self._storage_dir = storage_dir
        self._lock = Lock()
        self._entries_by_key: dict[str, CatalogEntry] = {}
        self._stale_persisted_paths: set[Path] = set()

        if self._storage_dir is not None:
            self._storage_dir.mkdir(parents=True, exist_ok=True)

        self._bootstrap_entries(entries)
        if self._storage_dir is not None:
            self.upsert_entries(self._load_persisted_entries())

    def search(self, mention: IngredientMention, limit: int = 5) -> list[IngredientCandidate]:
        normalized_query = normalize_text(mention.raw_name)
        if not normalized_query:
            return []

        matches: list[IngredientCandidate] = []
        with self._lock:
            entries = list(self._entries_by_key.values())

        for entry in entries:
            best_score = 0.0
            best_alias = entry.name
            best_facets = entry.default_facets

            for alias, alias_facets in entry.aliases.items():
                score = self._lexical_score(normalized_query, normalize_text(alias))
                if score > best_score:
                    best_score = score
                    best_alias = alias
                    best_facets = alias_facets or entry.default_facets

            if entry.quality_status == "placeholder":
                best_score = max(0.0, best_score - 0.2)

            if best_score < self._minimum_score:
                continue

            matches.append(
                IngredientCandidate(
                    candidate_id=make_identifier("candidate"),
                    catalog_item_id=entry.item_id,
                    display_name=entry.name,
                    score=round(best_score, 3),
                    rationale=f"Matched '{mention.raw_name}' against alias '{best_alias}'.",
                    facets=list(best_facets),
                    catalog_entry=entry,
                )
            )

        matches.sort(
            key=lambda candidate: (
                -candidate.score,
                1 if candidate.catalog_entry is not None and candidate.catalog_entry.quality_status == "placeholder" else 0,
                candidate.display_name,
            )
        )
        return matches[:limit]

    def entries(self) -> list[CatalogEntry]:
        with self._lock:
            return list(self._entries_by_key.values())

    def upsert_entries(self, entries: list[CatalogEntry]) -> list[CatalogEntry]:
        merged_entries: list[CatalogEntry] = []
        with self._lock:
            for entry in entries:
                merged_entry = self._merge_entry(entry)
                merged_entries.append(merged_entry)
                if self._storage_dir is not None:
                    self._persist_entry(merged_entry)
            stale_paths = list(self._stale_persisted_paths)
            self._stale_persisted_paths.clear()
        for path in stale_paths:
            if path.exists():
                path.unlink()
        return merged_entries

    def _bootstrap_entries(self, entries: list[CatalogEntry]) -> None:
        with self._lock:
            for entry in entries:
                self._merge_entry(entry)

    def _merge_entry(self, entry: CatalogEntry) -> CatalogEntry:
        entry_key = _catalog_entry_key(entry)
        if entry.quality_status != "placeholder":
            entry = self._merge_related_placeholders(entry)
        existing = self._entries_by_key.get(entry_key)
        if existing is None:
            self._entries_by_key[entry_key] = _normalized_catalog_entry(entry)
            return self._entries_by_key[entry_key]

        merged_aliases = {
            **existing.aliases,
            **entry.aliases,
        }
        merged_entry = CatalogEntry(
            item_id=existing.item_id,
            name=existing.name or entry.name,
            category=existing.category or entry.category,
            aliases={alias: list(facets) for alias, facets in merged_aliases.items()},
            default_unit=existing.default_unit or entry.default_unit,
            default_quantity=existing.default_quantity if existing.default_quantity is not None else entry.default_quantity,
            facet_definitions=_merged_facet_definitions(existing.facet_definitions, entry.facet_definitions),
            default_facets=list(existing.default_facets or entry.default_facets),
            unit_overrides=_merged_unit_overrides(existing.unit_overrides, entry.unit_overrides),
            notes=existing.notes or entry.notes,
            substitutes=list(existing.substitutes or entry.substitutes),
            storage=existing.storage or entry.storage,
            freshness_by_storage=_merged_freshness_ranges(existing.freshness_by_storage, entry.freshness_by_storage),
            quality_status=_merged_quality_status(existing.quality_status, entry.quality_status),
            provenance=_merged_string_list(existing.provenance, entry.provenance),
            evidence_count=max(existing.evidence_count, entry.evidence_count),
            recipe_reference_count=max(existing.recipe_reference_count, entry.recipe_reference_count),
            first_seen_at=existing.first_seen_at or entry.first_seen_at,
            last_seen_at=entry.last_seen_at or existing.last_seen_at,
        )
        self._entries_by_key[entry_key] = _normalized_catalog_entry(merged_entry)
        return self._entries_by_key[entry_key]

    def _merge_related_placeholders(self, entry: CatalogEntry) -> CatalogEntry:
        alias_keys = {
            normalize_text(entry.name),
            *(normalize_text(alias) for alias in entry.aliases),
        }
        placeholders_to_merge = [
            existing
            for key, existing in list(self._entries_by_key.items())
            if existing.quality_status == "placeholder" and key in alias_keys
        ]
        if not placeholders_to_merge:
            return entry

        merged_aliases = {alias: list(facets) for alias, facets in entry.aliases.items()}
        merged_provenance = list(entry.provenance)
        notes = entry.notes
        first_seen_at = entry.first_seen_at
        last_seen_at = entry.last_seen_at
        evidence_count = entry.evidence_count
        recipe_reference_count = entry.recipe_reference_count

        for placeholder in placeholders_to_merge:
            merged_aliases.update({alias: list(facets) for alias, facets in placeholder.aliases.items()})
            merged_provenance = _merged_string_list(merged_provenance, placeholder.provenance)
            notes = notes or placeholder.notes
            first_seen_at = first_seen_at or placeholder.first_seen_at
            last_seen_at = last_seen_at or placeholder.last_seen_at
            evidence_count = max(evidence_count, placeholder.evidence_count)
            recipe_reference_count = max(recipe_reference_count, placeholder.recipe_reference_count)
            self._entries_by_key.pop(_catalog_entry_key(placeholder), None)
            if self._storage_dir is not None:
                placeholder_path = self._storage_dir / f"{placeholder.item_id}.json"
                if placeholder_path.exists():
                    placeholder_path.unlink()

        return CatalogEntry(
            item_id=entry.item_id,
            name=entry.name,
            category=entry.category,
            aliases=merged_aliases,
            default_unit=entry.default_unit,
            default_quantity=entry.default_quantity,
            facet_definitions=list(entry.facet_definitions),
            default_facets=list(entry.default_facets),
            unit_overrides={key: dict(value) for key, value in entry.unit_overrides.items()},
            notes=notes,
            substitutes=list(entry.substitutes),
            storage=entry.storage,
            freshness_by_storage=dict(entry.freshness_by_storage),
            quality_status=entry.quality_status,
            provenance=merged_provenance,
            evidence_count=evidence_count,
            recipe_reference_count=recipe_reference_count,
            first_seen_at=first_seen_at,
            last_seen_at=last_seen_at,
        )

    def _load_persisted_entries(self) -> list[CatalogEntry]:
        if self._storage_dir is None or not self._storage_dir.exists():
            return []
        entries: list[CatalogEntry] = []
        for path in sorted(self._storage_dir.glob("*.json")):
            payload = json.loads(path.read_text(encoding="utf-8"))
            entry = _catalog_alignment_service.align_entry(
                CatalogEntry(
                    item_id=str(payload["item_id"]),
                    name=str(payload["name"]),
                    category=str(payload["category"]),
                    aliases={
                        str(alias): [FacetSelection(key=str(facet["key"]), value=str(facet["value"])) for facet in facets]
                        for alias, facets in payload.get("aliases", {}).items()
                    },
                    default_unit=_clean_optional_string(payload.get("default_unit")),
                    default_quantity=_float_or_none(payload.get("default_quantity")),
                    facet_definitions=_facet_definitions_from_payload(payload.get("facet_definitions")),
                    default_facets=[
                        FacetSelection(key=str(facet["key"]), value=str(facet["value"]))
                        for facet in payload.get("default_facets", [])
                    ],
                    unit_overrides=_unit_overrides_from_payload(payload.get("unit_overrides")),
                    notes=_clean_optional_string(payload.get("notes")),
                    substitutes=_ingredient_references_from_payload(payload.get("substitutes")),
                    storage=_storage_from_payload(payload.get("storage")),
                    freshness_by_storage=_freshness_ranges_from_payload(payload.get("freshness_by_storage")),
                    quality_status=_clean_optional_string(payload.get("quality_status")) or "seed",
                    provenance=_clean_string_sequence(payload.get("provenance")),
                    evidence_count=max(0, int(payload.get("evidence_count", 0))),
                    recipe_reference_count=max(0, int(payload.get("recipe_reference_count", 0))),
                    first_seen_at=_clean_optional_string(payload.get("first_seen_at")),
                    last_seen_at=_clean_optional_string(payload.get("last_seen_at")),
                )
            )
            if entry.item_id != path.stem:
                self._stale_persisted_paths.add(path)
            entries.append(entry)
        return entries

    def _persist_entry(self, entry: CatalogEntry) -> None:
        if self._storage_dir is None:
            return
        path = self._storage_dir / f"{entry.item_id}.json"
        path.write_text(
            json.dumps(
                {
                    "item_id": entry.item_id,
                    "name": entry.name,
                    "category": entry.category,
                    "aliases": {
                        alias: [{"key": facet.key, "value": facet.value} for facet in facets]
                        for alias, facets in entry.aliases.items()
                    },
                    "default_unit": entry.default_unit,
                    "default_quantity": entry.default_quantity,
                    "facet_definitions": [asdict(definition) for definition in entry.facet_definitions],
                    "default_facets": [{"key": facet.key, "value": facet.value} for facet in entry.default_facets],
                    "unit_overrides": dict(entry.unit_overrides),
                    "notes": entry.notes,
                    "substitutes": [asdict(reference) for reference in entry.substitutes],
                    "storage": None if entry.storage is None else asdict(entry.storage),
                    "freshness_by_storage": {
                        storage_key: asdict(freshness)
                        for storage_key, freshness in entry.freshness_by_storage.items()
                    },
                    "quality_status": entry.quality_status,
                    "provenance": list(entry.provenance),
                    "evidence_count": entry.evidence_count,
                    "recipe_reference_count": entry.recipe_reference_count,
                    "first_seen_at": entry.first_seen_at,
                    "last_seen_at": entry.last_seen_at,
                },
                indent=2,
                sort_keys=True,
            ) + "\n",
            encoding="utf-8",
        )

    @staticmethod
    def _lexical_score(query: str, alias: str) -> float:
        if query == alias:
            return 1.0

        query_tokens = set(query.split())
        alias_tokens = set(alias.split())
        if not query_tokens or not alias_tokens:
            return 0.0

        overlap_count = len(query_tokens & alias_tokens)
        union_count = len(query_tokens | alias_tokens)
        overlap = overlap_count / union_count
        contains_bonus = 0.15 if query in alias or alias in query else 0.0
        length_penalty = abs(len(alias_tokens) - len(query_tokens)) * 0.05
        return max(0.0, min(0.99, overlap + contains_bonus - length_penalty))


class HeuristicAmbiguityResolver:
    def resolve(
        self,
        spec: DishSpec,
        recipe: RecipeCandidate,
        mention: IngredientMention,
        candidates: list[IngredientCandidate],
    ) -> ResolutionRecord:
        rescored = [
            (round(candidate.score, 3), candidate)
            for candidate in candidates
        ]
        rescored.sort(key=lambda pair: (-pair[0], pair[1].display_name))
        top_score, top_candidate = rescored[0]
        second_score = rescored[1][0] if len(rescored) > 1 else 0.0

        if top_score - second_score < 0.05:
            return ResolutionRecord(
                mention_id=mention.mention_id,
                status="unresolved",
                selected_candidate_id=None,
                selected_catalog_item_id=None,
                confidence=top_score,
                rationale="Ambiguity remained after bounded resolver scoring.",
                candidates=candidates,
            )

        return ResolutionRecord(
            mention_id=mention.mention_id,
            status="resolved",
            selected_candidate_id=top_candidate.candidate_id,
            selected_catalog_item_id=top_candidate.catalog_item_id,
            confidence=top_score,
            rationale=f"Resolved via bounded ambiguity scoring for '{mention.raw_name}'.",
            candidates=candidates,
        )


class ScriptedAmbiguityResolver:
    def __init__(self, preferences: dict[str, str], fallback: AmbiguityResolver | None = None) -> None:
        self._preferences = {normalize_text(key): value for key, value in preferences.items()}
        self._fallback = fallback or HeuristicAmbiguityResolver()

    def resolve(
        self,
        spec: DishSpec,
        recipe: RecipeCandidate,
        mention: IngredientMention,
        candidates: list[IngredientCandidate],
    ) -> ResolutionRecord:
        preferred_catalog_item_id = self._preferences.get(normalize_text(mention.raw_name))
        if preferred_catalog_item_id is None:
            return self._fallback.resolve(spec, recipe, mention, candidates)

        for candidate in candidates:
            if candidate.catalog_item_id == preferred_catalog_item_id:
                return ResolutionRecord(
                    mention_id=mention.mention_id,
                    status="resolved",
                    selected_candidate_id=candidate.candidate_id,
                    selected_catalog_item_id=candidate.catalog_item_id,
                    confidence=max(candidate.score, 0.96),
                    rationale=f"Resolved via scripted ambiguity rule for '{mention.raw_name}'.",
                    candidates=candidates,
                )

        return self._fallback.resolve(spec, recipe, mention, candidates)


class NoOpIngredientEnricher:
    def enrich(
        self,
        spec: DishSpec,
        recipe: RecipeCandidate,
        unresolved_mentions: list[IngredientMention],
    ) -> IngredientEnrichmentReport:
        return IngredientEnrichmentReport()


class ScriptedIngredientEnricher:
    def __init__(self, decisions_by_name: dict[str, IngredientEnrichmentDecision]) -> None:
        self._decisions_by_name = {normalize_text(key): value for key, value in decisions_by_name.items()}

    def enrich(
        self,
        spec: DishSpec,
        recipe: RecipeCandidate,
        unresolved_mentions: list[IngredientMention],
    ) -> IngredientEnrichmentReport:
        decisions: list[IngredientEnrichmentDecision] = []
        generated_entries: list[CatalogEntry] = []
        ignored_mentions: dict[str, str] = {}

        for mention in unresolved_mentions:
            decision = self._decisions_by_name.get(normalize_text(mention.raw_name))
            if decision is None:
                continue
            decisions.append(decision)
            if decision.action == "ignore":
                ignored_mentions[normalize_text(mention.raw_name)] = decision.rationale
                continue
            generated_entries.append(_catalog_entry_from_enrichment(decision, mention))

        return IngredientEnrichmentReport(
            decisions=decisions,
            generated_entries=generated_entries,
            ignored_mentions=ignored_mentions,
        )


class OpenAIIngredientEnricher:
    def __init__(self, client: OpenAIChatClient, model: str | None = None) -> None:
        self._client = client
        self._model = model

    def enrich(
        self,
        spec: DishSpec,
        recipe: RecipeCandidate,
        unresolved_mentions: list[IngredientMention],
    ) -> IngredientEnrichmentReport:
        if not unresolved_mentions:
            return IngredientEnrichmentReport()

        system_prompt, user_prompt = ingredient_enrichment_messages(spec, recipe, unresolved_mentions)
        payload = self._client.complete_json(
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            schema=ingredient_enrichment_schema(),
            schema_name="ingredient_enrichment",
            temperature=0.1,
            model=self._model,
        )

        decisions: list[IngredientEnrichmentDecision] = []
        generated_entries: list[CatalogEntry] = []
        ignored_mentions: dict[str, str] = {}
        mention_by_name = {normalize_text(mention.raw_name): mention for mention in unresolved_mentions}

        for item in payload.get("decisions", []):
            raw_name = _required_string(item, "raw_name")
            normalized_raw_name = normalize_text(raw_name)
            mention = mention_by_name.get(normalized_raw_name)
            if mention is None:
                continue

            decision = IngredientEnrichmentDecision(
                raw_name=raw_name,
                action=_required_string(item, "action"),
                rationale=_required_string(item, "rationale"),
                canonical_name=_optional_string(item, "canonical_name"),
                category=_optional_string(item, "category"),
                aliases=_clean_string_sequence(item.get("aliases")),
                default_unit=_optional_string(item, "default_unit"),
                default_quantity=_float_or_none(item.get("default_quantity")),
                facet_definitions=_facet_definitions_from_payload(item.get("facet_definitions")),
                default_facets=_facet_selections_from_payload(item.get("default_facets")),
                unit_overrides=_unit_overrides_from_payload(item.get("unit_overrides")),
                substitutes=_ingredient_references_from_payload(item.get("substitutes")),
                storage=_storage_from_payload(item.get("storage")),
                freshness_by_storage=_freshness_ranges_from_payload(item.get("freshness_by_storage")),
                quality_status="enriched",
            )
            decisions.append(decision)

            if decision.action == "ignore":
                ignored_mentions[normalized_raw_name] = decision.rationale
                continue

            generated_entries.append(_catalog_entry_from_enrichment(decision, mention))

        return IngredientEnrichmentReport(
            decisions=decisions,
            generated_entries=generated_entries,
            ignored_mentions=ignored_mentions,
        )


class OpenAIRecipeGenerator:
    def __init__(
        self,
        client: OpenAIChatClient,
        corpus_index: RecipeCorpusIndex | None = None,
        max_attempts: int = 3,
        model: str | None = None,
    ) -> None:
        self._client = client
        self._corpus_index = corpus_index
        self._max_attempts = max(1, max_attempts)
        self._model = model

    def generate(self, spec: DishSpec, revision_feedback: list[str] | None = None) -> RecipeCandidate:
        rejected_titles: list[str] = []
        last_reason: str | None = None

        for _ in range(self._max_attempts):
            awareness_context = None
            if self._corpus_index is not None:
                awareness_context = self._corpus_index.awareness_context_for_spec(spec, rejected_titles=rejected_titles)

            system_prompt, user_prompt = recipe_generation_messages(
                spec,
                awareness_context=awareness_context,
                revision_feedback=revision_feedback,
            )
            payload = self._client.complete_json(
                system_prompt=system_prompt,
                user_prompt=user_prompt,
                schema=recipe_generation_schema(),
                schema_name="recipe_candidate",
                temperature=0.7,
                model=self._model,
            )
            candidate = RecipeCandidate(
                title=spec.title,
                description=_optional_string(payload, "description"),
                ingredients=[_parse_recipe_ingredient(item) for item in payload.get("ingredients", [])],
                steps=[_parse_recipe_step(item) for item in payload.get("steps", [])],
                servings=max(1, int(payload.get("servings", spec.servings))),
                prep_time_minutes=_optional_int(payload, "prep_time_minutes"),
                cook_time_minutes=_optional_int(payload, "cook_time_minutes"),
                difficulty=_bounded_difficulty(payload.get("difficulty", 2)),
                dietary_tags=_normalized_dietary_tags(payload.get("dietary_tags", [])),
                meal_type=spec.meal_type or _optional_string(payload, "meal_type"),
                cuisine=spec.cuisine or _optional_string(payload, "cuisine"),
                source="aiGenerated",
            )

            last_reason = self._duplicate_reason(candidate, spec)
            if last_reason is None:
                return candidate
            rejected_titles.append(candidate.title)

        raise DuplicateRecipeError(last_reason or f"Unable to generate a unique recipe for '{spec.title}'.")

    def _duplicate_reason(self, candidate: RecipeCandidate, spec: DishSpec) -> str | None:
        normalized_avoid_titles = {normalize_text(value) for value in spec.avoid_titles}
        if normalize_text(candidate.title) in normalized_avoid_titles:
            return f"Generated title '{candidate.title}' matches an avoided peer title."

        if self._corpus_index is None:
            return None
        return self._corpus_index.duplicate_reason_for_candidate(candidate, extra_avoid_titles=spec.avoid_titles)


class DeterministicRecipeReviewer:
    def review(
        self,
        spec: DishSpec,
        candidate: RecipeCandidate,
        artifact: ResolvedRecipeArtifact,
        validation: ValidationReport,
        attempt_number: int,
    ) -> RecipeReviewReport:
        if validation.is_valid:
            return RecipeReviewReport(
                status="accepted",
                reviewer="deterministic",
                rationale="Recipe passed deterministic validation and required no revision.",
                retryable=False,
            )

        issues = [
            ReviewIssue(code=code, severity="error", message=message)
            for code, message in zip(validation.error_codes, validation.errors)
        ]
        revision_instructions = [f"Fix validation issue: {message}" for message in validation.errors]
        return RecipeReviewReport(
            status="revise",
            reviewer="deterministic",
            rationale="Recipe failed deterministic validation and must be revised before acceptance.",
            issues=issues,
            revision_instructions=revision_instructions,
            retryable=True,
        )


class OpenAIRecipeReviewer:
    def __init__(self, client: OpenAIChatClient, model: str | None = None) -> None:
        self._client = client
        self._model = model

    def review(
        self,
        spec: DishSpec,
        candidate: RecipeCandidate,
        artifact: ResolvedRecipeArtifact,
        validation: ValidationReport,
        attempt_number: int,
    ) -> RecipeReviewReport:
        system_prompt, user_prompt = recipe_review_messages(spec, candidate, artifact, validation, attempt_number)
        payload = self._client.complete_json(
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            schema=recipe_review_schema(),
            schema_name="recipe_review",
            temperature=0.2,
            model=self._model,
        )

        issues = [
            ReviewIssue(
                code=_required_string(issue, "code"),
                severity=_required_string(issue, "severity"),
                message=_required_string(issue, "message"),
            )
            for issue in payload.get("issues", [])
        ]
        revision_instructions = [
            str(value).strip()
            for value in payload.get("revision_instructions", [])
            if str(value).strip()
        ]

        return RecipeReviewReport(
            status=_required_string(payload, "status"),
            reviewer=_required_string(payload, "reviewer"),
            rationale=_required_string(payload, "rationale"),
            issues=issues,
            revision_instructions=revision_instructions,
            retryable=bool(payload.get("retryable", False)),
        )


class OpenAIAmbiguityResolver:
    def __init__(self, client: OpenAIChatClient, model: str | None = None) -> None:
        self._client = client
        self._model = model

    def resolve(
        self,
        spec: DishSpec,
        recipe: RecipeCandidate,
        mention: IngredientMention,
        candidates: list[IngredientCandidate],
    ) -> ResolutionRecord:
        system_prompt, user_prompt = ambiguity_resolution_messages(spec, recipe, mention, candidates)
        payload = self._client.complete_json(
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            schema=ambiguity_resolution_schema([candidate.candidate_id for candidate in candidates]),
            schema_name="ingredient_resolution",
            temperature=0.1,
            model=self._model,
        )

        status = str(payload.get("status", "unresolved"))
        selected_candidate_id = payload.get("selected_candidate_id")
        selected_catalog_item_id = payload.get("selected_catalog_item_id")
        confidence = max(0.0, min(1.0, float(payload.get("confidence", 0.0))))
        rationale = _required_string(payload, "rationale")

        if status != "resolved" or not selected_candidate_id:
            return ResolutionRecord(
                mention_id=mention.mention_id,
                status="unresolved",
                selected_candidate_id=None,
                selected_catalog_item_id=None,
                confidence=confidence,
                rationale=rationale,
                candidates=candidates,
            )

        selected_candidate = next(
            (candidate for candidate in candidates if candidate.candidate_id == selected_candidate_id),
            None,
        )
        if selected_candidate is None:
            return ResolutionRecord(
                mention_id=mention.mention_id,
                status="unresolved",
                selected_candidate_id=None,
                selected_catalog_item_id=None,
                confidence=confidence,
                rationale="Model returned a candidate id that was not supplied.",
                candidates=candidates,
            )

        return ResolutionRecord(
            mention_id=mention.mention_id,
            status="resolved",
            selected_candidate_id=selected_candidate.candidate_id,
            selected_catalog_item_id=selected_catalog_item_id or selected_candidate.catalog_item_id,
            confidence=max(confidence, selected_candidate.score),
            rationale=rationale,
            candidates=candidates,
        )


def _required_string(payload: dict, key: str) -> str:
    value = str(payload.get(key, "")).strip()
    if not value:
        raise ValueError(f"Missing required field: {key}")
    return value


def _optional_string(payload: dict, key: str) -> str | None:
    value = payload.get(key)
    if value is None:
        return None
    cleaned = str(value).strip()
    return cleaned or None


def _clean_optional_string(value: object) -> str | None:
    if value is None:
        return None
    cleaned = str(value).strip()
    return cleaned or None


def _float_or_none(value: object) -> float | None:
    if value in (None, ""):
        return None
    return float(value)


def _clean_string_sequence(value: object) -> list[str]:
    if not isinstance(value, list):
        return []
    cleaned: list[str] = []
    seen: set[str] = set()
    for item in value:
        normalized = normalize_text(str(item))
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        cleaned.append(str(item).strip())
    return cleaned


def _facet_selections_from_payload(value: object) -> list[FacetSelection]:
    if not isinstance(value, list):
        return []
    selections: list[FacetSelection] = []
    seen: set[tuple[str, str]] = set()
    for item in value:
        if not isinstance(item, dict):
            continue
        key = _clean_optional_string(item.get("key"))
        option = _clean_optional_string(item.get("value"))
        if key is None or option is None:
            continue
        if (key, option) in seen:
            continue
        seen.add((key, option))
        selections.append(FacetSelection(key=key, value=option))
    return selections


def _facet_definitions_from_payload(value: object) -> list[FacetDefinition]:
    if not isinstance(value, list):
        return []
    definitions: list[FacetDefinition] = []
    seen: set[str] = set()
    for item in value:
        if not isinstance(item, dict):
            continue
        key = _clean_optional_string(item.get("key"))
        if key is None or key in seen:
            continue
        options = _clean_string_sequence(item.get("options"))
        if not options:
            continue
        seen.add(key)
        definitions.append(FacetDefinition(key=key, options=options))
    return definitions


def _unit_overrides_from_payload(value: object) -> dict[str, dict[str, str]]:
    if not isinstance(value, dict):
        return {}
    cleaned: dict[str, dict[str, str]] = {}
    for facet_key, overrides in value.items():
        if not isinstance(overrides, dict):
            continue
        normalized_facet_key = str(facet_key).strip()
        if not normalized_facet_key:
            continue
        option_overrides: dict[str, str] = {}
        for option, unit in overrides.items():
            normalized_option = str(option).strip()
            normalized_unit = _clean_optional_string(unit)
            if not normalized_option or normalized_unit is None:
                continue
            option_overrides[normalized_option] = normalized_unit
        if option_overrides:
            cleaned[normalized_facet_key] = option_overrides
    return cleaned


def _normalized_dietary_tags(value: object) -> list[str]:
    if not isinstance(value, list):
        return []
    tags: list[str] = []
    seen: set[str] = set()
    for item in value:
        cleaned = str(item).strip()
        if not cleaned:
            continue
        normalized = normalize_text(cleaned)
        if normalized in seen:
            continue
        seen.add(normalized)
        tags.append(cleaned)
    return tags


def _optional_int(payload: dict, key: str) -> int | None:
    value = payload.get(key)
    if value in (None, ""):
        return None
    return int(value)


def _bounded_difficulty(value: object) -> int:
    difficulty = int(value)
    return max(1, min(5, difficulty))


def _parse_recipe_ingredient(payload: dict) -> RecipeIngredientInput:
    return RecipeIngredientInput(
        name=_required_string(payload, "name"),
        quantity=max(0.0, float(payload.get("quantity", 0.0))),
        unit=_optional_string(payload, "unit"),
        category=_required_string(payload, "category"),
        is_optional=bool(payload.get("is_optional", False)),
        notes=_optional_string(payload, "notes"),
    )


def _parse_recipe_step(payload: dict) -> RecipeStepInput:
    return RecipeStepInput(
        step_number=max(1, int(payload.get("step_number", 1))),
        instruction=_required_string(payload, "instruction"),
        timer_minutes=_optional_int(payload, "timer_minutes"),
        estimated_duration_seconds=_optional_int(payload, "estimated_duration_seconds"),
        tip=_optional_string(payload, "tip"),
    )


def _catalog_entry_key(entry: CatalogEntry) -> str:
    return normalize_text(entry.name) or entry.item_id


def _normalized_catalog_entry(entry: CatalogEntry) -> CatalogEntry:
    aliases: dict[str, list[FacetSelection]] = {}
    for alias, facets in entry.aliases.items():
        cleaned_alias = alias.strip()
        if not cleaned_alias:
            continue
        aliases[cleaned_alias] = list(facets)
    if entry.name not in aliases:
        aliases[entry.name] = list(entry.default_facets)
    return _catalog_alignment_service.align_entry(CatalogEntry(
        item_id=entry.item_id,
        name=entry.name,
        category=entry.category,
        aliases=aliases,
        default_unit=entry.default_unit,
        default_quantity=entry.default_quantity,
        facet_definitions=list(entry.facet_definitions),
        default_facets=list(entry.default_facets),
        unit_overrides={key: dict(value) for key, value in entry.unit_overrides.items()},
        notes=entry.notes,
        substitutes=list(entry.substitutes),
        storage=entry.storage,
        freshness_by_storage=dict(entry.freshness_by_storage),
        quality_status=entry.quality_status,
        provenance=list(entry.provenance),
        evidence_count=entry.evidence_count,
        recipe_reference_count=entry.recipe_reference_count,
        first_seen_at=entry.first_seen_at,
        last_seen_at=entry.last_seen_at,
    ))


def _catalog_entry_from_enrichment(decision: IngredientEnrichmentDecision, mention: IngredientMention) -> CatalogEntry:
    canonical_name = decision.canonical_name or mention.raw_name
    aliases = {
        alias: []
        for alias in [canonical_name, mention.raw_name, *decision.aliases]
        if alias.strip()
    }
    return _catalog_alignment_service.align_entry(CatalogEntry(
        item_id=slugify(canonical_name),
        name=canonical_name,
        category=decision.category or mention.category,
        aliases=aliases,
        default_unit=decision.default_unit or mention.unit,
        default_quantity=decision.default_quantity,
        facet_definitions=list(decision.facet_definitions),
        default_facets=list(decision.default_facets),
        unit_overrides={key: dict(value) for key, value in decision.unit_overrides.items()},
        notes=decision.rationale,
        substitutes=list(decision.substitutes),
        storage=decision.storage,
        freshness_by_storage=dict(decision.freshness_by_storage),
        quality_status=decision.quality_status,
        provenance=["ingredient_enrichment"],
        first_seen_at=None,
        last_seen_at=None,
    ))


def build_placeholder_catalog_entries(mentions: list[IngredientMention]) -> list[CatalogEntry]:
    entries: list[CatalogEntry] = []
    seen: set[str] = set()
    for mention in mentions:
        item_id = slugify(mention.raw_name)
        if item_id in seen:
            continue
        seen.add(item_id)
        entries.append(
            CatalogEntry(
                item_id=item_id,
                name=mention.raw_name.strip() or item_id,
                category=mention.category,
                aliases={mention.raw_name: []},
                default_unit=mention.unit,
                notes="Auto-provisioned placeholder ingredient created because enrichment did not fully resolve the mention yet.",
                quality_status="placeholder",
                provenance=["placeholder_provisioning"],
            )
        )
    return entries


def _merged_string_list(left: list[str], right: list[str]) -> list[str]:
    seen: set[str] = set()
    merged: list[str] = []
    for value in [*left, *right]:
        normalized = normalize_text(value)
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        merged.append(value)
    return merged


def _merged_facet_definitions(left: list[FacetDefinition], right: list[FacetDefinition]) -> list[FacetDefinition]:
    options_by_key: dict[str, set[str]] = {}
    for definition in [*left, *right]:
        options_by_key.setdefault(definition.key, set()).update(definition.options)
    return [
        FacetDefinition(key=key, options=sorted(options))
        for key, options in sorted(options_by_key.items())
        if options
    ]


def _merged_unit_overrides(left: dict[str, dict[str, str]], right: dict[str, dict[str, str]]) -> dict[str, dict[str, str]]:
    merged: dict[str, dict[str, str]] = {}
    for facet_key, overrides in left.items():
        merged[facet_key] = dict(overrides)
    for facet_key, overrides in right.items():
        merged.setdefault(facet_key, {}).update(overrides)
    return merged


def _merged_freshness_ranges(
    left: dict[str, FreshnessRange],
    right: dict[str, FreshnessRange],
) -> dict[str, FreshnessRange]:
    merged = dict(left)
    merged.update(right)
    return merged


def _merged_quality_status(existing: str, incoming: str) -> str:
    rank = {"placeholder": 0, "seed": 1, "enriched": 2}
    return incoming if rank.get(incoming, 0) >= rank.get(existing, 0) else existing


def _storage_from_payload(value: object) -> IngredientStorage | None:
    if not isinstance(value, dict):
        return None
    preferred = _clean_optional_string(value.get("preferred"))
    pantry_days = _int_or_none(value.get("pantry_days"))
    refrigerator_days = _int_or_none(value.get("refrigerator_days"))
    freezer_days = _int_or_none(value.get("freezer_days"))
    notes = _clean_optional_string(value.get("notes"))
    if preferred is None and pantry_days is None and refrigerator_days is None and freezer_days is None and notes is None:
        return None
    return IngredientStorage(
        preferred=preferred,
        pantry_days=pantry_days,
        refrigerator_days=refrigerator_days,
        freezer_days=freezer_days,
        notes=notes,
    )


def _freshness_ranges_from_payload(value: object) -> dict[str, FreshnessRange]:
    if not isinstance(value, dict):
        return {}
    freshness: dict[str, FreshnessRange] = {}
    for storage_key, payload in value.items():
        if not isinstance(payload, dict):
            continue
        minimum = _int_or_none(payload.get("min_days"))
        maximum = _int_or_none(payload.get("max_days"))
        if minimum is None or maximum is None:
            minimum = _int_or_none(payload.get("minDays"))
            maximum = _int_or_none(payload.get("maxDays"))
        if minimum is None or maximum is None:
            continue
        normalized_storage_key = str(storage_key).strip()
        if not normalized_storage_key:
            continue
        freshness[normalized_storage_key] = FreshnessRange(min_days=minimum, max_days=max(maximum, minimum))
    return freshness


def _ingredient_references_from_payload(value: object) -> list[IngredientReference]:
    if not isinstance(value, list):
        return []
    references: list[IngredientReference] = []
    seen: set[str] = set()
    for item in value:
        if not isinstance(item, dict):
            continue
        name = _clean_optional_string(item.get("name"))
        if name is None:
            continue
        item_id = slugify(name)
        if item_id in seen:
            continue
        seen.add(item_id)
        references.append(
            IngredientReference(
                item_id=item_id,
                name=name,
                rationale=_clean_optional_string(item.get("rationale")),
                facets=_facet_selections_from_payload(item.get("facets")),
                ratio=_clean_optional_string(item.get("ratio")),
                taste_impact=_clean_optional_string(item.get("taste_impact") or item.get("tasteImpact")),
                texture_impact=_clean_optional_string(item.get("texture_impact") or item.get("textureImpact")),
                cooking_impact=_clean_optional_string(item.get("cooking_impact") or item.get("cookingImpact")),
                nutrition_impact=_clean_optional_string(item.get("nutrition_impact") or item.get("nutritionImpact")),
                notes=_clean_optional_string(item.get("notes")),
                dietary=_clean_string_sequence(item.get("dietary")),
            )
        )
    return references


def _int_or_none(value: object) -> int | None:
    if value in (None, ""):
        return None
    return int(value)


def build_default_catalog(
    storage_dir: Path | None = None,
    **_kwargs,
) -> MutableIngredientCatalog:
    return MutableIngredientCatalog([], storage_dir=storage_dir)