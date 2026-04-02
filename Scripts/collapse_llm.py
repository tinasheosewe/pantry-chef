#!/usr/bin/env python3
"""
LLM-based aggressive collapse of catalog_bases.json.

Sends each category's base names to GPT-4.1 and asks it to merge
over-specific bases into broader ones. The guiding principle:
"Same store shelf = same base. Granularity will be captured in facets."

Examples of expected merges:
  - asian pear → pear, blood orange → orange, cherry tomato → tomato
  - almond milk, rice milk, soy milk, oat milk → non-dairy milk
  - greek yogurt, vanilla yogurt → yogurt
  - cheerios, rice krispies → cereal
  - cherry jam, apricot jam → jam
  - meyer lemon → lemon

Reads catalog_bases.json, applies LLM-suggested merges, writes back.
Backs up to catalog_bases_v2.json before overwriting.
"""

import concurrent.futures
import json
import logging
import os
import sys
import threading
import time
from pathlib import Path

try:
    from openai import OpenAI
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "openai"])
    from openai import OpenAI

# ── Config ──────────────────────────────────────────────────────────────────
SCRIPTS_DIR = Path(__file__).parent
INPUT = SCRIPTS_DIR / "triage_output" / "catalog_bases.json"
BACKUP = SCRIPTS_DIR / "triage_output" / "catalog_bases_v2.json"
OUTPUT = INPUT  # overwrite in place
LOG_FILE = SCRIPTS_DIR / "collapse_llm.log"

MODEL = "gpt-4.1"
MAX_RETRIES = 3
MAX_CONCURRENT = 5

OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "").strip()
if not OPENAI_API_KEY:
    config_path = Path(__file__).parent.parent / "Config" / "LocalSecrets.xcconfig"
    if config_path.exists():
        for line in config_path.read_text().splitlines():
            if line.startswith("OPENAI_API_KEY"):
                OPENAI_API_KEY = line.split("=", 1)[1].strip()
                break

if not OPENAI_API_KEY:
    print("ERROR: No OPENAI_API_KEY found")
    sys.exit(1)

client = OpenAI(api_key=OPENAI_API_KEY)

# ── Logging ─────────────────────────────────────────────────────────────────
logger = logging.getLogger("collapse_llm")
logger.setLevel(logging.DEBUG)
_fh = logging.FileHandler(LOG_FILE, mode="w")
_fh.setFormatter(logging.Formatter("%(asctime)s [%(levelname)s] %(message)s", datefmt="%H:%M:%S"))
logger.addHandler(_fh)
_ch = logging.StreamHandler()
_ch.setFormatter(logging.Formatter("%(message)s"))
_ch.setLevel(logging.INFO)
logger.addHandler(_ch)

# ── Schema ──────────────────────────────────────────────────────────────────
MERGE_SCHEMA = {
    "type": "object",
    "properties": {
        "merges": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "source": {
                        "type": "string",
                        "description": "The over-specific base to merge away"
                    },
                    "target": {
                        "type": "string",
                        "description": "The broader base to merge into (may be an existing base or a new name)"
                    }
                },
                "required": ["source", "target"],
                "additionalProperties": False
            }
        }
    },
    "required": ["merges"],
    "additionalProperties": False
}

SYSTEM_PROMPT = """You are an expert food ingredient taxonomist for a home pantry app.

You will receive a list of BASE INGREDIENT NAMES within a single food category. These bases have already been partially deduplicated, but many are still too specific. Your job is to find bases that should be MERGED into a broader base.

## Guiding Principle
"Same store shelf or aisle section = same base." Granularity (flavor, brand, color, variety, cut, form) will be captured later as facets/attributes. Be AGGRESSIVE about collapsing.

## Rules for merging:

1. **Variety/cultivar → generic**: asian pear → pear, blood orange → orange, meyer lemon → lemon, cherry tomato → tomato, kalamata olive → olive, roma tomato → tomato, yukon gold potato → potato, jalapeño → pepper, serrano → pepper, poblano → pepper, habanero → pepper, anaheim pepper → pepper, banana pepper → pepper, thai chili → pepper

2. **Flavored/branded → generic**: greek yogurt → yogurt, vanilla yogurt → yogurt, cheerios → cereal, rice krispies → cereal, frosted flakes → cereal, cherry jam → jam, apricot preserves → jam, strawberry jam → jam, marmalade → jam

3. **Non-dairy milk variants → "non-dairy milk"**: almond milk, rice milk, soy milk, oat milk, coconut milk (as beverage) all merge to "non-dairy milk"

4. **Flavor-prefixed variants → base**: vanilla extract stays (it's a distinct product), but vanilla ice cream → ice cream, vanilla pudding → pudding, chocolate cake mix → cake mix, lemon curd → curd

5. **Form/preparation variants → base**: smoked salmon → salmon, pickled ginger → ginger (UNLESS the pickled/smoked form is a truly different product — e.g. "bacon" stays separate from "pork")

6. **Specific sauces/condiments → broader group ONLY when they share a shelf**: different hot sauces = "hot sauce", different BBQ sauces = "bbq sauce". But don't merge ketchup into "sauce" — it's its own thing.

7. **Brand names → generic**: e.g. "tabasco" → "hot sauce", "velveeta" → "processed cheese" or "cheese"

## What NOT to merge:
- Don't merge things that are genuinely purchased separately: cream cheese ≠ cheese, peanut butter ≠ butter, tomato paste ≠ tomato, soy sauce ≠ sauce
- Don't merge across fundamentally different textures: butter ≠ cream, flour ≠ wheat
- If something is already a good generic base, leave it alone
- Don't merge if you're unsure — err on the side of keeping

## Output:
Return a list of merges: each is {source, target} where source is the over-specific base to eliminate, and target is what it should merge into. The target may be an existing base in the list OR a new broader name. Only include items that SHOULD be merged. If no merges are needed for this category, return an empty list."""


def process_category(category: str, bases: list[str]) -> list[dict]:
    """Send a category's bases to the LLM, get merge suggestions back."""
    input_text = "\n".join(f"- {b}" for b in bases)
    user_msg = f"Category: {category}\n\n{len(bases)} base ingredients:\n\n{input_text}"

    for attempt in range(MAX_RETRIES):
        try:
            t0 = time.time()
            response = client.responses.create(
                model=MODEL,
                input=[
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": user_msg},
                ],
                text={
                    "format": {
                        "type": "json_schema",
                        "name": "collapse_response",
                        "schema": MERGE_SCHEMA,
                        "strict": True,
                    }
                },
            )
            elapsed = time.time() - t0
            logger.debug(f"{category}: API call took {elapsed:.1f}s (attempt {attempt + 1})")

            result = json.loads(response.output_text)
            merges = result["merges"]

            # Validate: every source must be in the input bases
            base_set = set(bases)
            valid_merges = []
            for m in merges:
                src = m["source"].strip().lower()
                tgt = m["target"].strip().lower()
                if src not in base_set:
                    logger.warning(f"{category}: source '{src}' not in bases, skipping")
                    continue
                if src == tgt:
                    logger.warning(f"{category}: source == target '{src}', skipping")
                    continue
                valid_merges.append({"source": src, "target": tgt})

            return valid_merges

        except Exception as e:
            logger.error(f"{category}: attempt {attempt + 1} error: {e}")
            if attempt < MAX_RETRIES - 1:
                time.sleep(2 ** attempt)
            else:
                logger.error(f"{category}: FAILED after {MAX_RETRIES} attempts, no merges applied")
                return []


def apply_merges(catalog: dict, all_merges: dict) -> dict:
    """Apply merges to the catalog. Returns new catalog."""
    new_catalog = {}
    total_merged = 0

    for cat, entries in catalog.items():
        merges = all_merges.get(cat, [])
        if not merges:
            new_catalog[cat] = entries
            continue

        # Build merge map: source → target
        merge_map = {}
        for m in merges:
            merge_map[m["source"]] = m["target"]

        # Resolve chains: if A → B → C, then A → C
        def resolve(base):
            seen = set()
            while base in merge_map and base not in seen:
                seen.add(base)
                base = merge_map[base]
            return base

        # Group entries by resolved target
        groups = {}  # resolved_base → {"variants": set(), "original_entry": entry_or_None}
        for entry in entries:
            base = entry["base"]
            target = resolve(base)

            if target not in groups:
                groups[target] = {"variants": set()}

            # Add existing variants
            for v in entry.get("variants", []):
                groups[target]["variants"].add(v)

            # If this base is being merged away, add it as a variant
            if base != target:
                groups[target]["variants"].add(base)
                total_merged += 1
            # Also add the base's own name if it's not the target
            # (so we don't lose the original base name)

        # Build output entries
        cat_entries = []
        for base in sorted(groups.keys()):
            entry = {"base": base}
            variants = sorted(groups[base]["variants"] - {base})
            if variants:
                entry["variants"] = variants
            cat_entries.append(entry)

        new_catalog[cat] = cat_entries

    return new_catalog, total_merged


def main():
    # Load catalog
    catalog = json.load(open(INPUT))
    total_before = sum(len(v) for v in catalog.values())
    logger.info(f"Loaded {total_before} bases in {len(catalog)} categories from {INPUT}")

    # Backup
    import shutil
    if not BACKUP.exists():
        shutil.copy2(INPUT, BACKUP)
        logger.info(f"Backed up to {BACKUP}")
    else:
        logger.info(f"Backup already exists at {BACKUP}")

    # Process each category via LLM
    all_merges = {}  # cat → [{"source", "target"}]
    lock = threading.Lock()

    def do_work(cat, bases):
        base_names = [e["base"] for e in bases]
        logger.info(f"  {cat} ({len(base_names)} bases)...")
        merges = process_category(cat, base_names)
        with lock:
            all_merges[cat] = merges
        logger.info(f"  ✓ {cat}: {len(merges)} merges suggested")
        if merges:
            for m in merges:
                logger.debug(f"    {m['source']} → {m['target']}")

    t_start = time.time()
    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_CONCURRENT) as executor:
        futures = {
            executor.submit(do_work, cat, entries): cat
            for cat, entries in catalog.items()
        }
        for future in concurrent.futures.as_completed(futures):
            try:
                future.result()
            except Exception as e:
                logger.error(f"FATAL: {futures[future]} raised {e}")

    elapsed = time.time() - t_start
    logger.info(f"\nAll LLM calls done in {elapsed:.0f}s")

    # Log all merges
    total_merges = sum(len(v) for v in all_merges.values())
    logger.info(f"\nTotal merges: {total_merges}")
    for cat in catalog:
        merges = all_merges.get(cat, [])
        if merges:
            logger.info(f"\n  {cat} ({len(merges)} merges):")
            for m in merges:
                logger.info(f"    {m['source']} → {m['target']}")

    # Apply merges
    new_catalog, merged_count = apply_merges(catalog, all_merges)
    total_after = sum(len(v) for v in new_catalog.values())

    # Summary
    logger.info(f"\n{'='*60}")
    logger.info(f"COLLAPSE RESULTS: {total_before} → {total_after} bases ({total_before - total_after} eliminated)")
    logger.info(f"{'='*60}")
    for cat in new_catalog:
        before = len(catalog.get(cat, []))
        after = len(new_catalog[cat])
        diff = before - after
        logger.info(f"  {cat:<25s} {before:>4} → {after:>4}  (-{diff})")

    # Write output
    with open(OUTPUT, "w") as f:
        json.dump(new_catalog, f, indent=2, ensure_ascii=False)
    logger.info(f"\nCatalog → {OUTPUT}")


if __name__ == "__main__":
    main()
