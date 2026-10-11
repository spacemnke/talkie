# Talkie

A walkie-talkie for the Mac with a switchboard instead of a contact list. Drag a patch cord into a
friend's jack and the line opens instantly. While a line is open, a mic drops out of the menu bar on
a coiled cord and floats above every app: hold it (or ⌥Space) to talk.

- **Design reference:** open [`design/prototype.html`](design/prototype.html) in a browser.
- **Decisions so far:** [`design/DECISIONS.md`](design/DECISIONS.md).

## Status

Step 1 of 3: the board. The switchboard window, patch cords with physics and haptics, and the
floating mic all work, with simulated friends. There's no networking or real audio yet; the sounds
are the board's own clicks and beeps.

## Run it

You need a Mac with macOS 14 or newer.

**From Xcode (15 or newer):** open `Package.swift`, pick the `Talkie` scheme and press Run.

**From the terminal:**

```sh
swift run Talkie
```

**As an app:** `scripts/bundle.sh` builds `build/Talkie.app`. Every push also builds one on GitHub
Actions: open the latest run of the **Build** workflow and download the `Talkie-app` artifact.
It isn't notarized yet, so the first time, right-click Talkie.app and choose **Open**.

## Try it

- Drag a plug into a friend's jack, or click a jack to send the next free cord flying in.
- When the line opens the mic drops onto your screen. Hold it to talk, drag or fling it anywhere.
- Space (while the board is in front) or ⌥Space (from any app) also talks. `F` changes the effect.
- Click the menu bar icon to put the mic away or bring it back. Right-click it for more, including
  **Simulate**: have Otto patch in, Maya talk, or Ruby switch do not disturb off.

## Layout

| Path | What's there |
| --- | --- |
| `Sources/TalkieCore` | Switchboard rules, cord and mic physics. No AppKit, fully unit-tested. |
| `Sources/Talkie` | The Mac app: menu bar item, board window (SwiftUI), floating mic overlay, sounds. |
| `Tests/TalkieCoreTests` | `swift test` |
| `design/` | The interactive prototype and the decisions behind it. |

Fonts: [Jura](https://fonts.google.com/specimen/Jura) and [Doto](https://fonts.google.com/specimen/Doto), both under the SIL Open Font License (see `Sources/Talkie/Resources/Fonts`).
