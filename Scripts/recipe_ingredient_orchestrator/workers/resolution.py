from __future__ import annotations

from ..corpus import normalize_text
from ..models import DishSpec, IngredientMention, RecipeCandidate, ResolvedIngredient, ResolutionRecord
from ..services import AmbiguityResolver, IngredientCatalog


class IngredientResolutionWorker:
    def __init__(
        self,
        catalog: IngredientCatalog,
        ambiguity_resolver: AmbiguityResolver,
        auto_accept_score: float = 0.92,
        auto_accept_margin: float = 0.12,
    ) -> None:
        self._catalog = catalog
        self._ambiguity_resolver = ambiguity_resolver
        self._auto_accept_score = auto_accept_score
        self._auto_accept_margin = auto_accept_margin

    def upsert_entries(self, entries) -> list:
        return self._catalog.upsert_entries(entries)

    def resolve(
        self,
        spec: DishSpec,
        recipe: RecipeCandidate,
        mentions: list[IngredientMention],
        ignored_mentions: dict[str, str] | None = None,
        allow_placeholder_resolution: bool = False,
    ) -> tuple[list[ResolvedIngredient], list[ResolutionRecord]]:
        resolved: list[ResolvedIngredient] = []
        records: list[ResolutionRecord] = []

        for mention in mentions:
            record = self._resolve_one(
                spec,
                recipe,
                mention,
                ignored_mentions=ignored_mentions or {},
                allow_placeholder_resolution=allow_placeholder_resolution,
            )
            records.append(record)
            resolved.append(self._materialize_resolved_ingredient(mention, record))

        return resolved, records

    def _resolve_one(
        self,
        spec: DishSpec,
        recipe: RecipeCandidate,
        mention: IngredientMention,
        ignored_mentions: dict[str, str],
        allow_placeholder_resolution: bool,
    ) -> ResolutionRecord:
        normalized_name = normalize_text(mention.raw_name)
        ignored_reason = ignored_mentions.get(normalized_name)
        if ignored_reason is not None:
            return ResolutionRecord(
                mention_id=mention.mention_id,
                status="ignored",
                selected_candidate_id=None,
                selected_catalog_item_id=None,
                confidence=1.0,
                rationale=ignored_reason,
                candidates=[],
            )

        candidates = self._catalog.search(mention)
        if not candidates:
            return ResolutionRecord(
                mention_id=mention.mention_id,
                status="unresolved",
                selected_candidate_id=None,
                selected_catalog_item_id=None,
                confidence=0.0,
                rationale=f"No catalog candidates found for '{mention.raw_name}'.",
                candidates=[],
            )

        if not allow_placeholder_resolution and all(
            candidate.catalog_entry is not None and candidate.catalog_entry.quality_status == "placeholder"
            for candidate in candidates
        ):
            return ResolutionRecord(
                mention_id=mention.mention_id,
                status="unresolved",
                selected_candidate_id=None,
                selected_catalog_item_id=None,
                confidence=candidates[0].score,
                rationale=f"Only placeholder ingredient records exist for '{mention.raw_name}', so enrichment should run again.",
                candidates=candidates,
            )

        if len(candidates) == 1 or self._should_auto_accept(candidates):
            top_candidate = candidates[0]
            return ResolutionRecord(
                mention_id=mention.mention_id,
                status="resolved",
                selected_candidate_id=top_candidate.candidate_id,
                selected_catalog_item_id=top_candidate.catalog_item_id,
                confidence=top_candidate.score,
                rationale=f"Deterministically accepted top candidate for '{mention.raw_name}'.",
                candidates=candidates,
            )

        return self._ambiguity_resolver.resolve(spec, recipe, mention, candidates)

    def _should_auto_accept(self, candidates: list) -> bool:
        top_score = candidates[0].score
        second_score = candidates[1].score if len(candidates) > 1 else 0.0
        return top_score >= self._auto_accept_score and (top_score - second_score) >= self._auto_accept_margin

    @staticmethod
    def _materialize_resolved_ingredient(
        mention: IngredientMention,
        record: ResolutionRecord,
    ) -> ResolvedIngredient:
        selected_candidate = None
        if record.selected_candidate_id is not None:
            selected_candidate = next(
                (candidate for candidate in record.candidates if candidate.candidate_id == record.selected_candidate_id),
                None,
            )

        return ResolvedIngredient(
            mention_id=mention.mention_id,
            raw_name=mention.raw_name,
            quantity=mention.quantity,
            unit=mention.unit,
            category=mention.category,
            is_optional=mention.is_optional,
            notes=mention.notes,
            status=record.status,
            catalog_item_id=record.selected_catalog_item_id,
            display_name=selected_candidate.display_name if selected_candidate else mention.raw_name,
            confidence=record.confidence,
            rationale=record.rationale,
            facets=list(selected_candidate.facets) if selected_candidate else [],
            ingredient_record=None if selected_candidate is None else selected_candidate.catalog_entry,
        )