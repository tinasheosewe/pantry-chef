"""Show hybrid output summary for documentation."""
import json

groups = json.load(open("ml_outputs/hybrid_groups.json"))
sizes = [len(g["members"]) for g in groups]

print(f"Total groups: {len(groups)}")
print(f"Total items: {sum(sizes)}")
print(f"Avg group size: {sum(sizes)/len(sizes):.1f}")
print(f"Singletons: {sum(1 for s in sizes if s == 1)}")
print(f"Groups with 2+: {sum(1 for s in sizes if s >= 2)}")
print(f"Groups with 5+: {sum(1 for s in sizes if s >= 5)}")
print(f"Groups with 10+: {sum(1 for s in sizes if s >= 10)}")
print()

sorted_groups = sorted(groups, key=lambda g: len(g["members"]), reverse=True)

print("=== 5 LARGEST GROUPS ===")
for g in sorted_groups[:5]:
    print(f'{g["group_name"]} ({len(g["members"])} members):')
    for m in g["members"][:3]:
        print(f'  - {m["parsed_name"]}')
    if len(g["members"]) > 3:
        print(f'  ... and {len(g["members"]) - 3} more')
    print()

print("=== MEDIUM GROUPS WITH FACETS ===")
count = 0
for g in sorted_groups:
    if 4 <= len(g["members"]) <= 10 and g.get("suggested_facets"):
        print(f'{g["group_name"]} ({len(g["members"])} members):')
        print(f'  Facets: {g["suggested_facets"]}')
        for m in g["members"][:5]:
            attrs = m.get("distinguishing_attrs", {})
            attr_str = ", ".join(f"{k}={v}" for k, v in attrs.items()) if attrs else ""
            print(f'  - {m["parsed_name"]}' + (f" [{attr_str}]" if attr_str else ""))
        print()
        count += 1
        if count >= 5:
            break
