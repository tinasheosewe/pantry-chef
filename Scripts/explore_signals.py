#!/usr/bin/env python3
"""Explore ConceptNet + MISKG bidirectionality signals."""
import json
from collections import Counter, defaultdict

with open("Scripts/miskg_data/Competition-Dataset/conceptnet.json") as f:
    cn = json.load(f)

# Build name -> entry lookup
name_to_entry = {}
for entry in cn.values():
    node_id = entry.get("@id", "")
    if node_id.startswith("/c/en/"):
        name = node_id[6:]
        name_to_entry[name] = entry

# All relation types
rel_counter = Counter()
for entry in cn.values():
    for edge in entry.get("edges", []):
        rel_counter[edge["rel"]["label"]] += 1

print("All ConceptNet relation types:")
for rel, count in rel_counter.most_common(30):
    print(f"  {count:6d}  {rel}")

# Check butter
print("\nButter SimilarTo/IsA/Synonym edges:")
butter = name_to_entry.get("butter")
if butter:
    for e in butter.get("edges", []):
        if e["rel"]["label"] in ("SimilarTo", "Synonym", "IsA", "RelatedTo"):
            start = e["start"]["label"]
            end = e["end"]["label"]
            print(f"  {e['rel']['label']}: {start} -> {end}")

# How many pairs are bidirectional in MISKG?
print("\n--- MISKG bidirectionality ---")
with open("Scripts/miskg_data/Competition-Dataset/substitution_pairs.json") as f:
    pairs = json.load(f)

directed = defaultdict(set)
for p in pairs:
    ingr = p["ingredient"].lower().strip()
    sub = p["substitution"].lower().strip()
    directed[ingr].add(sub)

both_ways = 0
one_way = 0
for ingr, subs in directed.items():
    for sub in subs:
        if ingr in directed.get(sub, set()):
            both_ways += 1
        else:
            one_way += 1

print(f"  Bidirectional pairs: {both_ways}")
print(f"  One-directional pairs: {one_way}")
print(f"  Ratio: {both_ways/(both_ways+one_way)*100:.1f}% bidirectional")

# Show examples of bidirectional pairs (more likely to be real substitutions)
print("\nSample bidirectional pairs:")
n = 0
for ingr in sorted(directed.keys()):
    for sub in sorted(directed[ingr]):
        if ingr in directed.get(sub, set()) and ingr < sub:
            print(f"  {ingr} <-> {sub}")
            n += 1
            if n >= 20:
                break
    if n >= 20:
        break
