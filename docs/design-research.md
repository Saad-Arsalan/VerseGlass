# VerseGlass design notebook

## Reference shelf

| App | What to study | What it suggests for VerseGlass |
| --- | --- | --- |
| [Lumn](https://www.trylumn.xyz/) | The album supplies the edge colors. Audio supplies their movement. Color balance, edge width and glow spread have separate controls. | Let a listener rebalance a two-color palette without also changing how much of the screen it lights. Check quiet passages as well as bass hits. |
| [Verci](https://www.verci.xyz/) | A sample song makes styles comparable before selection. Favorites and per-player status stay close to playback. | Use the same phrase when comparing lyric treatments. Put the reason for missing lyrics where the listener expects to see them. |
| [Needle](https://needlemac.com/) | The same recording can occupy a small player, an album cover, or an entire lyric scene. | Let the listener switch focus without losing the song or waiting for a new lookup. |
| Wevy | Exact identity pending. [Weyv](https://www.weyv.app/) is a possible match, with Windows desktop visualizers and saved layouts. [Wevy](https://wevyapp.com/faq) is also the name of a bead-pattern editor. | Keep the supplied name until the intended app is confirmed. If it is Weyv, study how a saved layout behaves when changing monitors. |

## Needle on Mac

The official Mac disk image contained version 1.3.1. Its signature verified and Gatekeeper accepted its notarization. The app launched on November 25, 2026. The desktop was locked during the initial inspection, so this entry records demo observations and leaves the installed-app walkthrough open. Needle says its trial starts on first launch and lasts two days. [Download and onboarding](https://needlemac.com/download.html) · [Trial terms](https://needlemac.com/terms.html)

| Surface | What the published demos show | Question for hands-on testing |
| --- | --- | --- |
| Island | The compact player expands down from the top edge. Transport controls sit below the song title. [Clip](https://needlemac.com/media/island-card.mp4) | How easy is it to open deliberately, dismiss, and reach controls on an external display? |
| Lock screen | The clock stays visible above the centered cover. A separate, smaller transport row leaves the cover unobstructed. The background picks up color from the artwork. [Compact](https://needlemac.com/media/lock-normal.mp4) · [Expanded](https://needlemac.com/media/lock-art.mp4) | With music already playing, compare Control–Command–Q, screen saver activation, sleep, and wake. Record the exact entry path each time. |
| Desktop | A turntable gives the record and tonearm room. The sleeve treatment puts the square cover in front, leaves part of the disc visible, and moves song information below. [Turntable](https://needlemac.com/img/desktop/turntable.mp4) · [Sleeve](https://needlemac.com/img/desktop/sleeve.mp4) | What happens to the widget on pause, a track change, or a change of display? |
| Lyrics | Lens gives one word most of the space. Terminal leaves earlier lines dim. Stars keeps previous words as nodes, with the current word at a halo. Each treatment gives the eye one clear place to look. [Lens](https://needlemac.com/img/lyrics/lens.mp4) · [Terminal](https://needlemac.com/img/lyrics/terminal.mp4) · [Stars with edge lighting](https://needlemac.com/media/stars-glow.mp4) | Compare a fast verse, a long sustained word, a seek backward, and a song with no synced lyrics. |
| Lighting and backgrounds | Needle documents per-display Beat Glow, artwork-driven colors, live wallpaper scenes and gallery previews. Its FAQ describes a five-painting trial selection. [Feature guide and FAQ](https://needlemac.com/) · [Changes by version](https://needlemac.com/changelog.html) | On light and dark artwork, can the words stay readable when the glow peaks? Does the animation settle during silence? |

Other surfaces to inventory during the trial include the floating island on a Mac without a notch, settings persistence, favorite-song handling, weather, headphone status, brightness and volume, listening history, typing feedback, and the optional Face Unlock beta. Music, display, and permission behavior take priority for VerseGlass. [Publisher’s overview](https://needlemac.com/)

## First implementation

**Listening View** gives the Mac app a dedicated window for the current recording. Switch between cover art and lyrics while the player keeps its place. For this surface, the important test is whether you can switch mid-line, return after a seek, and still recognize what is playing when artwork or lyrics are unavailable.
