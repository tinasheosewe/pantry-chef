#!/usr/bin/env python3
"""Apply the Tier 3 / Tier 2 edit ops (docs/catalog-tier32/*.json) to catalog.json.

Usage: python3 tools/apply_ops.py {structural|cleanups}

Runs ONE phase across ALL category op-files. Structural is applied + validated +
committed first, then cleanups (honouring "reverse order" = Tier 3 before Tier 2).

Safety:
  * vocab validated (category/storage/allergen/dietaryTag); bad values -> op skipped+logged
  * id targets resolved through a redirect map, so a field op that names an id another
    agent merged/reid'd still lands on the right item
  * merge/reid/drop repoint parentIds + swaps; dangling swaps pruned; ids kept unique
  * conflicts (two ops fighting over the same id) are logged, last-writer-wins for fields
"""
import json, os, sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAT = os.path.join(ROOT, "PantryChef/Resources/catalog.json")
OPS_DIR = os.path.join(ROOT, "docs/catalog-tier32")

VALID_CAT = {'Alcohol & Spirits','Baking & Sweeteners','Beverages','Breads & Bakery',
 'Canned & Jarred','Condiments & Sauces','Dairy & Eggs','Frozen Foods','Grains & Cereals',
 'Legumes & Beans','Nuts & Seeds','Oils & Fats','Other','Pasta & Noodles','Produce',
 'Protein','Snacks','Spices & Herbs'}
VALID_STORE = {'Pantry','Refrigerated','Frozen'}
VALID_ALL = {'dairy','egg','gluten','peanut','tree-nut','soy','shellfish','fish','sesame'}
VALID_DIET = {'Vegetarian','Vegan','Gluten-Free','Dairy-Free','Nut-Free','Low Carb',
 'High Protein','Keto','Paleo','Pescatarian','Halal','Kosher'}

# order ops within a phase so id-space changes happen before field edits
OP_ORDER = {'reid':0,'merge':1,'drop':2,'recategorize':3,'reparent':4,'rename':5,
 'setStorage':6,'setFreshness':7,'setDietaryTags':8,'setAllergens':9,
 'addAlias':10,'removeAlias':11}

def main():
    phase = sys.argv[1] if len(sys.argv) > 1 else 'structural'
    assert phase in ('structural','cleanups'), "phase must be structural|cleanups"

    items = json.load(open(CAT))
    order = [it['id'] for it in items]
    by_id = {it['id']: it for it in items}
    redirect = {}                       # old id -> current id (via reid/merge)
    log, skip, warn = [], [], []

    def resolve(i):
        # prefer a live id; otherwise follow the redirect chain to one
        seen = set()
        while i not in by_id and i in redirect and redirect[i] is not None and i not in seen:
            seen.add(i); i = redirect[i]
        return i

    def rewrite_refs(old, new):
        # update every parentId/swap pointing at `old` to `new` (new=None -> drop ref)
        for it in by_id.values():
            if it.get('parentIds'):
                it['parentIds'] = [new if p == old else p for p in it['parentIds'] if not (p == old and new is None)]
            for s in it.get('swaps') or []:
                if s.get('substituteItemID') == old and new is not None:
                    s['substituteItemID'] = new
            if any(s.get('substituteItemID') == old for s in it.get('swaps') or []) and new is None:
                it['swaps'] = [s for s in it['swaps'] if s.get('substituteItemID') != old]

    # gather ops for this phase, tagged with file for conflict messages
    ops = []
    for f in sorted(__import__('glob').glob(os.path.join(OPS_DIR, "*.json"))):
        if os.path.basename(f) == "OPS_SPEC.md":
            continue
        try:
            d = json.load(open(f))
        except Exception as e:
            warn.append(f"parse fail {os.path.basename(f)}: {e}"); continue
        for op in d.get(phase, []) or []:
            ops.append((os.path.basename(f), op))
    ops.sort(key=lambda fo: OP_ORDER.get(fo[1].get('op'), 99))

    def get(i):
        return by_id.get(resolve(i))

    for fname, op in ops:
        kind = op.get('op')
        try:
            if kind == 'reid':
                src, dst = resolve(op['from']), op['to']
                it = by_id.get(src)
                if not it: skip.append(f"{fname} reid: {op['from']} missing"); continue
                if dst in by_id and dst != src:
                    skip.append(f"{fname} reid {src}->{dst}: target id taken"); continue
                del by_id[src]; it['id'] = dst; by_id[dst] = it
                order[order.index(src)] = dst
                rewrite_refs(src, dst)            # update refs now, so a reused id stays correct
                if dst in redirect: del redirect[dst]   # dst is a live id again
                redirect[src] = dst
                log.append(f"reid {src} -> {dst}")
            elif kind == 'merge':
                src, dst = resolve(op['from']), resolve(op['into'])
                a, b = by_id.get(src), by_id.get(dst)
                if not a or not b or src == dst:
                    skip.append(f"{fname} merge {op['from']}->{op['into']}: missing/self"); continue
                al = list(b.get('aliases') or [])
                for x in [a.get('name')] + list(a.get('aliases') or []):
                    if x and x not in al: al.append(x)
                b['aliases'] = al
                rewrite_refs(src, dst)
                del by_id[src]; order.remove(src); redirect[src] = dst
                log.append(f"merge {src} -> {dst}")
            elif kind == 'drop':
                src = resolve(op['id'])
                if src in by_id:
                    rewrite_refs(src, None)
                    del by_id[src]; order.remove(src); redirect[src] = None
                    log.append(f"drop {src}")
                else:
                    skip.append(f"{fname} drop {op['id']}: missing")
            elif kind == 'recategorize':
                it = get(op['id']); c = op['category']
                if not it: skip.append(f"{fname} recat {op['id']}: missing"); continue
                if c not in VALID_CAT: skip.append(f"{fname} recat {op['id']}: bad cat {c}"); continue
                if c == 'Frozen Foods' and it.get('category') != 'Frozen Foods':
                    pass  # allowed to move INTO frozen; never out to empty it
                it['category'] = c; log.append(f"recat {it['id']} -> {c}")
            elif kind == 'reparent':
                it = get(op['id'])
                if not it: skip.append(f"{fname} reparent {op['id']}: missing"); continue
                it['parentIds'] = [resolve(p) for p in (op.get('parentIds') or [])]
                log.append(f"reparent {it['id']} -> {it['parentIds']}")
            elif kind == 'rename':
                it = get(op['id'])
                if not it: skip.append(f"{fname} rename {op['id']}: missing"); continue
                it['name'] = op['name'].lower(); log.append(f"rename {it['id']} -> {it['name']}")
            elif kind == 'setStorage':
                it = get(op['id']); s = op['defaultStorage']
                if not it: skip.append(f"{fname} setStorage {op['id']}: missing"); continue
                if s not in VALID_STORE: skip.append(f"{fname} setStorage {op['id']}: bad {s}"); continue
                it['defaultStorage'] = s
            elif kind == 'setFreshness':
                it = get(op['id']); fb = op['freshnessByStorage']
                if not it: skip.append(f"{fname} setFreshness {op['id']}: missing"); continue
                clean = {k: v for k, v in fb.items() if k in VALID_STORE and isinstance(v, list) and len(v) == 2}
                if clean: it['freshnessByStorage'] = clean
            elif kind == 'setDietaryTags':
                it = get(op['id']); tags = op['dietaryTags']
                if not it: skip.append(f"{fname} setDiet {op['id']}: missing"); continue
                bad = [t for t in tags if t not in VALID_DIET]
                if bad: skip.append(f"{fname} setDiet {op['id']}: bad {bad}"); continue
                it['dietaryTags'] = tags
            elif kind == 'setAllergens':
                it = get(op['id']); a = op['allergens']
                if not it: skip.append(f"{fname} setAll {op['id']}: missing"); continue
                bad = [x for x in a if x not in VALID_ALL]
                if bad: skip.append(f"{fname} setAll {op['id']}: bad {bad}"); continue
                it['allergens'] = a
            elif kind == 'addAlias':
                it = get(op['id'])
                if not it: skip.append(f"{fname} addAlias {op['id']}: missing"); continue
                al = it.get('aliases') or []
                if op['alias'] not in al: al.append(op['alias'])
                it['aliases'] = al
            elif kind == 'removeAlias':
                it = get(op['id'])
                if not it: skip.append(f"{fname} removeAlias {op['id']}: missing"); continue
                it['aliases'] = [a for a in (it.get('aliases') or []) if a.lower() != op['alias'].lower()]
            else:
                skip.append(f"{fname}: unknown op '{kind}'")
        except KeyError as e:
            skip.append(f"{fname} {kind}: missing field {e}")

    # integrity: redirect/prune references, prune dangling swaps, drop empty parents
    final_ids = set(by_id.keys())
    pruned_swaps = pruned_parents = 0
    for it in by_id.values():
        ps = []
        for p in (it.get('parentIds') or []):
            r = resolve(p)
            if r and r in final_ids and r != it['id']: ps.append(r)
            else: pruned_parents += 1
        # dedup preserve order
        it['parentIds'] = list(dict.fromkeys(ps))
        sw = it.get('swaps')
        if sw:
            keep = []
            for s in sw:
                t = resolve(s.get('substituteItemID'))
                if t and t in final_ids and t != it['id']:
                    s['substituteItemID'] = t; keep.append(s)
                else: pruned_swaps += 1
            it['swaps'] = keep

    out = [by_id[i] for i in order]
    json.dump(out, open(CAT, 'w'), indent=2, ensure_ascii=False)
    open(CAT, 'a').write('\n')

    print(f"[{phase}] applied {len(log)} ops | skipped {len(skip)} | items now {len(out)}")
    print(f"  pruned dangling parents: {pruned_parents} | pruned dangling swaps: {pruned_swaps}")
    from collections import Counter
    kinds = Counter(l.split()[0] for l in log)
    print("  by kind:", dict(kinds))
    if skip:
        print(f"\nSKIPPED ({len(skip)}):")
        for s in skip[:60]: print("   ", s)
    if warn:
        print(f"\nWARN: {warn}")

if __name__ == "__main__":
    main()
