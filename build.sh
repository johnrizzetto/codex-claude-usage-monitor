#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
swift build --disable-sandbox -c release
APP="$PWD/dist/Usage Pace.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/UsagePace "$APP/Contents/MacOS/UsagePace"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.johnrizzetto.usagepace</string>
<key>CFBundleName</key><string>Usage Pace</string>
<key>CFBundleDisplayName</key><string>Usage Pace</string>
<key>CFBundleExecutable</key><string>UsagePace</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.2</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
print "Built $APP"
