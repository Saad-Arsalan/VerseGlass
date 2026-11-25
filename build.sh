#!/bin/zsh
set -eu
cd "$(dirname "$0")"
out="build/Verseglass.app"
mkdir -p "$out/Contents/MacOS" "$out/Contents/Resources" build/Verseglass.iconset
cp Info.plist "$out/Contents/Info.plist"
swiftc Brand.swift Tools/Icon.swift -o build/IconTool
build/IconTool build/Verseglass.iconset
iconutil -c icns build/Verseglass.iconset -o "$out/Contents/Resources/Verseglass.icns"
saver="$out/Contents/Resources/Verseglass.saver"
mkdir -p "$saver/Contents/MacOS" "$saver/Contents/Resources"
for resources in "$out/Contents/Resources" "$saver/Contents/Resources"; do
    cp Resources/ConstellationInk.jpg "$resources/"
done
cp Saver/Info.plist "$saver/Contents/Info.plist"
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos15.0" -module-name VerseglassSaver -parse-as-library -Xlinker -bundle -framework ScreenSaver \
    LyricModels.swift Models.swift Styles.swift ConstellationScene.swift ConstellationBackdrop.swift SaverWire.swift RimSurface.swift Saver/ScreenSaver.swift -o "$saver/Contents/MacOS/VerseglassSaver"
codesign --force --sign - "$saver"
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos15.0" ./*.swift -o "$out/Contents/MacOS/Verseglass"
codesign --force --sign - --identifier local.verseglass.app "$out"
codesign --verify --strict "$out"
echo "$PWD/$out"
