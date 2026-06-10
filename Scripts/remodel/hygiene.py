#!/usr/bin/env python3
"""Stage B: name / alias hygiene on the restructured flat catalog.

  python3 remodel/hygiene.py          # report
  python3 remodel/hygiene.py --apply  # rewrite catalog.json + catalog.source.json
"""
from __future__ import annotations

import argparse
import collections
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR.parent))

from catalog_lib import load_catalog, normalize_lookup_key, save_catalog, slugify  # noqa: E402
from catalog_source_lib import flat_to_source, save_source  # noqa: E402


# Categories whose items are prepared products: a bare `variant` style name there
# (e.g. "original" barbecue sauce) needs parent context, whereas a bare variant name
# in a whole-food category (e.g. "almond" under nut) is a genuine kind to keep.
PREPARED_CATEGORIES = {"Condiments & Sauces", "Beverages", "Alcohol & Spirits", "Snacks"}


def _facet_values(cat: list[dict], *, exclude_variant: bool) -> set[str]:
    values: set[str] = set()
    for x in cat:
        for facet in x.get("facets", []):
            if exclude_variant and facet.get("key") == "variant":
                continue
            for option in facet.get("options", []):
                values.add(normalize_lookup_key(option))
    return values


def _state_modifier_values(cat: list[dict]) -> set[str]:
    """Modifier vocabulary derived from the catalog itself: every value used under
    a STATE facet (any key except `variant`, which holds genuine kinds like
    'ginger'). State words describe a condition and must never be a bare id."""
    return _facet_values(cat, exclude_variant=True)


def repair_ids(cat: list[dict]) -> int:
    """Rename misleading single-token ids (e.g. 'fresh' -> 'fresh-goji-berry').

    "Misleading" is determined data-driven: a single-token id that is a state
    modifier word (per the catalog's own facet vocabulary) whose descriptive name
    slugifies to something else. Ids that already match their name (flour, sauce,
    clove) slugify back to themselves and are left alone."""
    state_values = _state_modifier_values(cat)
    existing = {x["id"] for x in cat}
    renames: dict[str, str] = {}
    for x in cat:
        iid = x["id"]
        # malformed ids (spaces, uppercase) are always repaired; bare single-token
        # state-word ids are repaired when they have a descriptive name.
        malformed = (" " in iid) or (iid != iid.lower())
        bare_state = "-" not in iid and normalize_lookup_key(iid) in state_values
        if not (malformed or bare_state):
            continue
        new = slugify(x["name"])
        if not new or new == iid:
            continue
        if new in existing or new in renames.values():
            new = f"{new}-{iid}".replace(" ", "-")
        renames[iid] = new
        existing.add(new)
    if not renames:
        return 0
    for x in cat:
        if x["id"] in renames:
            x["id"] = renames[x["id"]]
        if x.get("parentIds"):
            x["parentIds"] = [renames.get(p, p) for p in x["parentIds"]]
    return len(renames)


def dedupe_tokens(name: str) -> str:
    """Remove duplicate words preserving first occurrence (case-insensitive)."""
    out, seen = [], set()
    for word in name.split():
        key = word.lower()
        if key in seen:
            continue
        seen.add(key)
        out.append(word)
    return " ".join(out)


def repair_name(name: str) -> str:
    n = " ".join(name.split())
    # strip stray "meatball" stacked into a non-meatball cut name
    # e.g. "chicken meatball chicken breast" -> "chicken breast"
    toks = n.split()
    if "meatball" in [t.lower() for t in toks] and toks[-1].lower() not in {"meatball", "meatballs"}:
        toks = [t for t in toks if t.lower() != "meatball"]
        n = " ".join(toks)
    # collapse any duplicate tokens (adjacent or not)
    if len(n.split()) != len({t.lower() for t in n.split()}):
        n = dedupe_tokens(n)
    return n


def disambiguate_names(cat: list[dict]) -> int:
    """Rename items whose name collides with another item, using parent context
    (e.g. a tomato-sauce child named 'garlic' -> 'garlic tomato sauce'), so a bare
    ingredient term resolves to the real ingredient, not a flavored derivative.
    Also fixes single items named with a bare modifier word ('original' -> 'original
    barbecue sauce')."""
    by_id = {x["id"]: x for x in cat}
    # Bare modifier vocabulary derived from the catalog's own facets: state values
    # are always modifiers; variant values are modifiers only in prepared-product
    # categories (a style like "original"), not whole-food kinds (almond, walnut).
    state_vals = _state_modifier_values(cat)
    variant_vals = _facet_values(cat, exclude_variant=False) - state_vals
    groups: dict[str, list[dict]] = collections.defaultdict(list)
    for x in cat:
        groups[normalize_lookup_key(x["name"])].append(x)
    names_in_use = {k for k, v in groups.items()}
    renamed = 0

    # bare-modifier single names -> prefix with parent context
    for x in cat:
        nm = normalize_lookup_key(x["name"])
        if " " in nm:
            continue
        is_bare = nm in state_vals or (nm in variant_vals and x.get("category") in PREPARED_CATEGORIES)
        if not is_bare:
            continue
        parents = x.get("parentIds", [])
        if not parents or parents[0] not in by_id:
            continue
        new = dedupe_tokens(f"{x['name']} {by_id[parents[0]]['name']}")
        new_key = normalize_lookup_key(new)
        if new_key == nm or new_key in names_in_use:
            continue
        x["name"] = new
        names_in_use.add(new_key)
        renamed += 1
    for nm, items in groups.items():
        if len(items) <= 1:
            continue
        # canonical owner keeps the bare name: prefer no-parent, else id==slug(name),
        # else shortest id.
        def rank(it: dict) -> tuple:
            return (bool(it.get("parentIds")), slugify(it["name"]) != it["id"], len(it["id"]))
        canonical = min(items, key=rank)
        for it in items:
            if it is canonical:
                continue
            parents = it.get("parentIds", [])
            if not parents or parents[0] not in by_id:
                continue
            pname = by_id[parents[0]]["name"]
            if normalize_lookup_key(pname) == nm:
                continue  # self-referential; leave as benign duplicate
            new = dedupe_tokens(f"{it['name']} {pname}")
            new_key = normalize_lookup_key(new)
            if new_key == nm or new_key in names_in_use:
                continue
            it["name"] = new
            names_in_use.add(new_key)
            renamed += 1
    return renamed


def token_overlap(a_tokens: set[str], b_tokens: set[str]) -> float:
    if not a_tokens or not b_tokens:
        return 0.0
    return len(a_tokens & b_tokens) / len(a_tokens | b_tokens)


def run(apply: bool) -> int:
    cat = load_catalog()
    by_id = {x["id"]: x for x in cat}
    name_keys = {normalize_lookup_key(x["name"]): x["id"] for x in cat}

    stats = collections.Counter()

    # 1. repair names
    for x in cat:
        new = repair_name(x["name"])
        if new != x["name"]:
            stats["names_repaired"] += 1
            x["name"] = new

    # 1b. disambiguate duplicate names using parent context
    stats["names_disambiguated"] = disambiguate_names(cat)

    # 1c. repair misleading single-token ids (after names are finalized, so a
    #     fixed name like "sweetened applesauce" yields a proper slug)
    stats["ids_repaired"] = repair_ids(cat)
    by_id = {x["id"]: x for x in cat}
    name_keys = {normalize_lookup_key(x["name"]): x["id"] for x in cat}

    # 2. per-item alias cleanup: drop self-alias, within-item dup, and alias equal to
    #    ANOTHER item's canonical name.
    for x in cat:
        nk = normalize_lookup_key(x["name"])
        cleaned, seen = [], set()
        for a in x.get("aliases", []):
            ak = normalize_lookup_key(a)
            if not ak or ak == nk:
                stats["self_alias_removed"] += 1
                continue
            if ak in seen:
                stats["within_dup_removed"] += 1
                continue
            owner = name_keys.get(ak)
            if owner is not None and owner != x["id"]:
                stats["alias_eq_other_name_removed"] += 1
                continue
            seen.add(ak)
            cleaned.append(a)
        x["aliases"] = cleaned

    # 3. resolve heavily-shared aliases (owned by >= 3 items): keep on best token match.
    alias_owners: dict[str, list[str]] = collections.defaultdict(list)
    for x in cat:
        for a in x.get("aliases", []):
            alias_owners[normalize_lookup_key(a)].append(x["id"])
    name_tokens = {x["id"]: set(normalize_lookup_key(x["name"]).split()) for x in cat}
    for ak, owners in alias_owners.items():
        if len(owners) < 3:
            continue
        atoks = set(ak.split())
        best = max(owners, key=lambda i: (token_overlap(atoks, name_tokens[i]), -len(by_id[i]["name"])))
        for oid in owners:
            if oid == best:
                continue
            item = by_id[oid]
            before = len(item.get("aliases", []))
            item["aliases"] = [a for a in item.get("aliases", []) if normalize_lookup_key(a) != ak]
            stats["shared_alias_pruned"] += before - len(item["aliases"])

    print("=== HYGIENE SUMMARY ===")
    for k, v in stats.most_common():
        print(f"  {k}: {v}")

    if not apply:
        print("\n(dry run — pass --apply to write)")
        return 0

    save_catalog(cat)
    save_source(flat_to_source(cat))
    print(f"\nwrote catalog.json ({len(cat)} items) + catalog.source.json")
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    sys.exit(run(ap.parse_args().apply))
