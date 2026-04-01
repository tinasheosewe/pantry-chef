"""Show remaining taxonomy parse failures by running evaluation directly."""
from ml_approaches.evaluate import evaluate_parse

result = evaluate_parse("taxonomy")
failed = [s for s in result.case_scores if not s.passed]
print(f"Total golden cases: {len(result.case_scores)}, Passed: {len(result.case_scores) - len(failed)}, Failed: {len(failed)}\n")

for s in failed:
    print(f"  desc='{s.usda_desc[:60]:60s}'")
    print(f"    expected='{s.expected_name:30s}'  got='{s.actual_name:30s}'  score={s.name_score:.0f}")
    print(f"    base_match={s.base_match}  brand_det={s.brand_detected}")
    print()
