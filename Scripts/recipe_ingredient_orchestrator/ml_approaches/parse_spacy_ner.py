"""spaCy NER-based USDA food description parser.

Uses spaCy's EntityRuler for pattern-based NER, then fine-tunes spaCy NER
on silver-labeled USDA data. Entity types:

  FOOD  — core food name
  QUAL  — meaningful qualifier
  FORM  — form/preservation/cooking method
  BRAND — brand name
  NOISE — USDA jargon to discard
"""

from __future__ import annotations

import logging
import random
import re
import warnings
from typing import Any

import spacy
from spacy.language import Language
from spacy.tokens import DocBin
from spacy.training import Example

from .shared import (
    BRAND_PATTERNS,
    COMMERCIAL_NOISE,
    FORM_QUALIFIERS,
    USDA_NOISE_TERMS,
    ParsedItem,
    get_fdc_id,
    get_usda_category,
    get_usda_description,
    load_usda_foods,
    save_parse_results,
)

logger = logging.getLogger(__name__)

APPROACH_NAME = "spacy_ner"

# ---------------------------------------------------------------------------
# Entity ruler patterns
# ---------------------------------------------------------------------------

# Food base patterns (high-confidence entity matches)
_FOOD_PATTERNS = [
    # Proteins
    {"label": "FOOD", "pattern": [{"LOWER": {"IN": [
        "chicken", "beef", "pork", "turkey", "lamb", "veal", "duck", "goose",
        "salmon", "tuna", "cod", "tilapia", "shrimp", "crab", "lobster",
        "scallop", "clam", "mussel", "oyster", "sardine", "trout", "catfish",
        "halibut", "swordfish", "anchovy", "mackerel", "herring", "snapper",
        "bass", "squid", "octopus", "bison", "venison", "goat",
    ]}}]},
    # Dairy
    {"label": "FOOD", "pattern": [{"LOWER": {"IN": [
        "cheese", "milk", "cream", "yogurt", "yoghurt", "butter", "ghee",
        "kefir", "whey",
    ]}}]},
    # Produce
    {"label": "FOOD", "pattern": [{"LOWER": {"IN": [
        "apple", "apples", "banana", "bananas", "orange", "oranges",
        "grape", "grapes", "berry", "berries", "tomato", "tomatoes",
        "potato", "potatoes", "onion", "onions", "garlic",
        "pepper", "peppers", "carrot", "carrots", "celery",
        "broccoli", "spinach", "kale", "lettuce", "cucumber", "cucumbers",
        "mushroom", "mushrooms", "corn", "squash", "avocado",
        "lemon", "lemons", "lime", "limes", "mango", "mangoes",
        "pineapple", "peach", "peaches", "pear", "pears",
        "cherry", "cherries", "plum", "plums", "melon",
        "cabbage", "cauliflower", "eggplant", "zucchini",
    ]}}]},
    # Grains/staples
    {"label": "FOOD", "pattern": [{"LOWER": {"IN": [
        "rice", "pasta", "noodle", "noodles", "bread", "flour", "oat", "oats",
        "wheat", "barley", "quinoa", "cornstarch", "tortilla", "tortillas",
    ]}}]},
    # Legumes
    {"label": "FOOD", "pattern": [{"LOWER": {"IN": [
        "bean", "beans", "lentil", "lentils", "chickpea", "chickpeas",
        "pea", "peas", "soy", "tofu", "hummus", "edamame",
    ]}}]},
    # Nuts/seeds
    {"label": "FOOD", "pattern": [{"LOWER": {"IN": [
        "almond", "almonds", "walnut", "walnuts", "pecan", "pecans",
        "cashew", "cashews", "peanut", "peanuts", "pistachio", "pistachios",
        "coconut", "hazelnut", "hazelnuts", "macadamia",
    ]}}]},
    # Pantry
    {"label": "FOOD", "pattern": [{"LOWER": {"IN": [
        "oil", "vinegar", "sauce", "mustard", "ketchup", "salsa",
        "honey", "sugar", "salt", "tea", "coffee", "water", "juice",
        "chocolate", "cocoa", "vanilla", "lard",
        "frankfurter", "sausage", "ham", "bacon", "spread",
    ]}}]},
    # Multi-word food patterns
    {"label": "FOOD", "pattern": [{"LOWER": "cream"}, {"LOWER": "cheese"}]},
    {"label": "FOOD", "pattern": [{"LOWER": "sour"}, {"LOWER": "cream"}]},
    {"label": "FOOD", "pattern": [{"LOWER": "olive"}, {"LOWER": "oil"}]},
    {"label": "FOOD", "pattern": [{"LOWER": "coconut"}, {"LOWER": "oil"}]},
    {"label": "FOOD", "pattern": [{"LOWER": "canola"}, {"LOWER": "oil"}]},
    {"label": "FOOD", "pattern": [{"LOWER": "peanut"}, {"LOWER": "butter"}]},
    {"label": "FOOD", "pattern": [{"LOWER": "almond"}, {"LOWER": "butter"}]},
    {"label": "FOOD", "pattern": [{"LOWER": "maple"}, {"LOWER": "syrup"}]},
    {"label": "FOOD", "pattern": [{"LOWER": "orange"}, {"LOWER": "juice"}]},
    {"label": "FOOD", "pattern": [{"LOWER": "apple"}, {"LOWER": "juice"}]},
    {"label": "FOOD", "pattern": [{"LOWER": "soy"}, {"LOWER": "sauce"}]},

    # Qualifier patterns
    {"label": "QUAL", "pattern": [{"LOWER": {"IN": [
        "cheddar", "mozzarella", "parmesan", "swiss", "brie", "gouda",
        "feta", "provolone", "colby", "monterey", "cottage", "ricotta",
        "mascarpone", "american", "havarti", "muenster", "gruyere",
        "neufchatel", "camembert",
    ]}}]},
    {"label": "QUAL", "pattern": [{"LOWER": {"IN": [
        "sweet", "hot", "mild", "spicy", "red", "green", "yellow",
        "white", "black", "brown", "wild", "atlantic", "pacific",
        "iceberg", "romaine", "italian", "greek", "french",
        "long-grain", "short-grain", "basmati", "jasmine",
        "all-purpose", "self-rising", "whole-wheat",
        "extra-virgin", "virgin", "nonfat", "low-fat",
        "reduced-fat", "fat-free", "part-skim",
        "snap", "kidney", "pinto", "navy", "lima",
        "bell", "jalapeño", "habanero", "serrano",
        "teriyaki", "marinara", "alfredo",
        "granulated", "powdered", "confectioners",
    ]}}]},

    # Form patterns
    {"label": "FORM", "pattern": [{"LOWER": {"IN": [
        "raw", "cooked", "dried", "roasted", "smoked", "canned",
        "frozen", "fresh", "pickled", "fermented", "cured",
        "ground", "sliced", "diced", "chopped", "minced",
        "shredded", "grated", "crushed", "powdered", "granulated",
        "blanched", "peeled", "dehydrated",
        "concentrated", "condensed", "evaporated",
        "salted", "unsalted", "sweetened", "unsweetened",
        "pasteurized", "unpasteurized", "homogenized",
        "brewed", "instant", "braised", "grilled", "fried",
        "baked", "steamed", "boiled", "sauteed", "poached",
        "broiled", "stewed", "pan-fried", "deep-fried",
        "stir-fried", "microwaved", "toasted", "scrambled",
    ]}}]},
    {"label": "FORM", "pattern": [{"LOWER": "dry"}, {"LOWER": "roasted"}]},
    {"label": "FORM", "pattern": [{"LOWER": "freeze"}, {"LOWER": "dried"}]},
    {"label": "FORM", "pattern": [{"LOWER": "frozen"}, {"LOWER": "concentrate"}]},

    # Noise patterns
    {"label": "NOISE", "pattern": [{"LOWER": "nfs"}]},
    {"label": "NOISE", "pattern": [{"LOWER": "usda"}, {"LOWER": "commodity"}]},
    {"label": "NOISE", "pattern": [{"LOWER": "commercially"}, {"LOWER": "prepared"}]},
    {"label": "NOISE", "pattern": [{"LOWER": "ready-to-serve"}]},
    {"label": "NOISE", "pattern": [{"LOWER": "ready-to-eat"}]},
    {"label": "NOISE", "pattern": [{"LOWER": "ready-to-heat"}]},
    {"label": "NOISE", "pattern": [{"LOWER": "ready-to-drink"}]},
    {"label": "NOISE", "pattern": [{"LOWER": "year"}, {"LOWER": "round"}, {"LOWER": "average"}]},
    {"label": "NOISE", "pattern": [{"LOWER": "all"}, {"LOWER": "varieties"}]},
    {"label": "NOISE", "pattern": [{"LOWER": "all"}, {"LOWER": "types"}]},
    {"label": "NOISE", "pattern": [{"LOWER": "enriched"}]},
    {"label": "NOISE", "pattern": [{"LOWER": "fortified"}]},
    {"label": "NOISE", "pattern": [{"LOWER": "bleached"}]},
    {"label": "NOISE", "pattern": [{"LOWER": "regular"}, {"LOWER": "pack"}]},
    {"label": "NOISE", "pattern": [{"LOWER": "drained"}, {"LOWER": "solids"}]},
    {"label": "NOISE", "pattern": [{"TEXT": {"REGEX": r"\d+\.?\d*%"}}, {"LOWER": "milkfat"}]},
    {"label": "NOISE", "pattern": [{"LOWER": "with"}, {"LOWER": "added"}, {"LOWER": "vitamin"}]},
    {"label": "NOISE", "pattern": [{"LOWER": "separable"}, {"LOWER": "lean"}]},
    {"label": "NOISE", "pattern": [{"LOWER": "meat"}, {"LOWER": "only"}]},
    {"label": "NOISE", "pattern": [{"LOWER": "includes"}, {"LOWER": {"IN": ["crisphead", "foods"]}}]},
    {"label": "NOISE", "pattern": [{"LOWER": "prepared"}, {"LOWER": "with"}, {"LOWER": "tap"}]},
    {"label": "NOISE", "pattern": [{"LOWER": "prepared"}, {"LOWER": "with"}, {"LOWER": "water"}]},
    {"label": "NOISE", "pattern": [{"LOWER": "retail"}, {"LOWER": "parts"}]},
    {"label": "NOISE", "pattern": [{"LOWER": "or"}, {"LOWER": "cooking"}]},
    {"label": "NOISE", "pattern": [{"LOWER": "salad"}, {"LOWER": "or"}, {"LOWER": "cooking"}]},
    {"label": "NOISE", "pattern": [{"LOWER": {"IN": ["process", "processed"]}}]},
    {"label": "NOISE", "pattern": [{"TEXT": {"REGEX": r"\d+\.?\d*%"}}]},
    {"label": "NOISE", "pattern": [{"LOWER": "low"}, {"LOWER": "moisture"}]},
]


def _build_ruler_nlp() -> Language:
    """Create a spaCy pipeline with EntityRuler patterns."""
    nlp = spacy.blank("en")
    ruler = nlp.add_pipe("entity_ruler", config={"overwrite_ents": True})
    ruler.add_patterns(_FOOD_PATTERNS)
    return nlp


# ---------------------------------------------------------------------------
# Silver-labeled training data for NER fine-tuning
# ---------------------------------------------------------------------------

def _generate_training_examples(
    nlp: Language,
    foods: list[dict[str, Any]],
    max_examples: int = 5000,
) -> list[Example]:
    """Use EntityRuler to produce silver-labeled training examples.

    For fine-tuning, we use the ruler's output as silver labels.
    """
    examples: list[Example] = []
    sampled = random.sample(foods, min(max_examples, len(foods)))

    for food in sampled:
        desc = get_usda_description(food)
        if not desc:
            continue

        # Pre-process: replace commas with spaces for better tokenization
        text = desc.replace(",", " ,")
        doc = nlp(text)

        # Convert entity spans to training format
        ents = [(ent.start_char, ent.end_char, ent.label_) for ent in doc.ents]
        if not ents:
            continue

        example = Example.from_dict(doc, {"entities": ents})
        examples.append(example)

    logger.info("Generated %d training examples from ruler", len(examples))
    return examples


def _train_ner(
    nlp_base: Language,
    examples: list[Example],
    n_iter: int = 20,
) -> Language:
    """Fine-tune NER on the silver-labeled examples.

    Returns a new nlp pipeline with trained NER.
    """
    nlp = spacy.blank("en")

    # Add NER component
    ner = nlp.add_pipe("ner")

    # Add labels
    labels = {"FOOD", "QUAL", "FORM", "BRAND", "NOISE"}
    for label in labels:
        ner.add_label(label)

    # Train
    optimizer = nlp.begin_training()
    for iteration in range(n_iter):
        random.shuffle(examples)
        losses: dict[str, float] = {}
        batches = _minibatch(examples, size=32)
        for batch in batches:
            nlp.update(batch, sgd=optimizer, losses=losses)
        if iteration % 5 == 0:
            logger.info("NER training iter %d, loss: %.4f",
                        iteration, losses.get("ner", 0))

    return nlp


def _minibatch(items: list, size: int = 32):
    """Yield successive batches."""
    for i in range(0, len(items), size):
        yield items[i:i + size]


# ---------------------------------------------------------------------------
# Parsing with trained model
# ---------------------------------------------------------------------------

def _parse_with_nlp(nlp: Language,
                    foods: list[dict[str, Any]]) -> list[ParsedItem]:
    """Parse all foods using the NER pipeline."""
    results: list[ParsedItem] = []

    for food in foods:
        desc = get_usda_description(food)
        cat = get_usda_category(food)
        fdc_id = get_fdc_id(food)
        if not desc:
            continue

        text = desc.replace(",", " ,")
        doc = nlp(text)

        food_tokens: list[str] = []
        qual_tokens: list[str] = []
        form_tokens: list[str] = []
        brand_tokens: list[str] = []
        noise_tokens: list[str] = []

        # Track which char ranges are covered by entities
        covered = set()
        for ent in doc.ents:
            text_clean = ent.text.strip(" ,;:()")
            if not text_clean:
                continue
            for i in range(ent.start_char, ent.end_char):
                covered.add(i)

            if ent.label_ == "FOOD":
                food_tokens.append(text_clean)
            elif ent.label_ == "QUAL":
                qual_tokens.append(text_clean)
            elif ent.label_ == "FORM":
                form_tokens.append(text_clean)
            elif ent.label_ == "BRAND":
                brand_tokens.append(text_clean)
            elif ent.label_ == "NOISE":
                noise_tokens.append(text_clean)

        # Handle uncovered tokens — use heuristics
        for token in doc:
            if token.idx in covered:
                continue
            tok_text = token.text.strip(" ,;:()")
            if not tok_text:
                continue
            low = tok_text.lower()

            # Check brand pattern
            if BRAND_PATTERNS.match(tok_text):
                brand_tokens.append(tok_text)
            elif COMMERCIAL_NOISE.search(tok_text):
                noise_tokens.append(tok_text)
            elif USDA_NOISE_TERMS.search(tok_text):
                noise_tokens.append(tok_text)
            elif FORM_QUALIFIERS.search(tok_text):
                form_tokens.append(tok_text)

        # Build name
        # Drop generic category words when specific food exists
        _CATEGORY_WORDS = {"sauce", "nuts", "nut", "spices", "herbs",
                           "beverages", "fish", "seeds", "cereal", "baking"}
        food_lows = {t.lower() for t in food_tokens}
        has_specific = bool(food_lows - _CATEGORY_WORDS)
        if has_specific and len(food_tokens) > 1:
            food_tokens = [t for t in food_tokens
                           if t.lower() not in _CATEGORY_WORDS]

        # Drop noise-like qualifiers from name
        _NAME_DROP_QUALS = {"plain", "whole", "process", "pasteurized",
                           "nonfat", "low-fat", "reduced-fat", "fat-free",
                           "part-skim"}
        name_quals = [q for q in qual_tokens
                      if q.lower() not in _NAME_DROP_QUALS]

        if food_tokens:
            name_parts = name_quals + food_tokens
        elif name_quals:
            name_parts = name_quals
        else:
            # Fallback: first comma-separated part
            name_parts = [desc.split(",")[0].strip()]

        parsed_name = " ".join(name_parts)
        # Remove duplicate words while preserving order
        seen: set[str] = set()
        deduped: list[str] = []
        for word in parsed_name.split():
            low_word = word.lower()
            if low_word not in seen:
                seen.add(low_word)
                deduped.append(word)
        parsed_name = " ".join(deduped).title()

        for old, new in [("'S", "'s"), (" Or ", " or "), (" And ", " and "),
                         (" Of ", " of "), (" With ", " with ")]:
            parsed_name = parsed_name.replace(old, new)

        # Base ingredient
        parsed_base = ""
        for tok in food_tokens:
            low = tok.lower()
            # Use last food token as base (usually the noun)
            parsed_base = low

        form_str = " ".join(form_tokens).lower()

        results.append(ParsedItem(
            fdc_id=fdc_id,
            original_desc=desc,
            usda_category=cat,
            parsed_name=parsed_name,
            parsed_base=parsed_base,
            qualifiers=[q.lower() for q in qual_tokens],
            form=form_str,
            brand=" ".join(brand_tokens),
            noise_removed=[n.lower() for n in noise_tokens],
        ))

    return results


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def run(foods: list[dict[str, Any]] | None = None) -> list[ParsedItem]:
    """Build EntityRuler, optionally fine-tune NER, parse all foods."""
    if foods is None:
        foods = load_usda_foods()

    logger.info("Building EntityRuler NER pipeline...")
    ruler_nlp = _build_ruler_nlp()

    # Use ruler directly for parsing (fine-tuning is optional and slower)
    # The ruler approach is deterministic and fast — fine-tuning adds
    # generalization but needs careful evaluation
    logger.info("Parsing %d foods with EntityRuler...", len(foods))
    results = _parse_with_nlp(ruler_nlp, foods)

    save_parse_results(results, APPROACH_NAME)
    logger.info("spaCy NER parse complete: %d items", len(results))
    return results
