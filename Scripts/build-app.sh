#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

# 可用 DEVELOPER_DIR 覆盖；否则优先 xcode-select，回退到常见 Xcode 安装位置
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  dev="$(xcode-select -p 2>/dev/null || true)"
  if [[ -z "$dev" || "$dev" == *CommandLineTools* ]]; then
    for c in /Applications/Xcode.app/Contents/Developer "$HOME/Downloads/work/download/Xcode.app/Contents/Developer"; do
      if [[ -d "$c" ]]; then dev="$c"; break; fi
    done
  fi
  export DEVELOPER_DIR="$dev"
fi

swift build -c release

APP=build/SideReel.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SideReel "$APP/Contents/MacOS/SideReel"
cp Support/Info.plist "$APP/Contents/Info.plist"
if [[ -f Support/AppIcon.icns ]]; then
  cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
codesign --force --sign - "$APP"
echo "built: $APP"