# Changelog

## v2.4

- Added an opt-in saver-first Control–Command–Q handler on Mac. During playback it requests the selected saver before the standard shortcut is delivered. It only consumes the keypress after macOS confirms the session is already locked.

## v2.3

- Fixed a missed screen saver request when VerseGlass started during a locked session. The app rechecks Automation readiness on unlock and checks the actual permission at lock time.
- When locking during playback, VerseGlass listens for its full-screen saver and tries the macOS screen saver host once if needed. A live macOS 27.0.1 test still showed the lock wallpaper after Control–Command–Q.

## v2.2

- Documented the installed Needle trial across 12 settings sections and recorded the playback checks still outstanding. Kept Wevy on the reference shelf pending its Instagram link. This is a research-notes release.

## v2.1

- Added **Open Listening View** on Mac. Switch between album artwork and timed lyrics in a dedicated window while your music keeps playing.
- Started a [design notebook](docs/design-research.md) for Lumn, Verci, Needle, and Wevy, with observations from Needle’s demos and questions to check in the trial.

## v2

- Added a native iPad app with the Constellation scene, all 13 lyric styles, full-screen playback, and a built-in silent demo.
- Follow Apple Music on iPad or play a local audio file with imported LRC lyrics. Apple Music lyric lookup is opt-in. Imported and cached lyrics work offline.
- Added an unsigned iPad download for personal signing, a simulator playback check, and iPad coverage in the Swift security scan.

## v1.7

- Rebuilt Constellation around the star trail in [Needle’s reel](https://www.instagram.com/needlemacb/reel/DgJS6sPoyyG/). Each sung word adds a star, earlier words settle into small labels, and emphasized words appear in bold italic type.
- Added an original ink-wash backdrop, a live serif clock, and album art when available in the Constellation screen saver. The desktop overlay keeps your own wallpaper visible.
- Made Constellation the initial style for new installations. Existing style selections are preserved.

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
