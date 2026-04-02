#!/usr/bin/env python3
"""
Phase 2: Collapse KEEP items into generic base ingredients per category.

Takes keep.json (3,328 items grouped by category) and for each item determines
the generic base ingredient. E.g.:
  - "red bell pepper", "green bell pepper" → base "bell pepper"
  - "sharp cheddar", "white cheddar" → base "cheddar cheese"
  - "chicken breast", "chicken thigh", "chicken wing" → base "chicken"
  - "dijon mustard", "yellow mustard" → base "mustard"

Then deduplicates: each base appears once per category, with all variants listed.

Output: catalog_bases.json — the clean, deduplicated ingredient catalog.
"""

import concurrent.futures
import json
import logging
import os
import sys
import threading
import time
from argparse import ArgumentParser
from pathlib import Path

try:
    from openai import OpenAI
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "openai"])
    from openai import OpenAI

# ── Config ──────────────────────────────────────────────────────────────────
SCRIPTS_DIR = Path(__file__).parent
INPUT = SCRIPTS_DIR / "triage_output" / "keep.json"
OUTPUT = SCRIPTS_DIR / "triage_output" / "catalog_bases.json"
LOG_FILE = SCRIPTS_DIR / "dedup.log"

MODEL = "gpt-4.1"
MAX_RETRIES = 3
MAX_CONCURRENT = 5
BATCH_SIZE = 150  # Items per LLM call (categories can exceed this)

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
logger = logging.getLogger("dedup")
logger.setLevel(logging.DEBUG)
_fh = logging.FileHandler(LOG_FILE, mode="w")
_fh.setFormatter(logging.Formatter("%(asctime)s [%(levelname)s] %(message)s", datefmt="%H:%M:%S"))
logger.addHandler(_fh)
_ch = logging.StreamHandler()
_ch.setFormatter(logging.Formatter("%(message)s"))
_ch.setLevel(logging.INFO)
logger.addHandler(_ch)

# ── Schema ──────────────────────────────────────────────────────────────────
ITEM_SCHEMA = {
    "type": "object",
    "properties": {
        "name": {
            "type": "string",
            "description": "The original ingredient name from the input"
        },
        "base": {
            "type": "string",
            "description": "The generic base ingredient this collapses to. Lowercase, singular."
        },
    },
    "required": ["name", "base"],
    "additionalProperties": False,
}

RESPONSE_SCHEMA = {
    "type": "object",
    "properties": {
        "items": {
            "type": "array",
            "items": ITEM_SCHEMA,
        }
    },
    "required": ["items"],
    "additionalProperties": False,
}

SYSTEM_PROMPT = """You are an expert food ingredient taxonomist for a home cooking pantry app.

You will receive a list of ingredient names within a single food category. For EVERY item, determine the **generic base ingredient** it belongs to.

Rules for determining base:
1. **Strip color/size/variety qualifiers**: "red bell pepper" → "bell pepper", "yellow onion" → "onion", "baby spinach" → "spinach"
2. **Strip cut/form qualifiers**: "chicken breast" → "chicken", "pork chop" → "pork", "beef chuck" → "beef", "salmon fillet" → "salmon"
3. **BUT keep qualifiers that create genuinely different pantry items**:
   - "cream cheese" stays "cream cheese" (not "cheese")
   - "peanut butter" stays "peanut butter" (not "peanut")
   - "coconut milk" stays "coconut milk" (not "coconut" or "milk")
   - "soy sauce" stays "soy sauce" (not "soy")
   - "tomato paste" stays "tomato paste" (not "tomato")
   - "ground beef" stays "ground beef" (not "beef") — different purchase
   - "cream of mushroom soup" stays "cream of mushroom soup"
   - "smoked paprika" stays "smoked paprika" (different flavor than paprika)
   - "dark chocolate" → "chocolate" (same base)
   - "italian sausage" → "sausage" (same base, variety qualifier)
   - "sharp cheddar" → "cheddar cheese" (variety qualifier)
   - "dijon mustard" → "mustard" (variety qualifier)
   - "extra virgin olive oil" → "olive oil" (grade qualifier)
4. **Cheese rule**: Most specific cheeses collapse to "cheese" as the base — cheddar, mozzarella, parmesan, feta, gouda, brie, swiss, provolone, gruyère, jack, blue cheese, etc. are all variants of "cheese". EXCEPTIONS that stay as their own base: "cream cheese", "cottage cheese", "ricotta", "mascarpone", "velveeta", "vegan cream cheese" — these are genuinely different products.
5. **Herb/spice rule**: Each herb and spice is its own base. "dried basil" → "basil", "fresh thyme" → "thyme".
6. **Juice rule**: "lemon juice", "lime juice", "orange juice" are their own bases (distinct pantry items from the fresh fruit).
7. **The base must be a real thing you'd find in a store**. Don't over-generalize.

Return the base for EVERY item. Do not skip any."""


def process_batch(names, category, batch_label):
    """Send a list of ingredient names to the LLM, get base for each."""
    input_text = "\n".join(f"- {name}" for name in names)
    user_msg = f"Category: {category}\n\nDetermine the base ingredient for each ({len(names)} items):\n\n{input_text}"

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
                        "name": "dedup_response",
                        "schema": RESPONSE_SCHEMA,
                        "strict": True,
                    }
                },
            )
            elapsed = time.time() - t0
            logger.debug(f"{batch_label}: API call took {elapsed:.1f}s (attempt {attempt + 1})")

            result = json.loads(response.output_text)
            items = result["items"]

            # Validate 1-to-1
            returned_names = {item["name"] for item in items}
            expected_names = set(names)
            missing = expected_names - returned_names
            extra = returned_names - expected_names

            if missing:
                logger.warning(f"{batch_label}: MISSING {len(missing)} items: {list(missing)[:5]}")
                if attempt < MAX_RETRIES - 1:
                    continue
                # Fill missing with self-as-base
                for name in missing:
                    items.append({"name": name, "base": name})

            if extra:
                logger.warning(f"{batch_label}: EXTRA {len(extra)} items: {list(extra)[:5]}")
                items = [i for i in items if i["name"] in expected_names]

            # Deduplicate returned names
            seen = set()
            deduped = []
            for item in items:
                if item["name"] not in seen:
                    seen.add(item["name"])
                    deduped.append(item)

            return deduped

        except Exception as e:
            logger.error(f"{batch_label}: attempt {attempt + 1} error: {e}")
            if attempt < MAX_RETRIES - 1:
                time.sleep(2 ** attempt)
            else:
                logger.error(f"{batch_label}: FAILED, using self-as-base fallback")
                return [{"name": n, "base": n} for n in names]


def main():
    parser = ArgumentParser(description="Collapse keep items to base ingredients")
    parser.add_argument("--sample", type=int, default=0,
                        help="Only process first N categories (for testing)")
    args = parser.parse_args()

    data = json.load(open(INPUT))
    total_items = sum(len(v) for v in data.values())
    logger.info(f"Loaded {total_items} KEEP items in {len(data)} categories from {INPUT}")
    logger.info(f"Logging to {LOG_FILE}")

    categories = list(data.items())
    if args.sample:
        categories = categories[:args.sample]
        logger.info(f"SAMPLE MODE: processing {len(categories)} categories")

    # Build work units: (category, batch_of_names, batch_label)
    work = []
    for cat, items in categories:
        names = [item["name"] for item in items]
        if len(names) <= BATCH_SIZE:
            work.append((cat, names, f"{cat}"))
        else:
            # Split large categories into batches
            for i in range(0, len(names), BATCH_SIZE):
                chunk = names[i:i + BATCH_SIZE]
                part = i // BATCH_SIZE + 1
                work.append((cat, chunk, f"{cat} part {part}"))

    logger.info(f"{len(work)} API calls needed ({MAX_CONCURRENT} concurrent)")

    # Process in parallel
    results_by_cat = {}  # cat → list of {name, base}
    lock = threading.Lock()

    def do_work(cat, names, label):
        logger.info(f"  {label} ({len(names)} items)...")
        result = process_batch(names, cat, label)
        with lock:
            results_by_cat.setdefault(cat, []).extend(result)
        logger.info(f"  ✓ {label}: {len(result)} items → {len(set(i['base'] for i in result))} bases")

    t_start = time.time()
    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_CONCURRENT) as executor:
        futures = {
            executor.submit(do_work, cat, names, label): label
            for cat, names, label in work
        }
        for future in concurrent.futures.as_completed(futures):
            try:
                future.result()
            except Exception as e:
                logger.error(f"FATAL: {futures[future]} raised {e}")

    elapsed = time.time() - t_start
    logger.info(f"\nAll done in {elapsed:.0f}s")

    # ── Build deduplicated catalog ──────────────────────────────────────
    catalog = {}
    total_bases = 0
    total_variants = 0

    for cat, items in categories:
        mappings = results_by_cat.get(cat, [])

        # Group variants by base
        base_groups = {}
        for m in mappings:
            base = m["base"].strip().lower()
            name = m["name"].strip().lower()
            base_groups.setdefault(base, set()).add(name)

        # Build catalog entry: sorted by base name
        cat_entries = []
        for base in sorted(base_groups.keys()):
            variants = base_groups[base]
            # Remove the base itself from variants
            other_variants = sorted(variants - {base})
            entry = {"base": base}
            if other_variants:
                entry["variants"] = other_variants
            cat_entries.append(entry)

        catalog[cat] = cat_entries
        total_bases += len(cat_entries)
        total_variants += sum(len(e.get("variants", [])) for e in cat_entries)

    # ── Summary ─────────────────────────────────────────────────────────
    logger.info(f"\n{'='*60}")
    logger.info(f"DEDUP RESULTS: {total_items} items → {total_bases} bases")
    logger.info(f"{'='*60}")
    for cat in catalog:
        n_bases = len(catalog[cat])
        n_input = len(data.get(cat, []))
        pct = (1 - n_bases / n_input) * 100 if n_input else 0
        logger.info(f"  {cat:<25s} {n_input:>4} → {n_bases:>4} bases  ({pct:.0f}% reduction)")

    # Write output
    with open(OUTPUT, "w") as f:
        json.dump(catalog, f, indent=2, ensure_ascii=False)
    logger.info(f"\nCatalog → {OUTPUT}")


if __name__ == "__main__":
    main()
