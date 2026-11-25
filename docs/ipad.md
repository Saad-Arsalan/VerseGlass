# VerseGlass on iPad

VerseGlass runs on iPadOS 17 or later. It opens with a built-in lyric demo. Use **Music source** to open a track from Files or follow Apple Music playback. **Lyric style** changes the scene. **Enter full screen** hides the controls. In Constellation, a lavender and ivory glow follows each word cue.

For local playback, choose **Open Audio File**, then **Import Synced Lyrics** to pair the audio with a timestamped LRC file. For Apple Music, play a song in Music, return to VerseGlass, and choose **Follow Apple Music**. Allow access to your media library. Choose **Enable Online Lookup** or import an LRC for the song yourself. Keep VerseGlass open to see the lyrics. Spotify playback detection and the macOS screen saver are Mac features.

## Run on your iPad

The release includes an unsigned IPA. A physical iPad requires an app signed for your device. If you use AltStore Classic, download the IPA to Files and import it under **My Apps** using **+**. AltStore signs it with your Apple development account. [Download the iPad IPA](https://github.com/Saad-Arsalan/VerseGlass/releases/latest/download/VerseGlass-iPad-unsigned.ipa) · [Set up AltStore Classic](https://faq.altstore.io/altstore-classic/how-to-install-altstore-macos) · [How AltStore signing works](https://github.com/altstoreio/AltStore#altstore)

### Install from source with Xcode

1. Download the source from the [latest release](https://github.com/Saad-Arsalan/VerseGlass/releases/latest) and open `iPad/VerseGlass.xcodeproj` in Xcode on a Mac.
2. Connect your iPad, select it as the run destination, and enable Developer Mode on the iPad if prompted.
3. Select the **VerseGlass** app target. In **Signing & Capabilities**, choose your Apple development team. If Xcode needs a unique bundle identifier, change it to one your team owns.
4. Choose **Product → Run**. Xcode signs and installs the app.

For a preview without a device, select an iPad simulator in Xcode and run. **Product → Test** exercises local audio, lyric import, and the demo controls. The same tests run in GitHub Actions. [iPad simulator checks](https://github.com/Saad-Arsalan/VerseGlass/actions/workflows/ipad.yml) · [Apple’s device setup guide](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)
