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
import remodel.vocab as V  # noqa: E402

# Single-token ids that are really state/modifier words (misleading leftovers).
BAD_BARE_IDS = (V.COLOR | V.GRADE | V.FAT | V.TEXTURE | V.PREPARATION
                | set(V.PROCESSING) | set(V.PRESERVATION) | V.FORM
                | {"baby", "large", "jumbo", "mini", "blend", "small", "medium",
                   "big", "giant", "whole", "half"})


def repair_ids(cat: list[dict]) -> int:
    """Rename misleading single-token ids (e.g. 'fresh' -> 'fresh-goji-berry')."""
    existing = {x["id"] for x in cat}
    renames: dict[str, str] = {}
    for x in cat:
        iid = x["id"]
        # malformed ids (spaces, uppercase) are always repaired; bare single-token
        # state-word ids are repaired when they have a descriptive name.
        malformed = (" " in iid) or (iid != iid.lower())
        bare_state = "-" not in iid and iid in BAD_BARE_IDS
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


# Bare modifier/quality words that must never stand alone as an item name.
BARE_MODIFIER_NAMES = (V.COLOR | V.GRADE | V.FAT | V.TEXTURE | V.PREPARATION
                       | set(V.PROCESSING) | set(V.PRESERVATION)
                       | {"original", "classic", "premium", "deluxe", "signature",
                          "authentic", "gourmet", "homestyle", "assorted", "mixed",
                          "regular", "standard", "traditional"})


def disambiguate_names(cat: list[dict]) -> int:
    """Rename items whose name collides with another item, using parent context
    (e.g. a tomato-sauce child named 'garlic' -> 'garlic tomato sauce'), so a bare
    ingredient term resolves to the real ingredient, not a flavored derivative.
    Also fixes single items named with a bare modifier word ('original' -> 'original
    barbecue sauce')."""
    by_id = {x["id"]: x for x in cat}
    groups: dict[str, list[dict]] = collections.defaultdict(list)
    for x in cat:
        groups[normalize_lookup_key(x["name"])].append(x)
    names_in_use = {k for k, v in groups.items()}
    renamed = 0

    # bare-modifier single names -> prefix with parent context
    for x in cat:
        nm = normalize_lookup_key(x["name"])
        if nm not in BARE_MODIFIER_NAMES:
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

    # 0. repair misleading single-token ids
    stats["ids_repaired"] = repair_ids(cat)
    by_id = {x["id"]: x for x in cat}

    # 1. repair names
    for x in cat:
        new = repair_name(x["name"])
        if new != x["name"]:
            stats["names_repaired"] += 1
            x["name"] = new

    # 1b. disambiguate duplicate names using parent context
    stats["names_disambiguated"] = disambiguate_names(cat)

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
