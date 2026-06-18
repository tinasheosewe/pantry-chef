#!/usr/bin/env python3
"""Fold docs/catalog-enrich/*.json (the fleshed-out versions of the Tier-1 newItems)
back into PantryChef/Resources/catalog.json.

Policy (deliberately conservative — never clobber or silently re-home an item):
  * id exists, SAME category  -> merge in place (existing as base, enriched richness
    overlaid; enriched empties never wipe a populated field).
  * id exists, DIFFERENT cat   -> SKIP, log as a Tier-3 collision (e.g. peanut-butter
    lives in Condiments but Nuts enriched it; mirin Condiments vs Alcohol; fresh herbs
    Spices vs Produce). These are structural decisions for the Tier-3 pass.
  * id absent                  -> add as a new item.
  * same id in >1 enrich file  -> first writer wins (legumes.json is ordered first so
    its `edamame` — a soybean/legume — is the canonical one).

Also sanitises the two decode-breakers found in the enrich output:
  allergen 'tree nut' -> 'tree-nut';  defaultUnit 'packet' -> 'pkg', 'jar' -> dropped
(MeasurementUnit has no 'jar'/'packet' raw; defaultUnit is optional so dropping is safe).
"""
import json, glob, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAT = os.path.join(ROOT, "PantryChef/Resources/catalog.json")
ENRICH = os.path.join(ROOT, "docs/catalog-enrich")

VALID_UNIT = {'tsp','tbsp','cup','fl oz','ml','L','g','kg','oz','lb','piece','whole',
              'loaf','slice','clove','bunch','can','pkg','pinch','splash'}
ALL_FIX = {'tree nut': 'tree-nut'}
UNIT_FIX = {'packet': 'pkg'}   # 'jar' has no MeasurementUnit equivalent -> drop

def sanitize(it):
    if it.get('allergens'):
        it['allergens'] = [ALL_FIX.get(a, a) for a in it['allergens']]
    u = it.get('defaultUnit')
    if u is not None:
        u = UNIT_FIX.get(u, u)
        if u in VALID_UNIT:
            it['defaultUnit'] = u
        else:
            it.pop('defaultUnit', None)
    return it

def meaningful(v):
    if v is None: return False
    if isinstance(v, (list, str, dict)) and len(v) == 0: return False
    return True

def main():
    items = json.load(open(CAT))
    assert isinstance(items, list), "catalog.json is expected to be a bare array"
    order = [it['id'] for it in items]
    by_id = {it['id']: it for it in items}
    start_count = len(items)

    files = glob.glob(os.path.join(ENRICH, "*.json"))
    files.sort(key=lambda f: (os.path.basename(f) != 'legumes.json', f))  # edamame: legumes wins

    seen = set()
    n_update = n_new = 0
    collisions = []
    dups = []
    for f in files:
        for raw in json.load(open(f)):
            it = sanitize(dict(raw))
            iid = it['id']
            if iid in seen:
                dups.append((iid, os.path.basename(f)))
                continue
            ex = by_id.get(iid)
            if ex is not None:
                if ex.get('category') == it.get('category'):
                    merged = dict(ex)
                    for k, v in it.items():
                        if meaningful(v):
                            merged[k] = v
                    by_id[iid] = merged
                    seen.add(iid); n_update += 1
                else:
                    collisions.append((iid, ex.get('category'), it.get('category'), os.path.basename(f)))
            else:
                by_id[iid] = it
                order.append(iid)
                seen.add(iid); n_new += 1

    # Prune dangling swap targets; report unresolved parentIds.
    final_ids = set(by_id.keys())
    pruned_swaps = 0
    bad_parents = []
    for iid, it in by_id.items():
        sw = it.get('swaps')
        if sw:
            keep = [s for s in sw if s.get('substituteItemID') in final_ids]
            pruned_swaps += len(sw) - len(keep)
            it['swaps'] = keep
        for p in (it.get('parentIds') or []):
            if p not in final_ids:
                bad_parents.append((iid, p))

    out = [by_id[i] for i in order]
    json.dump(out, open(CAT, 'w'), indent=2, ensure_ascii=False)
    open(CAT, 'a').write('\n')

    print(f"catalog: {start_count} -> {len(out)} items (+{len(out)-start_count})")
    print(f"  updated in place : {n_update}")
    print(f"  added new        : {n_new}")
    print(f"  pruned dangling swaps: {pruned_swaps}")
    print(f"\nSKIPPED category collisions (kept existing; Tier-3 decisions): {len(collisions)}")
    for c in collisions: print("   ", c)
    print(f"\nCross-file duplicate ids (first writer won): {len(dups)}")
    for d in dups: print("   ", d)
    if bad_parents:
        print(f"\n!! UNRESOLVED parentIds: {len(bad_parents)}")
        for b in bad_parents[:40]: print("   ", b)
    else:
        print("\nall parentIds resolve.")

if __name__ == "__main__":
    main()
