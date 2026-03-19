#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
from pathlib import Path


def load_report(xcresult_path: Path) -> object:
    command = ["xcrun", "xccov", "view", "--report", "--json", str(xcresult_path)]
    completed = subprocess.run(command, capture_output=True, text=True)
    if completed.returncode != 0:
        sys.stderr.write(completed.stderr)
        raise SystemExit(completed.returncode)
    return json.loads(completed.stdout)


def iter_targets(node: object):
    if isinstance(node, list):
        for item in node:
            yield from iter_targets(item)
        return
    if not isinstance(node, dict):
        return
    if "targets" in node:
        yield from iter_targets(node["targets"])
        return
    if "name" in node and "lineCoverage" in node:
        yield node


def main() -> int:
    parser = argparse.ArgumentParser(description="Fail when Xcode code coverage drops below a threshold.")
    parser.add_argument("xcresult", type=Path)
    parser.add_argument("--target", required=True)
    parser.add_argument("--minimum", required=True, type=float, help="Minimum line coverage percentage, e.g. 35")
    args = parser.parse_args()

    report = load_report(args.xcresult)
    targets = {target["name"]: target for target in iter_targets(report)}
    if args.target not in targets:
        available = ", ".join(sorted(targets))
        sys.stderr.write(f"Target '{args.target}' not found in coverage report. Available: {available}\n")
        return 2

    coverage = float(targets[args.target]["lineCoverage"]) * 100.0
    print(f"Coverage for {args.target}: {coverage:.2f}% (minimum {args.minimum:.2f}%)")
    if coverage < args.minimum:
        sys.stderr.write(
            f"Coverage gate failed for {args.target}: {coverage:.2f}% < {args.minimum:.2f}%\n"
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
