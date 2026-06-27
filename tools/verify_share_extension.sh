#!/usr/bin/env bash
# Deterministic proof the Share extension is wired correctly end-to-end at the OS level:
# build the app (which embeds the extension), install it on the booted sim, launch it so
# PluginKit scans the bundle, then assert the system actually registered our extension for
# the share-sheet protocol under the display name users will tap. This is the reliable
# companion to the (inherently flaky) Safari share-sheet UITest — no UI driving, just the
# plugin database, which is the source of truth for "does it show up in Share?".
set -euo pipefail

UDID="${PC_SIM_UDID:-BD5728DA-C4DA-488C-B81F-DC050751AEE1}"
APP_ID="com.tboya.pantrychef.PantryChef"
EXT_ID="com.tboya.pantrychef.PantryChef.ShareExtension"
EXPECT_NAME="Save to PantryChef"
cd "$(dirname "$0")/.."

echo "▸ Building (embeds the extension)…"
xcodebuild build -scheme PantryChef \
  -destination "platform=iOS Simulator,id=$UDID" -quiet

APP_PATH=$(xcodebuild -scheme PantryChef -showBuildSettings \
  -destination "platform=iOS Simulator,id=$UDID" 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{d=$2} END{print d}')/PantryChef.app

if [[ ! -d "$APP_PATH/PlugIns/ShareExtension.appex" ]]; then
  echo "✗ ShareExtension.appex not embedded in $APP_PATH"; exit 1
fi
echo "▸ Embedded: $APP_PATH/PlugIns/ShareExtension.appex"

echo "▸ Installing + launching so PluginKit scans the bundle…"
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$APP_PATH"
xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
sleep 2

echo "▸ Querying the share-services plugin registry…"
OUT=$(xcrun simctl spawn "$UDID" pluginkit -mAvv -p com.apple.share-services 2>&1 || true)

if grep -q "$EXT_ID" <<<"$OUT" && grep -q "$EXPECT_NAME" <<<"$OUT"; then
  echo "✓ Registered: $EXT_ID  →  “$EXPECT_NAME” (com.apple.share-services)"
  echo "  The extension will appear in the system share sheet for web URLs and text."
  exit 0
fi

echo "✗ Extension not registered for com.apple.share-services."
echo "$OUT" | grep -iE "pantry|tboya" || echo "  (no PantryChef plugin found in registry)"
exit 1
