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

### Lock-screen shortcut

Select **Verseglass** as your system screen saver. In VerseGlass → **Lock Screen**, enable **Show lyrics** and **Start lyrics first on ⌃⌘Q**. While a song plays, hold **Command** and **Control** in either order, then tap **Q** once. The shortcut starts the selected saver. With macOS set to require a password immediately, the saver can lock the session while the words animate.

VerseGlass registers that one shortcut during playback. Device Control and Accessibility can stay off. System Events may ask for Automation access to start the saver. If the saver request is rejected, VerseGlass asks macOS to lock immediately. If the request is pending or accepted, VerseGlass gives the session up to two seconds from the keypress to lock before calling the fallback. That fallback uses a private macOS lock function. VerseGlass only registers the shortcut on systems that provide it. Pausing playback, quitting VerseGlass or turning the option off releases the shortcut.

**Start screen saver on lock during playback** also tries to start the saver after other lock events. On macOS 27.0.1, this path can leave the wallpaper and clock visible. **Start Lyric Screen Saver** in the menu starts the saver from the desktop. **Lyric notification banners** is a separate option for showing each line in a notification.

## Display lighting

Open **Lighting**, choose **Music sync**, and grant macOS system-audio access when prompted. The glow follows audio level and bass onsets. Choose album colors or set a palette, then adjust thickness, intensity, and displays.

## Offline lyrics

VerseGlass checks AMLL for word timestamps, then LRCLIB for line timestamps. With line timing, it estimates when each word is sung. Apple Music catalog matching uses Apple’s iTunes Search service. [AMLL](https://github.com/amll-dev/amll-ttml-db) · [LRCLIB](https://lrclib.net/)

To use only local lyrics, open either player panel and turn off **Look up lyrics online**. Play or pause the target song and click **Import LRC for this track**. Standard and enhanced LRC files are supported.

Previously fetched lyrics also work offline. Imported lyrics take precedence for that recording. Both are stored under `~/Library/Application Support/Verseglass/Lyrics`. Third-party lyrics and album artwork belong to their respective rights holders.
