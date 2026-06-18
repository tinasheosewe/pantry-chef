#!/usr/bin/env python3
"""Post-enrichment invariant repair on PantryChef/Resources/catalog.json.

Run AFTER tools/integrate_enrich.py. Fixes the four CatalogInvariantTests failures
the enrichment introduced, without reducing richness:

  1. Facet orthogonality — a value must live under exactly one facet key catalog-wide
     ("whole" is the allowed exception). Enrichment agents each chose keys
     independently, so values like 'dried'/'fresh'/'ground' straddled keys. We
     canonicalise every value to one key, taken from the pre-enrichment catalog
     (which passed) where the value existed there, else the majority key now.
  2. Name round-trip / single-word foreign-category — strip hijacking aliases so a
     name like 'pomegranate' or 'berbere' resolves to its own item, not to
     pomegranate-juice / berbere-paste.
  3. Bare state-word id/name — re-id 'original' -> 'original-baked-beans' (fixing
     references), and restore parentIds:[] on croutons / half-and-half (Tier-1's
     decision, which enrichment re-parented).
"""
import json, os
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAT = os.path.join(ROOT, "PantryChef/Resources/catalog.json")
BEFORE = "/tmp/catalog.before.json"

# Names whose resolution is hijacked by another item's alias (from the test output).
HIJACKED_NAMES = {
    "almond flour", "berbere", "cheese sauce", "nacho cheese sauce", "pomace oil",
    "pomegranate", "rye groats", "sticky rice", "chickpea flour", "hazelnut flour",
    "kingfish",
}

def canon_map(before_items, final_items):
    """value(lowercased, != 'whole') -> the single facet key it should live under."""
    before_key = {}
    for it in before_items:
        for f in it.get("facets") or []:
            for o in f.get("options") or []:
                lo = o.lower()
                if lo == "whole":
                    continue
                before_key.setdefault(lo, f["key"])  # before passed: one key per value
    final_keys = {}
    for it in final_items:
        for f in it.get("facets") or []:
            for o in f.get("options") or []:
                lo = o.lower()
                if lo == "whole":
                    continue
                final_keys.setdefault(lo, Counter())[f["key"]] += 1
    canon = {}
    for v, counter in final_keys.items():
        if v in before_key:
            canon[v] = before_key[v]
        else:
            # purely-new value: majority key, ties broken alphabetically for determinism
            best = sorted(counter.items(), key=lambda kv: (-kv[1], kv[0]))[0][0]
            canon[v] = best
    return canon

def regroup_facets(item, canon):
    """Rebuild facets so each option sits under canon[option] ('whole' stays put)."""
    grouped = {}          # key -> ordered unique options
    order = []            # preserve first-seen key order
    for f in item.get("facets") or []:
        k0 = f["key"]
        for o in f.get("options") or []:
            tgt = k0 if o.lower() == "whole" else canon.get(o.lower(), k0)
            if tgt not in grouped:
                grouped[tgt] = []
                order.append(tgt)
            if o not in grouped[tgt]:
                grouped[tgt].append(o)
    item["facets"] = [{"key": k, "options": grouped[k]} for k in order]
    # defaultSelections + facetAliases: point key at the canonical key for the value
    for sel in item.get("defaultSelections") or []:
        if sel.get("value", "").lower() != "whole":
            sel["key"] = canon.get(sel["value"].lower(), sel["key"])
    for fa in item.get("facetAliases") or []:
        for sel in fa.get("facets") or []:
            if sel.get("value", "").lower() != "whole":
                sel["key"] = canon.get(sel["value"].lower(), sel["key"])

def main():
    items = json.load(open(CAT))
    before = json.load(open(BEFORE))
    canon = canon_map(before, items)

    # 1. Facet orthogonality
    for it in items:
        regroup_facets(it, canon)

    # 2. Strip hijacking aliases (an item must not claim another item's exact name,
    #    unless that's its own name).
    n_alias = 0
    for it in items:
        nm = it.get("name", "").lower()
        kept = []
        for a in it.get("aliases") or []:
            if a.lower() in HIJACKED_NAMES and a.lower() != nm:
                n_alias += 1
                continue
            kept.append(a)
        if "aliases" in it:
            it["aliases"] = kept

    # 3a. Re-id 'original' -> 'original-baked-beans' + fix references
    OLD, NEW = "original", "original-baked-beans"
    if any(it["id"] == OLD for it in items):
        for it in items:
            if it["id"] == OLD:
                it["id"] = NEW
            it["parentIds"] = [NEW if p == OLD else p for p in (it.get("parentIds") or [])]
            for s in it.get("swaps") or []:
                if s.get("substituteItemID") == OLD:
                    s["substituteItemID"] = NEW

    # 3b. Restore parentIds:[] on croutons / half-and-half (single-word state-word names)
    for it in items:
        if it["id"] in ("croutons", "half-and-half"):
            it["parentIds"] = []

    json.dump(items, open(CAT, "w"), indent=2, ensure_ascii=False)
    open(CAT, "a").write("\n")
    print(f"items: {len(items)} | canon values mapped: {len(canon)} | aliases stripped: {n_alias}")

if __name__ == "__main__":
    main()
