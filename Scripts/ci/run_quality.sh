#!/usr/bin/env bash
# Unit tests + coverage gate for the checked-in PantryChef.xcodeproj.
#
#   bash Scripts/ci/run_quality.sh                  unit tests, then the coverage floor
#   RUN_UI_TESTS=1 bash Scripts/ci/run_quality.sh   the same, then the UI tests
#
# No scheme file is tracked: `PantryChef` is the scheme Xcode creates automatically for
# the app target, and its test action covers PantryChefTests and PantryChefUITests.
#
# Overrides: SIMULATOR_ID (a simulator UDID) or SIMULATOR_NAME, SCHEME, PROJECT,
# RESULTS_DIR, DERIVED_DATA_PATH, SOURCE_PACKAGES_DIR (reuse an existing SwiftPM
# checkout directory instead of downloading the packages again), COVERAGE_TARGET,
# COVERAGE_MINIMUM. Arguments given to the script are passed on to xcodebuild, for
# example a build setting such as COMPILER_INDEX_STORE_ENABLE=NO.
set -euo pipefail

EXTRA_ARGS=("$@")

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$ROOT_DIR/.artifacts/test-results}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.artifacts/DerivedData}"
SCHEME="${SCHEME:-PantryChef}"
PROJECT="${PROJECT:-PantryChef.xcodeproj}"
COVERAGE_TARGET="${COVERAGE_TARGET:-PantryChef.app}"
# A ratchet, not a target: the unit tests cover the engines, the store and the bundled
# data, while most of the app target's lines are SwiftUI views. Measured 19.1% in CI.
COVERAGE_MINIMUM="${COVERAGE_MINIMUM:-18}"

# Prints the UDID of an available iPhone simulator on the newest iOS runtime that the
# selected Xcode's simulator SDK can target (and that is not older than iOS 17, the
# app's deployment target).
select_simulator() {
  python3 - <<'PY'
import json
import subprocess
import sys

preferred = [
    "iPhone 17",
    "iPhone 17 Pro",
    "iPhone 16",
    "iPhone 16 Pro",
    "iPhone 15",
    "iPhone 15 Pro",
]
minimum = (17, 0)


def version(text):
    return tuple(int(part) for part in text.split(".") if part.isdigit())


sdk = version(
    subprocess.check_output(
        ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], text=True
    ).strip()
)
raw = subprocess.check_output(
    ["xcrun", "simctl", "list", "devices", "available", "-j"], text=True
)

phones_by_runtime = {}
for runtime, devices in json.loads(raw).get("devices", {}).items():
    # e.g. com.apple.CoreSimulator.SimRuntime.iOS-26-2
    name = runtime.rsplit(".", 1)[-1]
    if not name.startswith("iOS-"):
        continue
    runtime_version = version(name[len("iOS-"):].replace("-", "."))
    phones = [
        device
        for device in devices
        if device.get("isAvailable") and device["name"].startswith("iPhone")
    ]
    if phones and runtime_version >= minimum:
        phones_by_runtime[runtime_version] = phones

if not phones_by_runtime:
    raise SystemExit("No available iPhone simulator found")

usable = [v for v in phones_by_runtime if v[:2] <= sdk[:2]] or list(phones_by_runtime)
runtime_version = max(usable)
phones = phones_by_runtime[runtime_version]
by_name = {device["name"]: device for device in phones}
device = next((by_name[name] for name in preferred if name in by_name), phones[0])
sys.stderr.write(
    "Using simulator: {} (iOS {})\n".format(
        device["name"], ".".join(str(part) for part in runtime_version)
    )
)
print(device["udid"])
PY
}

run_test_bundle() {
  local bundle_name="$1"
  local result_path="$2"
  rm -rf "$result_path"
  xcrun simctl shutdown all >/dev/null 2>&1 || true
  # ${a[@]+...} because macOS ships bash 3.2, where expanding an empty array trips `set -u`.
  xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    ${PACKAGE_ARGS[@]+"${PACKAGE_ARGS[@]}"} \
    -resultBundlePath "$result_path" \
    -enableCodeCoverage YES \
    -parallel-testing-enabled NO \
    -only-testing:"$bundle_name" \
    ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
}

cd "$ROOT_DIR"
mkdir -p "$RESULTS_DIR"
rm -rf "$DERIVED_DATA_PATH"

if [[ -n "${SIMULATOR_ID:-}" ]]; then
  DESTINATION="platform=iOS Simulator,id=$SIMULATOR_ID"
elif [[ -n "${SIMULATOR_NAME:-}" ]]; then
  DESTINATION="platform=iOS Simulator,name=$SIMULATOR_NAME"
else
  DESTINATION="platform=iOS Simulator,id=$(select_simulator)"
fi
echo "Destination: $DESTINATION"

PACKAGE_ARGS=()
if [[ -n "${SOURCE_PACKAGES_DIR:-}" ]]; then
  PACKAGE_ARGS=(-clonedSourcePackagesDirPath "$SOURCE_PACKAGES_DIR")
fi

run_test_bundle "PantryChefTests" "$RESULTS_DIR/unit.xcresult"
python3 "$ROOT_DIR/Scripts/ci/check_coverage.py" \
  "$RESULTS_DIR/unit.xcresult" \
  --target "$COVERAGE_TARGET" \
  --minimum "$COVERAGE_MINIMUM"

if [[ "${RUN_UI_TESTS:-0}" == "1" ]]; then
  run_test_bundle "PantryChefUITests" "$RESULTS_DIR/ui.xcresult"
fi

echo "Quality run completed successfully. Results stored in $RESULTS_DIR"
