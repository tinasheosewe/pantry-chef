#!/usr/bin/env python3
"""Narrow search for specific items."""
import sys
sys.path.insert(0, ".")
from ml_approaches.shared import load_usda_foods

foods = load_usda_foods()

print("=== Beef ground 85% ===")
for f in foods:
    d = f.get("description", "")
    if "beef" in d.lower() and "ground" in d.lower() and "85" in d:
        print(f"  {d}")

print("\n=== Turkey breast meat only ===")
for f in foods:
    d = f.get("description", "")
    if "turkey" in d.lower() and "breast" in d.lower() and "meat only" in d.lower():
        print(f"  {d}")

print("\n=== Tea brewed ===")
for f in foods:
    d = f.get("description", "")
    if "tea" in d.lower() and "brewed" in d.lower() and "tap water" in d.lower():
        print(f"  {d}")
