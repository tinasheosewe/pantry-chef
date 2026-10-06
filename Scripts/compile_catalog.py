#!/usr/bin/env python3
"""Compile catalog.source.json into flat catalog.json for the app bundle.

catalog.json has been edited directly since the source was last rebuilt (see
Scripts/README.md), so the source compiles to fewer items than the bundled file
holds. The script refuses to overwrite a larger catalog.json unless --force is given.
"""
from __future__ import annotations

import argparse
import sys

from catalog_lib import CATALOG_PATH, load_catalog, save_catalog
from catalog_source_lib import CATALOG_SOURCE_PATH, apply_post_repair_fixes, compile_source, load_source
from remodel.enrich import enrich


def main() -> int:
    parser = argparse.ArgumentParser(description="Compile catalog.source.json to catalog.json")
    parser.add_argument(
        "--force",
        action="store_true",
        help="Overwrite catalog.json even when the compiled result has fewer items",
    )
    args = parser.parse_args()

    if not CATALOG_SOURCE_PATH.exists():
        print(f"Missing source catalog: {CATALOG_SOURCE_PATH}")
        return 1

    source = load_source()
    compiled = compile_source(source)
    compiled, fix_count = apply_post_repair_fixes(compiled)
    # Deterministic enrichment (density, allergens, dietary tags, substitutions).
    compiled = enrich(compiled)

    existing_count = len(load_catalog()) if CATALOG_PATH.exists() else 0
    if len(compiled) < existing_count and not args.force:
        print(
            f"Not writing catalog.json: the source compiles to {len(compiled)} items but "
            f"catalog.json holds {existing_count}.\n"
            "catalog.json has been edited directly since the source was last rebuilt; "
            "pass --force to overwrite it anyway."
        )
        return 1

    save_catalog(compiled)
    print(f"Compiled {len(compiled)} items to catalog.json")
    if fix_count:
        print(f"  post_compile_fixes: {fix_count}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
