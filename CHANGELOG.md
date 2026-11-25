# Changelog

## v1.6

- Fixed desktop lyrics staying hidden after a missed display-wake event. VerseGlass now checks the actual power state of each display when the session changes and during playback.
- When an album lookup has no synced lyrics, VerseGlass checks other releases for a matching title, artist, and recording duration.

## v1.5

- Download VerseGlass for Apple silicon as a disk image with a stable download link and a SHA-256 checksum.
- Added automated macOS builds, release packaging, CodeQL scans, and Dependabot updates for GitHub Actions.
- Shortened the README and added issue forms, contributor guidance, and a private security reporting channel.

## v1.4

- Added **Start Lyric Screen Saver** to the menu bar so macOS can select the saver before entering the lock interface.

## v1.3

- Added an optional System Events request to start the selected screen saver when macOS locks during music playback. The Lock Screen panel reports Automation permission and request errors.

## v1.2

First public source release.

- Added the VerseGlass icon, screen saver, and a live feed from the menu-bar app.
- Added music-reactive display-edge lighting with adjustable colors, thickness, and glow.
- Updated kinetic lyric styles so phrases build word by word with changing size and emphasis.

## v1.1

Local release. Added optional silent lock-screen notifications that update with each lyric line and clear on unlock or pause.

## v1.0

Local release. Introduced Spotify and Apple Music playback tracking, 13 lyric styles, a click-through desktop overlay, menu-bar controls, online lyric lookup, local caching, and LRC import.
