# VerseGlass

A local macOS menu-bar app for synced Spotify and Apple Music lyrics. Requires macOS 15 or later. To build on your Mac with the Xcode Command Line Tools, run `./build.sh` and open `build/Verseglass.app`.

## Playing a song

Start a song in the Spotify or Music desktop app and allow Verseglass to read the player when macOS asks. Click the player's icon in the top right of the Verseglass window to see its connection, timing source, and lyric offset. The style browser plays its own preview. Select a style to use it for playback, or pin it to the menu bar.

For the full-screen lyric scene, install the bundled `Contents/Resources/Verseglass.saver` in `~/Library/Screen Savers`, then choose **Wallpaper → Screen Saver → Custom → Verseglass** in System Settings. Keep the menu-bar app running so the screen saver receives the current song. macOS controls when the saver appears and when it switches to the password screen. **Lock Screen → Lyric notification banners** is a separate optional display mode.

Under **Lighting**, choose **Music sync** and grant system-audio access when prompted. The display edges brighten with the audio level and bass onsets. Pick custom colors or follow the album cover. **Fisheye Visual** builds each lyric phrase from the sung words. **Show lyrics while unlocked** enables the click-through desktop overlay. Closing the window leaves Verseglass running in the menu bar.

## Lyric sources and offline use

Online lookup checks [AMLL](https://github.com/amll-dev/amll-ttml-db) by recording ID for word timestamps, then [LRCLIB](https://lrclib.net/) by song metadata for line timestamps. Apple Music catalog matching uses Apple's iTunes Search service. For line-timed recordings, Verseglass estimates word position within each line. The player panel identifies the source and timing type.

Songs already fetched work offline. To use only local files, turn off **Look up lyrics online** in either player panel, play or pause the target song, then choose **Import LRC for this track**. Ordinary and enhanced LRC files are supported. Imported lyrics take precedence for that recording. Verseglass stores these files and fetched lyrics in `~/Library/Application Support/Verseglass/Lyrics`.

The 13 styles are independently implemented. macOS manages lock-screen notifications, including preview privacy, placement, and Focus filtering.

## Releases and license

See the [release history](CHANGELOG.md) for changes and [GitHub Releases](https://github.com/Saad-Arsalan/VerseGlass/releases) for downloads. VerseGlass source code is available under the [MIT License](LICENSE). Third-party lyrics and album artwork belong to their respective rights holders.
