#!/usr/bin/env python3
"""Analyze ingredient_frequencies.json to identify cleanup needs."""

import json
import random

with open("Scripts/ingredient_frequencies.json") as f:
    data = json.load(f)

names = {name: count for name, count in data}

print("=== DUPLICATES: singular/plural ===")
pairs = [
    ("egg", "eggs"), ("onion", "onions"), ("tomato", "tomatoes"),
    ("potato", "potatoes"), ("carrot", "carrots"), ("banana", "bananas"),
    ("apple", "apples"), ("mushroom", "mushrooms"), ("pecan", "pecans"),
    ("walnut", "walnuts"), ("clove", "cloves"), ("bay leaf", "bay leaves"),
    ("green onion", "green onions"), ("chicken breast", "chicken breasts"),
    ("scallion", "scallions"), ("shallot", "shallots"),
]
for s, p in pairs:
    sc = names.get(s, 0)
    pc = names.get(p, 0)
    print(f"  {s:<25s} {sc:>7,}  +  {p:<25s} {pc:>7,}  = {sc+pc:>8,}")

print("\n=== DUPLICATES: qualifier variants ===")
groups = [
    ["salt", "kosher salt", "sea salt", "table salt"],
    ["pepper", "black pepper", "ground black pepper", "freshly ground black pepper", "ground pepper"],
    ["butter", "unsalted butter", "salted butter"],
    ["sugar", "white sugar", "granulated sugar"],
    ["cinnamon", "ground cinnamon"],
    ["cumin", "ground cumin"],
    ["olive oil", "extra-virgin olive oil", "extra virgin olive oil"],
    ["cilantro", "fresh cilantro"],
    ["basil", "fresh basil", "dried basil"],
    ["ginger", "ground ginger", "fresh ginger"],
    ["nutmeg", "ground nutmeg"],
    ["parsley", "fresh parsley", "dried parsley"],
]
for group in groups:
    parts = [f"{g}={names.get(g,0):,}" for g in group]
    total = sum(names.get(g, 0) for g in group)
    print(f"  {' | '.join(parts)}  => {total:,}")

print("\n=== JUNK / NON-INGREDIENTS ===")
junk_candidates = [
    "water", "boiling water", "cold water", "hot water", "warm water",
    "ice", "soda", "all-purpose", "\u00bc", "cooking spray",
    "nonstick cooking spray", "oleo", "hamburger",
]
for j in junk_candidates:
    print(f"  {j:<35s} {names.get(j, 0):>7,}")

print("\n=== PREPARED FOODS (not base ingredients) ===")
prepared = [
    "cream of mushroom soup", "cream of chicken soup", "italian dressing",
    "ranch dressing", "french dressing", "cake mix", "pie crust",
    "biscuit mix", "brownie mix", "pizza dough",
]
for p in prepared:
    print(f"  {p:<40s} {names.get(p, 0):>7,}")

print("\n=== TAIL: items appearing 1-5 times (sample) ===")
tail = [(n, c) for n, c in data if c <= 5]
print(f"  Total: {len(tail):,} items with count <= 5")
random.seed(42)
sample = random.sample(tail, min(20, len(tail)))
for n, c in sorted(sample, key=lambda x: -x[1]):
    print(f"  {n:<55s} {c}")

print("\n=== FREQUENCY BRACKETS ===")
for lo, hi, label in [
    (100000, 9999999, "100k+"),
    (10000, 99999, "10k-100k"),
    (1000, 9999, "1k-10k"),
    (100, 999, "100-999"),
    (10, 99, "10-99"),
    (2, 9, "2-9"),
    (1, 1, "exactly 1"),
]:
    n = sum(1 for _, c in data if lo <= c <= hi)
    print(f"  {label:>12s}: {n:>6,}")
