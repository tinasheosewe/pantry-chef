#!/usr/bin/env python3
"""Scan catalog.json for facet values that appear under multiple facet keys
on the same ingredient. These cause display issues like "Ground Ground Elk"
where the CatalogSearchEngine resolves the same token to two different facet
keys and both end up in the display name."""

import json
import sys
from pathlib import Path
from collections import defaultdict

CATALOG_PATH = Path(__file__).resolve().parent.parent / "PantryChef" / "Resources" / "catalog.json"


def find_duplicates(catalog):
    """Return list of (item_id, value, [(key1), (key2), ...]) tuples."""
    results = []
    for item in catalog:
        value_to_keys = defaultdict(list)
        for facet in item.get("facets", []):
            for option in facet["options"]:
                value_to_keys[option.lower()].append(facet["key"])
        for value, keys in value_to_keys.items():
            if len(keys) > 1:
                results.append((item["id"], value, keys))
    return results


def main():
    if not CATALOG_PATH.exists():
        print(f"Error: catalog not found at {CATALOG_PATH}", file=sys.stderr)
        sys.exit(1)

    with open(CATALOG_PATH) as f:
        catalog = json.load(f)

    duplicates = find_duplicates(catalog)

    if not duplicates:
        print("No duplicate facet values found.")
        return

    # Group by (key1, key2) pair for readability
    by_pair = defaultdict(list)
    for item_id, value, keys in duplicates:
        pair = tuple(sorted(keys))
        by_pair[pair].append((item_id, value))

    total = len(duplicates)
    items_affected = len({item_id for item_id, _, _ in duplicates})

    print(f"Found {total} duplicate facet values across {items_affected} items\n")

    for pair, entries in sorted(by_pair.items(), key=lambda x: -len(x[1])):
        print(f"--- {' & '.join(pair)} ({len(entries)} occurrences) ---")
        for item_id, value in sorted(entries):
            print(f"  {item_id}: \"{value}\"")
        print()


if __name__ == "__main__":
    main()
