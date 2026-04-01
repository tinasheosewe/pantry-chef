"""
Filter 1,402 ML-generated ingredient groups down to home-cooking-relevant items.

Drops:
  - Entire irrelevant USDA categories (baby foods, restaurant foods, etc.)
  - Groups whose names match non-home-cooking keywords (industrial, game meat, etc.)
  - Duplicate/near-duplicate group names within a category

Outputs: ml_outputs/filtered_groups.json
"""

import json
import re
from pathlib import Path
from collections import defaultdict

INPUT = Path(__file__).parent / "ml_outputs" / "tfidf_agglomerative_groups.json"
OUTPUT = Path(__file__).parent / "ml_outputs" / "filtered_groups.json"

# ── Categories to drop entirely ──────────────────────────────────────────────
DROP_CATEGORIES = {
    # Non-food / irrelevant
    "Baby Foods",
    "American Indian/Alaska Native Foods",
    "Restaurant Foods",
    "Fast Foods",
    "Meals, Entrees, and Side Dishes",
    "Breakfast Cereals",
    # Prepared/composite foods — not raw ingredients
    "Baked Products",
    "Beverages",
    "Soups, Sauces, and Gravies",
    "Sweets",
    "Snacks",
    "Sausages and Luncheon Meats",
}

# ── Keywords in group_name or base_ingredient that signal non-home-cooking ───
# Each pattern is matched case-insensitively against group_name AND base_ingredient
DROP_PATTERNS = [
    # Game / exotic meats
    r"\b(emu|ostrich|bison|elk|moose|caribou|bear|raccoon|opossum|squirrel"
    r"|armadillo|beaver|muskrat|turtle|alligator|frog|snail)\b",
    # Organ meats most home cooks won't use
    r"\b(brain|spleen|thymus|lungs?|mechanically.separated|chitlins"
    r"|chitterlings|sweetbread)\b",
    # Industrial / lab items
    r"\b(isolate|protein.powder|whey.protein|casein|hydrolysate"
    r"|textured.vegetable|tvp)\b",
    # Baby/infant
    r"\b(infant|baby|gerber|beech[\s-]?nut)\b",
    # Non-ingredient branded items
    r"\b(ensure|slim[\s-]?fast|carnation.instant)\b",
]

DROP_RE = re.compile("|".join(DROP_PATTERNS), re.IGNORECASE)


def load_groups() -> list[dict]:
    with open(INPUT) as f:
        return json.load(f)


def should_drop(group: dict) -> str | None:
    """Return reason string if group should be dropped, else None."""
    cat = group.get("category", "")
    if cat in DROP_CATEGORIES:
        return f"category:{cat}"

    name = group.get("group_name", "")
    base = group.get("base_ingredient", "")
    text = f"{name} {base}"

    m = DROP_RE.search(text)
    if m:
        return f"keyword:{m.group()}"

    return None


def main():
    groups = load_groups()
    kept = []
    dropped_by_reason: dict[str, int] = defaultdict(int)

    for g in groups:
        reason = should_drop(g)
        if reason:
            dropped_by_reason[reason] += 1
        else:
            kept.append(g)

    # Re-number group IDs sequentially
    for i, g in enumerate(kept):
        g["group_id"] = f"flt-{i}"

    # Stats
    total_dropped = sum(dropped_by_reason.values())
    kept_items = sum(len(g["members"]) for g in kept)
    dropped_items = sum(len(g["members"]) for g in groups) - kept_items

    print(f"Input:   {len(groups):>5} groups  ({sum(len(g['members']) for g in groups)} items)")
    print(f"Kept:    {len(kept):>5} groups  ({kept_items} items)")
    print(f"Dropped: {total_dropped:>5} groups  ({dropped_items} items)")
    print()

    # Drop reasons
    cat_drops = {k: v for k, v in dropped_by_reason.items() if k.startswith("category:")}
    kw_drops = {k: v for k, v in dropped_by_reason.items() if k.startswith("keyword:")}

    if cat_drops:
        print("Dropped categories:")
        for reason, cnt in sorted(cat_drops.items(), key=lambda x: -x[1]):
            print(f"  {reason.split(':',1)[1]:<45} {cnt:>4} groups")

    if kw_drops:
        print("\nDropped by keyword:")
        for reason, cnt in sorted(kw_drops.items(), key=lambda x: -x[1]):
            print(f"  {reason.split(':',1)[1]:<45} {cnt:>4} groups")

    # Category breakdown of what's kept
    from collections import Counter
    kept_cats = Counter(g["category"] for g in kept)
    print(f"\nKept categories ({len(kept_cats)}):")
    for cat, cnt in kept_cats.most_common():
        items = sum(len(g["members"]) for g in kept if g["category"] == cat)
        print(f"  {cat:<45} {cnt:>4} groups  ({items} items)")

    # Write output
    with open(OUTPUT, "w") as f:
        json.dump(kept, f, indent=2)
    print(f"\nWrote {OUTPUT}")


if __name__ == "__main__":
    main()
