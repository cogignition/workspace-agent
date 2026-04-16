#!/bin/bash
# build_and_run.sh — Build, bundle, and relaunch WorkspaceAgent.
#
# Usage (from project root):
#   ./script/build_and_run.sh           # debug build + relaunch
#   ./script/build_and_run.sh release   # optimised build + relaunch
#   ./script/build_and_run.sh clean     # wipe build artifacts

set -euo pipefail

APP_NAME="WorkspaceAgent"
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"

case "$CONFIG" in
    clean)
        echo "🧹 Cleaning…"
        swift package clean
        rm -rf "${APP_NAME}.app"
        echo "✅ Clean complete."
        exit 0
        ;;
    release)
        SWIFT_CONFIG="release"
        ;;
    *)
        SWIFT_CONFIG="debug"
        ;;
esac

# ── 1. Build ──────────────────────────────────────────────────────────────────
echo "🔨 Building (${SWIFT_CONFIG})…"
swift build -c "$SWIFT_CONFIG"

EXECUTABLE=".build/${SWIFT_CONFIG}/${APP_NAME}"
if [ ! -f "$EXECUTABLE" ]; then
    echo "❌ Executable not found: ${EXECUTABLE}"
    exit 1
fi
echo "✅ Build succeeded."

# ── 2. Bundle ─────────────────────────────────────────────────────────────────
MACOS="${APP_NAME}.app/Contents/MacOS"
mkdir -p "$MACOS"
cp "$EXECUTABLE" "$MACOS/${APP_NAME}"

LLAMA_FW=$(find .build/artifacts -name "llama.framework" -path "*/macos-arm64*" 2>/dev/null | head -1)
if [ -n "$LLAMA_FW" ]; then
    cp -R "$LLAMA_FW" "$MACOS/"
    echo "✅ llama.framework bundled."
else
    echo "⚠️  llama.framework not found — inference will fail."
fi

cat > "${APP_NAME}.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>com.openlane.workspace-agent</string>
    <key>CFBundleName</key><string>Workspace Agent</string>
    <key>CFBundleVersion</key><string>0.2.0</string>
    <key>CFBundleShortVersionString</key><string>0.2.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>Openlane — Internal Tool</string>
</dict></plist>
PLIST

echo "✅ Bundle ready: ${APP_NAME}.app"

# ── 3. Relaunch ───────────────────────────────────────────────────────────────
echo "🔄 Restarting…"
pkill -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
sleep 0.5
open "${APP_NAME}.app"
echo "🚀 ${APP_NAME} running."
