#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="GhostPin"
BUNDLE_ID="com.oyuxi.TodoPin"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

cd "$ROOT_DIR"

if [[ "$MODE" != "--verify" && "$MODE" != "verify" ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

swift build
BUILD_DIR="$(swift build --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"
BUILD_CLI="$BUILD_DIR/ghostpin-cli"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_FRAMEWORKS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$BUILD_CLI" "$APP_MACOS/ghostpin-cli"
chmod +x "$APP_BINARY" "$APP_MACOS/ghostpin-cli"

if [[ -d "$ROOT_DIR/Sources/GhostPin/Resources" ]]; then
  rsync -a --exclude 'Models/README.md' "$ROOT_DIR/Sources/GhostPin/Resources/" "$APP_RESOURCES/"
fi

mkdir -p "$APP_RESOURCES/skills"
cp -R "$ROOT_DIR/skills/ghostpin-cli" "$APP_RESOURCES/skills/ghostpin-cli"
python3 "$ROOT_DIR/script/check_skill.py" "$ROOT_DIR/skills/ghostpin-cli" "$APP_RESOURCES/skills/ghostpin-cli"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    VERIFY_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ghostpin-verify.XXXXXX")"
    VERIFY_PID=""
    cleanup_verification() {
      if [[ -n "$VERIFY_PID" ]]; then
        kill "$VERIFY_PID" >/dev/null 2>&1 || true
        wait "$VERIFY_PID" 2>/dev/null || true
      fi
      rm -rf "$VERIFY_ROOT"
    }
    trap cleanup_verification EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    GHOSTPIN_TEST_SUPPORT_ROOT="$VERIFY_ROOT" "$APP_BINARY" >"$VERIFY_ROOT/app.log" 2>&1 &
    VERIFY_PID=$!
    for _ in {1..6}; do
      sleep 0.5
      if ! kill -0 "$VERIFY_PID" 2>/dev/null; then
        cat "$VERIFY_ROOT/app.log"
        exit 1
      fi
    done
    echo "已验证 GhostPin 进程启动，使用隔离任务目录。"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
