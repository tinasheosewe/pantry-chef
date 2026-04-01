#!/usr/bin/env python3
"""
Clean up raw RecipeNLG ingredient frequencies:
1. Frequency cutoff (drop items < MIN_COUNT)
2. Drop junk (parsing artifacts, equipment, water variants)
3. Lemmatize (merge singular/plural)
4. Strip form qualifiers (fresh/ground/dried/frozen etc.) → merge into base
5. Output clean seed list sorted by combined frequency
"""

import json
import re
import sys
from collections import defaultdict
from pathlib import Path

INPUT_PATH = Path(__file__).parent / "ingredient_frequencies.json"
OUTPUT_PATH = Path(__file__).parent / "cleaned_ingredients.json"

MIN_COUNT = 100  # must appear in 100+ recipes across 2.2M

# ── Junk: not real ingredients ──────────────────────────────────────────────
JUNK_EXACT = {
    "water", "boiling water", "cold water", "hot water", "warm water",
    "ice water", "ice cubes", "ice",
    "cooking spray", "nonstick cooking spray", "pam",
    "all-purpose",  # truncated "all-purpose flour"
    "\u00bc", "\u00bd", "\u00be",  # ¼ ½ ¾ (parsing artifacts)
    "oleo",  # archaic for margarine — will merge
    "hamburger",  # colloquial for ground beef — will merge
    "soda",  # ambiguous (baking soda? soda pop?)
    "salt and pepper",  # not a single ingredient
    "salt & pepper",
    "salt and pepper to taste",
}

# Patterns that indicate junk (equipment, instructions, garbage)
JUNK_PATTERNS = [
    r"^\d+$",                    # pure numbers
    r"^[\d\s/\.]+$",            # fractions / measurements
    r"\boptional\b",            # "optional" in name
    r"\bto taste\b",            # "salt to taste"
    r"\bas needed\b",
    r"\bfor garnish\b",
    r"\bfor frying\b",
    r"\bfor greasing\b",
    r"\bfor dusting\b",
    r"\bfor serving\b",
    r"\bfor dipping\b",
    r"\bfor coating\b",
    r"\bfor rolling\b",
    r"\bor more\b",
    r"\bif desired\b",
]
JUNK_RE = [re.compile(p, re.IGNORECASE) for p in JUNK_PATTERNS]

# ── Explicit merges: alias → canonical ──────────────────────────────────────
EXPLICIT_MERGES = {
    "oleo": "margarine",
    "hamburger": "ground beef",
    "hamburger meat": "ground beef",
    "ground chuck": "ground beef",
    "ground round": "ground beef",
    "ground sirloin": "ground beef",
    "confectioners sugar": "powdered sugar",
    "confectioners' sugar": "powdered sugar",
    "icing sugar": "powdered sugar",
    "powdered sugar": "powdered sugar",
    "confectioner's sugar": "powdered sugar",
    "caster sugar": "granulated sugar",
    "castor sugar": "granulated sugar",
    "white sugar": "sugar",
    "granulated sugar": "sugar",
    "cane sugar": "sugar",
    "kosher salt": "salt",
    "sea salt": "salt",
    "table salt": "salt",
    "fine salt": "salt",
    "coarse salt": "salt",
    "pepper": "black pepper",  # standalone "pepper" = "salt and pepper" usage
    "black pepper": "black pepper",
    "ground black pepper": "black pepper",
    "freshly ground black pepper": "black pepper",
    "ground pepper": "black pepper",
    "freshly ground pepper": "black pepper",
    "cracked black pepper": "black pepper",
    "cracked pepper": "black pepper",
    "whole black peppercorns": "black pepper",
    "black peppercorns": "black pepper",
    "peppercorns": "black pepper",
    "peppers": "bell pepper",  # generic plural = bell peppers
    "white pepper": "white pepper",  # keep separate — distinct flavor
    "extra-virgin olive oil": "olive oil",
    "extra virgin olive oil": "olive oil",
    "evoo": "olive oil",
    "salted butter": "butter",
    "unsalted butter": "butter",
    "sweet cream butter": "butter",
    "clove garlic": "garlic",
    "garlic clove": "garlic",
    "garlic cloves": "garlic",
    "cloves garlic": "garlic",
    "scallions": "green onions",
    "scallion": "green onions",
    "spring onion": "green onions",
    "spring onions": "green onions",
    "egg yolk": "egg yolks",
    "egg white": "egg whites",
    "cool whip": "whipped topping",
    "cool whip topping": "whipped topping",
}

# ── Form qualifiers to strip (these become facets, not base names) ──────────
# Order matters: longer prefixes first
FORM_PREFIXES = [
    "freshly ground ",
    "freshly grated ",
    "freshly squeezed ",
    "freshly chopped ",
    "finely chopped ",
    "finely diced ",
    "finely minced ",
    "finely grated ",
    "coarsely chopped ",
    "coarsely ground ",
    "thinly sliced ",
    "roughly chopped ",
    "fresh frozen ",
    "fresh ",
    "frozen ",
    "dried ",
    "ground ",
    "minced ",
    "chopped ",
    "diced ",
    "sliced ",
    "shredded ",
    "grated ",
    "crushed ",
    "crumbled ",
    "toasted ",
    "roasted ",
    "smoked ",
    "canned ",
    "cooked ",
    "raw ",
    "whole ",
    "boneless skinless ",
    "boneless ",
    "skinless ",
    "bone-in ",
    "skin-on ",
]

# Exceptions: don't strip qualifier when it changes the identity
# e.g., "ground beef" is a real base (not "beef" with form "ground")
FORM_STRIP_EXCEPTIONS = {
    "ground beef", "ground turkey", "ground pork", "ground lamb",
    "ground chicken", "ground veal", "ground bison",
    "ground cinnamon", "ground cumin", "ground nutmeg",
    "ground ginger", "ground cloves", "ground allspice",
    "ground cardamom", "ground coriander", "ground turmeric",
    "ground mustard",
    "dried oregano", "dried thyme", "dried basil", "dried rosemary",
    "dried parsley", "dried dill", "dried sage", "dried tarragon",
    "dried marjoram", "dried mint", "dried cilantro",
    "smoked paprika", "smoked sausage", "smoked salmon",
    "smoked ham", "smoked bacon", "smoked turkey",
    "canned tomatoes", "canned tuna", "canned salmon",
    "canned beans", "canned corn", "canned pineapple",
    "canned coconut milk", "canned chicken broth",
    "cream cheese",  # "cream" is the form/type, not a qualifier
    "shredded coconut",
    "roasted red peppers", "roasted red pepper",
    "roasted garlic",
    "frozen peas", "frozen corn", "frozen spinach",
    "frozen strawberries", "frozen blueberries",
    "whole milk", "whole wheat flour",
    "whipped topping", "whipped cream",
    "cooked rice", "cooked pasta", "cooked chicken",
    "cooked shrimp", "cooked ham",
}

# For ground spices, merge into the base spice
SPICE_GROUND_MERGES = {
    "ground cinnamon": "cinnamon",
    "ground cumin": "cumin",
    "ground nutmeg": "nutmeg",
    "ground ginger": "ginger",
    "ground cloves": "cloves",
    "ground allspice": "allspice",
    "ground cardamom": "cardamom",
    "ground coriander": "coriander",
    "ground turmeric": "turmeric",
    "ground mustard": "mustard powder",
}

# For dried herbs, merge into the base herb
HERB_DRIED_MERGES = {
    "dried oregano": "oregano",
    "dried thyme": "thyme",
    "dried basil": "basil",
    "dried rosemary": "rosemary",
    "dried parsley": "parsley",
    "dried dill": "dill",
    "dried sage": "sage",
    "dried tarragon": "tarragon",
    "dried marjoram": "marjoram",
    "dried mint": "mint",
    "dried cilantro": "cilantro",
}

# ── Simple pluralization rules ──────────────────────────────────────────────
def singularize(word):
    """Basic English singularization for food words."""
    if len(word) <= 2:
        return word
    # Don't singularize these
    keep_plural = {
        "hummus", "couscous", "molasses", "grits", "oats",
        "brussels sprouts", "bitters", "capers", "chives",
        "grapes", "greens", "herbs", "lentils", "noodles",
        "olives", "pancakes", "pretzels", "sprouts", "tortillas",
        "egg whites", "egg yolks", "green onions",
        "sesame seeds", "poppy seeds", "sunflower seeds",
        "pumpkin seeds", "flax seeds", "chia seeds",
        "bread crumbs", "graham crackers", "saltine crackers",
        "chocolate chips", "french fries",
    }
    if word in keep_plural:
        return word

    # Multi-word: only singularize the last word
    parts = word.rsplit(" ", 1)
    if len(parts) == 2:
        head, tail = parts
        return head + " " + singularize(tail)

    # ies → y (berries → berry, but not series)
    if word.endswith("ies") and len(word) > 4:
        return word[:-3] + "y"
    # ves → f/fe (leaves → leaf, halves → half)
    if word.endswith("ves"):
        ves_map = {
            "leaves": "leaf", "halves": "half", "loaves": "loaf",
            "knives": "knife", "lives": "life",
        }
        if word in ves_map:
            return ves_map[word]
        # Most food words ending in -ves → -ve (cloves→clove, chives→chive)
        return word[:-1]
    # oes → o (tomatoes → tomato, potatoes → potato)
    if word.endswith("oes") and word not in ("shoes",):
        return word[:-2]
    # ses → s for some (molasses stays)
    # es → e or drop es
    if word.endswith("es") and not word.endswith("ses"):
        return word[:-1]  # es → e (not ideal for all, but decent for food)
    # s → drop
    if word.endswith("s") and not word.endswith("ss") and not word.endswith("us"):
        return word[:-1]

    return word


def strip_form_prefix(name):
    """Strip form qualifiers from ingredient name.
    Returns (stripped_name, was_stripped)."""
    if name in FORM_STRIP_EXCEPTIONS:
        return name, False

    for prefix in FORM_PREFIXES:
        if name.startswith(prefix):
            stripped = name[len(prefix):]
            if stripped:  # don't strip to empty
                return stripped, True
    return name, False


def is_junk(name):
    if name in JUNK_EXACT:
        return True
    for pat in JUNK_RE:
        if pat.search(name):
            return True
    return False


def normalize(name):
    """Full normalization pipeline for a single name."""
    # 1. Explicit merge
    if name in EXPLICIT_MERGES:
        name = EXPLICIT_MERGES[name]

    # 2. Spice ground merges (ground cinnamon → cinnamon)
    if name in SPICE_GROUND_MERGES:
        name = SPICE_GROUND_MERGES[name]

    # 3. Herb dried merges (dried basil → basil)
    if name in HERB_DRIED_MERGES:
        name = HERB_DRIED_MERGES[name]

    # 4. Strip form prefixes (fresh parsley → parsley)
    name, _ = strip_form_prefix(name)

    # 5. Singularize (tomatoes → tomato, chicken breasts → chicken breast)
    name = singularize(name)

    # 6. Re-apply merges — form stripping may have revealed a mergeable name
    #    e.g. "fresh ground black pepper" → strip "fresh " → "ground black pepper" → merge → "black pepper"
    if name in EXPLICIT_MERGES:
        name = EXPLICIT_MERGES[name]
    if name in SPICE_GROUND_MERGES:
        name = SPICE_GROUND_MERGES[name]
    if name in HERB_DRIED_MERGES:
        name = HERB_DRIED_MERGES[name]

    return name


def main():
    with open(INPUT_PATH) as f:
        raw = json.load(f)

    print(f"Loaded {len(raw):,} raw entries")

    # Phase 1: frequency cutoff
    above_cutoff = [(name, count) for name, count in raw if count >= MIN_COUNT]
    print(f"After cutoff (>={MIN_COUNT}): {len(above_cutoff):,}")

    # Phase 2: drop junk
    no_junk = [(name, count) for name, count in above_cutoff if not is_junk(name)]
    dropped_junk = len(above_cutoff) - len(no_junk)
    print(f"After junk removal: {len(no_junk):,} (dropped {dropped_junk})")

    # Phase 3: normalize and merge
    merged = defaultdict(int)
    merge_log = defaultdict(list)  # canonical → list of (original, count)

    for name, count in no_junk:
        canonical = normalize(name)
        merged[canonical] += count
        if canonical != name:
            merge_log[canonical].append((name, count))

    # Sort by combined count
    sorted_items = sorted(merged.items(), key=lambda x: -x[1])

    print(f"After normalization/merge: {len(sorted_items):,}")

    # Save output
    output = []
    for name, count in sorted_items:
        entry = {"name": name, "count": count}
        if name in merge_log:
            entry["merged_from"] = {n: c for n, c in merge_log[name]}
        output.append(entry)

    with open(OUTPUT_PATH, "w") as f:
        json.dump(output, f, indent=2)

    print(f"\nSaved to {OUTPUT_PATH}")

    # Preview
    print(f"\n=== TOP 60 CLEANED INGREDIENTS ===")
    for rank, item in enumerate(output[:60], 1):
        extras = ""
        if "merged_from" in item:
            sources = list(item["merged_from"].keys())
            if len(sources) <= 3:
                extras = f"  <- {', '.join(sources)}"
            else:
                extras = f"  <- {', '.join(sources[:3])} +{len(sources)-3} more"
        print(f"  {rank:3d}. {item['name']:<40s} {item['count']:>9,}{extras}")

    # Show some notable merges
    print(f"\n=== NOTABLE MERGES ===")
    big_merges = [(name, data_) for name, data_ in
                  ((n, m) for n, m in merge_log.items())
                  if sum(c for _, c in data_) > 10000]
    big_merges.sort(key=lambda x: -sum(c for _, c in x[1]))
    for canonical, sources in big_merges[:20]:
        total_merged = sum(c for _, c in sources)
        src_str = ", ".join(f"{n}({c:,})" for n, c in sorted(sources, key=lambda x: -x[1])[:4])
        print(f"  {canonical:<35s} merged {total_merged:>9,} from: {src_str}")

    # Frequency distribution of cleaned data
    print(f"\n=== CLEANED FREQUENCY BRACKETS ===")
    for lo, label in [(100000, "100k+"), (10000, "10k+"), (1000, "1k+"), (100, "100+")]:
        n = sum(1 for item in output if item["count"] >= lo)
        print(f"  {label:>8s}: {n:>5,}")


if __name__ == "__main__":
    main()
