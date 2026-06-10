"""Controlled facet vocabulary + token classifier for the catalog remodel.

This module encodes the one-time decisions that turn the legacy
"every variation is its own row" catalog into a governed
entity + facet model. It is consumed by build.py.

Facet keys (final taxonomy):
  color       - visual color (red, green, ...)
  variant     - named style / cultivar / flavor / region that does NOT earn a row
  grade       - intensity / quality on the product's strength axis (mild..sharp, hot, light)
  fat         - dairy fat level (skim, 2%, whole, ...)
  form        - physical / market form (whole, ground, powder, liquid, paste, ...)
  preparation - knife + prep state (sliced, diced, peeled, seeded, ...)
  preservation- how it is kept (fresh, frozen, dried, canned, pickled, ...)
  processing  - treatment / cooking (raw, cooked, roasted, smoked, toasted, ...)
  texture     - consistency (smooth, chunky, creamy, thick, thin, ...)
  medium      - packing / cooking liquid (in water, in oil, in brine, in syrup, ...)
"""
from __future__ import annotations

# Final ordered facet keys. `base` and `concentration` are retired by the remap.
FACET_KEYS = [
    "color", "variant", "grade", "fat",
    "form", "preparation", "preservation", "processing", "texture", "medium",
]

# Keys treated as "kind/narrowing" facets by runtime matching.
NARROWING_KEYS = {"variant", "color", "grade", "fat"}

# Categories whose children are predominantly *prepared products*: an un-typed
# distinguishing token becomes a `variant` rather than keeping its own row.
PREPARED_CATEGORIES = {
    "Condiments & Sauces",
    "Beverages",
    "Alcohol & Spirits",
    "Snacks",
}

# Parents (by id) whose children are styles/variants even though the category is a
# whole-food one. e.g. pasta shapes, bread styles, cheese-as-flavor, tea/coffee styles.
VARIANT_PARENT_IDS = {
    "pasta", "noodle", "tea", "coffee", "bread", "cracker", "chip", "wrapper",
    "tortilla", "yogurt", "ice-cream", "jam", "jelly", "honey", "syrup", "vinegar",
    "mustard", "salsa", "hummus", "pickle", "olive", "broth", "stock", "tofu",
}

# ---------------------------------------------------------------------------
# Controlled vocabularies (lowercased)
# ---------------------------------------------------------------------------

COLOR = {"red", "green", "yellow", "orange", "purple", "white", "black", "brown",
         "pink", "blue", "golden", "gold", "ivory"}

# Dairy fat levels
FAT = {"skim", "nonfat", "non-fat", "fat free", "fat-free", "1%", "2%", "low fat",
       "low-fat", "reduced fat", "reduced-fat", "whole", "full fat", "full-fat",
       "half and half", "half-and-half"}

# Intensity / quality / diet grade
GRADE = {
    "mild", "medium", "sharp", "extra sharp", "extra-sharp", "hot", "extra hot",
    "extra-hot", "spicy", "extra spicy", "light", "dark", "strong", "premium",
    "lite", "reduced sodium", "reduced-sodium", "low sodium", "low-sodium",
    "reduced sugar", "reduced-sugar", "no sugar added", "no-sugar-added",
    "low sugar", "unsalted", "salted", "concentrated", "condensed",
    "double", "double fold", "double-fold", "double concentrated",
    "double-concentrated", "double strength", "double-strength", "single fold",
    "high proof", "overproof", "regular", "standard", "extra virgin", "virgin",
    "light roast", "medium roast", "dark roast",
}

# Packing / cooking liquid
MEDIUM = {
    "in water", "in oil", "in olive oil", "in vegetable oil", "in sesame oil",
    "in brine", "in juice", "in syrup", "in vinegar", "in salt", "in tomato puree",
    "in tomato purée", "water-packed", "oil-packed",
}

# Preservation (how it is kept) — wins over processing for these tokens.
PRESERVATION = {
    "fresh", "frozen", "dried", "canned", "jarred", "bottled", "pickled", "cured",
    "fermented", "freeze-dried", "freeze dried", "sun-dried", "sun dried",
    "dehydrated", "preserved", "refrigerated", "salt-packed", "salt packed",
    "vacuum-packed", "vacuum packed", "shelf-stable", "shelf stable", "brined",
    "crystallized", "candied", "day-old", "day old", "semi-dry", "semi dry",
    "pre-packaged", "bagged", "smoked",  # smoked is a preservation here (see note)
}

# Processing (treatment / cooking). NOTE: when a token is in both PRESERVATION and
# PROCESSING, PRESERVATION wins, EXCEPT "smoked" which we route to processing
# because in this catalog it overwhelmingly means the cooking treatment.
PROCESSING = {
    "raw", "cooked", "roasted", "smoked", "toasted", "blanched", "marinated",
    "seasoned", "fried", "baked", "grilled", "braised", "boiled", "poached",
    "steamed", "stewed", "seared", "pan-seared", "battered", "breaded", "blended",
    "instant", "precooked", "pre-cooked", "parboiled", "rotisserie", "jerked",
    "spiced", "soaked", "sprouted", "popped", "rendered", "cultured", "filtered",
    "unfiltered", "pasteurized", "ultra-pasteurized", "homogenized", "distilled",
    "aged", "unaged", "refined", "unrefined", "cold-pressed", "expeller-pressed",
    "hydrogenated", "non-hydrogenated", "sweetened", "unsweetened", "flavored",
    "unflavored", "plain", "homemade", "store-bought", "desalted",
    "honey-roasted", "dry-roasted", "spray-dried",
}
PROCESSING_WINS = {"smoked"}  # tokens that go to processing despite being in PRESERVATION

# Texture / consistency
TEXTURE = {"smooth", "chunky", "creamy", "thick", "thin", "coarse", "fine", "soft",
           "firm", "extra firm", "extra-firm", "medium firm", "silken",
           "crispy", "crisp", "crunchy", "chewy", "tender", "fluffy",
           "powdery", "clear", "cloudy", "flaky"}

# Cut / prep states (these belong under `preparation`, not `form`).
PREPARATION = {
    "sliced", "diced", "chopped", "minced", "shredded", "grated", "cubed",
    "julienned", "crushed", "crumbled", "mashed", "riced", "spiralized", "slivered",
    "quartered", "halved", "halves", "cut", "coins", "rings", "strips", "wedge",
    "wedged", "shaved", "shavings", "snipped", "split", "broken", "cracked",
    "balled", "scooped", "milled", "pulled", "flaked", "pieces", "piece",
    "peeled", "unpeeled", "seeded", "seedless", "pitted", "cored", "trimmed",
    "cleaned", "deveined", "destemmed", "stemmed", "shelled", "unshelled",
    "deshelled", "husked", "hulled", "shucked", "washed", "scrubbed", "zested",
    "zest", "segmented", "juiced", "smashed", "skin-on", "skinless", "skinned",
    "boned", "bone-in", "boneless", "pre-cut", "ready-to-eat", "rubbed", "picked",
    "ripe", "unripe", "raw",  # (raw also processing; preparation rarely used)
}

# Physical / market form (kept under `form`).
FORM = {
    "whole", "ground", "powder", "powdered", "liquid", "paste", "puree", "pureed",
    "flakes", "flake", "granules", "granulated", "crystals", "kernels", "leaves",
    "leaf", "sprigs", "stalks", "stems", "florets", "fillet", "steak", "steaks",
    "chop", "roast", "link", "patty", "loaf", "slice", "slices", "stick", "sticks",
    "block", "cube", "ball", "balls", "log", "rod", "roll", "rolls", "sheet",
    "slab", "round", "spears", "pod", "pods", "clove", "bulb", "extract", "gel",
    "syrup", "concentrate", "meal", "flour", "grits", "groats", "pearled", "bun",
    "muffin", "spread", "spreadable", "nest", "threads", "bits", "chips", "crumbs",
    "crumb", "croutons", "solid", "whipped", "creamed", "cream-style", "evaporated",
    "rendered", "filled", "stuffed", "unfilled", "dry", "drinkable",
    "ready-to-drink", "spreadable", "lump", "claws", "tail-on", "tail-off",
    "half-shell", "on the cob", "berries", "arils", "petals", "rind", "peel",
    "hearts", "heart", "yolk", "white", "bar",
}

# Packaging / serving descriptors to DROP entirely (not culinary identity).
DROP = {
    "aerosol", "bags", "bagged", "basket", "bottle", "bottles", "bulk", "carton",
    "jar", "packet", "pre-measured pouch", "pre-portioned", "sachet",
    "single-serve", "squeeze", "tub", "tube", "bag", "box", "can", "cans", "pkg",
    "package", "loose", "set", "stack", "bundle", "comb", "blade",
    "pre-washed", "pre-sifted", "barista", "malossol", "prepared", "store-bought",
    "homemade",
}

# Lemmatization / canonicalization of facet values.
LEMMATIZE = {
    "powdered": "powder", "chops": "chop", "steaks": "steak", "slices": "slice",
    "sticks": "stick", "balls": "ball", "rolls": "roll", "pods": "pod",
    "halves": "halved", "crumbles": "crumbled", "flake": "flakes",
    "granule": "granules", "leaf": "leaves", "stems": "stem",
    "pureed": "puree", "purée": "puree", "puréed": "puree", "fat-free": "fat free",
    "non-fat": "nonfat", "low-fat": "low fat", "reduced-fat": "reduced fat",
    "extra-sharp": "extra sharp", "extra-hot": "extra hot",
    "freeze dried": "freeze-dried", "sun dried": "sun-dried",
    "pre cooked": "pre-cooked", "precooked": "pre-cooked",
    "half-and-half": "half and half",
}

# Concentration (retired key) -> (new_key, value-or-None). None means use the token.
CONCENTRATION_REMAP = {
    "chocolate": ("variant", "chocolate"), "vanilla": ("variant", "vanilla"),
    "strawberry": ("variant", "strawberry"), "mocha": ("variant", "mocha"),
    "original": ("variant", "original"),
    "mild": ("grade", "mild"), "hot": ("grade", "hot"), "spicy": ("grade", "spicy"),
    "extra hot": ("grade", "extra hot"), "extra spicy": ("grade", "extra spicy"),
    "lite": ("grade", "lite"), "regular": ("grade", "regular"),
    "standard": ("grade", "standard"), "sweet": ("grade", "sweet"),
    "reduced sodium": ("grade", "reduced sodium"),
    "reduced sugar": ("grade", "reduced sugar"),
    "no sugar added": ("grade", "no sugar added"),
    "unsweetened": ("processing", "unsweetened"),
    "fat free": ("fat", "nonfat"), "fat-free": ("fat", "nonfat"),
    "concentrated": ("grade", "concentrated"), "condensed": ("grade", "condensed"),
    "double": ("grade", "double"), "double fold": ("grade", "double fold"),
    "double-concentrated": ("grade", "double concentrated"),
    "double-strength": ("grade", "double strength"),
    "single fold": ("grade", "single fold"), "high proof": ("grade", "high proof"),
}

# Base (retired key) -> new key. Liquid mediums -> medium; the rest -> base-as-variant.
BASE_TO_MEDIUM = {
    "in water", "in oil", "in brine", "in juice", "in syrup", "in vinegar",
    "in salt", "in sesame oil", "in vegetable oil", "in tomato purée",
    "in tomato puree", "olive oil", "grapeseed oil", "sunflower oil",
}
# Protein/plant bases (stock, milk, gelatin) keep meaning under `variant`.
BASE_TO_VARIANT = {
    "beef", "chicken", "pork", "lamb", "turkey", "venison", "fish", "vegetable",
    "mushroom", "soy", "oat", "almond", "coconut", "rum", "brandy", "vodka",
    "neutral spirit", "alcohol", "glycerin", "dry", "milk",
}


# Single canonical key for values that would otherwise straddle two facet keys.
# ("whole" is intentionally omitted: it is `form` for solids but `fat` for milk.)
CANONICAL_KEY: dict[str, str] = {
    "baked": "processing", "boiled": "processing", "cooked": "processing",
    "grilled": "processing", "marinated": "processing", "pasteurized": "processing",
    "poached": "processing", "pre-cooked": "processing", "roasted": "processing",
    "sweetened": "processing", "unsweetened": "processing", "steamed": "processing",
    "braised": "processing", "fried": "processing", "seared": "processing",
    "diced": "preparation", "peeled": "preparation", "pitted": "preparation",
    "pre-cut": "preparation", "ready-to-eat": "preparation", "shelled": "preparation",
    "unshelled": "preparation", "washed": "preparation", "sliced": "preparation",
    "chopped": "preparation", "minced": "preparation", "grated": "preparation",
    "shredded": "preparation", "cubed": "preparation",
    "butter": "variant", "chocolate": "variant", "strawberry": "variant",
    "vanilla": "variant", "traditional": "variant", "shell": "form",
    "dry": "form", "juice": "form", "paste": "form", "puree": "form", "round": "form",
    "medium": "grade", "salted": "grade", "unsalted": "grade", "sweet": "grade",
    "fresh": "preservation", "olive oil": "medium",
}


def lemma(value: str) -> str:
    v = value.strip().lower()
    return LEMMATIZE.get(v, v)


# Fat-level detection from a raw name (the % sign is stripped by normalization, so
# match on the raw string).
_FAT_PATTERNS = [
    ("nonfat", ["fat free", "fat-free", "nonfat", "non-fat", "0%"]),
    ("1%", ["1%", "1 %"]),
    ("2%", ["2%", "2 %"]),
    ("low fat", ["low fat", "low-fat", "lowfat"]),
    ("reduced fat", ["reduced fat", "reduced-fat"]),
    ("half and half", ["half and half", "half-and-half"]),
    ("skim", ["skim"]),
    ("full fat", ["full fat", "full-fat"]),
]


def fat_from_name(name: str) -> str | None:
    n = name.lower()
    for canon, pats in _FAT_PATTERNS:
        if any(p in n for p in pats):
            return canon
    return None


def _canon(result: tuple[str, str] | None) -> tuple[str, str] | None:
    if result is None:
        return None
    key, value = result
    return (CANONICAL_KEY.get(value, key), value)


def classify_value(key: str, value: str) -> tuple[str, str] | None:
    """Reassign an existing (key, value) facet option to the new taxonomy.

    Returns (new_key, new_value) or None to drop the value.
    """
    return _canon(_classify_value(key, value))


def _classify_value(key: str, value: str) -> tuple[str, str] | None:
    v = lemma(value)
    if key == "concentration":
        if v in CONCENTRATION_REMAP:
            return CONCENTRATION_REMAP[v]
    if key == "base":
        if v in BASE_TO_MEDIUM:
            return ("medium", v)
        if v in BASE_TO_VARIANT:
            return ("variant", v)
        return ("variant", v)
    # form may contain cuts (->preparation), states (->processing/preservation),
    # textures, packaging (drop).
    if key == "form":
        if v in DROP:
            return None
        if v in PRESERVATION and v not in PROCESSING_WINS:
            return ("preservation", v)
        if v in PROCESSING:
            return ("processing", v)
        if v in PREPARATION and v not in FORM:
            return ("preparation", v)
        if v in TEXTURE and v not in FORM:
            return ("texture", v)
        return ("form", v)
    # Other state keys: drop packaging, otherwise keep but de-overlap.
    if v in DROP:
        return None
    if key == "preservation" and v in PROCESSING_WINS:
        return ("processing", v)
    if key == "processing" and v in PRESERVATION and v not in PROCESSING_WINS:
        return ("preservation", v)
    return (key, v)


def classify_token(token: str) -> str | None:
    """Classify a leaf's distinguishing token into a facet key, or None if it is a
    distinct *kind* that should keep its own catalog row."""
    t = lemma(token)
    if t in CANONICAL_KEY:
        return CANONICAL_KEY[t]
    if t in COLOR:
        return "color"
    if t in FAT:
        return "fat"
    if t in GRADE:
        return "grade"
    if t in MEDIUM or t.startswith("in "):
        return "medium"
    if t in PRESERVATION and t not in PROCESSING_WINS:
        return "preservation"
    if t in PROCESSING:
        return "processing"
    if t in PREPARATION and t not in FORM:
        return "preparation"
    if t in TEXTURE and t not in FORM:
        return "texture"
    if t in FORM:
        return "form"
    return None  # distinct kind -> keep row (unless caller forces variant)
