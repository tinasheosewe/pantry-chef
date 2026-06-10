#!/usr/bin/env python3
"""Structural remodel of the ingredient catalog (Stage A).

Reads Scripts/remodel/baseline_catalog.json and produces a restructured flat
catalog: facet vocabulary remapped to the new taxonomy, adds-nothing leaves
collapsed into facet values on their parents, defaultSelections remapped.

  python3 remodel/build.py            # dry-run decision report, writes nothing
  python3 remodel/build.py --apply    # write catalog.json + catalog.source.json
"""
from __future__ import annotations

import argparse
import collections
import copy
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR.parent))

import vocab  # noqa: E402
from catalog_lib import normalize_lookup_key, save_catalog  # noqa: E402
from catalog_source_lib import flat_to_source, save_source  # noqa: E402

BASELINE = SCRIPT_DIR / "baseline_catalog.json"
REDIRECTS_PATH = SCRIPT_DIR / "redirects.json"
DECISIONS_PATH = SCRIPT_DIR / "decisions.json"


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def load_baseline() -> list[dict]:
    with open(BASELINE, encoding="utf-8") as f:
        return json.load(f)


def facet_map(item: dict) -> dict[str, set[str]]:
    return {f["key"]: set(f.get("options", [])) for f in item.get("facets", [])}


def single_parent(item: dict) -> str | None:
    ps = item.get("parentIds", [])
    return ps[0] if len(ps) == 1 else None


def children_map(by_id: dict[str, dict]) -> dict[str, list[str]]:
    cm: dict[str, list[str]] = collections.defaultdict(list)
    for iid, item in by_id.items():
        for p in item.get("parentIds", []):
            cm[p].append(iid)
    return cm


def ancestor_chain(iid: str, by_id: dict[str, dict]) -> list[str]:
    chain, cur, seen = [], single_parent(by_id[iid]), set()
    while cur and cur in by_id and cur not in seen:
        seen.add(cur)
        chain.append(cur)
        cur = single_parent(by_id[cur])
    return chain


def compute_own(by_id: dict[str, dict]) -> dict[str, dict[str, set[str]]]:
    """Own facet contribution per node = node facets minus single-parent ancestors'."""
    own: dict[str, dict[str, set[str]]] = {}
    for iid, item in by_id.items():
        node = facet_map(item)
        if len(item.get("parentIds", [])) >= 2:
            own[iid] = {k: set(v) for k, v in node.items()}
            continue
        inherited: dict[str, set[str]] = {}
        for anc in ancestor_chain(iid, by_id):
            for k, v in facet_map(by_id[anc]).items():
                inherited.setdefault(k, set()).update(v)
        own[iid] = {k: {x for x in vals if x not in inherited.get(k, set())}
                    for k, vals in node.items()
                    if {x for x in vals if x not in inherited.get(k, set())}}
    return own


def remap_facets(facets: dict[str, set[str]]) -> dict[str, set[str]]:
    out: dict[str, set[str]] = {}
    for key, values in facets.items():
        for value in values:
            res = vocab.classify_value(key, value)
            if res is None:
                continue
            nk, nv = res
            out.setdefault(nk, set()).add(nv)
    return out


def distinguishing_token(child: dict, parent: dict) -> str:
    pw = set(normalize_lookup_key(parent["name"]).split())
    resid = [w for w in normalize_lookup_key(child["name"]).split() if w not in pw]
    return " ".join(resid) if resid else normalize_lookup_key(child["name"])


def decide_collapse(child: dict, parent: dict, token: str) -> tuple[str, str] | None:
    if not token:
        return None
    fat = vocab.fat_from_name(child["name"])
    if fat is not None:
        return ("fat", fat)
    if token == "whole" and "milk" in parent["name"].lower():
        return ("fat", "whole")
    key = vocab.classify_token(token)
    if key is not None:
        return (key, vocab.lemma(token))
    if parent.get("category") in vocab.PREPARED_CATEGORIES or parent["id"] in vocab.VARIANT_PARENT_IDS:
        return ("variant", token)
    return None


def safe_aliases_for_facet(child: dict, parent: dict) -> list[str]:
    """Leaf aliases worth keeping as facetAlias text (skip ones that collapse to the
    parent name or are already parent aliases)."""
    pkey = normalize_lookup_key(parent["name"])
    parent_alias_keys = {normalize_lookup_key(a) for a in parent.get("aliases", [])}
    out, seen = [], set()
    for a in [child["name"]] + child.get("aliases", []):
        k = normalize_lookup_key(a)
        if not k or k == pkey or k in parent_alias_keys or k in seen:
            continue
        seen.add(k)
        out.append(a)
    return out


# ---------------------------------------------------------------------------
# main transform
# ---------------------------------------------------------------------------
def transform(items: list[dict]) -> tuple[list[dict], dict, dict]:
    by_id = {x["id"]: x for x in items}
    cm = children_map(by_id)
    own = {iid: remap_facets(f) for iid, f in compute_own(by_id).items()}
    # all normalized name keys (to avoid creating a facetAlias token that collides
    # with a real ingredient name, e.g. variant "honey" vs the honey ingredient).
    name_keys = {normalize_lookup_key(x["name"]) for x in items}

    facet_aliases: dict[str, list[dict]] = collections.defaultdict(list)
    redirects: dict[str, dict] = {}
    decisions = {"collapse": [], "keep_kind": [], "keep_own": []}
    deleted: set[str] = set()

    for iid, item in list(by_id.items()):
        p = single_parent(item)
        if not p or p not in by_id or cm.get(iid):
            continue
        if own.get(iid):
            decisions["keep_own"].append(iid)
            continue
        parent = by_id[p]
        token = distinguishing_token(item, parent)
        decision = decide_collapse(item, parent, token)
        if decision is None:
            decisions["keep_kind"].append(iid)
            continue
        key, val = decision
        own.setdefault(p, {}).setdefault(key, set()).add(val)
        texts = safe_aliases_for_facet(item, parent)
        # Also let the bare token resolve (e.g. "spaghetti" -> pasta+variant:spaghetti),
        # but only if it does not collide with a real ingredient name.
        if normalize_lookup_key(val) not in name_keys:
            texts.append(val)
        for text in texts:
            facet_aliases[p].append({"text": text, "facets": [{"key": key, "value": val}]})
        redirects[iid] = {"to": p, "facets": [{"key": key, "value": val}]}
        decisions["collapse"].append({"id": iid, "to": p, "key": key, "value": val})
        deleted.add(iid)

    # Build the new flat catalog from survivors.
    survivors = [x for x in items if x["id"] not in deleted]
    by_id = {x["id"]: x for x in survivors}

    # Re-materialize facets = union of own over single-parent ancestor chain (+ self).
    out: list[dict] = []
    for item in survivors:
        iid = item["id"]
        new = copy.deepcopy(item)
        if len(item.get("parentIds", [])) >= 2:
            eff = {k: set(v) for k, v in own.get(iid, {}).items()}
        else:
            eff = {}
            for src in [iid] + ancestor_chain(iid, by_id):
                for k, v in own.get(src, {}).items():
                    eff.setdefault(k, set()).update(v)
        # facets list, ordered by FACET_KEYS
        new["facets"] = [
            {"key": k, "options": sorted(eff[k])}
            for k in vocab.FACET_KEYS if eff.get(k)
        ]
        # remap + prune defaultSelections
        ds_new, seen = [], set()
        for sel in item.get("defaultSelections", []):
            res = vocab.classify_value(sel["key"], sel["value"])
            if not res:
                continue
            nk, nv = res
            if nv in eff.get(nk, set()) and nk not in seen:
                seen.add(nk)
                ds_new.append({"key": nk, "value": nv})
        if ds_new:
            new["defaultSelections"] = ds_new
        else:
            new.pop("defaultSelections", None)
        # facetAliases (dedup by (text,key,value))
        fa = item.get("facetAliases", []) + facet_aliases.get(iid, [])
        dedup, fseen = [], set()
        for entry in fa:
            sel = entry.get("facets", [{}])[0]
            sig = (normalize_lookup_key(entry["text"]), sel.get("key"), sel.get("value"))
            if sig in fseen:
                continue
            # only keep aliases whose value exists in effective facets
            if sel.get("value") not in eff.get(sel.get("key"), set()):
                continue
            fseen.add(sig)
            dedup.append(entry)
        if dedup:
            new["facetAliases"] = dedup
        else:
            new.pop("facetAliases", None)
        out.append(new)

    return out, redirects, decisions


def run(apply: bool) -> int:
    items = load_baseline()
    new_items, redirects, decisions = transform(items)

    print("=== REMODEL SUMMARY ===")
    print(f"  baseline items : {len(items)}")
    print(f"  collapsed      : {len(decisions['collapse'])}")
    print(f"  kept (kind)    : {len(decisions['keep_kind'])}")
    print(f"  kept (own fac) : {len(decisions['keep_own'])}")
    print(f"  final items    : {len(new_items)}")

    # facet key distribution after transform
    keydist = collections.Counter()
    for it in new_items:
        for f in it["facets"]:
            keydist[f["key"]] += len(f["options"])
    print("  facet option counts:", dict(keydist))

    if not apply:
        print("\n(dry run — pass --apply to write)")
        return 0

    save_catalog(new_items)
    source = flat_to_source(new_items)
    save_source(source)
    with open(REDIRECTS_PATH, "w") as f:
        json.dump(redirects, f, indent=2, ensure_ascii=False)
    with open(DECISIONS_PATH, "w") as f:
        json.dump(decisions, f, indent=2, ensure_ascii=False)
    print(f"\nwrote catalog.json ({len(new_items)} items), catalog.source.json, "
          f"redirects.json ({len(redirects)})")
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    sys.exit(run(ap.parse_args().apply))
