#!/usr/bin/env python3
"""
Comprehensive data quality analysis for substitutions.json
Outputs issues grouped by type so we can write targeted fixes.
"""
import json, re, sys
from pathlib import Path

ROOT = Path(__file__).parent.parent
DATA = ROOT / "PantryChef/Resources/substitutions.json"

with open(DATA) as f:
    raw = json.load(f)
subs = raw["substitutions"]
names = sorted(subs.keys())

def subs_for(n):
    return [e["substitute"] for e in subs[n]]

# ─────────────────────────────────────────────
# 1. TRUNCATED / GARBLED INGREDIENT NAMES
# e.g. "asparagu", "watercres", "beaujolai", "black sea bas"
# Strategy: look for names whose canonical form (with suffix restored) exists in
# a reference word list, OR that look like partial English words.
# ─────────────────────────────────────────────
KNOWN_TRUNCATIONS = {
    # truncated_key: correct_key
    "asparagu": "asparagus",
    "baby octopu": "baby octopus",
    "watercres": "watercress",
    "beaujolai": "beaujolais",
    "black sea bas": "black sea bass",
    "cape capensi": "cape capensis",
    "molass": "molasses",
    "saccarin": "saccharin",
    "dianthu": "dianthus",
    "blackstrap molass": "blackstrap molasses",
    "barley malt syrup": "barley malt syrup",  # ok
}

print("=== 1. TRUNCATED / GARBLED KEYS ===")
for bad, good in KNOWN_TRUNCATIONS.items():
    if bad in subs:
        status = "CONFLICT" if good in subs else "SAFE_TO_RENAME"
        print(f"  [{status}] '{bad}' -> '{good}'  subs={subs_for(bad)}")

# Also scan for any key that ends in a truncated-looking suffix
def looks_truncated(n):
    # Specifically the pattern of a word cut before its final 's' or 'ss'
    suspicious = [
        r'\bagu$',        # asparagus -> asparagu
        r'\boctopu$',     # octopus
        r'\bcres$',       # watercress
        r'\blai$',        # beaujolais
        r'\bbas$',        # bass
        r'\bpensi$',      # capensis
        r'\blass$',       # molasses (already 'molass')
        r'\barin$',       # saccharin (already 'saccarin' -> watch for 'sacarin')
        r'\banthu$',      # dianthus
    ]
    return any(re.search(p, n) for p in suspicious)

extra_truncated = [n for n in names if looks_truncated(n) and n not in KNOWN_TRUNCATIONS]
if extra_truncated:
    print(f"\n  Other suspicious names:")
    for n in extra_truncated:
        print(f"    '{n}': {subs_for(n)}")

# ─────────────────────────────────────────────
# 2. TYPOS IN SUBSTITUTE VALUES
# ─────────────────────────────────────────────
print("\n=== 2. TYPOS IN SUBSTITUTE VALUES ===")
# Collect all substitute values
all_subs_used = set()
for entries in subs.values():
    for e in entries:
        all_subs_used.add(e["substitute"])

# Find substitute values that look like truncated names
suspicious_sub_values = [s for s in sorted(all_subs_used) if looks_truncated(s)]
for s in suspicious_sub_values:
    print(f"  sub value '{s}' appears truncated")

# Known bad substitute values
BAD_SUB_VALUES = {
    "watercres": "watercress",
    "asparagu": "asparagus",
    "beaujolai": "beaujolais",
    "molass": "molasses",
    "saccarin": "saccharin",
    "blackstrap molass": "blackstrap molasses",
    "baby octopu": "baby octopus",
}
for bad, good in BAD_SUB_VALUES.items():
    users = [k for k, entries in subs.items() for e in entries if e["substitute"] == bad]
    if users:
        print(f"  sub value '{bad}' -> '{good}' used in: {users[:10]}")

# ─────────────────────────────────────────────
# 3. YEAST FRAGMENTATION
# ─────────────────────────────────────────────
print("\n=== 3. YEAST FRAGMENTATION ===")
yeast_keys = [n for n in names if "yeast" in n]
for k in yeast_keys:
    print(f"  '{k}': {subs_for(k)}")

# ─────────────────────────────────────────────
# 4. NON-FOOD ITEMS (kitchen tools etc.)
# ─────────────────────────────────────────────
print("\n=== 4. NON-FOOD ITEMS ===")
non_food_patterns = [
    r'\bpan\b', r'\bpot\b', r'\bknife\b', r'\bboard\b',
    r'\bbrush\b', r'\bbaster\b', r'\bfoil\b', r'\bwrap\b',
    r'\bprocessor\b', r'\bblender\b',
]
for n in names:
    if any(re.search(p, n) for p in non_food_patterns):
        print(f"  '{n}': {subs_for(n)}")

# ─────────────────────────────────────────────
# 5. DUPLICATE / NEAR-DUPLICATE KEYS
# e.g. 'agar' and 'agar agar', 'agave' and 'agave nectar' and 'agave syrup'
# ─────────────────────────────────────────────
print("\n=== 5. FRAGMENTED INGREDIENT FAMILIES ===")
# Group keys by their first significant word
from collections import defaultdict
word_groups = defaultdict(list)
for n in names:
    first_word = n.split()[0]
    word_groups[first_word].append(n)

for word, group in sorted(word_groups.items()):
    if len(group) >= 3:
        print(f"  '{word}' family ({len(group)}): {group}")

# ─────────────────────────────────────────────
# 6. CIRCULAR / SELF-REFERENTIAL pairs  
# ─────────────────────────────────────────────
print("\n=== 6. CIRCULAR/SELF-REF PAIRS ===")
circular = []
for k, entries in subs.items():
    for e in entries:
        s = e["substitute"]
        if s == k:
            circular.append((k, s))
        elif s in subs:
            back = [e2["substitute"] for e2 in subs[s]]
            # A->B->A is the desired bidirectionality; flag A->A (pure circular)
            pass
print(f"  Self-references: {circular}")

# ─────────────────────────────────────────────
# 7. CLEARLY WRONG SUBSTITUTIONS STILL PRESENT
# (run a targeted check on categories likely to have noise)
# ─────────────────────────────────────────────
print("\n=== 7. CROSS-CATEGORY SPOT CHECK ===")
# Meat keys should not substitute to non-meats
meat_keys = ["beef", "pork", "chicken", "lamb", "turkey", "venison", "duck", "veal"]
non_meat_sub_check = ["sugar", "flour", "butter", "oil", "milk", "cream", "water", "vinegar", "yeast"]
for mk in meat_keys:
    if mk in subs:
        bad = [e["substitute"] for e in subs[mk] if e["substitute"] in non_meat_sub_check]
        if bad:
            print(f"  WARNING: '{mk}' -> {bad}")

# Sweet/dessert should not substitute to savory proteins
sweet_keys = ["sugar", "honey", "maple syrup", "vanilla", "chocolate"]
meat_subs = ["beef", "chicken", "pork", "fish", "shrimp", "turkey"]
for sk in sweet_keys:
    if sk in subs:
        bad = [e["substitute"] for e in subs[sk] if e["substitute"] in meat_subs]
        if bad:
            print(f"  WARNING: '{sk}' -> {bad}")

print("\n=== 8. KEYS THAT ARE SUBSTITUTE VALUES BUT HAVE NO OWN ENTRY ===")
# Ingredients mentioned as substitutes but not present as top-level keys
missing_as_key = []
for entries in subs.values():
    for e in entries:
        s = e["substitute"]
        if s not in subs:
            missing_as_key.append(s)

from collections import Counter
miss_count = Counter(missing_as_key)
print(f"  {len(set(missing_as_key))} unique subs missing as top-level keys")
print(f"  Most-mentioned missing subs:")
for s, c in miss_count.most_common(30):
    print(f"    '{s}' referenced {c}x but has no own entry")

print("\nDone.")
