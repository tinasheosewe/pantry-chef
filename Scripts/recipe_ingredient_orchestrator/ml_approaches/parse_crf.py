"""CRF-based USDA food description parser.

Uses sklearn-crfsuite to do token-level sequence labeling on USDA
food descriptions. Silver labels are generated from USDA structure
(comma-separated fields, known patterns).

Label scheme:
  FOOD  — core food token (part of the display name)
  QUAL  — meaningful qualifier (variant, color, size)
  FORM  — form/preservation token (raw, canned, dried, etc.)
  BRAND — brand name token
  NOISE — USDA jargon / technical detail to discard
  COOK  — cooking method token
"""

from __future__ import annotations

import logging
import re
from typing import Any

import sklearn_crfsuite
from sklearn_crfsuite import metrics as crf_metrics

from .shared import (
    BRAND_PATTERNS,
    COMMERCIAL_NOISE,
    COOKING_METHODS,
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

APPROACH_NAME = "crf"

# ---------------------------------------------------------------------------
# Silver labeling — derive token labels from USDA structure
# ---------------------------------------------------------------------------

# Tokens that are always noise
_ALWAYS_NOISE = frozenset({
    "nfs", "usda", "commodity", "includes", "foods", "for",
    "year", "round", "average", "all", "commercial", "varieties",
    "types", "composite", "cuts", "separable", "lean", "fat",
    "meat", "only", "skin", "bone-in", "boneless", "skinless",
    "flesh", "trimmed", "added", "vitamin", "with",
    "enriched", "fortified", "bleached", "unbleached",
    "regular", "pack", "drained", "solids", "fluid",
    "milkfat", "calcium", "sulfate",
    "process", "processed", "pasteurized", "homogenized",
    "commercially", "prepared", "retail", "parts",
    "ready-to-serve", "ready-to-eat", "ready-to-heat",
    "ready-to-drink", "undiluted", "diluted",
    "distribution", "program",
})

# Tokens that indicate form/preservation
_FORM_TOKENS = frozenset({
    "raw", "cooked", "dried", "dry", "roasted", "smoked",
    "canned", "frozen", "fresh", "pickled", "fermented", "cured",
    "ground", "whole", "sliced", "diced", "chopped", "minced",
    "shredded", "grated", "crushed", "powdered", "granulated",
    "blanched", "peeled", "dehydrated", "freeze-dried",
    "concentrated", "condensed", "evaporated", "concentrate",
    "salted", "unsalted", "sweetened", "unsweetened",
    "brewed", "instant",
    "nonfat", "low-fat", "reduced-fat", "fat-free",
})

# Cooking method tokens
_COOK_TOKENS = frozenset({
    "braised", "grilled", "fried", "baked", "steamed", "boiled",
    "sauteed", "sautéed", "poached", "broiled", "stewed",
    "pan-fried", "deep-fried", "stir-fried", "microwaved", "toasted",
    "scrambled",
})

# Known food base words (high-frequency)
_FOOD_BASES = frozenset({
    "chicken", "beef", "pork", "turkey", "lamb", "veal", "duck",
    "salmon", "tuna", "cod", "shrimp", "crab", "lobster",
    "cheese", "milk", "cream", "yogurt", "butter", "egg",
    "rice", "pasta", "noodle", "bread", "flour", "oat", "wheat",
    "bean", "beans", "lentil", "chickpea", "pea", "soy", "tofu",
    "apple", "banana", "orange", "grape", "berry", "tomato",
    "potato", "onion", "garlic", "pepper", "carrot", "celery",
    "broccoli", "spinach", "kale", "lettuce", "cucumber",
    "mushroom", "corn", "squash", "avocado", "lemon", "lime",
    "oil", "vinegar", "sauce", "mustard", "ketchup", "salsa",
    "honey", "sugar", "salt", "tea", "coffee", "water", "juice",
    "nut", "nuts", "almond", "almonds", "walnut", "pecan",
    "cashew", "peanut", "coconut", "chocolate", "cocoa", "vanilla",
    "tortilla", "hummus", "lard", "cornstarch",
    "frankfurter", "sausage", "ham", "bacon",
    "spread",
})

_QUALIFIER_HINTS = frozenset({
    "sweet", "hot", "mild", "spicy", "red", "green", "yellow",
    "white", "black", "brown", "wild", "atlantic", "pacific",
    "iceberg", "romaine", "italian", "greek", "french",
    "cheddar", "mozzarella", "parmesan", "swiss", "brie",
    "gouda", "feta", "provolone", "colby", "monterey",
    "american", "cottage", "cream", "ricotta", "mascarpone",
    "long-grain", "short-grain", "basmati", "jasmine",
    "all-purpose", "self-rising", "whole-wheat",
    "extra-virgin", "virgin", "light",
    "nonfat", "low-fat", "reduced-fat", "fat-free", "part-skim",
    "teriyaki", "marinara", "spaghetti", "alfredo",
    "snap", "kidney", "pinto", "navy", "black", "lima",
    "bell", "jalapeño", "habanero", "serrano",
    "iceberg", "romaine", "butterhead",
})


def _silver_label_token(token: str, position: int, total_tokens: int,
                        is_first_field: bool, cat_code: str) -> str:
    """Assign a silver label to a single token based on heuristics."""
    low = token.lower().strip(".,;:()")

    # Brand: ALL CAPS multi-char token or known brand
    if len(token) > 2 and token == token.upper() and token.isalpha():
        return "BRAND"

    # Form tokens
    if low in _FORM_TOKENS:
        return "FORM"

    # Cooking methods
    if low in _COOK_TOKENS:
        return "COOK"

    # Noise: known USDA jargon
    if low in _ALWAYS_NOISE:
        return "NOISE"

    # Noise: percentage patterns (3.25%, 85%, etc.)
    if re.match(r"\d+\.?\d*%", token):
        return "NOISE"

    # Noise: conjunctions, articles, prepositions in later fields
    if low in ("or", "and", "the", "a", "an", "not", "further",
               "specified", "cooking", "salad") and not is_first_field:
        return "NOISE"

    # Food bases — core food tokens (especially in first field)
    if low in _FOOD_BASES:
        return "FOOD"

    # Qualifier hints
    if low in _QUALIFIER_HINTS:
        return "QUAL"

    # First field tokens are likely food names
    if is_first_field and position < 3:
        return "FOOD"

    # Default: if late and unrecognized, probably noise
    if position > 4:
        return "NOISE"

    return "QUAL"


def _tokenize_desc(desc: str) -> list[tuple[str, int, bool]]:
    """Split USDA description into tokens with metadata.

    Returns list of (token, position, is_first_field).
    """
    fields = desc.split(",")
    tokens: list[tuple[str, int, bool]] = []
    pos = 0
    for field_idx, field_str in enumerate(fields):
        is_first = field_idx == 0
        for word in field_str.strip().split():
            word = word.strip()
            if word:
                tokens.append((word, pos, is_first))
                pos += 1
    return tokens


def _token_features(tokens: list[tuple[str, int, bool]], i: int,
                    cat_code: str) -> dict[str, Any]:
    """Extract features for a single token for CRF."""
    token, pos, is_first = tokens[i]
    low = token.lower().strip(".,;:()")
    n = len(tokens)

    features: dict[str, Any] = {
        "bias": 1.0,
        "token.lower": low,
        "token.isupper": token.isupper(),
        "token.istitle": token.istitle(),
        "token.isdigit": token.isdigit(),
        "token.has_hyphen": "-" in token,
        "token.has_percent": "%" in token,
        "token.len": len(token),
        "position": pos,
        "position_rel": pos / max(n, 1),
        "is_first_field": is_first,
        "category": cat_code,
        # Token identity features
        "is_food_base": low in _FOOD_BASES,
        "is_form_token": low in _FORM_TOKENS,
        "is_cook_token": low in _COOK_TOKENS,
        "is_noise_token": low in _ALWAYS_NOISE,
        "is_qualifier": low in _QUALIFIER_HINTS,
    }

    # Suffix features
    if len(low) > 3:
        features["suffix3"] = low[-3:]
        features["suffix2"] = low[-2:]

    # Prefix features
    if len(low) > 3:
        features["prefix3"] = low[:3]

    # Context: previous token
    if i > 0:
        prev_tok = tokens[i - 1][0].lower().strip(".,;:()")
        features["prev.lower"] = prev_tok
        features["prev.is_food_base"] = prev_tok in _FOOD_BASES
        features["prev.is_first_field"] = tokens[i - 1][2]
    else:
        features["BOS"] = True

    # Context: next token
    if i < n - 1:
        next_tok = tokens[i + 1][0].lower().strip(".,;:()")
        features["next.lower"] = next_tok
        features["next.is_food_base"] = next_tok in _FOOD_BASES
    else:
        features["EOS"] = True

    return features


def _create_training_data(foods: list[dict[str, Any]]) -> tuple[
    list[list[dict[str, Any]]], list[list[str]]
]:
    """Create silver-labeled training data from USDA foods.

    Returns (X_sequences, y_sequences) for CRF training.
    """
    X: list[list[dict[str, Any]]] = []
    y: list[list[str]] = []

    for food in foods:
        desc = get_usda_description(food)
        cat = get_usda_category(food)
        if not desc:
            continue

        tokens = _tokenize_desc(desc)
        if not tokens:
            continue

        total = len(tokens)
        features_seq = [_token_features(tokens, i, cat) for i in range(total)]
        labels_seq = [
            _silver_label_token(tok, pos, total, is_first, cat)
            for tok, pos, is_first in tokens
        ]

        X.append(features_seq)
        y.append(labels_seq)

    return X, y


# ---------------------------------------------------------------------------
# CRF training and prediction
# ---------------------------------------------------------------------------

def train_crf(foods: list[dict[str, Any]]) -> sklearn_crfsuite.CRF:
    """Train a CRF model on silver-labeled USDA data."""
    logger.info("Creating silver-labeled training data from %d foods...", len(foods))
    X_train, y_train = _create_training_data(foods)
    logger.info("Training CRF on %d sequences...", len(X_train))

    crf = sklearn_crfsuite.CRF(
        algorithm="lbfgs",
        c1=0.1,
        c2=0.1,
        max_iterations=100,
        all_possible_transitions=True,
    )
    crf.fit(X_train, y_train)

    # Log label distribution
    labels = crf.classes_
    logger.info("CRF labels: %s", labels)

    return crf


def predict_parse(crf: sklearn_crfsuite.CRF,
                  foods: list[dict[str, Any]]) -> list[ParsedItem]:
    """Use trained CRF to parse all food descriptions."""
    results: list[ParsedItem] = []

    for food in foods:
        desc = get_usda_description(food)
        cat = get_usda_category(food)
        fdc_id = get_fdc_id(food)
        if not desc:
            continue

        tokens = _tokenize_desc(desc)
        if not tokens:
            continue

        features_seq = [_token_features(tokens, i, cat) for i in range(len(tokens))]
        pred_labels = crf.predict_single(features_seq)

        # Assemble parsed output from labels
        food_tokens: list[str] = []
        qual_tokens: list[str] = []
        form_tokens: list[str] = []
        brand_tokens: list[str] = []
        noise_tokens: list[str] = []
        cook_tokens: list[str] = []

        for (tok, _pos, _is_first), label in zip(tokens, pred_labels):
            clean_tok = tok.strip(".,;:()")
            if not clean_tok:
                continue
            if label == "FOOD":
                food_tokens.append(clean_tok)
            elif label == "QUAL":
                qual_tokens.append(clean_tok)
            elif label == "FORM":
                form_tokens.append(clean_tok)
            elif label == "BRAND":
                brand_tokens.append(clean_tok)
            elif label == "COOK":
                cook_tokens.append(clean_tok)
            else:  # NOISE
                noise_tokens.append(clean_tok)

        # Build parsed name: food tokens first, then meaningful qualifiers
        # Filter out noise-like qualifiers from the name
        _NAME_DROP_QUALS = {"plain", "whole", "nonfat", "low-fat",
                           "reduced-fat", "fat-free", "part-skim"}
        name_quals = [q for q in qual_tokens
                      if q.lower() not in _NAME_DROP_QUALS]

        # Post-process: if food_tokens has a specific type AND a generic
        # category word, drop the generic (e.g., ["Sauce", "Salsa"] → ["Salsa"])
        _CATEGORY_WORDS = {"sauce", "nuts", "nut", "spices", "herbs",
                           "beverages", "fish", "seeds", "cereal",
                           "baking"}
        _SPECIFIC_FOODS = {"salsa", "frankfurter", "sausage", "ham"}
        food_lows = {t.lower() for t in food_tokens}
        has_specific = bool(food_lows & (_FOOD_BASES - _CATEGORY_WORDS))
        if has_specific and len(food_tokens) > 1:
            food_tokens = [t for t in food_tokens
                           if t.lower() not in _CATEGORY_WORDS]

        name_parts = name_quals + food_tokens
        if not name_parts:
            name_parts = [tokens[0][0].strip(".,;:()")]

        parsed_name = " ".join(name_parts).title()
        # Fix common title-case artifacts
        for old, new in [("'S", "'s"), (" Or ", " or "), (" And ", " and "),
                         (" Of ", " of "), (" With ", " with ")]:
            parsed_name = parsed_name.replace(old, new)

        # Derive base ingredient from food tokens
        parsed_base = ""
        for tok in food_tokens:
            low = tok.lower()
            if low in _FOOD_BASES:
                parsed_base = low
                break
        if not parsed_base and food_tokens:
            parsed_base = food_tokens[0].lower()

        # Combine form + cook as form string
        form_str = " ".join(form_tokens + cook_tokens).lower()

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
    """Train CRF and parse all USDA foods. Returns list of ParsedItem."""
    if foods is None:
        foods = load_usda_foods()

    crf = train_crf(foods)
    results = predict_parse(crf, foods)

    save_parse_results(results, APPROACH_NAME)
    logger.info("CRF parse complete: %d items", len(results))
    return results
