# VerseGlass design notebook

## Reference shelf

| App | What to study | What it suggests for VerseGlass |
| --- | --- | --- |
| [Lumn](https://www.trylumn.xyz/) | The album supplies the edge colors. Audio supplies their movement. Color balance, edge width and glow spread have separate controls. | Let a listener rebalance a two-color palette without also changing how much of the screen it lights. Check quiet passages as well as bass hits. |
| [Verci](https://www.verci.xyz/) | A sample song makes styles comparable before selection. Favorites and per-player status stay close to playback. | Use the same phrase when comparing lyric treatments. Put the reason for missing lyrics where the listener expects to see them. |
| [Needle](https://needlemac.com/) | The same recording can occupy a small player, an album cover, or an entire lyric scene. | Let the listener switch focus without losing the song or waiting for a new lookup. |
| Wevy | Name recorded as supplied. The Instagram link is pending from the maintainer. [Weyv](https://www.weyv.app/) is a possible match, with Windows desktop visualizers and saved layouts. [Wevy](https://wevyapp.com/faq) is also the name of a bead-pattern editor. | Keep the supplied name until the intended app is confirmed. If it is Weyv, study how a saved layout behaves when changing monitors. |

## Needle on Mac

The official Mac disk image contained version 1.3.1. Its signature verified and Gatekeeper accepted its notarization. The app launched on November 25, 2026. The first pass used published demos. A subsequent walkthrough opened all 12 sidebar sections in the installed trial. The settings tour offered 14 steps and a skip action. An animated lyric sample was visible behind the tour, even with Spotify paused. General showed two days remaining. Needle says its trial starts on first launch and lasts two days. [Download and onboarding](https://needlemac.com/download.html) · [Trial terms](https://needlemac.com/terms.html)

| Surface | What the published demos show | Question for hands-on testing |
| --- | --- | --- |
| Island | The compact player expands down from the top edge. Transport controls sit below the song title. [Clip](https://needlemac.com/media/island-card.mp4) | How easy is it to open deliberately, dismiss, and reach controls on an external display? |
| Lock screen | The clock stays visible above the centered cover. A separate, smaller transport row leaves the cover unobstructed. The background picks up color from the artwork. [Compact](https://needlemac.com/media/lock-normal.mp4) · [Expanded](https://needlemac.com/media/lock-art.mp4) | With music already playing, compare Control–Command–Q, screen saver activation, sleep, and wake. Record the exact entry path each time. |
| Desktop | A turntable gives the record and tonearm room. The sleeve treatment puts the square cover in front, leaves part of the disc visible, and moves song information below. [Turntable](https://needlemac.com/img/desktop/turntable.mp4) · [Sleeve](https://needlemac.com/img/desktop/sleeve.mp4) | What happens to the widget on pause, a track change, or a change of display? |
| Lyrics | Lens gives one word most of the space. Terminal leaves earlier lines dim. Stars keeps previous words as nodes, with the current word at a halo. Each treatment gives the eye one clear place to look. [Lens](https://needlemac.com/img/lyrics/lens.mp4) · [Terminal](https://needlemac.com/img/lyrics/terminal.mp4) · [Stars with edge lighting](https://needlemac.com/media/stars-glow.mp4) | Compare a fast verse, a long sustained word, a seek backward, and a song with no synced lyrics. |
| Lighting and backgrounds | Needle documents per-display Beat Glow, artwork-driven colors, live wallpaper scenes and gallery previews. Its FAQ describes a five-painting trial selection. [Feature guide and FAQ](https://needlemac.com/) · [Changes by version](https://needlemac.com/changelog.html) | On light and dark artwork, can the words stay readable when the glow peaks? Does the animation settle during silence? |

### Installed trial walkthrough

| Section | Observed in version 1.3.1 |
| --- | --- |
| Now Playing | A transport row offers previous, play, next, and audio output. Four shortcuts lead to lock-screen, glow, island, and desktop settings. |
| Island | Size and scale are separate. There are two finishes, two cover treatments, two island shapes, and optional weather, timer, and notes pages reached by swiping. Browser video detection has its own setup instructions. |
| Lock Screen | A clock preview sits above settings for the player card. Three glass finishes are available. The on-screen tips describe successive cover clicks for artwork and lyrics. |
| Desktop | The style chooser offers a turntable, sleeve, aura, lyrics, or live wallpaper. The panel teaches the entry gesture by telling the listener to drag the cover out of the open island. |
| Lyrics | Five lyric styles and five background choices are independent. Switching the background from black to white updated its description immediately; switching it back restored the original setting. Scatter changes distance from center, while Tilt changes angle. Additional controls cover artwork inside letters, where lyrics appear, and keeping the display awake. |
| Sound | Five EQ bands cover sub-bass through treble. The interface offers five presets and explains how to reset an individual band. |
| Beat Glow | Four placements illuminate the rim, all edges, corners, or sides. Thickness and brightness are separate, as are motion (steady or beat-driven) and color source (album or custom). |
| Keys | Keyboard sounds and the animated typing companion appear as separate options. |
| Headphones | Connection announcements and the output-button appearance are configured separately. The latter offers a rotating model or a static icon. |
| Wallpapers | The gallery opened in its own window. Five paintings were selectable; a separate tile identified the paid collection. Preview and apply were distinct actions. |
| Face Unlock | Selecting the beta entry left the settings panel and opened a separate surface. Enrollment and authentication behavior remain unverified. |
| General | The panel reported version and remaining trial time together. It also exposed update status, app appearance, startup, haptics, edge controls, and the permissions associated with specific features. |

**Design takeaway.** Try a placement selector for VerseGlass lighting before adding more colors. A listener who wants quieter visuals might prefer light only at the sides even with exactly the same palette. Preview that choice on the actual display, and keep the existing thickness and intensity settings.

**Control–Command–Q trial.** Spotify reported active playback before a single lock shortcut. macOS confirmed the session locked. WindowServer continued listing Needle windows as on screen, including a display-sized window. Some of the same windows were listed before locking, so that observation alone cannot distinguish visible lyrics, artwork, and transparent content. Spotify was paused after the observation. Sleep/wake and external-display behavior remain open.

**Lock-screen permissions.** Needle's release notes describe the cover and word-synced lyrics, and its privacy page associates keyboard monitoring with typing sounds. Neither page identifies how Needle draws on the lock screen. On the test Mac, Device Control and Data Access was off for both apps. A separate product, NepTunes, documents a private window-server API for its lock player. VerseGlass uses the system-selected lyric saver and a single registered shortcut. [Needle release notes](https://needlemac.com/changelog.html) · [Needle privacy](https://needlemac.com/privacy.html) · [NepTunes lock-screen player](https://neptunesmac.app/lock-screen/)

## First implementation

**Listening View** gives the Mac app a dedicated window for the current recording. Switch between cover art and lyrics while the player keeps its place. For this surface, the important test is whether you can switch mid-line, return after a seek, and still recognize what is playing when artwork or lyrics are unavailable.
