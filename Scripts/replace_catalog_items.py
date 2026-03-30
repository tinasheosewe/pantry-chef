#!/usr/bin/env python3
"""Replace allItems content in PantryCatalog.swift with generated items."""

import sys
from pathlib import Path

def main():
    base = Path(__file__).parent.parent
    catalog_path = base / "PantryChef" / "Models" / "PantryCatalog.swift"
    generated_path = base / "Scripts" / "generated_catalog_items.swift"

    # Read files
    with open(catalog_path) as f:
        lines = f.readlines()

    with open(generated_path) as f:
        # Skip the header comments (first 3 lines)
        generated_lines = f.readlines()[3:]

    # Find the start and end of allItems
    start_line = None
    end_line = None

    for i, line in enumerate(lines):
        if "static let allItems: [PantryCatalogItemDefinition] = [" in line:
            start_line = i
        elif start_line is not None and line.strip() == "]":
            # Check if nearby lines contain itemsByID to confirm this is the end
            for j in range(i + 1, min(i + 5, len(lines))):
                if "itemsByID" in lines[j]:
                    end_line = i
                    break
            if end_line is not None:
                break

    if start_line is None or end_line is None:
        print(f"Could not find allItems: start={start_line}, end={end_line}")
        sys.exit(1)

    print(f"Found allItems at lines {start_line + 1} to {end_line + 1}")

    # Build new file
    new_lines = lines[:start_line + 1]  # Include "static let allItems: [PantryCatalogItemDefinition] = ["
    new_lines.extend(generated_lines)  # Add generated items
    new_lines.append("    ]\n")  # Close the array
    new_lines.extend(lines[end_line + 1:])  # Rest of the file

    # Write back
    with open(catalog_path, "w") as f:
        f.writelines(new_lines)

    print(f"Replaced {end_line - start_line - 1} lines with {len(generated_lines)} lines of generated items")


if __name__ == "__main__":
    main()
