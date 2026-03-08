# Third-Party Data Licenses

## MISKG — Multimodal Ingredient Substitution Knowledge Graph

- **Source**: https://www.kaggle.com/datasets/kanakraj/multimodal-ingredient-substitution
- **License**: [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/)
- **Usage**: Ingredient substitution pairs in `PantryChef/Resources/substitutions.json`
- **Preprocessing**: `Scripts/preprocess_miskg.py` merges MISKG data with hand-curated entries

### ⚠️  Commercialization Note

The MISKG dataset is licensed under **Creative Commons Attribution-NonCommercial 4.0**.
This means the data **cannot be used for commercial purposes** in its current form.

**Before monetization**, you must either:
1. Replace MISKG-sourced entries with a commercially-licensed dataset, OR
2. Contact the MISKG authors to negotiate a commercial license, OR
3. Build a fully original substitution database (e.g., via AI generation with human review)

Hand-curated entries (tagged `"enriched": true` in the JSON) are original work and
have no licensing restrictions.
