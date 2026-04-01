"""Debug the remaining 4 taxonomy failures."""
from ml_approaches.parse_taxonomy import _parse_single

tests = [
    ("Cheese, cheddar (Includes foods for USDA's Food Distribution Program)", "Dairy and Egg Products"),
    ("Yogurt, Greek, plain, nonfat", "Dairy and Egg Products"),
    ("Oil, olive, salad or cooking", "Fats and Oils"),
    ("Nuts, almonds, dry roasted, with salt added", "Nut and Seed Products"),
]
for desc, cat in tests:
    result = _parse_single(desc, cat, 0)
    r = result
    print("=" * 60)
    print("INPUT: ", desc)
    print("OUTPUT:", repr(r.parsed_name), "base=", repr(r.parsed_base))
    print("  quals=", r.qualifiers, "form=", repr(r.form))
    print("  noise=", r.noise_removed)
    print()
