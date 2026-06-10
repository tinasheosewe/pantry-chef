#!/usr/bin/env python3
"""Deterministic enrichment of catalog items: density (g/cup, g/piece), allergens,
dietary tags, and substitutions.

Computed from category + name + facets so it is fully regenerable. Wired into
compile_catalog.py so re-compiling from source reproduces the enriched catalog.

  python3 remodel/enrich.py          # report coverage
  python3 remodel/enrich.py --apply  # rewrite catalog.json in place
"""
from __future__ import annotations

import argparse
import collections
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR.parent))

from catalog_lib import load_catalog, normalize_lookup_key, save_catalog  # noqa: E402


def _has(name: str, words) -> bool:
    n = f" {name} "
    return any(f" {w} " in n or name.startswith(w + " ") or name.endswith(" " + w) or name == w
               for w in words)


# ---------------------------------------------------------------------------
# Density: grams per US cup
# ---------------------------------------------------------------------------
# Ordered (first match wins). Keys matched as whole-word substrings of the name.
DENSITY_KEYWORDS: list[tuple[list[str], float]] = [
    (["powdered sugar", "confectioner", "icing sugar"], 120),
    (["brown sugar"], 213),
    (["granulated sugar", "white sugar", "caster sugar", "sugar"], 200),
    (["cocoa powder", "cacao powder", "cocoa"], 85),
    (["cornstarch", "corn starch"], 120),
    (["almond flour"], 96),
    (["cake flour"], 114),
    (["bread flour"], 130),
    (["whole wheat flour"], 120),
    (["all-purpose flour", "all purpose flour", "flour"], 125),
    (["rolled oats", "oats", "oatmeal"], 90),
    (["panko"], 60),
    (["breadcrumb", "bread crumb"], 108),
    (["cornmeal", "polenta"], 122),
    (["quinoa"], 170),
    (["couscous"], 173),
    (["white rice", "rice"], 185),
    (["lentil"], 192),
    (["chickpea", "garbanzo"], 200),
    (["dried bean", "dry bean"], 200),
    (["table salt", "salt"], 273),
    (["baking soda", "baking powder"], 220),
    (["honey"], 340),
    (["molasses"], 337),
    (["maple syrup"], 322),
    (["corn syrup"], 328),
    (["agave"], 330),
    (["syrup"], 315),
    (["peanut butter"], 258),
    (["nut butter", "almond butter", "cashew butter", "tahini"], 250),
    (["cream cheese"], 232),
    (["sour cream"], 230),
    (["yogurt", "yoghurt"], 245),
    (["grated parmesan", "grated cheese", "shredded cheese"], 100),
    (["butter", "margarine"], 227),
    (["shortening", "lard"], 205),
    (["ghee"], 210),
    (["mayonnaise", "mayo"], 220),
    (["ketchup"], 240),
    (["mustard"], 249),
    (["tomato paste"], 262),
    (["tomato sauce", "marinara", "pasta sauce"], 245),
    (["salsa"], 240),
    (["applesauce"], 244),
    (["jam", "jelly", "preserve", "marmalade"], 320),
    (["soy sauce", "tamari"], 255),
    (["vinegar"], 239),
    (["oil"], 218),
    (["broth", "stock"], 240),
    (["juice"], 240),
    (["wine", "beer", "milk", "cream", "water", "buttermilk"], 240),
    (["chopped nuts", "almonds", "cashews", "walnuts", "pecans", "nuts"], 135),
    (["blueberr", "raspberr", "blackberr", "strawberr", "berries", "berry"], 150),
]

DENSITY_CATEGORY_FALLBACK = {
    "Oils & Fats": 215,
    "Beverages": 240,
    "Alcohol & Spirits": 240,
    "Condiments & Sauces": 245,
    "Grains & Cereals": 160,
    "Legumes & Beans": 195,
    "Pasta & Noodles": 100,
    "Nuts & Seeds": 140,
    "Baking & Sweeteners": 180,
    "Spices & Herbs": 100,
    "Produce": 150,
    "Canned & Jarred": 240,
    "Frozen Foods": 150,
    "Dairy & Eggs": 230,
}
# Categories where a "cup" density is not meaningful (sold by weight/piece).
DENSITY_SKIP_CATEGORIES = {"Protein", "Breads & Bakery", "Snacks", "Other"}


def density_for(item: dict) -> float | None:
    name = normalize_lookup_key(item["name"])
    for words, grams in DENSITY_KEYWORDS:
        if _has(name, words):
            return float(grams)
    if item["category"] in DENSITY_SKIP_CATEGORIES:
        return None
    return DENSITY_CATEGORY_FALLBACK.get(item["category"])


# ---------------------------------------------------------------------------
# Mass per piece (grams)
# ---------------------------------------------------------------------------
PIECE_WEIGHTS: list[tuple[list[str], float]] = [
    (["garlic clove"], 5), (["garlic"], 45),
    (["green onion", "scallion", "spring onion"], 15), (["shallot"], 30),
    (["leek"], 90), (["onion"], 150),
    (["cherry tomato", "grape tomato"], 17), (["roma tomato", "plum tomato"], 62),
    (["tomato"], 123),
    (["lemon"], 60), (["lime"], 67), (["orange"], 131), (["grapefruit"], 230),
    (["apple"], 182), (["banana"], 118), (["pear"], 178), (["peach"], 150),
    (["plum"], 66), (["kiwi"], 75), (["avocado"], 200), (["mango"], 200),
    (["potato"], 170), (["sweet potato"], 130), (["carrot"], 61),
    (["celery"], 40), (["cucumber"], 300), (["bell pepper", "capsicum"], 119),
    (["jalapeno", "jalapeño"], 14), (["zucchini", "courgette"], 196),
    (["eggplant", "aubergine"], 458), (["corn"], 103), (["mushroom"], 18),
    (["strawberry"], 12), (["egg white"], 33), (["egg yolk"], 18),
    (["egg"], 50), (["bread", "tortilla", "pita"], 30),
    (["chicken breast"], 174), (["chicken thigh"], 130),
]


def piece_weight_for(item: dict) -> float | None:
    name = normalize_lookup_key(item["name"])
    for words, grams in PIECE_WEIGHTS:
        if _has(name, words):
            return float(grams)
    return None


# ---------------------------------------------------------------------------
# Allergens
# ---------------------------------------------------------------------------
DAIRY = (["milk", "cheese", "cream", "yogurt", "yoghurt", "whey", "ghee", "butter",
          "custard", "kefir", "paneer", "curd", "buttermilk", "casein", "dairy",
          "ricotta", "mozzarella", "cheddar", "parmesan", "gelato", "ice cream"])
DAIRY_EXCLUDE = (["non-dairy", "nondairy", "dairy-free", "dairy free", "coconut",
                  "almond", "oat", "soy", "cashew", "rice milk", "hemp", "pea ",
                  "plant", "vegan", "peanut butter", "cocoa butter", "shea",
                  "butternut", "butter bean", "butter lettuce", "apple butter",
                  "nut butter", "sunflower butter", "seed butter", "body butter"])
EGG = (["egg", "eggs", "mayonnaise", "mayo", "meringue", "albumen", "eggnog", "aioli"])
EGG_EXCLUDE = (["eggplant", "egg-free", "eggless", "egg substitute", "egg replacer",
                "vegan mayo"])
GLUTEN = (["wheat", "flour", "bread", "pasta", "noodle", "barley", "rye", "malt",
           "couscous", "bulgur", "semolina", "spelt", "farro", "cracker", "cookie",
           "cake", "pastry", "seitan", "beer", "crouton", "bun", "bagel", "pretzel",
           "muffin", "biscuit", "naan", "roux", "panko", "breadcrumb", "wrap",
           "tortilla", "dumpling", "wonton", "ramen", "udon", "soy sauce",
           "graham", "cereal", "matzo", "stuffing", "vital wheat"])
GLUTEN_EXCLUDE = (["gluten-free", "gluten free", "rice flour", "almond flour",
                   "coconut flour", "chickpea flour", "corn flour", "cornflour",
                   "tapioca flour", "buckwheat", "rice noodle", "corn tortilla",
                   "rice paper", "cellophane noodle", "glass noodle", "tamari",
                   "potato flour", "cassava flour", "oat flour", "millet flour",
                   "corn pasta", "rice pasta", "polenta", "grits"])
PEANUT = (["peanut", "groundnut"])
PEANUT_EXCLUDE = (["peanut-free"])
TREENUT = (["almond", "walnut", "pecan", "cashew", "pistachio", "hazelnut",
            "macadamia", "brazil nut", "pine nut", "chestnut", "praline",
            "marzipan", "nutella", "gianduja", "coconut", "filbert", "nut butter",
            "mixed nut", "nut "])
TREENUT_EXCLUDE = (["nutmeg", "butternut", "water chestnut", "doughnut", "donut",
                    "nutritional yeast", "peanut", "nut-free", "coconut water",
                    "coconut aminos"])
SOY = (["soy", "soya", "tofu", "tempeh", "edamame", "miso", "tamari", "natto",
        "soybean"])
SOY_EXCLUDE = (["soy-free", "soy free"])
SHELLFISH = (["shrimp", "prawn", "crab", "lobster", "crayfish", "crawfish", "clam",
              "mussel", "oyster", "scallop", "squid", "octopus", "snail", "abalone",
              "langoustine", "cockle", "calamari", "cuttlefish", "krill"])
FISH = (["fish", "salmon", "tuna", "cod", "anchovy", "sardine", "halibut", "trout",
         "herring", "mackerel", "tilapia", "bass", "snapper", "catfish", "haddock",
         "caviar", "roe", "surimi", "pollock", "mahi", "swordfish", "eel", "carp",
         "worcestershire"])
FISH_EXCLUDE = (["cuttlefish", "shellfish", "fish sauce free"])
SESAME = (["sesame", "tahini", "halva", "gomashio", "hummus", "za'atar", "zaatar"])

ALLERGEN_RULES = [
    ("dairy", DAIRY, DAIRY_EXCLUDE),
    ("egg", EGG, EGG_EXCLUDE),
    ("gluten", GLUTEN, GLUTEN_EXCLUDE),
    ("peanut", PEANUT, PEANUT_EXCLUDE),
    ("tree-nut", TREENUT, TREENUT_EXCLUDE),
    ("soy", SOY, SOY_EXCLUDE),
    ("shellfish", SHELLFISH, ()),
    ("fish", FISH, FISH_EXCLUDE),
    ("sesame", SESAME, ()),
]


def allergens_for(item: dict) -> list[str]:
    name = normalize_lookup_key(item["name"])
    out = []
    for tag, includes, excludes in ALLERGEN_RULES:
        if _has(name, includes) and not _has(name, excludes):
            out.append(tag)
    # Dairy & Eggs category safety net (cheese/milk products not caught by name).
    if item["category"] == "Dairy & Eggs":
        if "egg" in name and "egg" not in out and not _has(name, EGG_EXCLUDE):
            out.append("egg")
        if "dairy" not in [a for a in out] and not _has(name, DAIRY_EXCLUDE) \
                and not _has(name, ["egg"]) and "dairy" not in out:
            # plain dairy items (e.g. "kefir", "skyr") — add dairy unless plant-based
            if not _has(name, ["non-dairy", "plant", "vegan", "coconut", "almond", "soy", "oat", "cashew"]):
                out.append("dairy")
    return sorted(set(out))


# ---------------------------------------------------------------------------
# Dietary tags (derived)
# ---------------------------------------------------------------------------
MEAT = (["beef", "pork", "chicken", "turkey", "lamb", "veal", "bacon", "ham",
         "sausage", "meat", "duck", "goose", "bison", "venison", "rabbit", "goat",
         "prosciutto", "salami", "pepperoni", "jerky", "steak", "brisket", "ribs",
         "chorizo", "pancetta", "mutton", "boar", "elk", "ostrich", "quail",
         "poultry", "hot dog", "bratwurst", "liver", "gelatin", "lard", "tallow",
         "schmaltz", "anchovy", "broth", "bone"])
MEAT_EXCLUDE = (["meatless", "meat-free", "vegan", "vegetarian", "plant-based",
                 "mock", "imitation", "vegetable broth", "mushroom broth",
                 "coconut meat", "nutmeat", "beefsteak tomato", "vegetable stock"])
HONEY = (["honey", "bee pollen", "royal jelly"])
GELATIN = (["gelatin", "gelatine"])


def dietary_for(item: dict, allergens: list[str]) -> list[str]:
    name = normalize_lookup_key(item["name"])
    cat = item["category"]
    is_flesh = ("shellfish" in allergens or "fish" in allergens
                or (_has(name, MEAT) and not _has(name, MEAT_EXCLUDE))
                or cat == "Protein" and _has(name, MEAT) and not _has(name, MEAT_EXCLUDE))
    is_gelatin = _has(name, GELATIN)
    has_dairy = "dairy" in allergens
    has_egg = "egg" in allergens
    has_honey = _has(name, HONEY)

    tags = []
    vegetarian = not is_flesh and not is_gelatin
    vegan = vegetarian and not has_dairy and not has_egg and not has_honey
    if vegetarian:
        tags.append("Vegetarian")
    if vegan:
        tags.append("Vegan")
    if "gluten" not in allergens:
        tags.append("Gluten-Free")
    if not has_dairy:
        tags.append("Dairy-Free")
    if "tree-nut" not in allergens and "peanut" not in allergens:
        tags.append("Nut-Free")
    return tags


# ---------------------------------------------------------------------------
# Substitutions
# ---------------------------------------------------------------------------
# Curated common swaps keyed by catalog id (best-effort; only applied if ids exist).
CURATED_SWAPS: dict[str, list[tuple[str, str, str | None]]] = {
    "butter": [("olive-oil", "3:4", "Use ¾ the amount of oil for butter in cooking."),
               ("margarine", "1:1", None), ("coconut-oil", "1:1", None)],
    "olive-oil": [("vegetable-oil", "1:1", None), ("canola-oil", "1:1", None),
                  ("butter", "4:3", "Use a bit more butter by volume.")],
    "vegetable-oil": [("canola-oil", "1:1", None), ("olive-oil", "1:1", None)],
    "buttermilk": [("milk", "1:1", "Add 1 tbsp lemon juice or vinegar per cup of milk and rest 5 min.")],
    "sour-cream": [("greek-yogurt", "1:1", None), ("yogurt", "1:1", None)],
    "heavy-cream": [("milk", "1:1", "For richness add 2 tbsp melted butter per cup."),
                    ("coconut-cream", "1:1", "Dairy-free option.")],
    "milk": [("non-dairy-milk", "1:1", None), ("almond-milk", "1:1", None),
             ("oat-milk", "1:1", None)],
    "egg": [("applesauce", "1:1", "¼ cup applesauce per egg in baking."),
            ("banana", "1:2", "½ mashed banana per egg in baking.")],
    "all-purpose-flour": [("bread-flour", "1:1", None), ("whole-wheat-flour", "1:1", None)],
    "sugar": [("honey", "1:1", "Reduce liquid slightly; honey is sweeter."),
              ("brown-sugar", "1:1", None), ("maple-syrup", "1:1", None)],
    "brown-sugar": [("sugar", "1:1", "Add 1 tbsp molasses per cup for flavor.")],
    "soy-sauce": [("tamari", "1:1", "Gluten-free option."), ("coconut-aminos", "1:1", "Soy-free option.")],
    "lemon-juice": [("lime-juice", "1:1", None), ("vinegar", "1:2", None)],
    "cornstarch": [("flour", "1:2", "Use twice as much flour to thicken."),
                   ("arrowroot", "1:1", None)],
    "mayonnaise": [("greek-yogurt", "1:1", None), ("sour-cream", "1:1", None)],
    "breadcrumbs": [("panko", "1:1", None), ("oats", "1:1", None)],
    "cilantro": [("parsley", "1:1", "Different flavor; works as garnish.")],
    "shallot": [("onion", "1:1", None)],
    "scallion": [("onion", "1:2", None), ("chives", "1:1", None)],
    "ricotta": [("cottage-cheese", "1:1", None)],
    "creme-fraiche": [("sour-cream", "1:1", None)],
    "vegetable-oil-baking": [],
}


# Generic functional parents whose children are NOT interchangeable, so sibling
# substitution is meaningless (e.g. all "sauce" children, all "spice" children).
NO_SIBLING_SWAP_PARENTS = {
    "sauce", "condiment", "seasoning", "spice", "herb", "mix", "baking-mix",
    "paste", "topping", "dip", "spread", "marinade", "dressing", "extract",
    "powder", "flavoring", "garnish", "filling", "glaze",
}


def swaps_for(item: dict, by_id: dict, children: dict) -> list[dict]:
    out: list[dict] = []
    seen = set()
    for sub_id, ratio, note in CURATED_SWAPS.get(item["id"], []):
        if sub_id in by_id and sub_id != item["id"] and sub_id not in seen:
            seen.add(sub_id)
            out.append({"substituteItemID": sub_id, "ratio": ratio, "notes": note})
    # Sibling fallback: other children of the same single parent are natural swaps,
    # but only for "kind" families (skip generic functional parents).
    if len(out) < 3:
        for parent in item.get("parentIds", []):
            if parent in NO_SIBLING_SWAP_PARENTS:
                continue
            for sib in sorted(children.get(parent, [])):
                if sib == item["id"] or sib in seen:
                    continue
                seen.add(sib)
                out.append({"substituteItemID": sib, "ratio": "1:1",
                            "notes": f"Same family as {by_id[parent]['name']}."})
                if len(out) >= 3:
                    break
            if len(out) >= 3:
                break
    return out


# ---------------------------------------------------------------------------
def _clean_aliases(items: list[dict]) -> None:
    """Final alias hygiene at compile time: drop self-aliases, within-item dups, and
    aliases that exactly equal another item's canonical name."""
    name_owner = {normalize_lookup_key(x["name"]): x["id"] for x in items}
    for item in items:
        nk = normalize_lookup_key(item["name"])
        cleaned, seen = [], set()
        for a in item.get("aliases", []):
            ak = normalize_lookup_key(a)
            if not ak or ak == nk or ak in seen:
                continue
            owner = name_owner.get(ak)
            if owner is not None and owner != item["id"]:
                continue
            seen.add(ak)
            cleaned.append(a)
        if cleaned:
            item["aliases"] = cleaned
        else:
            item.pop("aliases", None)


def enrich(items: list[dict]) -> list[dict]:
    _clean_aliases(items)
    by_id = {x["id"]: x for x in items}
    children: dict[str, list[str]] = collections.defaultdict(list)
    for x in items:
        for p in x.get("parentIds", []):
            children[p].append(x["id"])

    for item in items:
        gpc = density_for(item)
        gpp = piece_weight_for(item)
        allergens = allergens_for(item)
        dietary = dietary_for(item, allergens)
        swaps = swaps_for(item, by_id, children)

        for k in ("gramsPerCup", "gramsPerPiece", "allergens", "dietaryTags", "swaps"):
            item.pop(k, None)
        if gpc is not None:
            item["gramsPerCup"] = gpc
        if gpp is not None:
            item["gramsPerPiece"] = gpp
        if allergens:
            item["allergens"] = allergens
        if dietary:
            item["dietaryTags"] = dietary
        if swaps:
            item["swaps"] = swaps
    return items


def run(apply: bool) -> int:
    items = load_catalog()
    enrich(items)
    cov = collections.Counter()
    for it in items:
        for k in ("gramsPerCup", "gramsPerPiece", "allergens", "dietaryTags", "swaps"):
            if it.get(k):
                cov[k] += 1
    print("=== ENRICHMENT COVERAGE ===")
    print(f"  items: {len(items)}")
    for k, v in cov.most_common():
        print(f"  {k}: {v} ({100*v//len(items)}%)")
    if not apply:
        print("\n(dry run — pass --apply to write)")
        return 0
    save_catalog(items)
    print("\nwrote enriched catalog.json")
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    sys.exit(run(ap.parse_args().apply))
