# Talkie

A walkie-talkie for the Mac with a switchboard instead of a contact list. Drag a patch cord into a
friend's jack and the line opens instantly. While a line is open, a mic drops out of the menu bar on
a coiled cord and floats above every app: hold it (or ⌥Space) to talk.

- **Design:** the Relay redesign in [`design/relay/`](design/relay/) (review boards, handoff, and
  `Talkie-Relay-Prototype.html` to open in a browser). The earlier prototype is `design/prototype.html`.
- **Decisions so far:** [`design/DECISIONS.md`](design/DECISIONS.md).

## Status

Step 1 of 3: the board, in the Relay design. The switchboard, patch cords with physics and
haptics, the floating Relay mic, adding friends by code, the open-line panel, voice effects, settings
and the welcome steps all work, with simulated friends and codes. There's no networking or real audio yet; the sounds
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

- The first launch walks you through three welcome steps, including microphone access.
- Drag a plug into a friend's jack, or click a socket to send the next free cord flying in.
- When the line opens the mic drops onto your screen. Hold its TALK key (or anywhere on it) to
  talk; drag or fling it anywhere. Its orange side key changes the effect; the grey one buzzes.
- Space (while the board is in front) or ⌥Space (from any app) also talks. `F` changes the effect.
- Drag any Talkie window by its title strip. Its round keys close and minimise it (⌘W closes too).
- Click the menu bar icon to put the mic away or bring it back. Right-click it to add a friend, see
  the open line, voice effects, settings (or ⌘,) and **Simulate**: pick a friend on the board and
  have them patch in, talk, or switch do not disturb, or have someone who isn't on your board try to
  patch in (only the eight on your board can open a line; anyone else just knocks). When a friend
  patches in, the open-line panel appears under the icon; muting them there only changes what you hear.

### Adding friends

It all happens on the switchboard. Press **ADD** on the deck, or click the free socket (08).

- The top panel turns into code entry. Type or paste a friend's code and press **Check** (or Return).
  `TLK-ZOE7`, `TLK-PIP3` and `TLK-NICO` work; `TLK-0000` doesn't. The LCD says how it went and the
  friend lands on the jack that's lit orange. Esc or **×** puts the panel away.
- Your own code sits next to it. **Copy** copies it; **Send card** shares a picture of your line card
  with the code, through Messages, Mail or AirDrop. Pasting that whole message into a board still works.
- The board holds eight friends. To make room, right-click a jack and choose **Eject**. Their code
  brings them back: the sample friends' codes are `TLK-` and their name, like `TLK-MAYA` (the full list
  is in `Sources/TalkieCore/Invite.swift`).

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
