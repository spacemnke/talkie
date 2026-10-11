# Talkie — design notes

The app follows the **Relay** design in `design/relay/` (review boards, the handoff and an
interactive prototype). `design/prototype.html` is the earlier prototype the features were worked
out in. This file records what has been settled.

## The idea

A walkie-talkie for the Mac with a switchboard instead of a contact list. To talk to a friend you drag
a patch cord into their jack. The line opens instantly; there is no ringing and no answer button.

## Decided

| Topic | Decision |
| --- | --- |
| Opening a line | Instant. Plugging a cord into a friend's jack opens the line straight away. This is what sets Talkie apart. |
| Do not disturb | Each person has a DND switch. A patch into someone on DND waits in the jack (lamp shows a dash) and opens the moment they switch DND off. Switching DND on during a call closes the line but leaves the cord in. |
| Talking | Full duplex. Both people can talk at the same time, like a phone call. |
| Mute | Private. Muting a friend only changes what you hear; nothing is sent to them and their board never shows it. It's kept per friend, so it lasts beyond the call. |
| The mic | Lives in the menu bar when there is no call. When a line opens it drops onto the desktop on a coiled cord and floats above every app. Hold it (or a hotkey) to talk, drag or fling it anywhere, it remembers where you left it. Clicking the menu bar icon puts it away; pulling the last plug winds it back up automatically. |
| Conference | Two cords. Plugging both into different friends makes a three-way line. |
| Voice FX | Off, Canyon (echo), Tin can (thin, crunchy), Helium (octave up), Machine (ring-modulated). Applied before sending, so the friend hears them. |
| Buzz | A key on the mic plays a call tone to everyone on an open line. |
| Eight friends | A board has eight jacks, so eight friends at a time. Everyone you have ever added keeps a line card in your Rolodex, so you can eject someone and punch an old card back in. |
| Adding friends | A friend sends you their code (`TLK-7Q4F`). You check it in the card file, it issues a line card, and you drag the card into the punch. The punch reads it, accepts it, puts the friend on the next free jack and files the card in the Rolodex. Each code works once. |
| Look | **Relay.** Light hardware grey, ink outlines, one signal orange; Jura for the hardware, Doto for the LCD. Rounded device shells (20pt windows), inset panels, short raised keys (5pt corners on a 3pt ink base). |
| The mic's shape | The Relay handset: a rounded body with a slotted grille, a round TALK key on the front, FX (orange) and buzz side keys, effect and level lights, and a name tag on a cord from the top. Replaces the earlier squeeze-handle mic. |
| Domain | **switchtalkie.com**: the switchboard plus the walkie-talkie, and the instant line between them. Hosts the landing page now and invite links later. |

## Still open

- **Ejected means unreachable?** If only the eight people on your board can patch into you, ejecting someone also stops them reaching you, without telling them. The prototype assumes yes.
- **Hear yourself?** Monitoring your own voice with effects is fun but can feed back through speakers. Maybe headphones only.
- **iPhone?** iOS has Apple's Push to Talk framework. Mac first either way.
- **The name.** Talkie, or Switchtalkie to match the domain?

## Board anatomy (Relay)

- **Identity panel:** TALKIE / PATCH INTERCOM, a slotted speaker grille, and NET, MIC and SPKR lights.
- **LCD** in a dark bezel: big line shows who is patched (`MAYA + OTTO`, or `READY TO PATCH`), small line shows state (`LINE A · OPEN · 00:42`, `PATCHING IN…`, `TWO CORDS · THREE PEOPLE`), flags `A B TX RX FX DND`, and a 12-step level meter.
- **Socket panels:** eight, one per friend: number, lamp, name, the jack, and presence as a shape plus a word (`HERE`, `AWAY`, `DND`). A free socket reads `+ ADD`; clicking it opens the card file.
- **Lamps:** off · blinking (connecting) · orange (open) · orange with glow (you're talking) · flicker (they're talking) · dash (do not disturb).
- **Deck:** the cord well with cord A (orange) and cord B (slate), a volume knob, and SND, DND and FILE keys.

## Other windows (Relay)

- **Open line:** appears under the menu bar icon when a friend patches in: their name and line time, a big hold-to-talk key, private mute and do not disturb.
- **Voice effects:** the five effects with a line each.
- **Settings:** microphone and output, a live input meter, push to talk, open at login, interaction sounds, reduce motion.
- **Welcome:** three steps on first launch: meet Talkie, allow the microphone (with a path to System Settings if denied), share your code.

## Card file

A second window, next to the board: the card punch on the left, the Rolodex on the right.

- **Your code** across the top, with a copy button, to send to friends however you like.
- **Code entry:** type a friend's code and press CHECK. The punch's LCD says `CHECKING`, then one of `CARD ISSUED`, `UNKNOWN CODE`, `ALREADY USED` or `YOUR OWN CODE`. An issued card drops into the OUT tray.
- **Line card:** a punched card with the friend's name, the date added, a stamp with their jack (`JACK 03`) once they're on the board, and a hole pattern unique to them.
- **The punch:** drag a card onto the slot (or click the card in the tray). It slides in, the LCD reads `READING ▮▮▮▯▯▯▯▯` with a chunk per step, then `ACCEPTED` (friend lands on the next free jack), `ON BOARD` (already there) or `BOARD FULL` (eject someone first).
- **Rolodex:** every card you have, one in front and the next few peeking behind. Turn it with the knobs, the scroll wheel or the arrow keys. EJECT takes the front card's friend off the board; the card stays. Dragging a card from the Rolodex into the punch puts that friend back.

## Interactions

- Drag a plug into a jack to patch; drag it out or tap it to unpatch. Tapping a jack sends the next free cord flying into it.
- Cords hang between their hole in the well and the plug, with a little spring lag so they swing.
- The floating mic: a short hold talks; moving first drags. It tilts in the direction it moves and drifts slightly while idle.
- Space bar = talk. `F` = next effect.

## Build order

1. **The board** — native SwiftUI switchboard, floating mic and card file, with real cord physics and haptics. Simulated friends and codes, no networking. *(in progress)*
2. **The line** — two Macs talking at the same time over WebRTC (likely LiveKit), with mute, DND and the four effects.
3. **The operator** — accounts, real invite codes behind the card file, presence lamps, launch at login (likely Supabase).
