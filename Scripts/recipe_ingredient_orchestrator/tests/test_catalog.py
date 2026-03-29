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
    FacetKey,
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
                SubstitutionSuggestion(substitute_name="Butter", ratio="1:1")
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
        """'Feta Cheese' should be rejected when 'Cheese' exists with variant=feta."""
        cheese = make_catalog_entry(
            id="cheese",
            name="Cheese",
            category=FoodCategory.DAIRY,
            facets=[FacetDefinition(key=FacetKey.VARIANT, options=["cheddar", "mozzarella", "feta", "parmesan"])],
        )
        feta = make_catalog_entry(
            id="feta-cheese",
            name="Feta Cheese",
            category=FoodCategory.DAIRY,
        )
        await catalog.add(cheese)
        assert await catalog.add(feta) is False
        assert catalog.size == 1

    @pytest.mark.asyncio
    async def test_variant_overlap_rejected_in_add_many(self, catalog):
        """add_many should also reject overlapping entries."""
        cheese = make_catalog_entry(
            id="cheese",
            name="Cheese",
            category=FoodCategory.DAIRY,
            facets=[FacetDefinition(key=FacetKey.VARIANT, options=["cheddar", "feta"])],
        )
        parmesan = make_catalog_entry(
            id="parmesan-cheese",
            name="Parmesan Cheese",
            category=FoodCategory.DAIRY,
        )
        await catalog.add(cheese)
        count = await catalog.add_many([parmesan])
        assert count == 0
        assert catalog.size == 1

    @pytest.mark.asyncio
    async def test_reverse_overlap_rejected(self, catalog):
        """If 'Sweet Potatoes' exists and 'Potatoes' is added, reject 'Potatoes'
        (candidate name is contained in existing entry name)."""
        sweet_potatoes = make_catalog_entry(
            id="sweet-potatoes",
            name="Sweet Potatoes",
            category=FoodCategory.PRODUCE,
        )
        potatoes = make_catalog_entry(
            id="potatoes",
            name="Potatoes",
            category=FoodCategory.PRODUCE,
        )
        await catalog.add(sweet_potatoes)
        assert await catalog.add(potatoes) is False

    @pytest.mark.asyncio
    async def test_substring_overlap_rejected(self, catalog):
        """'Garlic Powder' should be rejected when 'Garlic' exists."""
        garlic = make_catalog_entry(
            id="garlic",
            name="Garlic",
            category=FoodCategory.PRODUCE,
            facets=[FacetDefinition(key=FacetKey.FORM, options=["whole", "minced", "powdered"])],
        )
        garlic_powder = make_catalog_entry(
            id="garlic-powder",
            name="Garlic Powder",
            category=FoodCategory.SPICES_HERBS,
        )
        await catalog.add(garlic)
        assert await catalog.add(garlic_powder) is False

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
            facets=[FacetDefinition(key=FacetKey.VARIANT, options=["cheddar", "feta"])],
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
        """When adding a batch, later entries that overlap earlier ones are rejected."""
        vinegar = make_catalog_entry(
            id="vinegar",
            name="Vinegar",
            facets=[FacetDefinition(key=FacetKey.VARIANT, options=["balsamic", "red wine", "rice"])],
        )
        balsamic = make_catalog_entry(
            id="balsamic-vinegar",
            name="Balsamic Vinegar",
        )
        rice_vinegar = make_catalog_entry(
            id="rice-vinegar",
            name="Rice Vinegar",
        )
        count = await catalog.add_many([vinegar, balsamic, rice_vinegar])
        assert count == 1  # only vinegar accepted
        assert catalog.size == 1

    @pytest.mark.asyncio
    async def test_load_from_file_rebuilds_index(self, salt, sugar):
        """Loading from file should rebuild the overlap index."""
        data = [salt.model_dump(mode="json"), sugar.model_dump(mode="json")]
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            json.dump(data, f)
            path = Path(f.name)

        catalog = InMemoryCatalog.load_from_file(path)
        # Salt has auto-generated aliases, so an entry with a matching alias should overlap
        alias_entry = make_catalog_entry(id="salt-alias", name="Salt Alias-A")
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
                FacetDefinition(key=FacetKey.VARIANT, options=["cheddar", "feta"]),
                FacetDefinition(key=FacetKey.FORM, options=["block", "shredded"]),
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
