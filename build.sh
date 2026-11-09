#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/dist/ClariGauge.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .local/module-cache
test -x .local/python-runtime/bin/python3.12 || {
    echo "Prepare the standalone runtime with scripts/bundle_runtime.py first." >&2
    exit 1
}
ditto .local/python-runtime "$APP/Contents/Resources/python"
install_name_tool -id @rpath/libpython3.12.dylib "$APP/Contents/Resources/python/lib/libpython3.12.dylib"
clang -mmacosx-version-min=14.0 -O2 sensors/smc.c -framework IOKit -framework CoreFoundation -o "$APP/Contents/Resources/smc"
clang -mmacosx-version-min=14.0 -O2 sensors/temperature.m -framework Foundation -o "$APP/Contents/Resources/temperature"
swiftc -target arm64-apple-macosx15.0 -swift-version 5 -O -parse-as-library -module-cache-path "$PWD/.local/module-cache" src/MacPulse.swift src/MenuBarMetrics.swift src/MetricPopover.swift src/CompactStatusBar.swift src/TrafficWindow.swift src/NetworkAddresses.swift -o "$APP/Contents/MacOS/MacPulse" -framework SwiftUI -framework Charts -framework AppKit
cp src/collector.py "$APP/Contents/Resources/collector.py"
cp src/sensor_catalog.py "$APP/Contents/Resources/sensor_catalog.py"
mkdir -p .local/AppIcon.iconset
for points in 16 32 128 256 512; do
    sips -z "$points" "$points" assets/AppIcon-v1.png --out ".local/AppIcon.iconset/icon_${points}x${points}.png" >/dev/null
    pixels=$((points * 2))
    sips -z "$pixels" "$pixels" assets/AppIcon-v1.png --out ".local/AppIcon.iconset/icon_${points}x${points}@2x.png" >/dev/null
done
iconutil -c icns .local/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MacPulse</string>
<key>CFBundleIdentifier</key><string>local.sixing.macpulse</string>
<key>CFBundleName</key><string>ClariGauge</string>
<key>CFBundleDisplayName</key><string>ClariGauge</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.5.0</string>
<key>CFBundleVersion</key><string>15</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
printf '%s\n' "$APP"
