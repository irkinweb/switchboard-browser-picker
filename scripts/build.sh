#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift run -c release SwitchboardSelfCheck
swift build -c release --arch arm64 --arch x86_64 --product Switchboard
bin=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

app=build/Switchboard.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Switchboard" "$app/Contents/MacOS/Switchboard"
cp Resources/Info.plist "$app/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"
echo "Built $app"

if [[ "${1:-}" == "--install" ]]; then
  osascript -e 'quit app "Switchboard"' >/dev/null 2>&1 || true
  rm -rf /Applications/Switchboard.app
  cp -R "$app" /Applications/
  lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  "$lsregister" -u "$app" >/dev/null 2>&1 || true
  "$lsregister" -f /Applications/Switchboard.app
  echo "Installed /Applications/Switchboard.app"
fi
