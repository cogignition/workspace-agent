#!/bin/bash
# build_and_run.sh — Shell-first build loop for WorkspaceAgent
# Following the Codex macOS use-case pattern: compile, bundle, launch, log.
#
# Usage:
#   ./script/build_and_run.sh          # Build and run (debug)
#   ./script/build_and_run.sh release  # Build release config
#   ./script/build_and_run.sh clean    # Clean build artifacts

set -euo pipefail

APP_NAME="WorkspaceAgent"
BUILD_DIR=".build"
BUNDLE_DIR="${BUILD_DIR}/bundle"
CONFIG="${1:-debug}"

cd "$(dirname "$0")/.."

case "$CONFIG" in
    clean)
        echo "🧹 Cleaning build artifacts…"
        swift package clean
        rm -rf "$BUNDLE_DIR"
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

echo "🔨 Building ${APP_NAME} (${SWIFT_CONFIG})…"
swift build -c "$SWIFT_CONFIG" 2>&1

EXECUTABLE="${BUILD_DIR}/${SWIFT_CONFIG}/${APP_NAME}"

if [ ! -f "$EXECUTABLE" ]; then
    echo "❌ Build failed — executable not found at ${EXECUTABLE}"
    exit 1
fi

echo "✅ Build succeeded."

# Bundle as .app for proper macOS integration (Dock icon, MenuBarExtra, etc.)
echo "📦 Bundling as ${APP_NAME}.app…"

APP_BUNDLE="${BUNDLE_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS"

cp "$EXECUTABLE" "$MACOS/${APP_NAME}"

# Copy llama.framework next to the binary (rpath is @executable_path)
LLAMA_XCFRAMEWORK="${BUILD_DIR}/artifacts/localllmclient/LocalLLMClientLlamaFramework/llama.xcframework"
LLAMA_MACOS="${LLAMA_XCFRAMEWORK}/macos-arm64_x86_64/llama.framework"
if [ -d "$LLAMA_MACOS" ]; then
    cp -R "$LLAMA_MACOS" "$MACOS/llama.framework"
    echo "✅ Bundled llama.framework"
else
    echo "⚠️  llama.framework not found at ${LLAMA_MACOS}"
fi

cat > "${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.openlane.workspace-agent</string>
    <key>CFBundleName</key>
    <string>Workspace Agent</string>
    <key>CFBundleVersion</key>
    <string>0.1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Openlane — Internal Tool</string>
    <key>com.apple.developer.kernel.increased-memory-limit</key>
    <true/>
</dict>
</plist>
PLIST

echo "✅ Bundle created at ${APP_BUNDLE}"

# Kill any existing instance
pkill -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
sleep 0.5

# Launch
echo "🚀 Launching ${APP_NAME}…"
open "$APP_BUNDLE"

# Stream logs
echo "📋 Streaming logs (Ctrl+C to stop)…"
log stream --predicate "subsystem == 'com.openlane.workspace-agent'" --level debug
