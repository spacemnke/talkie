# Talkie

A walkie-talkie for the Mac with a switchboard instead of a contact list. Drag a patch cord into a
friend's jack and they hear a knock; when they let you in, the line opens. While a line is open, a mic
drops out of the menu bar on a coiled cord and floats above every app: hold it (or ⌥Space) to talk.

- **Design:** the Relay redesign in [`design/relay/`](design/relay/) (review boards, handoff, and
  `Talkie-Relay-Prototype.html` to open in a browser). The earlier prototype is `design/prototype.html`.
- **Decisions so far:** [`design/DECISIONS.md`](design/DECISIONS.md).

## Status

Real lines between Macs, in their first version. Talkie signs in to its operator (Supabase) on
launch, gets you a permanent code, keeps your board on the server, shows who's around, and
carries knocks. When someone lets you in, LiveKit carries your voices, through your voice effect if
you picked one. A practice board with simulated friends is in the menu bar menu.

Not yet: payments (everyone is on Free until they open), more than one real line at a time, and
notarization.

## Free and Pro

| | Free | Pro |
| --- | --- | --- |
| Jacks (friends on your board) | 3 | 8 |
| Call length | 10 minutes; no limit if the other person has Pro | No limit |
| Voice effects (Canyon, Tin can, Helium, Machine) | Try them on your own voice | On your calls; only your own voice changes |
| Knock sounds | The standard knock | Pick one per friend (right-click their jack) |
| Knocking, mic, do not disturb, private mute, buzz | Yes | Yes |
| Price | Free | $4 a month or $36 a year (payments open after the beta) |

The server decides: your plan, how many jacks you can fill and knock from, and how long each line can
last. The app shows locked jacks as **PRO**, counts down the last minute of a free call on the LCD,
and opens the **Talkie Pro** window when you reach for something Pro. To make someone Pro for
testing, run `update public.profiles set pro = true where code = 'TLK-XXXX';` in the Supabase SQL
editor (set `pro_until` to give it an end date). On the practice board, **Simulate → Free Plan / Pro
Plan** switches between the two, and **Free Call's Last Minute** skips to the end of a free call.

## Test it with a friend

1. Both of you install Talkie from the latest build (below) on a Mac with macOS 14 or newer, and
   let it use the microphone.
2. Each of you opens the switchboard: the LCD shows your code (also under **ADD**). Swap codes.
3. Press **ADD**, type the other's code and press **Check**. Do it both ways: your knock only rings
   for someone who has you on their board.
4. Drag a cord into their jack. They hear a knock and their mic drops with your name on it. They
   press **LET IN** (or hold it to talk at once); then hold the mic or ⌥Space to talk.

The menu bar menu's first line says whether you're online, and why not if you aren't.

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
- Drag a plug into a friend's jack, or click a socket to send the next free cord flying in. That
  knocks: the lamp blinks until they let you in (practice friends do after a moment).
- When the line opens the mic drops onto your screen. Hold its TALK key (or anywhere on it) to
  talk; drag or fling it anywhere. Its orange side key changes the effect (Pro); the grey one buzzes. The
  key on its left side opens the line's menu: mute, do not disturb, voice effect, hang up.
- Space (while the board is in front) or ⌥Space (from any app) also talks. `F` changes the effect.
- **Voice Effects…** in the menu bar menu: pick one, then hold **HOLD TO TRY IT**, say something and
  let go to hear yourself through it. Anyone can try them; on Pro the people on your line hear it.
- Drag any Talkie window by its title strip. Its round keys close and minimise it (⌘W closes too).
- Click the menu bar icon to put the mic away or bring it back. Right-click it to add a friend, voice
  effects, settings (or ⌘,) and **Practice Board**. On the practice board, **Simulate** picks a
  friend and has them knock, talk or
  switch do not disturb, or turn off **Answers Your Knocks** to see what a decline looks like from
  your side (no answer, and the cord drops out after 20 seconds). Someone who isn't on your board
  can only try to knock: you get a note and nothing rings.
- When a friend knocks you hear it, their jack pulses and the mic drops with their name on it.
  Press **LET IN** on the mic (hold it to talk straight away), hold ⌥Space, or click their jack.
  The **×** on the mic's name tag declines, and they're never told.

### Adding friends

It all happens on the switchboard. Press **ADD** on the deck, or click the free socket (08).

- The top panel turns into code entry. Type or paste a friend's code and press **Check** (or Return).
  The LCD says how it went and the friend lands on the jack that's lit orange. Esc or **×** puts
  the panel away. On the practice board `TLK-ZOE7`, `TLK-PIP3` and `TLK-NICO` work; `TLK-0000` doesn't.
- Your own code sits next to it. **Copy** copies it; **Send card** shares a picture of your line card
  with the code, through Messages, Mail or AirDrop. Pasting that whole message into a board still works.
- The board holds three friends on Free and eight on Pro. To make room, right-click a jack and choose **Eject**. Their code
  brings them back. (On the practice board the sample friends' codes are `TLK-` and their name, like
  `TLK-MAYA`; the full list is in `Sources/TalkieCore/Invite.swift`.)

## Website

The landing page lives in `site/` and goes out to **https://switchtalkie.com** through Cloudflare
Workers Builds: every push to the connected branch runs `npx wrangler deploy` with `wrangler.jsonc`.
`web/worker.js` sends `www.` to the bare domain and `/download` to the latest Talkie.dmg.
Open `site/index.html` in a browser to preview it.

## Layout

| Path | What's there |
| --- | --- |
| `Sources/TalkieCore` | Switchboard rules, cord and mic physics. No AppKit, fully unit-tested. |
| `Sources/Talkie` | The Mac app: menu bar item, board window (SwiftUI), floating mic overlay, sounds. `Online/` talks to the operator (Supabase) and carries voices (LiveKit). |
| `supabase/` | The operator's schema and the function that hands out line tokens. |
| `Tests/TalkieCoreTests` | `swift test` |
| `design/` | The interactive prototype and the decisions behind it. |
| `site/`, `web/` | The website at switchtalkie.com and the Worker that serves it. |

Fonts: [Jura](https://fonts.google.com/specimen/Jura) and [Doto](https://fonts.google.com/specimen/Doto), both under the SIL Open Font License (see `Sources/Talkie/Resources/Fonts`).
