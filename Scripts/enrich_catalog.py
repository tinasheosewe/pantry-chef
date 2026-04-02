#!/usr/bin/env python3
"""
Enrich all 779 ingredient bases with full PantryCatalogItemDefinition fields.

Strategy:
  - Tiered batch sizes: complex categories (8), medium (15), simple (20)
  - Schema-enforced structured output via GPT-4.1
  - Deterministic validation + retry with error feedback
  - Domain-specific gold examples in every prompt
  - Resume-capable: saves after each batch to enriched_catalog.json
  - Defers substitutions and unitOverrides (empty for now)
"""

import json, os, sys, time, re, math
from pathlib import Path
from openai import OpenAI

# ── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parent
BASES_PATH = SCRIPT_DIR / "triage_output" / "bases_by_aisle.json"
OUTPUT_PATH = SCRIPT_DIR / "triage_output" / "enriched_catalog.json"

# ── Constants ────────────────────────────────────────────────────────────────
VALID_UNITS = [
    "tsp", "tbsp", "cup", "fl oz", "ml", "L",
    "g", "kg", "oz", "lb",
    "piece", "whole", "loaf", "slice", "clove", "bunch", "can", "pkg",
    "pinch", "splash", "to taste",
]

VALID_STORAGES = ["pantry", "refrigerated", "frozen"]

VALID_FACET_KEYS = [
    "variant", "form", "preservation", "processing",
    "preparation", "texture", "concentration", "base",
]

# Batch size tiers by category complexity
COMPLEX_CATEGORIES = {"Protein", "Produce", "Dairy & Eggs", "Condiments & Sauces"}
MEDIUM_CATEGORIES = {
    "Spices & Herbs", "Grains & Cereals", "Breads & Bakery",
    "Nuts & Seeds", "Oils & Fats", "Legumes & Beans", "Pasta & Noodles",
}
SIMPLE_CATEGORIES = {
    "Frozen Foods", "Canned & Jarred", "Beverages", "Snacks",
    "Alcohol & Spirits", "Baking & Sweeteners", "Other",
}

BATCH_SIZES = {
    "complex": 8,
    "medium": 15,
    "simple": 20,
}

# ── API Key ──────────────────────────────────────────────────────────────────
def load_api_key() -> str:
    config = PROJECT_DIR / "Config" / "LocalSecrets.xcconfig"
    for line in config.read_text().splitlines():
        if line.strip().startswith("OPENAI_API_KEY"):
            return line.split("=", 1)[1].strip()
    raise RuntimeError("OPENAI_API_KEY not found in LocalSecrets.xcconfig")

# ── JSON Schema for structured output ────────────────────────────────────────
SHELF_LIFE_SCHEMA = {
    "type": "object",
    "properties": {
        "pantry": {
            "anyOf": [
                {"type": "array", "items": {"type": "integer"}},
                {"type": "null"},
            ]
        },
        "refrigerated": {
            "anyOf": [
                {"type": "array", "items": {"type": "integer"}},
                {"type": "null"},
            ]
        },
        "frozen": {
            "anyOf": [
                {"type": "array", "items": {"type": "integer"}},
                {"type": "null"},
            ]
        },
    },
    "required": ["pantry", "refrigerated", "frozen"],
    "additionalProperties": False,
}

FACET_SCHEMA = {
    "type": "object",
    "properties": {
        "key": {"type": "string", "enum": VALID_FACET_KEYS},
        "options": {"type": "array", "items": {"type": "string"}},
    },
    "required": ["key", "options"],
    "additionalProperties": False,
}

SELECTION_SCHEMA = {
    "type": "object",
    "properties": {
        "key": {"type": "string", "enum": VALID_FACET_KEYS},
        "value": {"type": "string"},
    },
    "required": ["key", "value"],
    "additionalProperties": False,
}

ITEM_SCHEMA = {
    "type": "object",
    "properties": {
        "id": {"type": "string"},
        "name": {"type": "string"},
        "category": {"type": "string"},
        "defaultUnit": {"type": "string", "enum": VALID_UNITS},
        "defaultQuantity": {"type": "number"},
        "defaultStorage": {"type": "string", "enum": VALID_STORAGES},
        "aliases": {"type": "array", "items": {"type": "string"}},
        "facets": {"type": "array", "items": FACET_SCHEMA},
        "defaultSelections": {"type": "array", "items": SELECTION_SCHEMA},
        "freshnessByStorage": SHELF_LIFE_SCHEMA,
    },
    "required": [
        "id", "name", "category", "defaultUnit", "defaultQuantity",
        "defaultStorage", "aliases", "facets", "defaultSelections",
        "freshnessByStorage",
    ],
    "additionalProperties": False,
}

RESPONSE_SCHEMA = {
    "type": "object",
    "properties": {
        "items": {"type": "array", "items": ITEM_SCHEMA},
    },
    "required": ["items"],
    "additionalProperties": False,
}

# ── Gold examples per domain ─────────────────────────────────────────────────
GOLD_COMPLEX_PROTEIN = {
    "id": "chicken",
    "name": "chicken",
    "category": "Protein",
    "defaultUnit": "lb",
    "defaultQuantity": 1.0,
    "defaultStorage": "refrigerated",
    "aliases": ["poultry"],
    "facets": [
        {"key": "variant", "options": ["breast", "thigh", "drumstick", "wing", "whole", "tender", "ground"]},
        {"key": "form", "options": ["whole", "boneless", "bone-in", "diced", "sliced", "shredded"]},
        {"key": "preservation", "options": ["fresh", "frozen"]},
        {"key": "processing", "options": ["raw", "cooked", "marinated", "smoked", "rotisserie"]},
    ],
    "defaultSelections": [{"key": "variant", "value": "breast"}, {"key": "form", "value": "boneless"}],
    "freshnessByStorage": {"pantry": None, "refrigerated": [1, 3], "frozen": [180, 365]},
}

GOLD_COMPLEX_PRODUCE = {
    "id": "onion",
    "name": "onion",
    "category": "Produce",
    "defaultUnit": "whole",
    "defaultQuantity": 1.0,
    "defaultStorage": "pantry",
    "aliases": ["bulb onion"],
    "facets": [
        {"key": "variant", "options": ["yellow", "white", "red", "sweet", "shallot", "pearl", "cipollini", "vidalia"]},
        {"key": "form", "options": ["whole", "diced", "sliced", "rings", "minced", "quartered"]},
        {"key": "preservation", "options": ["fresh", "frozen", "dehydrated", "pickled"]},
    ],
    "defaultSelections": [{"key": "variant", "value": "yellow"}],
    "freshnessByStorage": {"pantry": [30, 60], "refrigerated": [30, 60], "frozen": [180, 365]},
}

GOLD_COMPLEX_DAIRY = {
    "id": "cheese",
    "name": "cheese",
    "category": "Dairy & Eggs",
    "defaultUnit": "oz",
    "defaultQuantity": 8.0,
    "defaultStorage": "refrigerated",
    "aliases": ["fromage"],
    "facets": [
        {"key": "variant", "options": [
            "cheddar", "mozzarella", "parmesan", "gruyère", "brie", "gouda",
            "swiss", "provolone", "colby", "monterey jack", "feta", "blue cheese",
            "havarti", "muenster", "pepper jack", "american", "cotija", "manchego",
            "emmental", "asiago", "fontina", "goat cheese", "cream cheese",
        ]},
        {"key": "form", "options": ["block", "shredded", "sliced", "crumbled", "grated", "cubed", "spread", "wedge"]},
        {"key": "processing", "options": ["fresh", "aged", "smoked", "processed"]},
    ],
    "defaultSelections": [{"key": "variant", "value": "cheddar"}, {"key": "form", "value": "block"}],
    "freshnessByStorage": {"pantry": None, "refrigerated": [14, 42], "frozen": [120, 180]},
}

GOLD_COMPLEX_CONDIMENT = {
    "id": "mustard",
    "name": "mustard",
    "category": "Condiments & Sauces",
    "defaultUnit": "tbsp",
    "defaultQuantity": 1.0,
    "defaultStorage": "refrigerated",
    "aliases": ["prepared mustard"],
    "facets": [
        {"key": "variant", "options": ["yellow", "dijon", "whole grain", "spicy brown", "honey", "english", "chinese hot"]},
        {"key": "texture", "options": ["smooth", "whole grain", "coarse"]},
    ],
    "defaultSelections": [{"key": "variant", "value": "yellow"}],
    "freshnessByStorage": {"pantry": [365, 730], "refrigerated": [365, 730], "frozen": None},
}

GOLD_MEDIUM_SPICE = {
    "id": "cinnamon",
    "name": "cinnamon",
    "category": "Spices & Herbs",
    "defaultUnit": "tsp",
    "defaultQuantity": 1.0,
    "defaultStorage": "pantry",
    "aliases": ["ceylon cinnamon", "cassia"],
    "facets": [
        {"key": "variant", "options": ["ceylon", "cassia", "saigon", "korintje"]},
        {"key": "form", "options": ["ground", "stick", "chips"]},
    ],
    "defaultSelections": [{"key": "form", "value": "ground"}],
    "freshnessByStorage": {"pantry": [730, 1460], "refrigerated": None, "frozen": None},
}

GOLD_MEDIUM_GRAIN = {
    "id": "rice",
    "name": "rice",
    "category": "Grains & Cereals",
    "defaultUnit": "cup",
    "defaultQuantity": 1.0,
    "defaultStorage": "pantry",
    "aliases": [],
    "facets": [
        {"key": "variant", "options": ["white", "brown", "jasmine", "basmati", "arborio", "sushi", "sticky", "long grain", "short grain", "medium grain"]},
        {"key": "processing", "options": ["raw", "parboiled", "instant", "precooked"]},
    ],
    "defaultSelections": [{"key": "variant", "value": "white"}],
    "freshnessByStorage": {"pantry": [365, 730], "refrigerated": None, "frozen": [365, 730]},
}

GOLD_SIMPLE_FROZEN = {
    "id": "frozen-pizza",
    "name": "frozen pizza",
    "category": "Frozen Foods",
    "defaultUnit": "piece",
    "defaultQuantity": 1.0,
    "defaultStorage": "frozen",
    "aliases": ["frozen pie"],
    "facets": [
        {"key": "variant", "options": ["cheese", "pepperoni", "supreme", "margherita", "veggie"]},
    ],
    "defaultSelections": [{"key": "variant", "value": "cheese"}],
    "freshnessByStorage": {"pantry": None, "refrigerated": None, "frozen": [180, 365]},
}

GOLD_SIMPLE_BEVERAGE = {
    "id": "coffee",
    "name": "coffee",
    "category": "Beverages",
    "defaultUnit": "oz",
    "defaultQuantity": 12.0,
    "defaultStorage": "pantry",
    "aliases": ["java", "joe"],
    "facets": [
        {"key": "variant", "options": ["arabica", "robusta", "espresso", "decaf"]},
        {"key": "form", "options": ["whole bean", "ground", "instant", "pods"]},
        {"key": "processing", "options": ["light roast", "medium roast", "dark roast"]},
    ],
    "defaultSelections": [{"key": "form", "value": "ground"}, {"key": "processing", "value": "medium roast"}],
    "freshnessByStorage": {"pantry": [180, 365], "refrigerated": None, "frozen": [365, 730]},
}

# Map categories to their gold examples
GOLD_EXAMPLES = {
    "Protein": [GOLD_COMPLEX_PROTEIN],
    "Produce": [GOLD_COMPLEX_PRODUCE],
    "Dairy & Eggs": [GOLD_COMPLEX_DAIRY],
    "Condiments & Sauces": [GOLD_COMPLEX_CONDIMENT],
    "Spices & Herbs": [GOLD_MEDIUM_SPICE],
    "Grains & Cereals": [GOLD_MEDIUM_GRAIN],
    "Frozen Foods": [GOLD_SIMPLE_FROZEN],
    "Beverages": [GOLD_SIMPLE_BEVERAGE],
}

# ── Domain-specific facet guidance ───────────────────────────────────────────
DOMAIN_GUIDANCE = {
    "Protein": """Facet guidance for Protein:
- variant: specific cuts, types, or species. Meats need cuts (breast, thigh, loin, rib, ground, etc). 
  Fish/seafood need preparation styles. Deli meats need subtypes.
- form: physical form — whole, boneless, bone-in, fillet, diced, sliced, ground, shredded, steak, chop, roast
- preservation: fresh, frozen, canned, smoked, cured, dried, jerked, pickled
- processing: raw, cooked, marinated, seasoned, brined, rotisserie, grilled
Be generous with variant options — meats and seafood have many useful cuts/types.""",

    "Produce": """Facet guidance for Produce:
- variant: color/type varieties that change cooking behavior. Apples: gala, granny smith, honeycrisp, fuji. 
  Peppers: bell, jalapeño, serrano, habanero, poblano, anaheim. Mushrooms: button, cremini, portobello, shiitake, oyster, chanterelle, enoki.
  Lettuce: iceberg, romaine, butter, green leaf, red leaf. Squash: butternut, acorn, spaghetti, delicata, kabocha.
- form: whole, diced, sliced, chopped, minced, julienned, spiralized, halved, wedged
- preservation: fresh, frozen, canned, dried, pickled, dehydrated
- preparation: peeled, trimmed, washed, pre-cut
Items with many well-known varieties (pepper, mushroom, squash, lettuce, apple, berry, melon, herb) need extensive variant lists.""",

    "Dairy & Eggs": """Facet guidance for Dairy & Eggs:
- variant: subtypes — milk (whole, 2%, 1%, skim, raw), yogurt (greek, regular, skyr), cream (heavy, light, whipping)
  Cheese gets MANY variants (see gold example). Butter: salted, unsalted, cultured, european-style.
- form: block, shredded, sliced, liquid, powdered, whipped, stick
- concentration: whole, reduced-fat, low-fat, fat-free, light, heavy
- processing: pasteurized, ultra-pasteurized, raw, cultured, homogenized""",

    "Condiments & Sauces": """Facet guidance for Condiments & Sauces:
- variant: types/flavors — soy sauce (light, dark, tamari, shoyu), vinegar (white, red wine, apple cider, balsamic, rice, sherry),
  hot sauce (cayenne, habanero, chipotle), jam (strawberry, raspberry, apricot, grape), dressing (ranch, italian, caesar, vinaigrette)
- texture: smooth, chunky, coarse, creamy, thin, thick
- concentration: regular, lite, double-concentrated, reduced sodium
For sauces with many flavor varieties, list the most common 6-12.""",

    "Spices & Herbs": """Facet guidance for Spices & Herbs:
- form: ground, whole, flakes, crushed, cracked, fresh, dried, paste, seeds — this is the PRIMARY facet for spices
- variant: origin varieties where relevant — paprika (sweet, hot, smoked), chili powder (ancho, chipotle, cayenne, guajillo),
  salt (kosher, sea, table, flaky), pepper (black, white, green). Most single spices don't need variant.
Keep it simple — most spices only need a form facet.""",

    "Grains & Cereals": """Facet guidance for Grains & Cereals:
- variant: types — oats (rolled, steel-cut, instant, quick), flour (all-purpose, bread, cake, whole wheat, self-rising),
  rice (white, brown, jasmine, basmati, arborio)
- form: whole, cracked, flaked, rolled, puffed, pearled, flour
- processing: raw, toasted, parboiled, instant, precooked""",

    "Breads & Bakery": """Facet guidance for Breads & Bakery:
- variant: types — bread (white, wheat, sourdough, rye, multigrain), cake (chocolate, vanilla, carrot, red velvet),
  pastry (danish, éclair, croissant, palmier)
- form: whole, sliced, cubed, crumbs, croutons, rolls
- preservation: fresh, frozen, day-old""",

    "Nuts & Seeds": """Facet guidance for Nuts & Seeds:
- form: whole, halved, sliced, slivered, chopped, ground, flour, butter
- processing: raw, roasted, toasted, salted, unsalted, honey-roasted, candied, blanched
Most nuts follow the same pattern — keep it consistent.""",

    "Oils & Fats": """Facet guidance for Oils & Fats:
- variant: where there are grades/types — olive oil (extra virgin, virgin, light, pomace),
  coconut oil (refined, unrefined, virgin), sesame oil (toasted, light)
- processing: cold-pressed, refined, unrefined, extra virgin, virgin, expeller-pressed
Most oils are simple — just variant if applicable.""",

    "Legumes & Beans": """Facet guidance for Legumes & Beans:
- preservation: dried, canned, fresh, frozen — this is the PRIMARY facet
- form: whole, split, mashed, flour, paste
- processing: raw, cooked, sprouted""",

    "Pasta & Noodles": """Facet guidance for Pasta & Noodles:
- variant: shapes/types — pasta (spaghetti, penne, fusilli, rigatoni, fettuccine, linguine, angel hair, farfalle, orzo, elbow, shell, rotini, ziti, bucatini, orecchiette, lasagne sheet, macaroni, ditalini, cavatappi, pappardelle)
  Specific noodle items get their own subtypes.
- form: dry, fresh, frozen, stuffed
- preservation: dried, fresh, frozen
Pasta gets MANY variant shapes — be generous like the cheese example.""",

    "Frozen Foods": """Facet guidance for Frozen Foods:
- variant: flavor/type varieties where applicable
- form: usually not needed (already frozen form)
Most frozen items are simple — 1-2 facets max.""",

    "Canned & Jarred": """Facet guidance for Canned & Jarred:
- variant: flavor/type — broth (chicken, beef, vegetable, bone), cream soup (mushroom, chicken, celery, tomato)
- base: for items packed in liquid — in water, in oil, in juice, in syrup
- texture: smooth, chunky, puréed, diced, whole""",

    "Beverages": """Facet guidance for Beverages:
- variant: types/flavors
- form: concentrate, ready-to-drink, powder, pods, loose leaf, bags
Most beverages are simple.""",

    "Snacks": """Facet guidance for Snacks:
- variant: flavors where applicable — chips (plain, barbecue, sour cream, salt & vinegar)
- form: whole, crushed, pieces
Most snacks are simple.""",

    "Alcohol & Spirits": """Facet guidance for Alcohol & Spirits:
- variant: types — wine (red, white, rosé, sparkling), beer (lager, ale, stout, ipa, wheat, pilsner),
  whiskey (bourbon, scotch, rye, irish), rum (light, dark, spiced, gold), gin (london dry, old tom, navy strength)
- processing: aged, unaged, blended, single malt""",

    "Baking & Sweeteners": """Facet guidance for Baking & Sweeteners:
- variant: types — sugar (white, brown, powdered, demerara, turbinado, raw), flour (all-purpose, bread, cake, pastry, whole wheat, self-rising, gluten-free), chocolate (dark, milk, white, unsweetened, bittersweet, semisweet), extract (vanilla, almond, lemon, peppermint, coconut)
- form: granulated, powdered, liquid, syrup, block, chips, flakes, paste""",

    "Other": """Keep it minimal for items that don't fit elsewhere.""",
}

# ── System prompt ────────────────────────────────────────────────────────────
SYSTEM_PROMPT = """\
You are enriching an ingredient catalog for a recipe app called PantryChef.
For each ingredient name, produce a COMPLETE catalog entry with all required fields.

RULES:
1. **id**: lowercase, hyphenated (e.g., "sweet-potato", "frozen-pizza"). Use the ingredient name directly.
2. **name**: the ingredient name as given, lowercase.
3. **category**: use the category provided.
4. **defaultUnit**: the most common unit a home cook would use. Pick from the enum.
5. **defaultQuantity**: a sensible default amount when adding to pantry (e.g., 1 lb of meat, 1 dozen eggs, 1 can of broth).
6. **defaultStorage**: where this item is USUALLY stored at home.
7. **aliases**: alternative names, regional variants, common misspellings, plural forms. 
   Every item should have at least 1 alias. Include plural, common abbreviations, and regional terms.
8. **facets**: the variant dimensions. Use the facet keys (variant, form, preservation, processing, preparation, texture, concentration, base).
   - "variant" = subtypes/varieties (cheddar vs mozzarella, breast vs thigh)
   - "form" = physical form (whole, diced, sliced, ground, shredded)
   - "preservation" = how preserved (fresh, frozen, canned, dried, smoked, pickled)
   - "processing" = processing state (raw, cooked, roasted, toasted, marinated)
   - "preparation" = prep state (peeled, trimmed, washed, deveined)
   - "texture" = texture (smooth, chunky, creamy, crunchy)
   - "concentration" = strength/density (light, heavy, regular, double, reduced)
   - "base" = base medium (in water, in oil, in juice)
   Every item needs AT LEAST 1 facet. Most items need 2-3. Complex items (cheese, pasta, pepper, mushroom) need 3+.
9. **defaultSelections**: sensible defaults — typically 1-2 selections for the most common variant/form.
10. **freshnessByStorage**: days as [min, max] range. Use null for storage types that don't apply.
    - Pantry: shelf-stable items (spices: 730-1460, canned: 365-1095, oils: 365-730)
    - Refrigerated: perishables (meat: 1-5, dairy: 7-30, produce: 3-14)
    - Frozen: can be very long (180-365 typical, up to 730 for some)
    AT LEAST ONE storage type must be non-null.

QUALITY STANDARDS:
- Facet options should be LOWERCASE
- Don't include generic/obvious facets that add no value
- variant facets for items with known subtypes should have 5-20+ options
- form facets typically have 3-8 options
- Be specific and useful — these drive the app's ingredient matching"""

# ── Helpers ──────────────────────────────────────────────────────────────────
def get_batch_size(category: str) -> int:
    if category in COMPLEX_CATEGORIES:
        return BATCH_SIZES["complex"]
    elif category in MEDIUM_CATEGORIES:
        return BATCH_SIZES["medium"]
    else:
        return BATCH_SIZES["simple"]

def get_gold_examples(category: str) -> list[dict]:
    """Get best gold examples for this category."""
    if category in GOLD_EXAMPLES:
        return GOLD_EXAMPLES[category]
    # Fall back to closest domain
    if category in COMPLEX_CATEGORIES:
        return [GOLD_COMPLEX_PROTEIN, GOLD_COMPLEX_CONDIMENT]
    elif category in MEDIUM_CATEGORIES:
        return [GOLD_MEDIUM_SPICE, GOLD_MEDIUM_GRAIN]
    else:
        return [GOLD_SIMPLE_FROZEN, GOLD_SIMPLE_BEVERAGE]

def build_user_prompt(category: str, items: list[str]) -> str:
    golds = get_gold_examples(category)
    guidance = DOMAIN_GUIDANCE.get(category, "Use appropriate facets for this category.")
    
    gold_json = json.dumps(golds, indent=2, ensure_ascii=False)
    items_json = json.dumps(items)
    
    return f"""Category: "{category}"

{guidance}

GOLD EXAMPLES (follow this quality level):
{gold_json}

Now enrich these {len(items)} items: {items_json}

Return a JSON object with an "items" array containing one enriched entry per ingredient.
Match or exceed the gold example quality. Every field is required."""

# ── Validation ───────────────────────────────────────────────────────────────
def validate_item(item: dict, expected_category: str) -> list[str]:
    """Return list of validation errors for an enriched item."""
    errors = []
    
    # Required fields
    for field in ["id", "name", "category", "defaultUnit", "defaultQuantity",
                  "defaultStorage", "aliases", "facets", "defaultSelections",
                  "freshnessByStorage"]:
        if field not in item:
            errors.append(f"Missing field: {field}")
    
    if errors:
        return errors  # Can't check further if fields missing
    
    # Enum checks (schema should enforce these, but belt-and-suspenders)
    if item["defaultUnit"] not in VALID_UNITS:
        errors.append(f"Invalid unit: {item['defaultUnit']}")
    if item["defaultStorage"] not in VALID_STORAGES:
        errors.append(f"Invalid storage: {item['defaultStorage']}")
    
    # Aliases — should have at least 1
    if len(item["aliases"]) == 0:
        errors.append("No aliases provided (need at least 1)")
    
    # Facets — should have at least 1
    if len(item["facets"]) == 0:
        errors.append("No facets provided (need at least 1)")
    
    for facet in item["facets"]:
        if facet["key"] not in VALID_FACET_KEYS:
            errors.append(f"Invalid facet key: {facet['key']}")
        if len(facet["options"]) == 0:
            errors.append(f"Facet '{facet['key']}' has no options")
    
    # defaultSelections — key must match a facet key, value must be in that facet's options
    facet_map = {f["key"]: set(f["options"]) for f in item["facets"]}
    for sel in item["defaultSelections"]:
        if sel["key"] not in facet_map:
            errors.append(f"Default selection key '{sel['key']}' not in facets")
        elif sel["value"] not in facet_map[sel["key"]]:
            errors.append(f"Default selection value '{sel['value']}' not in facet '{sel['key']}' options")
    
    # freshnessByStorage — at least one non-null
    fbs = item["freshnessByStorage"]
    all_null = all(fbs[s] is None for s in VALID_STORAGES)
    if all_null:
        errors.append("All freshnessByStorage values are null (need at least 1)")
    
    for s in VALID_STORAGES:
        val = fbs[s]
        if val is not None:
            if not isinstance(val, list) or len(val) != 2:
                errors.append(f"freshnessByStorage.{s} must be [min, max] array, got {val}")
            elif val[0] > val[1]:
                errors.append(f"freshnessByStorage.{s} min > max: {val}")
            elif val[0] < 0:
                errors.append(f"freshnessByStorage.{s} has negative value: {val}")
    
    return errors

def validate_batch(items: list[dict], category: str, expected_names: list[str]) -> tuple[list[dict], list[str]]:
    """Validate a batch. Returns (valid_items, error_messages)."""
    all_errors = []
    valid = []
    
    # Check we got the right number of items
    if len(items) != len(expected_names):
        all_errors.append(f"Expected {len(expected_names)} items, got {len(items)}")
    
    returned_names = {item.get("name", "").lower() for item in items}
    for name in expected_names:
        if name.lower() not in returned_names:
            all_errors.append(f"Missing item: {name}")
    
    for item in items:
        errors = validate_item(item, category)
        if errors:
            all_errors.append(f"  {item.get('name', '???')}: {'; '.join(errors)}")
        else:
            valid.append(item)
    
    return valid, all_errors

# ── LLM call with retry ─────────────────────────────────────────────────────
def enrich_batch(
    client: OpenAI,
    category: str,
    items: list[str],
    max_retries: int = 2,
) -> list[dict]:
    """Enrich a batch of items with retry on validation failure."""
    
    user_prompt = build_user_prompt(category, items)
    
    for attempt in range(max_retries + 1):
        try:
            resp = client.chat.completions.create(
                model="gpt-4.1",
                messages=[
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": user_prompt},
                ],
                temperature=0.4,
                max_tokens=16000,
                response_format={
                    "type": "json_schema",
                    "json_schema": {
                        "name": "enriched_items",
                        "strict": True,
                        "schema": RESPONSE_SCHEMA,
                    },
                },
            )
            raw = resp.choices[0].message.content
            parsed = json.loads(raw)
            result_items = parsed["items"]
            
            valid, errors = validate_batch(result_items, category, items)
            
            if not errors:
                return result_items
            
            if attempt < max_retries:
                error_feedback = "\n".join(errors)
                user_prompt = f"""Your previous response had validation errors:
{error_feedback}

Please fix these issues and return ALL {len(items)} items again: {json.dumps(items)}

Category: "{category}"
{DOMAIN_GUIDANCE.get(category, '')}

Return the complete corrected JSON."""
                print(f"      ⚠ Retry {attempt+1}: {len(errors)} errors")
            else:
                # Accept what we got on last attempt
                if valid:
                    print(f"      ⚠ Accepting {len(valid)}/{len(items)} after retries")
                return valid if valid else result_items
                
        except Exception as e:
            print(f"      ✗ API error (attempt {attempt+1}): {e}")
            if attempt < max_retries:
                time.sleep(2 ** attempt)
            else:
                return []
    
    return []

# ── Main ─────────────────────────────────────────────────────────────────────
def main():
    print("=" * 60)
    print("PantryChef Catalog Enrichment")
    print("=" * 60)
    
    # Load bases
    with open(BASES_PATH) as f:
        catalog: dict[str, list[str]] = json.load(f)
    
    total_items = sum(len(v) for v in catalog.values())
    print(f"Loaded {total_items} items across {len(catalog)} categories")
    
    # Load existing progress (resume support)
    enriched: dict[str, dict] = {}
    if OUTPUT_PATH.exists():
        with open(OUTPUT_PATH) as f:
            enriched = json.load(f)
        print(f"Resuming: {len(enriched)} items already enriched")
    
    client = OpenAI(api_key=load_api_key())
    
    # Process each category
    batch_count = 0
    skipped = 0
    
    for category in sorted(catalog.keys()):
        items = catalog[category]
        batch_size = get_batch_size(category)
        
        # Filter out already-enriched items
        remaining = [item for item in items if item not in enriched]
        if not remaining:
            skipped += len(items)
            continue
        
        n_batches = math.ceil(len(remaining) / batch_size)
        print(f"\n{'─' * 50}")
        print(f"📦 {category}: {len(remaining)} to enrich ({n_batches} batches of ≤{batch_size})")
        
        for i in range(0, len(remaining), batch_size):
            batch = remaining[i:i + batch_size]
            batch_count += 1
            batch_num = i // batch_size + 1
            
            print(f"  Batch {batch_num}/{n_batches}: {', '.join(batch[:4])}{'...' if len(batch) > 4 else ''}")
            
            results = enrich_batch(client, category, batch)
            
            for item in results:
                enriched[item["name"]] = item
            
            print(f"    ✓ {len(results)}/{len(batch)} enriched")
            
            # Save progress after each batch
            with open(OUTPUT_PATH, 'w') as f:
                json.dump(enriched, f, indent=2, ensure_ascii=False)
            
            # Rate limiting courtesy
            time.sleep(0.5)
    
    # Final summary
    print(f"\n{'=' * 60}")
    print(f"ENRICHMENT COMPLETE")
    print(f"{'=' * 60}")
    print(f"Total enriched: {len(enriched)}/{total_items}")
    print(f"Batches processed: {batch_count}")
    print(f"Skipped (already done): {skipped}")
    
    # Validation summary
    facet_counts = {}
    alias_counts = {}
    for name, item in enriched.items():
        cat = item.get("category", "?")
        facet_counts.setdefault(cat, []).append(len(item.get("facets", [])))
        alias_counts.setdefault(cat, []).append(len(item.get("aliases", [])))
    
    print(f"\nFacet coverage by category:")
    for cat in sorted(facet_counts.keys()):
        counts = facet_counts[cat]
        avg = sum(counts) / len(counts)
        zeros = counts.count(0)
        print(f"  {cat}: avg {avg:.1f} facets, {zeros} items with 0 facets")
    
    print(f"\n✅ Written to {OUTPUT_PATH.relative_to(PROJECT_DIR)}")

if __name__ == "__main__":
    main()
