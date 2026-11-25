# VerseGlass

Word-synced lyrics for Mac and iPad in 13 styles. On Mac, follow Spotify or Apple Music with a desktop overlay, a full-screen saver, and music-reactive edge lighting. On iPad, follow Apple Music or open your own audio and synced lyrics.

**[Download for Mac (.dmg)](https://github.com/Saad-Arsalan/VerseGlass/releases/latest/download/VerseGlass-macOS-arm64.dmg)** · Apple silicon, macOS 15+

**[Download for iPad (.ipa)](https://github.com/Saad-Arsalan/VerseGlass/releases/latest/download/VerseGlass-iPad-unsigned.ipa)** · iPadOS 17+, requires [personal signing](docs/ipad.md)

[All releases and checksums](https://github.com/Saad-Arsalan/VerseGlass/releases)

![Constellation screen saver tracing the words of Blue Hour across a plum ink wash, with the sung word in large type](docs/constellation.jpg)

## Play your first song on Mac

1. Open the disk image, drag **Verseglass** to **Applications**, and launch it.
2. Play a song in the Spotify or Music desktop app. Allow playback access when macOS asks.
3. In VerseGlass, open **Lock Screen** and turn on **Show lyrics while unlocked** to see the words on your desktop.

For lyrics on **Control–Command–Q**, select the Verseglass screen saver and enable **Start lyrics first on ⌃⌘Q**. [Lock-screen setup](docs/usage.md#lock-screen-shortcut)

[Mac setup and troubleshooting](docs/usage.md) · [iPad setup and playback](docs/ipad.md) · [Report an issue](https://github.com/Saad-Arsalan/VerseGlass/issues/new/choose)

## Build from source

For Mac, install Xcode Command Line Tools and run these commands in a checkout of this repository. For iPad, open `iPad/VerseGlass.xcodeproj` in Xcode.

```sh
./build.sh
open build/Verseglass.app
```

[Changelog](CHANGELOG.md) · [Design notebook](docs/design-research.md) · [Roadmap](https://github.com/users/Saad-Arsalan/projects/2) · [Discussions](https://github.com/Saad-Arsalan/VerseGlass/discussions) · [MIT license](LICENSE)
