#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
app_path="$repo_root/dist/DayVDO-InteractionLab.app"
mkdir -p "$app_path/Contents/MacOS"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/dayvdo-interaction-lab-clang}"
swiftc -parse-as-library -O -framework AppKit -framework QuartzCore \
  "$repo_root/Tools/InteractionLab/InteractionLab.swift" \
  "$repo_root/Sources/DayVDO/Models/InteractionComparisonPolicy.swift" \
  -o "$app_path/Contents/MacOS/DayVDO-InteractionLab"
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DayVDO-InteractionLab</string>
<key>CFBundleIdentifier</key><string>local.dayvdo.interaction-lab</string>
<key>CFBundleName</key><string>DayVDO 操作手感对照</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app_path"
printf '%s\n' "$app_path"
