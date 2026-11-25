#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
name=VerseGlass-iPad-unsigned.ipa
work=$(mktemp -d "${TMPDIR:-/tmp}/verseglass-ipad.XXXXXX")
trap 'rm -rf "$work"' EXIT

xcodebuild -project iPad/VerseGlass.xcodeproj -scheme VerseGlass \
    -destination 'generic/platform=iOS' -configuration Release \
    -derivedDataPath "$work/derived" -archivePath "$work/VerseGlass.xcarchive" \
    CODE_SIGNING_ALLOWED=NO archive

app="$work/VerseGlass.xcarchive/Products/Applications/VerseGlass.app"
plist="$app/Info.plist"
for key in CFBundleVersion CFBundleShortVersionString; do
    test "$(plutil -extract "$key" raw "$plist")" = "$(plutil -extract "$key" raw Info.plist)"
done
test "$(plutil -extract CFBundleIdentifier raw "$plist")" = local.verseglass.ipad
test "$(plutil -extract CFBundleSupportedPlatforms.0 raw "$plist")" = iPhoneOS
test "$(plutil -extract UIDeviceFamily json -o - "$plist" | jq -c .)" = '[2]'
plutil -extract NSAppleMusicUsageDescription raw "$plist" | grep -q '[^[:space:]]'
lipo "$app/VerseGlass" -verify_arch arm64
test -s "$app/ConstellationInk.jpg"

mkdir "$work/Payload"
ditto --norsrc "$app" "$work/Payload/VerseGlass.app"
(cd "$work" && zip -qrXy "$name" Payload)
unzip -tq "$work/$name"
mkdir -p build/release
mv -f "$work/$name" build/release/
