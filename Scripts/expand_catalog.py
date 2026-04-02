#!/usr/bin/env python3
"""
Expand the ingredient catalog from ~600 bases to ~800-900.

Phases:
  1. Manual restores & known additions
  2. LLM broadening pass per category via GPT-4.1 structured output
  3. Programmatic cleanup: remove semantic dupes, junk, cross-category dupes
  4. Final QOL: sort, verify, print counts

Output is written to Scripts/triage_output/expansion_candidates.json — a SEPARATE
file from bases_by_aisle.json. Deduplicates against existing but does NOT merge.
"""

import json, os, re, sys, time
from pathlib import Path
from openai import OpenAI

# ── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parent
BASES_PATH = SCRIPT_DIR / "triage_output" / "bases_by_aisle.json"
OUTPUT_PATH = SCRIPT_DIR / "triage_output" / "expansion_candidates.json"

# ── API Key ──────────────────────────────────────────────────────────────────
def load_api_key() -> str:
    config = PROJECT_DIR / "Config" / "LocalSecrets.xcconfig"
    for line in config.read_text().splitlines():
        if line.strip().startswith("OPENAI_API_KEY"):
            return line.split("=", 1)[1].strip()
    raise RuntimeError("OPENAI_API_KEY not found in LocalSecrets.xcconfig")

# ── Phase 1: Manual restores & known additions ──────────────────────────────
MANUAL_ADDITIONS: dict[str, list[str]] = {
    "Condiments & Sauces": [
        "guacamole",
        "hummus",
        "pico de gallo",
        "baba ganoush",
        "sriracha",
        "tajin",
        "bouillon",
    ],
    "Spices & Herbs": [
        "smoked paprika",
        "everything bagel seasoning",
    ],
    "Legumes & Beans": [
        "refried beans",
        "pork and beans",
    ],
    "Produce": [
        "tamarind",
    ],
    "Protein": [
        "rotisserie chicken",
    ],
    "Produce": [
        "tamarind",
        "coleslaw mix",
        "salad mix",
        "stir fry mix",
    ],
}

# ── Phase 2: LLM broadening prompt ──────────────────────────────────────────
SYSTEM_PROMPT = """\
You are a grocery-store ingredient cataloger for a recipe app called PantryChef.
Your job: given a category name and its existing base ingredients, suggest NEW base
ingredients that are MISSING from the list.

Rules:
- Only suggest BASE ingredients (not facets/varieties). No "red onion"—just "onion".
- Include common international crossover ingredients home cooks actually buy.
- Include prepared/convenience items people use in recipes (e.g., rotisserie chicken, 
  frozen edamame, canned soup).
- Include brand names that have become generic product names (e.g., Sriracha, Tabasco).
- Do NOT suggest items too niche for a North American, European, or common 
  Asian/Latin grocery store.
- Do NOT re-suggest anything already in the existing list.
- Each suggestion should be lowercase, singular form, concise (1-4 words).
- Return ONLY a JSON array of strings. No explanations."""

def build_user_prompt(category: str, existing: list[str], all_bases_flat: set[str]) -> str:
    return f"""Category: "{category}"

Existing bases ({len(existing)} items):
{json.dumps(sorted(existing), indent=2)}

All bases across ALL categories (do NOT duplicate any of these):
{json.dumps(sorted(all_bases_flat), indent=2)}

Suggest 15-40 new base ingredients for the "{category}" category. 
Return a JSON array of strings, nothing else."""

# ── LLM call ─────────────────────────────────────────────────────────────────
def call_llm(client: OpenAI, category: str, existing: list[str], all_bases: set[str]) -> list[str]:
    user_prompt = build_user_prompt(category, existing, all_bases)
    for attempt in range(3):
        try:
            resp = client.chat.completions.create(
                model="gpt-4.1",
                messages=[
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": user_prompt},
                ],
                temperature=0.7,
                max_tokens=2000,
                response_format={"type": "json_object"},
            )
            raw = resp.choices[0].message.content.strip()
            parsed = json.loads(raw)
            # Handle both {"items": [...]} and plain [...]
            if isinstance(parsed, list):
                return [str(x).lower().strip() for x in parsed]
            elif isinstance(parsed, dict):
                for v in parsed.values():
                    if isinstance(v, list):
                        return [str(x).lower().strip() for x in v]
            print(f"  ⚠ Unexpected response format for {category}: {raw[:100]}")
            return []
        except Exception as e:
            print(f"  ⚠ Attempt {attempt+1} failed for {category}: {e}")
            time.sleep(2 ** attempt)
    return []

# ── Phase 3: Dedup & cleanup ────────────────────────────────────────────────
def normalize(s: str) -> str:
    """Normalize for dedup: lowercase, strip, remove trailing 's', collapse spaces."""
    s = s.lower().strip()
    s = re.sub(r'\s+', ' ', s)
    return s

def is_duplicate(candidate: str, existing_set: set[str]) -> bool:
    """Check if candidate is a duplicate of any existing item."""
    n = normalize(candidate)
    if n in existing_set:
        return True
    # Check plural/singular
    if n.endswith('s') and n[:-1] in existing_set:
        return True
    if n + 's' in existing_set:
        return True
    return False

# ── Main ─────────────────────────────────────────────────────────────────────
def main():
    print("=" * 60)
    print("PantryChef Catalog Expansion")
    print("=" * 60)

    # Load existing catalog
    with open(BASES_PATH) as f:
        catalog: dict[str, list[str]] = json.load(f)

    # Phase 1: Apply manual additions to working copy
    print("\n── Phase 1: Manual restores & known additions ──")
    working = {cat: list(items) for cat, items in catalog.items()}
    manual_count = 0
    for cat, items in MANUAL_ADDITIONS.items():
        if cat not in working:
            working[cat] = []
        for item in items:
            if not is_duplicate(item, {normalize(x) for x in working[cat]}):
                # Also check all categories
                all_existing = {normalize(x) for items_list in working.values() for x in items_list}
                if not is_duplicate(item, all_existing):
                    working[cat].append(item)
                    manual_count += 1
                    print(f"  + {cat}: {item}")
                else:
                    print(f"  ⊘ {item} (already exists elsewhere)")
            else:
                print(f"  ⊘ {item} (already in {cat})")
    print(f"  Added {manual_count} manual items")

    # Build the flat set of ALL existing bases (original + manual)
    all_bases_flat: set[str] = set()
    for items in working.values():
        for item in items:
            all_bases_flat.add(normalize(item))

    # Phase 2: LLM broadening
    print("\n── Phase 2: LLM broadening pass ──")
    client = OpenAI(api_key=load_api_key())

    expansion: dict[str, list[str]] = {}
    total_new = 0

    # Skip "Other" — it's a catch-all
    categories_to_expand = [c for c in sorted(working.keys()) if c != "Other"]

    for cat in categories_to_expand:
        print(f"\n  📦 {cat} ({len(working[cat])} existing)...")
        suggestions = call_llm(client, cat, working[cat], all_bases_flat)

        # Dedup against everything
        accepted = []
        for s in suggestions:
            if not s or len(s) > 50:
                continue
            if is_duplicate(s, all_bases_flat):
                continue
            # Accept and track
            accepted.append(s)
            all_bases_flat.add(normalize(s))

        if accepted:
            expansion[cat] = sorted(accepted)
            total_new += len(accepted)
            print(f"     ✓ {len(accepted)} new: {', '.join(accepted[:8])}{'...' if len(accepted) > 8 else ''}")
        else:
            print(f"     (no new items)")

    print(f"\n  Total new from LLM: {total_new}")

    # Phase 3: Cross-category dedup pass on expansion
    print("\n── Phase 3: Cross-category dedup ──")
    seen: set[str] = set()
    dupes_removed = 0
    for cat in sorted(expansion.keys()):
        cleaned = []
        for item in expansion[cat]:
            n = normalize(item)
            if n in seen:
                print(f"  ✗ Removed cross-cat dupe: {item} (in {cat})")
                dupes_removed += 1
            else:
                seen.add(n)
                cleaned.append(item)
        expansion[cat] = cleaned
    # Remove empty categories
    expansion = {k: v for k, v in expansion.items() if v}
    print(f"  Removed {dupes_removed} cross-category duplicates")

    # Phase 4: Final QOL — sort and summarize
    print("\n── Phase 4: Final QOL ──")
    # Include manual additions in expansion output too
    for cat, items in MANUAL_ADDITIONS.items():
        for item in items:
            n = normalize(item)
            # Check if it was actually added (not already existing in original catalog)
            original_set = {normalize(x) for x in catalog.get(cat, [])}
            if not is_duplicate(item, original_set):
                if cat not in expansion:
                    expansion[cat] = []
                if item not in expansion[cat]:
                    expansion[cat].append(item)

    # Sort everything
    for cat in expansion:
        expansion[cat] = sorted(set(expansion[cat]))

    # Final counts
    expansion_total = sum(len(v) for v in expansion.values())
    original_total = sum(len(v) for v in catalog.values())
    combined_total = original_total + expansion_total

    print(f"\n  Original catalog: {original_total}")
    print(f"  New expansion:    {expansion_total}")
    print(f"  Combined total:   {combined_total}")
    print(f"\n  Expansion by category:")
    for cat in sorted(expansion.keys()):
        orig = len(catalog.get(cat, []))
        new = len(expansion[cat])
        print(f"    {cat}: +{new} (was {orig}, would be {orig + new})")

    # Write output
    with open(OUTPUT_PATH, 'w') as f:
        json.dump(expansion, f, indent=2, ensure_ascii=False)
    print(f"\n  ✅ Written to {OUTPUT_PATH.relative_to(PROJECT_DIR)}")
    print(f"     (SEPARATE from bases_by_aisle.json — not merged)")

if __name__ == "__main__":
    main()
