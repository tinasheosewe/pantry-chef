#!/usr/bin/env python3
"""
LLM broadening pass: generate additional base ingredients that are missing
from the current catalog, per category.

Feeds current bases to GPT-4.1 and asks it to suggest commonly-used bases
that a home cook would need but aren't in the list yet. Species-level
separation preserved (individual fish, birds, grains, fruits, etc.).
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

SCRIPTS_DIR = Path(__file__).parent
INPUT = SCRIPTS_DIR / "triage_output" / "bases_by_aisle.json"
OUTPUT = SCRIPTS_DIR / "triage_output" / "new_bases.json"
LOG_FILE = SCRIPTS_DIR / "broaden.log"

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

logger = logging.getLogger("broaden")
logger.setLevel(logging.DEBUG)
_fh = logging.FileHandler(LOG_FILE, mode="w")
_fh.setFormatter(logging.Formatter("%(asctime)s [%(levelname)s] %(message)s", datefmt="%H:%M:%S"))
logger.addHandler(_fh)
_ch = logging.StreamHandler()
_ch.setFormatter(logging.Formatter("%(message)s"))
_ch.setLevel(logging.INFO)
logger.addHandler(_ch)

RESPONSE_SCHEMA = {
    "type": "object",
    "properties": {
        "new_bases": {
            "type": "array",
            "items": {"type": "string"}
        }
    },
    "required": ["new_bases"],
    "additionalProperties": False
}

SYSTEM_PROMPT = """You are an expert food ingredient taxonomist for a home pantry/cooking app.

You will receive a CATEGORY NAME and its EXISTING base ingredients. Your job is to suggest ADDITIONAL base ingredients that are MISSING from the list but that home cooks commonly use or encounter in recipes.

## Guidelines:

1. **Species-level separation**: Each distinct species of fish, bird, grain, fruit, vegetable, herb, nut, bean, etc. should be its own base. Don't collapse species together.
   - e.g. "tilapia", "salmon", "trout" are separate bases (not just "fish")
   - e.g. "basil", "thyme", "rosemary" are separate bases
   - e.g. "black bean", "kidney bean", "pinto bean" are separate bases IF they're not already in the list

2. **Generic form only**: Each base should be the simplest generic name — no colors, sizes, brands, cuts, or preparations.
   - ✓ "rice" NOT "brown rice" or "jasmine rice"
   - ✓ "chicken" NOT "chicken breast" or "rotisserie chicken"
   - ✓ "mustard" NOT "dijon mustard"

3. **Real pantry items**: Only suggest things that a home cook would actually buy at a grocery store. No restaurant-only or ultra-rare items.

4. **No duplicates**: Do NOT suggest anything already in the existing list, even if worded slightly differently.

5. **Think broadly**: Consider items from diverse cuisines — Asian, Latin, African, Middle Eastern, Indian, European, etc.

6. **Scope**: Stay within this specific category. Don't suggest items that belong in a different aisle/category.

Return the new base names as a flat list of lowercase strings."""


def process_category(category: str, existing: list[str]) -> list[str]:
    existing_text = "\n".join(f"- {b}" for b in existing)
    user_msg = f"""Category: {category}

Existing bases ({len(existing)} items):

{existing_text}

Suggest additional base ingredients that are MISSING from this list. Think about what a well-stocked grocery store carries in this section that isn't covered above. Be thorough but practical — only items that appear in real home recipes."""

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
                        "name": "broaden_response",
                        "schema": RESPONSE_SCHEMA,
                        "strict": True,
                    }
                },
            )
            elapsed = time.time() - t0
            logger.debug(f"{category}: API call took {elapsed:.1f}s (attempt {attempt + 1})")

            result = json.loads(response.output_text)
            new = [b.strip().lower() for b in result["new_bases"] if b.strip()]

            # Remove any that match existing (case-insensitive)
            existing_set = {b.lower() for b in existing}
            new = [b for b in new if b not in existing_set]

            # Dedup within response
            seen = set()
            deduped = []
            for b in new:
                if b not in seen:
                    seen.add(b)
                    deduped.append(b)

            return sorted(deduped)

        except Exception as e:
            logger.error(f"{category}: attempt {attempt + 1} error: {e}")
            if attempt < MAX_RETRIES - 1:
                time.sleep(2 ** attempt)
            else:
                logger.error(f"{category}: FAILED, returning empty")
                return []


def main():
    data = json.load(open(INPUT))
    existing_total = sum(len(v) for v in data.values())
    logger.info(f"Loaded {existing_total} existing bases across {len(data)} categories")

    all_new = {}
    lock = threading.Lock()

    def do_work(cat, bases):
        logger.info(f"  {cat} ({len(bases)} existing)...")
        new = process_category(cat, bases)
        with lock:
            all_new[cat] = new
        logger.info(f"  ✓ {cat}: +{len(new)} new bases suggested")

    t_start = time.time()
    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_CONCURRENT) as executor:
        futures = {
            executor.submit(do_work, cat, bases): cat
            for cat, bases in data.items()
        }
        for future in concurrent.futures.as_completed(futures):
            try:
                future.result()
            except Exception as e:
                logger.error(f"FATAL: {futures[future]} raised {e}")

    elapsed = time.time() - t_start
    logger.info(f"\nAll LLM calls done in {elapsed:.0f}s")

    # Cross-category dedup: remove any new base that appears in ANY existing category
    all_existing = set()
    for bases in data.values():
        all_existing.update(b.lower() for b in bases)

    cross_dupes = 0
    for cat in all_new:
        before = len(all_new[cat])
        all_new[cat] = [b for b in all_new[cat] if b not in all_existing]
        cross_dupes += before - len(all_new[cat])

    # Also dedup new bases across categories (same new base in 2 cats)
    seen_new = {}  # base → first category
    for cat in all_new:
        cleaned = []
        for b in all_new[cat]:
            if b not in seen_new:
                seen_new[b] = cat
                cleaned.append(b)
        all_new[cat] = cleaned

    # Remove empty categories
    all_new = {cat: bases for cat, bases in all_new.items() if bases}

    new_total = sum(len(v) for v in all_new.values())
    logger.info(f"\nRemoved {cross_dupes} cross-category duplicates")
    logger.info(f"\n{'='*60}")
    logger.info(f"NEW BASES: {new_total} additions across {len(all_new)} categories")
    logger.info(f"{'='*60}")
    for cat in sorted(all_new.keys()):
        logger.info(f"  {cat:<25s} +{len(all_new[cat]):>3}")

    with open(OUTPUT, "w") as f:
        json.dump(all_new, f, indent=2, ensure_ascii=False)
    logger.info(f"\nWritten → {OUTPUT}")


if __name__ == "__main__":
    main()
