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
| Look | Light hardware grey, ink outlines, one signal orange. Thin uppercase type, dot-matrix LCD. |

## Still open

- **Hear yourself?** Monitoring your own voice with effects is fun but can feed back through speakers. Maybe headphones only.
- **iPhone?** iOS has Apple's Push to Talk framework. Mac first either way.
- **The mic's look.** The squeeze handle is the closest remaining borrow from Teenage Engineering's FX-MIC. Fine for a prototype; change before shipping.

## Board anatomy

- **Status strip:** SPKR lights while a friend talks, MIC lights while you talk.
- **Nameplate + speaker grille.**
- **LCD:** big line shows who is patched (`MAYA+OTTO`), small line shows state (`LINE A · OPEN · 00:42`, `PATCHING IN…`, `RUBY · DO NOT DISTURB · PATCH WAITS`), flags `A B TX RX FX DND`, and a 12-step level meter.
- **Jack field:** 8 jacks. Each has a lamp, a number, a name strip with a presence dot (filled = online, hollow = away, dash = do not disturb) and the jack itself. The last jack is free (`+ ADD`, shows an invite code).
- **Lamps:** off · blinking (connecting) · orange (open) · orange with glow (you're talking) · flicker (they're talking) · dash (do not disturb).
- **Deck:** a well with cord A (orange) and cord B (slate), a volume knob, SND and DND keys.

## Interactions

- Drag a plug into a jack to patch; drag it out or tap it to unpatch. Tapping a jack sends the next free cord flying into it.
- Cords hang between their hole in the well and the plug, with a little spring lag so they swing.
- The floating mic: a short hold talks; moving first drags. It tilts in the direction it moves and drifts slightly while idle.
- Space bar = talk. `F` = next effect.

## Build order

1. **The board** — native SwiftUI switchboard and floating mic with real cord physics and haptics. Simulated friends, no networking. *(in progress)*
2. **The line** — two Macs talking at the same time over WebRTC (likely LiveKit), with mute, DND and the four effects.
3. **The operator** — accounts, friends, presence lamps, invite codes, launch at login (likely Supabase).
