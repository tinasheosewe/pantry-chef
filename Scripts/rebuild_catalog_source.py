#!/usr/bin/env python3
"""Repair flat catalog data and rebuild catalog.source.json."""
from __future__ import annotations

import argparse
import json
import sys

from catalog_lib import CATALOG_PATH, load_catalog, save_catalog
from catalog_source_lib import (
    CATALOG_SOURCE_PATH,
    apply_post_repair_fixes,
    compile_source,
    flat_to_source,
    repair_flat_catalog,
    save_source,
)


def main() -> int:
    parser = argparse.ArgumentParser(description="Repair flat catalog and rebuild catalog.source.json")
    parser.add_argument("--write-source", action="store_true", help="Write catalog.source.json")
    parser.add_argument("--write-catalog", action="store_true", help="Recompile catalog.json from source")
    parser.add_argument("--skip-repair", action="store_true", help="Skip flat-catalog repair pass")
    args = parser.parse_args()

    items = load_catalog()
    if not args.skip_repair:
        items, stats = repair_flat_catalog(items)
        save_catalog(items)
        print("Repair summary:")
        for key, value in sorted(stats.items()):
            print(f"  {key}: {value}")
        print(f"  items_after_repair: {len(items)}")

    source = flat_to_source(items)
    if args.write_source or not CATALOG_SOURCE_PATH.exists():
        save_source(source)
        print(f"Wrote {CATALOG_SOURCE_PATH.name}")
        print(f"  trees: {len(source.get('trees', []))}")
        print(f"  multiInheritance groups: {len(source.get('multiInheritance', []))}")
        multi_count = sum(len(g.get('items', [])) for g in source.get('multiInheritance', []))
        print(f"  multiInheritance items: {multi_count}")

    if args.write_catalog or args.write_source:
        compiled = compile_source(source)
        compiled, _ = apply_post_repair_fixes(compiled)
        save_catalog(compiled)
        print(f"Compiled {len(compiled)} items to catalog.json")

    return 0


if __name__ == "__main__":
    sys.exit(main())
