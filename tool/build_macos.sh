#!/bin/bash
# Builds an Apple Silicon-only Dremio.app and zips it to build/Dremio-macos.zip.
set -euo pipefail
cd "$(dirname "$0")/.."

export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
# Ruby 4 prefers IPv6, which some networks break for CocoaPods' CDN.
fallback="$(cd .. && pwd)/.tools/ipv4first.rb"
[ -f "$fallback" ] && export RUBYOPT="-r$fallback"

# A stable certificate keeps the Keychain from re-asking for saved links after every build; ad hoc otherwise.
identity="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*) \([0-9A-F]\{40\}\) "Apple Development.*/\1/p' | head -1)}"
identity="${identity:--}"

flutter build macos --release

app=build/macos/Build/Products/Release/Dremio.app
entitlements=$(mktemp)
codesign -d --entitlements - --xml "$app" > "$entitlements"

# The mpv frameworks ship prebuilt as universal binaries; drop their Intel slices.
while IFS= read -r -d '' file; do
  if lipo -archs "$file" 2>/dev/null | grep -q x86_64 && lipo -archs "$file" | grep -q arm64; then
    lipo -remove x86_64 "$file" -output "$file"
  fi
done < <(find "$app/Contents" -type f -perm -u+x -print0)

for framework in "$app"/Contents/Frameworks/*.framework; do
  codesign --force --sign "$identity" "$framework"
done
codesign --force --sign "$identity" --entitlements "$entitlements" "$app"
rm "$entitlements"
codesign --verify --deep --strict "$app"

rm -f build/Dremio-macos.zip
ditto -c -k --keepParent "$app" build/Dremio-macos.zip
du -sh "$app" build/Dremio-macos.zip
