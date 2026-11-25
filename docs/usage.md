# Using VerseGlass

## Installing the download

The release disk image contains the app, an Applications shortcut, and the optional screen saver. VerseGlass is ad-hoc signed. If macOS asks about the developer, check the disk image against the SHA-256 checksum on the release page. Apple documents the per-app approval under Privacy & Security. [Release downloads](https://github.com/Saad-Arsalan/VerseGlass/releases/latest) · [Apple’s guide to opening Mac apps](https://support.apple.com/en-us/102445)

## Styles and playback

Open VerseGlass from the menu bar. Click a style to preview it, then click **Select** to apply it to playback. Pin favorites for quick access from the menu bar. Closing the window keeps the lyrics running.

**Constellation** draws a path as each word is sung. Play it over your desktop or use **Start Lyric Screen Saver** for the ink backdrop, clock, and album cover. Edge lighting follows the settings under **Lighting**.

Click the Spotify or Apple Music icon at the top of the window to check which track VerseGlass sees, the source of its timing data, and any permission errors. Use **Timing shift** to adjust the lyrics for the current song.

## Listening View

Choose **Open Listening View** from the VerseGlass menu bar to see the current recording in its own window. Switch between **Lyrics** and **Album Cover** while Spotify or Music continues playing. Use the green window button to enter full screen.

## Lyric screen saver

1. Open `Verseglass.saver` in the downloaded disk image and install it for your user account. If you built from source, the same file lives in `build/Verseglass.app/Contents/Resources/`.
2. In System Settings, select **Verseglass** as your screen saver. On macOS 27, open **Wallpaper → Screen Saver → Custom**. Find Verseglass under **Other**.
3. Keep VerseGlass running and start a song. From the unlocked desktop, choose **Start Lyric Screen Saver** in the VerseGlass menu bar. Allow System Events automation if prompted.

For the keyboard shortcut, enable **Start screen saver on lock during playback** in the **Lock Screen** panel. While a song plays, press **Control–Command–Q** once. macOS locks normally and VerseGlass requests the selected saver. If the full-screen VerseGlass saver has not responded, the app makes one fallback request to the system screen saver host. Your macOS password settings govern when you’ll be asked to unlock. For silent notifications showing each lyric line, enable **Lyric notification banners** in the Lock Screen panel.

## Display lighting

Open **Lighting**, choose **Music sync**, and grant macOS system-audio access when prompted. The glow follows audio level and bass onsets. Choose album colors or set a palette, then adjust thickness, intensity, and displays.

## Offline lyrics

VerseGlass checks AMLL for word timestamps, then LRCLIB for line timestamps. With line timing, it estimates when each word is sung. Apple Music catalog matching uses Apple’s iTunes Search service. [AMLL](https://github.com/amll-dev/amll-ttml-db) · [LRCLIB](https://lrclib.net/)

To use only local lyrics, open either player panel and turn off **Look up lyrics online**. Play or pause the target song and click **Import LRC for this track**. Standard and enhanced LRC files are supported.

Previously fetched lyrics also work offline. Imported lyrics take precedence for that recording. Both are stored under `~/Library/Application Support/Verseglass/Lyrics`. Third-party lyrics and album artwork belong to their respective rights holders.
