# Talkie

A walkie-talkie for the Mac with a switchboard instead of a contact list. Drag a patch cord into a
friend's jack and the line opens instantly. While a line is open, a mic drops out of the menu bar on
a coiled cord and floats above every app: hold it (or ⌥Space) to talk.

- **Design reference:** open [`design/prototype.html`](design/prototype.html) in a browser.
- **Decisions so far:** [`design/DECISIONS.md`](design/DECISIONS.md).

## Status

Step 1 of 3: the board. The switchboard window, patch cords with physics and haptics, the
floating mic and the card file all work, with simulated friends and codes. There's no networking or real audio yet; the sounds
are the board's own clicks and beeps.

## Run it

You need a Mac with macOS 14 or newer.

**From Xcode (15 or newer):** open `Package.swift`, pick the `Talkie` scheme and press Run.

**From the terminal:**

```sh
swift run Talkie
```

**As an app:** `scripts/bundle.sh` builds `build/Talkie.app` and `build/Talkie.dmg`. Every push
also builds them on GitHub Actions and publishes the disk image as the **Talkie (latest build)**
release: https://github.com/spacemnke/talkie/releases/tag/latest

It isn't notarized yet. The first time you open it, macOS will refuse; open **System Settings →
Privacy & Security** and click **Open Anyway** (or run `xattr -dr com.apple.quarantine /Applications/Talkie.app`).

## Try it

- Drag a plug into a friend's jack, or click a jack to send the next free cord flying in.
- When the line opens the mic drops onto your screen. Hold it to talk, drag or fling it anywhere.
- Space (while the board is in front) or ⌥Space (from any app) also talks. `F` changes the effect.
- Click the menu bar icon to put the mic away or bring it back. Right-click it for more, including
  **Simulate**: pick a friend on the board and have them patch in, talk, or switch do not disturb.

### The card file

Click the free jack (08) or the **FILE** key on the board.

- Type a friend's code and press **Check**. `TLK-ZOE7` and `TLK-PIP3` work; `TLK-0000` doesn't. A line
  card drops into the OUT tray.
- Drag the card onto the slot above the punch (or just click it). The punch reads it, puts the friend
  on the next free jack and files the card in the Rolodex.
- The board holds eight friends. When it's full the punch refuses the card: turn the Rolodex (the
  knobs, the scroll wheel or the arrow keys) to someone on the board and press **Eject**. Their card
  stays, so you can drag it back into the punch later. Nico, Bea and Tom are already in there.

## Website

The landing page lives in `site/` and goes out to **https://switchtalkie.com** through Cloudflare
Workers Builds: every push to the connected branch runs `npx wrangler deploy` with `wrangler.jsonc`.
`web/worker.js` sends `www.` to the bare domain and `/download` to the latest Talkie.dmg.
Open `site/index.html` in a browser to preview it.

## Layout

| Path | What's there |
| --- | --- |
| `Sources/TalkieCore` | Switchboard rules, cord and mic physics. No AppKit, fully unit-tested. |
| `Sources/Talkie` | The Mac app: menu bar item, board window (SwiftUI), floating mic overlay, sounds. |
| `Tests/TalkieCoreTests` | `swift test` |
| `design/` | The interactive prototype and the decisions behind it. |
| `site/`, `web/` | The website at switchtalkie.com and the Worker that serves it. |

Fonts: [Jura](https://fonts.google.com/specimen/Jura) and [Doto](https://fonts.google.com/specimen/Doto), both under the SIL Open Font License (see `Sources/Talkie/Resources/Fonts`).
