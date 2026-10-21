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
identity="${SIGN_IDENTITY:--}"
sign=(codesign --force --sign "$identity")
[[ "$identity" != "-" ]] && sign+=(--options runtime --timestamp)
"${sign[@]}" "$app"
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

if [[ "${1:-}" == "--release" ]]; then
  rm -f build/Switchboard.zip build/Switchboard.dmg
  notarize() { xcrun notarytool submit "$1" --keychain-profile "${NOTARY_PROFILE:-foldout}" --wait; }
  if [[ "$identity" != "-" ]]; then
    ditto -c -k --keepParent "$app" build/Switchboard.zip
    notarize build/Switchboard.zip
    xcrun stapler staple "$app"
  fi
  ditto -c -k --norsrc --noextattr --noqtn --keepParent "$app" build/Switchboard.zip
  staging=$(mktemp -d)
  cp -R "$app" "$staging/"
  ln -s /Applications "$staging/Applications"
  hdiutil create -volname Switchboard -srcfolder "$staging" -fs HFS+ -format UDZO -ov build/Switchboard.dmg >/dev/null
  rm -rf "$staging"
  if [[ "$identity" != "-" ]]; then
    codesign --force --sign "$identity" --timestamp build/Switchboard.dmg
    notarize build/Switchboard.dmg
    xcrun stapler staple build/Switchboard.dmg
  fi
  echo "Packaged build/Switchboard.zip and build/Switchboard.dmg"
fi
