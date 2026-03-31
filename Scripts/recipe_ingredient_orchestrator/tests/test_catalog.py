"""Tests for InMemoryCatalog — add, get, dedup, overlap detection, linking, persistence."""

import asyncio
import json
import tempfile
from pathlib import Path

import pytest

from recipe_ingredient_orchestrator.catalog import InMemoryCatalog
from recipe_ingredient_orchestrator.models import (
    CatalogEntry,
    FacetDefinition,
    SubstitutionSuggestion,
)
from recipe_ingredient_orchestrator.schemas import (
    CookingImpact,
    FoodCategory,
    MeasurementUnit,
    PantryStorage,
    SubstitutionImpact,
)

from recipe_ingredient_orchestrator.tests.factories import make_catalog_entry


@pytest.fixture
def salt() -> CatalogEntry:
    return make_catalog_entry()


@pytest.fixture
def sugar() -> CatalogEntry:
    return make_catalog_entry(
        id="sugar",
        name="Sugar",
        category=FoodCategory.BAKING_SUPPLIES,
        aliases=["granulated sugar", "white sugar"],
        substitution_suggestions=[
            SubstitutionSuggestion(
                substitute_name="Salt",
                ratio="not applicable — opposite flavours",
                taste_impact=SubstitutionImpact.SIGNIFICANT,
                texture_impact=SubstitutionImpact.NONE,
                cooking_impact=CookingImpact.NONE,
            ),
        ],
    )


@pytest.fixture
def soy_sauce() -> CatalogEntry:
    return make_catalog_entry(
        id="soy-sauce",
        name="Soy Sauce",
        category=FoodCategory.CONDIMENTS_SAUCES,
        aliases=["soya sauce", "shoyu"],
        substitution_suggestions=[],
    )


class TestAddAndGet:
    @pytest.mark.asyncio
    async def test_add_returns_true_for_new_entry(self, catalog, salt):
        assert await catalog.add(salt) is True
        assert catalog.size == 1

    @pytest.mark.asyncio
    async def test_add_returns_false_for_duplicate(self, catalog, salt):
        await catalog.add(salt)
        assert await catalog.add(salt) is False
        assert catalog.size == 1

    @pytest.mark.asyncio
    async def test_get_returns_entry(self, catalog, salt):
        await catalog.add(salt)
        assert catalog.get("salt") == salt

    @pytest.mark.asyncio
    async def test_get_returns_none_for_missing(self, catalog):
        assert catalog.get("nonexistent") is None

    @pytest.mark.asyncio
    async def test_has(self, catalog, salt):
        assert catalog.has("salt") is False
        await catalog.add(salt)
        assert catalog.has("salt") is True


class TestAddMany:
    @pytest.mark.asyncio
    async def test_add_many_counts_new_only(self, catalog, salt, sugar):
        await catalog.add(salt)
        count = await catalog.add_many([salt, sugar])
        assert count == 1  # salt was duplicate
        assert catalog.size == 2

    @pytest.mark.asyncio
    async def test_add_many_empty_list(self, catalog):
        count = await catalog.add_many([])
        assert count == 0


class TestQueries:
    @pytest.mark.asyncio
    async def test_names(self, catalog, salt, sugar):
        await catalog.add_many([salt, sugar])
        names = catalog.names()
        assert "Salt" in names
        assert "Sugar" in names

    @pytest.mark.asyncio
    async def test_summary_empty(self, catalog):
        assert catalog.summary_for_prompt() == "(empty catalog)"

    @pytest.mark.asyncio
    async def test_summary_contains_entries(self, catalog, salt):
        await catalog.add(salt)
        summary = catalog.summary_for_prompt()
        assert "salt" in summary
        assert "Salt" in summary

    @pytest.mark.asyncio
    async def test_entries_for_resolution_includes_facets(self, catalog, salt):
        await catalog.add(salt)
        entries = catalog.entries_for_resolution()
        assert len(entries) == 1
        entry = entries[0]
        assert entry["id"] == "salt"
        assert "facets" in entry
        assert entry["facets"][0]["key"] == "variant"


class TestSubstitutionLinking:
    @pytest.mark.asyncio
    async def test_link_found_substitute(self, catalog, salt, soy_sauce):
        """Salt suggests Soy Sauce as a sub. Both in catalog → should link."""
        await catalog.add_many([salt, soy_sauce])
        stats = await catalog.link_substitutions()
        assert stats["linked"] >= 1

        updated_salt = catalog.get("salt")
        assert len(updated_salt.substitutions) == 1
        assert updated_salt.substitutions[0].substitute_id == "soy-sauce"

    @pytest.mark.asyncio
    async def test_link_drops_missing_substitute(self, catalog, salt):
        """Salt suggests Soy Sauce, but it's not in catalog → dropped."""
        await catalog.add(salt)
        stats = await catalog.link_substitutions()
        assert stats["dropped"] == 1
        assert stats["linked"] == 0

        updated = catalog.get("salt")
        assert len(updated.substitutions) == 0

    @pytest.mark.asyncio
    async def test_link_via_alias(self, catalog, soy_sauce):
        """If a suggestion name matches an alias, it should still link."""
        entry = make_catalog_entry(
            id="pepper",
            name="Pepper",
            substitution_suggestions=[
                SubstitutionSuggestion(
                    substitute_name="shoyu",  # alias of soy_sauce
                    ratio="1:1",
                    taste_impact=SubstitutionImpact.SLIGHT,
                    texture_impact=SubstitutionImpact.NONE,
                    cooking_impact=CookingImpact.NONE,
                )
            ],
        )
        await catalog.add_many([entry, soy_sauce])
        stats = await catalog.link_substitutions()
        assert stats["linked"] == 1

        updated = catalog.get("pepper")
        assert updated.substitutions[0].substitute_id == "soy-sauce"

    @pytest.mark.asyncio
    async def test_self_substitution_dropped(self, catalog):
        """An entry suggesting itself as a substitute should be dropped."""
        entry = make_catalog_entry(
            id="butter",
            name="Butter",
            substitution_suggestions=[
                SubstitutionSuggestion(
                    substitute_name="Butter",
                    ratio="1:1",
                    taste_impact=SubstitutionImpact.NONE,
                    texture_impact=SubstitutionImpact.NONE,
                    cooking_impact=CookingImpact.NONE,
                )
            ],
        )
        await catalog.add(entry)
        stats = await catalog.link_substitutions()
        assert stats["dropped"] == 1
        assert stats["linked"] == 0


class TestPersistence:
    @pytest.mark.asyncio
    async def test_load_from_file(self, salt, sugar):
        data = [salt.model_dump(mode="json"), sugar.model_dump(mode="json")]
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            json.dump(data, f)
            path = Path(f.name)

        catalog = InMemoryCatalog.load_from_file(path)
        assert catalog.size == 2
        assert catalog.get("salt") is not None
        assert catalog.get("sugar") is not None
        path.unlink()

    def test_load_from_file_rejects_non_array(self, tmp_path):
        path = tmp_path / "bad.json"
        path.write_text('{"not": "an array"}')
        with pytest.raises(ValueError, match="Expected JSON array"):
            InMemoryCatalog.load_from_file(path)


# -- Overlap Detection Tests -----------------------------------------------


class TestOverlapDetection:
    """Verify the 3-layer facet-variant overlap defense."""

    @pytest.mark.asyncio
    async def test_variant_overlap_rejected(self, catalog):
        """'Low Sodium Soy Sauce' should be rejected when 'Soy Sauce' exists
        with variant containing 'low sodium' (multi-word base = true overlap)."""
        soy_sauce = make_catalog_entry(
            id="soy-sauce",
            name="Soy Sauce",
            category=FoodCategory.CONDIMENTS_SAUCES,
            facets=[FacetDefinition(key="variant", options=["regular", "low sodium"])],
        )
        low_sodium_soy = make_catalog_entry(
            id="low-sodium-soy-sauce",
            name="Low Sodium Soy Sauce",
            category=FoodCategory.CONDIMENTS_SAUCES,
        )
        await catalog.add(soy_sauce)
        assert await catalog.add(low_sodium_soy) is False
        assert catalog.size == 1

    @pytest.mark.asyncio
    async def test_variant_overlap_rejected_in_add_many(self, catalog):
        """add_many should also reject overlapping entries."""
        olive_oil = make_catalog_entry(
            id="olive-oil",
            name="Olive Oil",
            category=FoodCategory.OILS_FATS,
            facets=[FacetDefinition(key="variant", options=["extra virgin", "virgin", "light"])],
        )
        ev_olive_oil = make_catalog_entry(
            id="extra-virgin-olive-oil",
            name="Extra Virgin Olive Oil",
            category=FoodCategory.OILS_FATS,
        )
        await catalog.add(olive_oil)
        count = await catalog.add_many([ev_olive_oil])
        assert count == 0
        assert catalog.size == 1

    @pytest.mark.asyncio
    async def test_reverse_overlap_rejected(self, catalog):
        """If 'Olive Oil' exists and 'Light Olive Oil' is added, reject it
        because 'Olive Oil' (2-word base) already covers it via variant facets."""
        olive_oil = make_catalog_entry(
            id="olive-oil",
            name="Olive Oil",
            category=FoodCategory.OILS_FATS,
            facets=[FacetDefinition(key="variant", options=["extra virgin", "light"])],
        )
        light_olive_oil = make_catalog_entry(
            id="light-olive-oil",
            name="Light Olive Oil",
            category=FoodCategory.OILS_FATS,
        )
        await catalog.add(olive_oil)
        assert await catalog.add(light_olive_oil) is False

    @pytest.mark.asyncio
    async def test_qualified_single_word_base_allowed(self, catalog):
        """A qualified variant of a single-word base is distinct.
        'Smoked Paprika' should be allowed alongside 'Paprika'."""
        paprika = make_catalog_entry(
            id="paprika",
            name="Paprika",
            category=FoodCategory.SPICES_HERBS,
        )
        smoked = make_catalog_entry(
            id="smoked-paprika",
            name="Smoked Paprika",
            category=FoodCategory.SPICES_HERBS,
        )
        await catalog.add(paprika)
        assert await catalog.add(smoked) is True

    @pytest.mark.asyncio
    async def test_substring_overlap_rejected(self, catalog):
        """'Toasted Sesame Oil' should be rejected when 'Sesame Oil' exists
        with variant=toasted (multi-word base = true overlap)."""
        sesame_oil = make_catalog_entry(
            id="sesame-oil",
            name="Sesame Oil",
            category=FoodCategory.OILS_FATS,
            facets=[FacetDefinition(key="variant", options=["regular", "toasted"])],
        )
        toasted_sesame = make_catalog_entry(
            id="toasted-sesame-oil",
            name="Toasted Sesame Oil",
            category=FoodCategory.OILS_FATS,
        )
        await catalog.add(sesame_oil)
        assert await catalog.add(toasted_sesame) is False

    @pytest.mark.asyncio
    async def test_qualified_single_word_base_cross_category_allowed(self, catalog):
        """'Garlic Powder' (Spices) alongside 'Garlic' (Produce) should be allowed.
        A qualifier extending a single-word base is a distinct product."""
        garlic = make_catalog_entry(
            id="garlic",
            name="Garlic",
            category=FoodCategory.PRODUCE,
            facets=[FacetDefinition(key="form", options=["whole", "minced", "powdered"])],
        )
        garlic_powder = make_catalog_entry(
            id="garlic-powder",
            name="Garlic Powder",
            category=FoodCategory.SPICES_HERBS,
        )
        await catalog.add(garlic)
        assert await catalog.add(garlic_powder) is True

    @pytest.mark.asyncio
    async def test_alias_overlap_rejected(self, catalog):
        """An entry whose name matches an existing alias should be rejected."""
        soy_sauce = make_catalog_entry(
            id="soy-sauce",
            name="Soy Sauce",
            aliases=["shoyu", "soya sauce"],
        )
        shoyu = make_catalog_entry(
            id="shoyu",
            name="Shoyu",
        )
        await catalog.add(soy_sauce)
        assert await catalog.add(shoyu) is False

    @pytest.mark.asyncio
    async def test_non_overlapping_entries_accepted(self, catalog):
        """Genuinely distinct entries should both be accepted."""
        cheese = make_catalog_entry(
            id="cheese",
            name="Cheese",
            category=FoodCategory.DAIRY,
            facets=[FacetDefinition(key="variant", options=["cheddar", "feta"])],
        )
        butter = make_catalog_entry(
            id="butter",
            name="Butter",
            category=FoodCategory.DAIRY,
        )
        await catalog.add(cheese)
        assert await catalog.add(butter) is True
        assert catalog.size == 2

    @pytest.mark.asyncio
    async def test_distinct_compound_names_accepted(self, catalog):
        """'Avocado' should NOT be rejected when 'Avocado Oil' exists — different products."""
        avocado_oil = make_catalog_entry(
            id="avocado-oil",
            name="Avocado Oil",
            category=FoodCategory.OILS_FATS,
        )
        avocado = make_catalog_entry(
            id="avocado",
            name="Avocado",
            category=FoodCategory.PRODUCE,
        )
        await catalog.add(avocado_oil)
        assert await catalog.add(avocado) is True
        assert catalog.size == 2

    @pytest.mark.asyncio
    async def test_distinct_compound_names_accepted_reverse(self, catalog):
        """'Apple' should NOT be rejected when 'Apple Cider Vinegar' exists."""
        acv = make_catalog_entry(
            id="apple-cider-vinegar",
            name="Apple Cider Vinegar",
            category=FoodCategory.CONDIMENTS_SAUCES,
        )
        apple = make_catalog_entry(
            id="apple",
            name="Apple",
            category=FoodCategory.PRODUCE,
        )
        await catalog.add(acv)
        assert await catalog.add(apple) is True
        assert catalog.size == 2

    @pytest.mark.asyncio
    async def test_batch_internal_overlap_rejected(self, catalog):
        """When adding a batch, later entries that overlap multi-word bases are rejected."""
        olive_oil = make_catalog_entry(
            id="olive-oil",
            name="Olive Oil",
            category=FoodCategory.OILS_FATS,
            facets=[FacetDefinition(key="variant", options=["extra virgin", "virgin", "light"])],
        )
        light_olive = make_catalog_entry(
            id="light-olive-oil",
            name="Light Olive Oil",
            category=FoodCategory.OILS_FATS,
        )
        coconut_oil = make_catalog_entry(
            id="coconut-oil",
            name="Coconut Oil",
            category=FoodCategory.OILS_FATS,
        )
        count = await catalog.add_many([olive_oil, light_olive, coconut_oil])
        assert count == 2  # olive oil + coconut oil accepted, light olive oil rejected
        assert catalog.size == 2

    @pytest.mark.asyncio
    async def test_load_from_file_rebuilds_index(self, salt, sugar):
        """Loading from file should rebuild the overlap index."""
        soy = make_catalog_entry(
            id="soy-sauce",
            name="Soy Sauce",
            aliases=["shoyu", "soya sauce"],
        )
        data = [soy.model_dump(mode="json"), sugar.model_dump(mode="json")]
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            json.dump(data, f)
            path = Path(f.name)

        catalog = InMemoryCatalog.load_from_file(path)
        # Soy Sauce has alias 'shoyu', so an entry named 'Shoyu' should overlap
        alias_entry = make_catalog_entry(id="shoyu", name="Shoyu")
        assert await catalog.add(alias_entry) is False
        path.unlink()


class TestSummaryWithFacets:
    @pytest.mark.asyncio
    async def test_empty_catalog(self, catalog):
        assert catalog.summary_with_facets() == "(empty catalog)"

    @pytest.mark.asyncio
    async def test_includes_facet_details(self, catalog):
        cheese = make_catalog_entry(
            id="cheese",
            name="Cheese",
            category=FoodCategory.DAIRY,
            aliases=["fromage", "queso"],
            facets=[
                FacetDefinition(key="variant", options=["cheddar", "feta"]),
                FacetDefinition(key="form", options=["block", "shredded"]),
            ],
        )
        await catalog.add(cheese)
        summary = catalog.summary_with_facets()
        assert "Cheese" in summary
        assert "variant=[cheddar, feta]" in summary
        assert "form=[block, shredded]" in summary
        assert "aliases: fromage, queso" in summary

    @pytest.mark.asyncio
    async def test_respects_max_entries(self, catalog):
        for i in range(10):
            await catalog.add(make_catalog_entry(id=f"item-{i}", name=f"Item {i}"))
        summary = catalog.summary_with_facets(max_entries=5)
        assert "... and 5 more entries" in summary


class TestMergeSemantics:
    """Tests for the new merge/upsert functionality."""

    @pytest.mark.asyncio
    async def test_merge_nonexistent_returns_false(self, catalog, salt):
        """Merging an entry that doesn't exist should return False."""
        assert await catalog.merge(salt) is False
        assert catalog.size == 0

    @pytest.mark.asyncio
    async def test_merge_combines_aliases(self, catalog):
        """Merging should union aliases, keeping existing first."""
        entry1 = make_catalog_entry(
            id="cheese",
            name="Cheese",
            aliases=["fromage", "queso"],
        )
        entry2 = make_catalog_entry(
            id="cheese",
            name="Cheese",
            aliases=["queso", "käse", "formaggio"],  # queso is duplicate
        )
        await catalog.add(entry1)
        await catalog.merge(entry2)

        result = catalog.get("cheese")
        assert "fromage" in result.aliases
        assert "queso" in result.aliases
        assert "käse" in result.aliases
        assert "formaggio" in result.aliases
        # Deduped: queso should appear only once
        assert result.aliases.count("queso") == 1

    @pytest.mark.asyncio
    async def test_merge_combines_facets(self, catalog):
        """Merging should union facet options for the same key."""
        entry1 = make_catalog_entry(
            id="cheese",
            name="Cheese",
            facets=[FacetDefinition(key="variant", options=["cheddar", "feta"])],
        )
        entry2 = make_catalog_entry(
            id="cheese",
            name="Cheese",
            facets=[
                FacetDefinition(key="variant", options=["feta", "mozzarella"]),  # feta is duplicate
                FacetDefinition(key="age", options=["fresh", "aged"]),  # new key
            ],
        )
        await catalog.add(entry1)
        await catalog.merge(entry2)

        result = catalog.get("cheese")
        facets_by_key = {f.key: f.options for f in result.facets}
        assert "variant" in facets_by_key
        assert "age" in facets_by_key
        assert set(facets_by_key["variant"]) == {"cheddar", "feta", "mozzarella"}
        assert set(facets_by_key["age"]) == {"fresh", "aged"}

    @pytest.mark.asyncio
    async def test_add_or_merge_adds_new(self, catalog, salt):
        """add_or_merge should add if entry doesn't exist."""
        success, action = await catalog.add_or_merge(salt)
        assert success is True
        assert action == "added"
        assert catalog.size == 1

    @pytest.mark.asyncio
    async def test_add_or_merge_merges_existing(self, catalog):
        """add_or_merge should merge if entry exists."""
        entry1 = make_catalog_entry(id="salt", name="Salt", aliases=["table salt"])
        entry2 = make_catalog_entry(id="salt", name="Salt", aliases=["sea salt"])

        await catalog.add(entry1)
        success, action = await catalog.add_or_merge(entry2)
        assert success is True
        assert action == "merged"
        assert catalog.size == 1

        result = catalog.get("salt")
        assert "table salt" in result.aliases
        assert "sea salt" in result.aliases

    @pytest.mark.asyncio
    async def test_add_or_merge_rejects_overlap(self, catalog):
        """add_or_merge should reject if new entry overlaps with a different entry."""
        soy_sauce = make_catalog_entry(
            id="soy-sauce",
            name="Soy Sauce",
            aliases=["shoyu"],
        )
        shoyu = make_catalog_entry(id="shoyu", name="Shoyu")

        await catalog.add(soy_sauce)
        success, action = await catalog.add_or_merge(shoyu)
        assert success is False
        assert action == "rejected"
        assert catalog.size == 1

    @pytest.mark.asyncio
    async def test_add_or_merge_many(self, catalog):
        """add_or_merge_many should handle mixed adds, merges, and rejections."""
        salt1 = make_catalog_entry(id="salt", name="Salt", aliases=["table salt"])
        salt2 = make_catalog_entry(id="salt", name="Salt", aliases=["sea salt"])
        sugar = make_catalog_entry(id="sugar", name="Sugar")
        soy_sauce = make_catalog_entry(id="soy-sauce", name="Soy Sauce", aliases=["shoyu"])
        shoyu = make_catalog_entry(id="shoyu", name="Shoyu")

        await catalog.add(salt1)
        await catalog.add(soy_sauce)

        stats = await catalog.add_or_merge_many([salt2, sugar, shoyu])
        assert stats["added"] == 1  # sugar
        assert stats["merged"] == 1  # salt2 → salt1
        assert stats["rejected"] == 1  # shoyu overlaps soy_sauce
        assert catalog.size == 3  # salt, soy-sauce, sugar
