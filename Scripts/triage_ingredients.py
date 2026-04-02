#!/usr/bin/env python3
"""
Phase 1: LLM Triage of raw ingredients.txt

Sends all ~5000 items to GPT-5.4 in batches using structured output.
For every input item, outputs:
  - original: the raw string from the file
  - rank: position in the original file (= frequency rank)
  - status: KEEP | JUNK | DUPLICATE
  - corrected_name: typo-fixed/encoding-fixed canonical name (always filled)
  - category: one of the 15 FoodCategory values
  - duplicate_of: if DUPLICATE, the corrected_name of the canonical entry
  - reason: short explanation for JUNK/DUPLICATE decisions

Nothing is dropped. Every input appears in the output.
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
    print("Installing openai package...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "openai"])
    from openai import OpenAI

# ── Config ──────────────────────────────────────────────────────────────────
INPUT = Path(__file__).parent.parent / "ingredients.txt"
OUTPUT = Path(__file__).parent / "triage_results.json"
PROGRESS = Path(__file__).parent / "triage_progress.json"
LOG_FILE = Path(__file__).parent / "triage.log"
OUT_DIR = Path(__file__).parent / "triage_output"

# ── Logging setup ───────────────────────────────────────────────────────────
logger = logging.getLogger("triage")
logger.setLevel(logging.DEBUG)
_fh = logging.FileHandler(LOG_FILE, mode="a")
_fh.setFormatter(logging.Formatter("%(asctime)s [%(levelname)s] %(message)s", datefmt="%H:%M:%S"))
logger.addHandler(_fh)
_ch = logging.StreamHandler()
_ch.setFormatter(logging.Formatter("%(message)s"))
_ch.setLevel(logging.INFO)
logger.addHandler(_ch)

MODEL = "gpt-4.1"  # Change to "gpt-5.4" when available
BATCH_SIZE = 100
MAX_RETRIES = 3
MAX_CONCURRENT = 5  # Parallel API calls

OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "").strip()
if not OPENAI_API_KEY:
    # Try reading from xcconfig
    config_path = Path(__file__).parent.parent / "Config" / "LocalSecrets.xcconfig"
    if config_path.exists():
        for line in config_path.read_text().splitlines():
            if line.startswith("OPENAI_API_KEY"):
                OPENAI_API_KEY = line.split("=", 1)[1].strip()
                break

if not OPENAI_API_KEY:
    print("ERROR: No OPENAI_API_KEY found. Set env var or Config/LocalSecrets.xcconfig")
    sys.exit(1)

client = OpenAI(api_key=OPENAI_API_KEY)

# ── FoodCategory values ─────────────────────────────────────────────────────
CATEGORIES = [
    "Dairy & Eggs",
    "Produce",
    "Protein",
    "Grains & Cereals",
    "Spices & Herbs",
    "Condiments & Sauces",
    "Baking & Sweeteners",
    "Frozen Foods",
    "Canned & Jarred",
    "Beverages",
    "Snacks",
    "Oils & Fats",
    "Pasta & Noodles",
    "Nuts & Seeds",
    "Alcohol & Spirits",
    "Legumes & Beans",
    "Breads & Bakery",
    "Other",
]

# ── Structured output JSON schema ──────────────────────────────────────────
ITEM_SCHEMA = {
    "type": "object",
    "properties": {
        "rank": {
            "type": "integer",
            "description": "The original rank/position from the input list"
        },
        "original": {
            "type": "string",
            "description": "The exact original string from the input"
        },
        "status": {
            "type": "string",
            "enum": ["KEEP", "JUNK", "DUPLICATE"],
            "description": "KEEP=valid ingredient, JUNK=not a real ingredient, DUPLICATE=same ingredient as another entry"
        },
        "corrected_name": {
            "type": "string",
            "description": "The clean, corrected ingredient name (fix typos, encoding, normalize). Always in English, lowercase, singular base form."
        },
        "category": {
            "type": "string",
            "enum": CATEGORIES,
            "description": "The food category this ingredient belongs to"
        },
        "duplicate_of": {
            "type": "string",
            "description": "If DUPLICATE, the corrected_name of the canonical/primary entry. Empty string if not a duplicate."
        },
        "reason": {
            "type": "string",
            "description": "Brief explanation for JUNK or DUPLICATE status. Empty string for KEEP items."
        },
    },
    "required": ["rank", "original", "status", "corrected_name", "category", "duplicate_of", "reason"],
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

# ── System prompt ───────────────────────────────────────────────────────────
SYSTEM_PROMPT = """You are an expert food/ingredient classifier for a home cooking app called PantryChef.

You will receive a numbered list of ingredient names extracted from a recipe dataset. For EVERY item, classify it.

Rules:
1. **Status**:
   - KEEP: A real ingredient that belongs in a pantry/grocery catalog
   - JUNK: Not a real ingredient (equipment, measurements, gibberish, non-English, brand names alone, parsing artifacts, instructions, prices)
   - DUPLICATE: Same ingredient as another entry IN THIS BATCH or a very common ingredient that would have appeared earlier. Mark the less-canonical form as DUPLICATE.

2. **corrected_name**: Always provide the clean English name.
   - Fix typos: "mzarella" → "mozzarella", "peache" → "peach"
   - Fix encoding: "crã¨me fraã®che" → "crème fraîche", "jalapeã±o" → "jalapeño"
   - Normalize to singular base form: "tomatoes" → "tomato", "chicken breasts" → "chicken breast"
   - Strip form qualifiers that are prep/storage, not identity: "unsalted butter" → "butter", "fresh parsley" → "parsley", "ground cumin" → "cumin"
   - BUT keep qualifiers that change identity: "ground beef" stays "ground beef", "smoked paprika" stays "smoked paprika", "cream cheese" stays "cream cheese"
   - IMPORTANT: "pepper" alone (in the context of "salt and pepper") = "black pepper". Bell peppers should be "bell pepper" or specific colors like "red bell pepper".
   - IMPORTANT: "soda" alone in a recipe context = "baking soda" (KEEP, Baking & Sweeteners). Do NOT mark as JUNK.
   - Translate non-English to English if recognizable: "salz und pfeffer" → JUNK (it's salt and pepper, already covered)

3. **category**: Use exactly one of these 18 categories:
   Dairy & Eggs, Produce, Protein, Grains & Cereals, Spices & Herbs, Condiments & Sauces, Baking & Sweeteners, Frozen Foods, Canned & Jarred, Beverages, Snacks, Oils & Fats, Pasta & Noodles, Nuts & Seeds, Alcohol & Spirits, Legumes & Beans, Breads & Bakery, Other
   - Dairy & Eggs: milk, cheese, yogurt, cream, butter, eggs, egg whites, egg yolks
   - Baking & Sweeteners: flour, baking powder, yeast, sugar, honey, maple syrup, molasses, agave, corn syrup, powdered sugar, cocoa powder, chocolate chips, vanilla extract
   - Alcohol & Spirits: wine, beer, rum, bourbon, vodka, sake, cooking sherry, liqueurs — anything alcoholic
   - Legumes & Beans: lentils, chickpeas, black beans, kidney beans, split peas, etc. (dried or canned forms)
   - Breads & Bakery: bread, tortillas, pita, naan, breadcrumbs, croutons, biscuits, pie crust, phyllo dough, puff pastry
   - Canned & Jarred: canned tomatoes, tomato paste, tomato sauce, broth/stock, coconut milk, applesauce, canned fruit, jarred peppers, pickles, olives, capers
   - Produce: fresh fruits and vegetables only
   - Other: water, ice — use sparingly, most items fit a real category

4. **duplicate_of**: When marking DUPLICATE, reference the corrected_name of the canonical entry. Common canonical forms:
   - "salt" (not "kosher salt", "sea salt")
   - "black pepper" (not "pepper", "ground pepper", "freshly ground black pepper")
   - "butter" (not "unsalted butter", "salted butter")
   - "sugar" (not "granulated sugar", "white sugar", "caster sugar")
   - "flour" (not "all-purpose flour", "plain flour")
   - "green onion" (not "scallion", "spring onion")
   - "vanilla" (not "vanilla extract", "pure vanilla extract")
   - Herbs merge: "fresh basil"/"dried basil" → "basil"
   - Ground spices merge: "ground cinnamon" → "cinnamon", "ground ginger" → "ginger"

5. **reason**: Brief for JUNK/DUPLICATE. Empty string for KEEP.

Process EVERY item in the input. Do not skip any."""

# ── Main processing ─────────────────────────────────────────────────────────
def load_input():
    with open(INPUT) as f:
        lines = [l.strip() for l in f if l.strip()]
    return [(i + 1, line) for i, line in enumerate(lines)]


def load_progress():
    """Load previously processed batches to support resume."""
    if PROGRESS.exists():
        with open(PROGRESS) as f:
            return json.load(f)
    return {"completed_batches": [], "results": []}


def save_progress(progress):
    with open(PROGRESS, "w") as f:
        json.dump(progress, f, indent=2)


def validate_batch(items, batch, batch_num):
    """Validate 1-to-1 mapping between input batch and output items.
    Returns (returned_map, issues). Logs issues in real time."""
    issues = []
    expected = {rank: name for rank, name in batch}
    returned = {}

    for item in items:
        rank = item["rank"]
        if rank in returned:
            msg = f"Batch {batch_num}: DUPLICATE OUTPUT rank {rank}"
            issues.append(msg)
            logger.warning(msg)
        returned[rank] = item

        if rank in expected:
            sent = expected[rank]
            got = item["original"]
            if got.strip() != sent.strip():
                msg = f"Batch {batch_num}: MISMATCH rank {rank}: sent \"{sent}\" got \"{got}\""
                issues.append(msg)
                logger.warning(msg)

    if len(items) != len(batch):
        msg = f"Batch {batch_num}: COUNT MISMATCH sent {len(batch)}, got {len(items)}"
        issues.append(msg)
        logger.warning(msg)

    missing = set(expected.keys()) - set(returned.keys())
    if missing:
        msg = f"Batch {batch_num}: MISSING RANKS {sorted(missing)}"
        issues.append(msg)
        logger.warning(msg)

    extra = set(returned.keys()) - set(expected.keys())
    if extra:
        msg = f"Batch {batch_num}: EXTRA RANKS {sorted(extra)}"
        issues.append(msg)
        logger.warning(msg)

    for item in items:
        if item["status"] == "DUPLICATE" and not item["duplicate_of"]:
            msg = f"Batch {batch_num}: rank {item['rank']} DUPLICATE with no duplicate_of"
            issues.append(msg)
            logger.warning(msg)
        if item["status"] == "JUNK" and not item["reason"]:
            msg = f"Batch {batch_num}: rank {item['rank']} JUNK with no reason"
            issues.append(msg)
            logger.warning(msg)
        if item["status"] != "JUNK" and not item["corrected_name"].strip():
            msg = f"Batch {batch_num}: rank {item['rank']} empty corrected_name"
            issues.append(msg)
            logger.warning(msg)

    return returned, issues


def process_batch(batch, batch_num, total_batches):
    """Send a batch of (rank, name) pairs to the LLM. Validates 1-to-1 mapping."""
    input_text = "\n".join(f"{rank}. {name}" for rank, name in batch)
    user_msg = f"Classify these {len(batch)} ingredients (batch {batch_num}/{total_batches}):\n\n{input_text}"

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
                        "name": "triage_response",
                        "schema": RESPONSE_SCHEMA,
                        "strict": True,
                    }
                },
            )
            elapsed = time.time() - t0
            logger.debug(f"Batch {batch_num}: API call took {elapsed:.1f}s (attempt {attempt + 1})")

            result = json.loads(response.output_text)
            items = result["items"]

            # Strict per-batch validation
            returned_map, issues = validate_batch(items, batch, batch_num)

            if issues:
                missing = set(r for r, _ in batch) - set(returned_map.keys())
                if missing and attempt < MAX_RETRIES - 1:
                    logger.info(f"Batch {batch_num}: retrying ({len(missing)} missing)")
                    continue

                if missing:
                    logger.warning(f"Batch {batch_num}: filling {len(missing)} missing with placeholders")
                    for rank, name in batch:
                        if rank not in returned_map:
                            items.append({
                                "rank": rank,
                                "original": name,
                                "status": "KEEP",
                                "corrected_name": name.lower().strip(),
                                "category": "Other",
                                "duplicate_of": "",
                                "reason": "PLACEHOLDER: missing from LLM response, needs manual review",
                            })

                # Deduplicate output ranks (keep first occurrence)
                seen_ranks = set()
                deduped = []
                for item in items:
                    if item["rank"] not in seen_ranks:
                        seen_ranks.add(item["rank"])
                        deduped.append(item)
                items = deduped

            return items

        except Exception as e:
            logger.error(f"Batch {batch_num}: attempt {attempt + 1} error: {e}")
            if attempt < MAX_RETRIES - 1:
                time.sleep(2 ** attempt)
            else:
                logger.error(f"Batch {batch_num}: FAILED after {MAX_RETRIES} attempts, using placeholders")
                return [
                    {
                        "rank": rank,
                        "original": name,
                        "status": "KEEP",
                        "corrected_name": name.lower().strip(),
                        "category": "Other",
                        "duplicate_of": "",
                        "reason": "ERROR: API call failed, needs manual review",
                    }
                    for rank, name in batch
                ]


def main():
    parser = ArgumentParser(description="LLM triage of ingredient list")
    parser.add_argument("--sample", type=int, default=0,
                        help="Only process first N batches (for testing)")
    args = parser.parse_args()

    items = load_input()
    input_map = {rank: name for rank, name in items}
    logger.info(f"Loaded {len(items)} items from {INPUT}")
    logger.info(f"Logging to {LOG_FILE}")

    progress = load_progress()
    completed = set(progress["completed_batches"])
    all_results = progress["results"]
    lock = threading.Lock()
    batch_issues_count = [0]  # mutable counter for threads

    # Create batches
    batches = []
    for i in range(0, len(items), BATCH_SIZE):
        batches.append(items[i : i + BATCH_SIZE])

    total = len(batches)
    pending = [(i + 1, batch) for i, batch in enumerate(batches) if (i + 1) not in completed]

    if args.sample:
        pending = pending[:args.sample]
        logger.info(f"SAMPLE MODE: processing {len(pending)} of {total} batches")

    logger.info(f"Processing {total} batches of ~{BATCH_SIZE} ({MAX_CONCURRENT} concurrent)")
    if completed:
        logger.info(f"Resuming: {len(completed)} batches already done, {len(pending)} remaining")

    def process_and_save(batch_num, batch):
        logger.info(f"Batch {batch_num}/{total} (ranks {batch[0][0]}-{batch[-1][0]}) starting...")
        results = process_batch(batch, batch_num, total)

        # Per-batch bijection check (final, after retries/placeholders)
        result_ranks = [r["rank"] for r in results]
        expected_ranks = [r for r, _ in batch]
        ok = (sorted(result_ranks) == sorted(expected_ranks) and
              len(result_ranks) == len(set(result_ranks)))

        with lock:
            all_results.extend(results)
            completed.add(batch_num)
            progress["completed_batches"] = list(completed)
            progress["results"] = all_results
            save_progress(progress)
            if not ok:
                batch_issues_count[0] += 1

        keep = sum(1 for r in results if r["status"] == "KEEP")
        junk = sum(1 for r in results if r["status"] == "JUNK")
        dupe = sum(1 for r in results if r["status"] == "DUPLICATE")
        status = "✓" if ok else "⚠"
        logger.info(f"  {status} Batch {batch_num}: {len(results)} items — KEEP={keep} JUNK={junk} DUPE={dupe}  [{len(completed)}/{total} done]")
        return batch_num, results

    # Process batches in parallel
    t_start = time.time()
    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_CONCURRENT) as executor:
        futures = {
            executor.submit(process_and_save, bn, b): bn
            for bn, b in pending
        }
        for future in concurrent.futures.as_completed(futures):
            try:
                future.result()
            except Exception as e:
                bn = futures[future]
                logger.error(f"FATAL: Batch {bn} raised {e}")

    elapsed = time.time() - t_start
    logger.info(f"\nAll batches complete in {elapsed:.0f}s")
    if batch_issues_count[0]:
        logger.warning(f"  {batch_issues_count[0]} batches had validation issues — check {LOG_FILE}")
    else:
        logger.info(f"  All {total} batches passed 1-to-1 validation")

    # Sort and summarize
    all_results.sort(key=lambda x: x["rank"])

    statuses = {}
    cats = {}
    placeholders = 0
    for r in all_results:
        statuses[r["status"]] = statuses.get(r["status"], 0) + 1
        if r["status"] == "KEEP":
            cats[r["category"]] = cats.get(r["category"], 0) + 1
        if "PLACEHOLDER" in r.get("reason", "") or "ERROR" in r.get("reason", ""):
            placeholders += 1

    logger.info(f"\n{'='*60}")
    logger.info(f"FINAL: {len(all_results)} items processed")
    logger.info(f"{'='*60}")
    for status, count in sorted(statuses.items()):
        logger.info(f"  {status}: {count}")
    if placeholders:
        logger.warning(f"  NEEDS REVIEW: {placeholders} placeholders/errors")

    logger.info(f"\nKEEP items by category:")
    for cat, count in sorted(cats.items(), key=lambda x: -x[1]):
        logger.info(f"  {cat:<25s} {count:>5}")

    # Write full JSON
    with open(OUTPUT, "w") as f:
        json.dump(all_results, f, indent=2, ensure_ascii=False)
    logger.info(f"\nFull JSON → {OUTPUT}")

    # ── Write split files for review ────────────────────────────────────
    OUT_DIR.mkdir(exist_ok=True)

    # --- KEEP file: grouped by category, sorted by rank within each ---
    keep_items = [r for r in all_results if r["status"] == "KEEP"]
    by_cat = {}
    for item in keep_items:
        by_cat.setdefault(item["category"], []).append(item)

    keep_data = {}
    for cat in CATEGORIES:
        items_in_cat = by_cat.get(cat, [])
        if not items_in_cat:
            continue
        keep_data[cat] = [
            {
                "rank": item["rank"],
                "name": item["corrected_name"],
                **({"was": item["original"]} if item["original"].lower().strip() != item["corrected_name"] else {}),
            }
            for item in sorted(items_in_cat, key=lambda x: x["rank"])
        ]

    keep_path = OUT_DIR / "keep.json"
    with open(keep_path, "w") as f:
        json.dump(keep_data, f, indent=2, ensure_ascii=False)
    logger.info(f"Keep     → {keep_path} ({len(keep_items)} items)")

    # --- JUNK file: sorted by rank ---
    junk_items = [r for r in all_results if r["status"] == "JUNK"]
    junk_data = [
        {
            "rank": item["rank"],
            "original": item["original"],
            "reason": item["reason"],
        }
        for item in sorted(junk_items, key=lambda x: x["rank"])
    ]

    junk_path = OUT_DIR / "junk.json"
    with open(junk_path, "w") as f:
        json.dump(junk_data, f, indent=2, ensure_ascii=False)
    logger.info(f"Junk     → {junk_path} ({len(junk_items)} items)")

    # --- DUPLICATE file: grouped by canonical ---
    dupe_items = [r for r in all_results if r["status"] == "DUPLICATE"]
    by_canonical = {}
    for item in dupe_items:
        canonical = item["duplicate_of"] or item["corrected_name"]
        by_canonical.setdefault(canonical, []).append(item)

    # Sort groups by lowest rank dupe
    dupe_data = {}
    sorted_groups = sorted(by_canonical.items(),
                           key=lambda x: min(i["rank"] for i in x[1]))
    for canonical, dupes in sorted_groups:
        dupe_data[canonical] = [
            {
                "rank": item["rank"],
                "original": item["original"],
                **({"corrected": item["corrected_name"]} if item["corrected_name"] != item["original"].lower().strip() else {}),
                "reason": item["reason"],
            }
            for item in sorted(dupes, key=lambda x: x["rank"])
        ]

    dupe_path = OUT_DIR / "duplicates.json"
    with open(dupe_path, "w") as f:
        json.dump(dupe_data, f, indent=2, ensure_ascii=False)
    logger.info(f"Dupes    → {dupe_path} ({len(dupe_items)} items in {len(dupe_data)} groups)")

    # Clean up progress file
    if PROGRESS.exists():
        PROGRESS.unlink()
        logger.info("Cleaned up progress file")


if __name__ == "__main__":
    main()
