# Talkie — design notes

Open `design/prototype.html` in a browser for the interactive reference. This file records what the
prototype settled, so the native app can match it.

## The idea

A walkie-talkie for the Mac with a switchboard instead of a contact list. To talk to a friend you drag
a patch cord into their jack. The line opens instantly; there is no ringing and no answer button.

## Decided

| Topic | Decision |
| --- | --- |
| Opening a line | Instant. Plugging a cord into a friend's jack opens the line straight away. This is what sets Talkie apart. |
| Do not disturb | Each person has a DND switch. A patch into someone on DND waits in the jack (lamp shows a dash) and opens the moment they switch DND off. Switching DND on during a call closes the line but leaves the cord in. |
| Talking | Full duplex. Both people can talk at the same time, like a phone call. |
| Mute | Private. The person who mutes sees it; the muted person's board never shows it. |
| The mic | Lives in the menu bar when there is no call. When a line opens it drops onto the desktop on a coiled cord and floats above every app. Hold it (or a hotkey) to talk, drag or fling it anywhere, it remembers where you left it. Clicking the menu bar icon puts it away; pulling the last plug winds it back up automatically. |
| Conference | Two cords. Plugging both into different friends makes a three-way line. |
| Voice FX | Off, Canyon (echo), Tin can (thin, crunchy), Helium (octave up), Machine (ring-modulated). Applied before sending, so the friend hears them. |
| Buzz | A key on the mic plays a call tone to everyone on an open line. |
| Eight friends | A board has eight jacks, so eight friends at a time. Everyone you have ever added keeps a line card in your Rolodex, so you can eject someone and punch an old card back in. |
| Adding friends | A friend sends you their code (`TLK-7Q4F`). You check it in the card file, it issues a line card, and you drag the card into the punch. The punch reads it, accepts it, puts the friend on the next free jack and files the card in the Rolodex. Each code works once. |
| Look | Light hardware grey, ink outlines, one signal orange. Thin uppercase type, dot-matrix LCD. |

## Still open

- **Ejected means unreachable?** If only the eight people on your board can patch into you, ejecting someone also stops them reaching you, without telling them. The prototype assumes yes.
- **Hear yourself?** Monitoring your own voice with effects is fun but can feed back through speakers. Maybe headphones only.
- **iPhone?** iOS has Apple's Push to Talk framework. Mac first either way.
- **The mic's look.** The squeeze handle is the closest remaining borrow from Teenage Engineering's FX-MIC. Fine for a prototype; change before shipping.

## Board anatomy

- **Status strip:** SPKR lights while a friend talks, MIC lights while you talk.
- **Nameplate + speaker grille.**
- **LCD:** big line shows who is patched (`MAYA+OTTO`), small line shows state (`LINE A · OPEN · 00:42`, `PATCHING IN…`, `RUBY · DO NOT DISTURB · PATCH WAITS`), flags `A B TX RX FX DND`, and a 12-step level meter.
- **Jack field:** 8 jacks. Each has a lamp, a number, a name strip with a presence dot (filled = online, hollow = away, dash = do not disturb) and the jack itself. A free jack reads `+ ADD`; clicking it opens the card file.
- **Lamps:** off · blinking (connecting) · orange (open) · orange with glow (you're talking) · flicker (they're talking) · dash (do not disturb).
- **Deck:** a well with cord A (orange) and cord B (slate), a volume knob, SND and DND keys.

## Card file

A second window, next to the board.

- **Your code** at the top, with a copy button, to send to friends however you like.
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

1. **The board** — native SwiftUI switchboard and floating mic with real cord physics and haptics. Simulated friends, no networking. *(in progress)*
2. **The line** — two Macs talking at the same time over WebRTC (likely LiveKit), with mute, DND and the four effects.
3. **The operator** — accounts, friends, presence lamps, invite codes and the card file, launch at login (likely Supabase).
