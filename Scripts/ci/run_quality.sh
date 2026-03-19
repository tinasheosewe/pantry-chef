#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$ROOT_DIR/.artifacts/test-results}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.artifacts/DerivedData}"
SCHEME="${SCHEME:-PantryChef}"
PROJECT="${PROJECT:-PantryChef.xcodeproj}"
COVERAGE_TARGET="${COVERAGE_TARGET:-PantryChef.app}"
COVERAGE_MINIMUM="${COVERAGE_MINIMUM:-20}"

select_simulator() {
  python3 - <<'PY'
import json
import subprocess

preferred = [
    "iPhone 17",
    "iPhone 16 Pro",
    "iPhone 16",
    "iPhone 15 Pro",
    "iPhone 15",
    "iPhone 14",
]

raw = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"], text=True)
devices = json.loads(raw).get("devices", {})
available = []
for runtime_devices in devices.values():
    for device in runtime_devices:
        if device.get("isAvailable"):
            available.append(device["name"])

for name in preferred:
    if name in available:
        print(name)
        raise SystemExit(0)

for name in available:
    if name.startswith("iPhone"):
        print(name)
        raise SystemExit(0)

raise SystemExit("No available iPhone simulator found")
PY
}

run_test_bundle() {
  local bundle_name="$1"
  local result_path="$2"
  rm -rf "$result_path"
  xcrun simctl shutdown all >/dev/null 2>&1 || true
  xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,name=$SIMULATOR_NAME" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -resultBundlePath "$result_path" \
    -enableCodeCoverage YES \
    -only-testing:"$bundle_name"
}

cd "$ROOT_DIR"
mkdir -p "$RESULTS_DIR"
rm -rf "$DERIVED_DATA_PATH"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required but was not found on PATH" >&2
  exit 1
fi

xcodegen generate
SIMULATOR_NAME="${SIMULATOR_NAME:-$(select_simulator)}"

echo "Using simulator: $SIMULATOR_NAME"
run_test_bundle "PantryChefTests" "$RESULTS_DIR/unit.xcresult"
python3 "$ROOT_DIR/Scripts/ci/check_coverage.py" \
  "$RESULTS_DIR/unit.xcresult" \
  --target "$COVERAGE_TARGET" \
  --minimum "$COVERAGE_MINIMUM"
run_test_bundle "PantryChefUITests" "$RESULTS_DIR/ui.xcresult"

echo "Quality run completed successfully. Results stored in $RESULTS_DIR"
