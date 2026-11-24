#!/bin/bash
set -euo pipefail

# Package the app produced by build.sh. Accept explicit paths for local testing.
app=${1:-build/Verseglass.app}
output=${2:-build/release}
name=VerseGlass-macOS-arm64.dmg
saver="$app/Contents/Resources/Verseglass.saver"

codesign --verify --deep --strict "$app"
for binary in "$app/Contents/MacOS/Verseglass" "$saver/Contents/MacOS/VerseglassSaver"; do
    if [[ "$(lipo -archs "$binary")" != arm64 ]]; then
        echo "Expected an Apple silicon binary at $binary" >&2
        exit 1
    fi
done

mkdir -p "$output"
work=$(mktemp -d "$output/.package.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir "$work/volume"
ditto "$app" "$work/volume/Verseglass.app"
ditto "$saver" "$work/volume/Verseglass.saver"
ln -s /Applications "$work/volume/Applications"
hdiutil create -quiet -volname VerseGlass -fs HFS+ -format UDZO -srcfolder "$work/volume" "$work/$name"
hdiutil verify -quiet "$work/$name"
(cd "$work" && shasum -a 256 "$name" > SHA256SUMS.txt)
mv -f "$work/$name" "$work/SHA256SUMS.txt" "$output/"
