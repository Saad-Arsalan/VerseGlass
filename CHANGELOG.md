# Changelog

## v2.10

- Touch ID lyrics now use the style, lettering and colors selected in the Mac app. Constellation traces the sung words, and Native Design highlights the current word inside alternating message bubbles.
- The lock-screen wallpaper follows the current word at a limited refresh rate. Short words can pass between pictures during fast verses.

## v2.9

- Added opt-in Touch ID lyrics on Mac. During playback, the current lyric line appears on the lock-screen wallpaper. macOS keeps its own clock and sign-in controls.
- Choose a static desktop picture or a plain black background in **Lock Screen → Touch ID lyrics**. VerseGlass restores that picture when you unlock. Control–Command–Q still starts the animated saver when its shortcut is enabled.

## v2.8

- Avoided redundant saver launches during lock-screen startup. VerseGlass sends the first lyric frame as soon as the saver connects.
- Clarified the lock shortcut in settings. Hold Command and Control in either order, then tap Q.

## v2.7

- Removed the duplicate clock and date from the Mac lyric screen saver and its preview. The lock screen uses the macOS clock. The iPad listening view keeps its full-screen clock.

## v2.6

- Lyric lettering is now laid out at its displayed size across all 13 styles on Mac and iPad, including the Mac screen saver.
- In Constellation, earlier words are larger and brighter, and labels move around nearby stars and words to stay legible. The sung word keeps its halo and the route follows the same lyric timing.

## v2.5

- Fixed an intermittent wallpaper-only lock when pressing Command–Control–Q or Control–Command–Q. VerseGlass gives the selected saver time to finish locking before requesting a standard lock. An explicit rejection still triggers the fallback immediately.
- When System Events has exited, VerseGlass can relaunch it in the background and retry starting the saver within the same keypress.

## v2.4

- Added an opt-in Control–Command–Q shortcut that starts the lyric saver during playback. It registers only that chord and works with Device Control and Accessibility off.
- Added a native lock fallback if the saver fails to lock the Mac promptly. Pausing playback or quitting VerseGlass releases the shortcut.
- Verified on macOS 27.0.1 with a single Control–Command–Q during playback. macOS reported a locked session, loaded the Verseglass saver, and the listener saw the words moving.

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
