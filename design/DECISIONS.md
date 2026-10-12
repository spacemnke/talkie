# Talkie — design notes

The app follows the **Relay** design in `design/relay/` (review boards, the handoff and an
interactive prototype). `design/prototype.html` is the earlier prototype the features were worked
out in. This file records what has been settled.

## The idea

A walkie-talkie for the Mac with a switchboard instead of a contact list. To talk to a friend you drag
a patch cord into their jack. They hear a knock; when they let you in, the line opens.

## Decided

| Topic | Decision |
| --- | --- |
| Opening a line | A knock (12 Oct; it used to open instantly). Plugging a cord into a friend's jack knocks: they hear a knock, their jack lamp pulses and their mic drops with your name on it. If they let you in, the line opens and you can both talk. If they decline, nothing is sent, so on your side it looks exactly like no answer: after 20 seconds the LCD reads `NO ANSWER` and the cord drops out. Knocking on each other at once opens the line. |
| Answering | Press LET IN on the mic (holding it lets them in and talks straight away), hold the talk hotkey, click their pulsing jack, or plug a cord into it. Decline with the × on the mic's name tag, by putting the mic away, or from the mic's menu. A knock you don't answer stops after 20 seconds (`KNOCKED · MISSED`). |
| Do not disturb | Each person has a DND switch. A knock on someone on DND waits in the jack (lamp shows a dash) and knocks the moment they switch DND off; it doesn't time out while it waits. On your own DND, knocks make no sound and come through when you switch it off. Switching DND on during a call closes the line but leaves the cord in. |
| Talking | Full duplex. Both people can talk at the same time, like a phone call. |
| Mute | Private. Muting a friend only changes what you hear; nothing is sent to them and their board never shows it. It's kept per friend, so it lasts beyond the call. |
| The mic | The one place you talk. Lives in the menu bar when there is no call. When a line opens, or someone knocks, it drops onto the desktop on a coiled cord and floats above every app, 198pt wide. Hold it (or a hotkey) to talk, drag or fling it anywhere, it remembers where you left it. Clicking the menu bar icon puts it away; pulling the last plug winds it back up automatically. A settings key on its left side opens the line's menu: mute for each person on the line, do not disturb, voice effect, hang up, the switchboard and settings. This replaced the separate Open Line window (12 Oct), which repeated what the mic does. |
| Conference | Two cords. Plugging both into different friends makes a three-way line. |
| Voice FX | Off, Canyon (echo), Tin can (thin, crunchy), Helium (octave up), Machine (ring-modulated). Applied before sending, so the friend hears them. |
| Buzz | A key on the mic plays a call tone to everyone on an open line. |
| Eight friends | A board has eight jacks, so eight friends at a time. Right-click a jack to eject someone and make room; their code brings them back. |
| Adding friends | All on the switchboard, no second window. A friend sends you their code (`TLK-7Q4F`), as text or on their line card. Press ADD (or click a free jack), type or paste it, and they land on the jack. Your code is yours to keep: it's how anyone adds you, and the rule below keeps that safe. Replaced the card file, punch and Rolodex (12 Oct): one place to do it is simpler. |
| Windows | Borderless device windows. The title strip drags them and carries Talkie's own window keys, drawn as hollow ink circles: close and minimise work, zoom is off because the devices don't resize. ⌘W closes. |
| Look | **Relay.** Light hardware grey, ink outlines, one signal orange; Jura for the hardware, Doto for the LCD. Rounded device shells (20pt windows), inset panels, short raised keys (5pt corners on a 3pt ink base). |
| The mic's shape | The Relay handset: a rounded body with a slotted grille, a round TALK key on the front, FX (orange) and buzz side keys, effect and level lights, and a name tag on a cord from the top. Replaces the earlier squeeze-handle mic. |
| Name | **Talkie.** switchtalkie.com is the address, not a new name. |
| Ejected friends | Only the eight on your board can knock. Someone you ejected (or never added) can still try: nothing rings and your LCD notes it (`BEA · TRIED TO KNOCK · ADD THEM TO LET IN`). Pressing ADD then offers their code. On their side it's just no answer, so they can't tell they were ejected. |
| Accounts and codes | No sign-up: Talkie signs in anonymously on first launch and the operator (Supabase) gives you a permanent code. Your board of eight lives on the server, so it comes back after a reinstall only if the sign-in does (kept in Talkie's preferences). Adding someone is one-way: their knock only rings for you once you've added them too. |
| The line | When a knock is let in, both Macs join a LiveKit room named after that knock; a server function hands out the passes, only to the two people in it. The microphone is published on joining and muted except while you hold to talk. Real lines are one at a time for now (the practice board still does three-way). Voice effects only change the practice board until they're wired into the outgoing audio. |
| Practice board | The simulated friends stay, one click away in the menu bar menu, so Talkie can be tried alone. |
| Domain | **switchtalkie.com**: the switchboard plus the walkie-talkie, and the line between them. Hosts the landing page now and invite links later. |

## Still open

- **Hear yourself?** Monitoring your own voice with effects is fun but can feed back through speakers. Maybe headphones only.
- **iPhone?** iOS has Apple's Push to Talk framework. Mac first either way.

## Board anatomy (Relay)

- **Identity panel:** TALKIE / PATCH INTERCOM, a slotted speaker grille, and NET, MIC and SPKR lights.
- **LCD** in a dark bezel: big line shows who is patched (`MAYA + OTTO`, or `READY TO PATCH`), small line shows state (`LINE A · OPEN · 00:42`, `KNOCKING…`, `KNOCKING · CLICK THE JACK TO LET IN`, `TWO CORDS · THREE PEOPLE`), flags `A B TX RX FX DND`, and a 12-step level meter.
- **Socket panels:** eight, one per friend: number, lamp, name, the jack, and presence as a shape plus a word (`HERE`, `AWAY`, `DND`). A free socket reads `+ ADD`; clicking it starts adding a friend there. Right-click a friend's socket to eject them.
- **Lamps:** off · blinking (your knock, waiting) · slow pulse with a glow (they're knocking on you) · orange (open) · orange with glow (you're talking) · flicker (they're talking) · dash (do not disturb).
- **Deck:** the cord well with cord A (orange) and cord B (slate), a volume knob, and SND, DND and ADD keys.
- **Adding:** while you add a friend, the identity panel turns into code entry: a friend's code with CHECK (and, until there's a server, codes to try), your code with COPY and SEND CARD, and × to finish. The LCD reads `ADD A FRIEND` / `JACK 08 · TYPE OR PASTE THEIR CODE`, then `CHECKING` and the result (`ZOE` / `NEW ON JACK 08`, `UNKNOWN CODE`, `YOUR OWN CODE`, `ALREADY ON JACK 03`, `BOARD FULL · EJECT SOMEONE FIRST`). The jack they'll land on lights orange.

## Other windows (Relay)

- **Voice effects:** the five effects with a line each.
- **Settings:** microphone and output, a live input meter, push to talk, open at login, interaction sounds, reduce motion.
- **Welcome:** three steps on first launch: meet Talkie, allow the microphone (with a path to System Settings if denied), share your code.

## Your line card

What you send a friend so they can add you: a punched card reading TALKIE LINE CARD, your name (the
first word of your Mac account's name), your code, a PATCH ME IN stamp, and a hole pattern from your
name. SEND CARD shares a picture of it with "Add me on Talkie: TLK-7Q4F", and the board picks the code
out of that whole message when it's pasted in. The welcome screen shows it too.

## Interactions

- Drag a plug into a jack to knock; drag it out or tap it to unpatch. Tapping a jack sends the next free cord flying into it. Tapping a jack that's knocking on you lets them in.
- Cords hang between their hole in the well and the plug, with a little spring lag so they swing.
- The floating mic: a short hold talks; moving first drags. It tilts in the direction it moves and drifts slightly while idle. While someone knocks, its front key reads LET IN and its name tag shows who it is, with a × to decline.
- Space bar = talk. `F` = next effect.

## Build order

1. **The board** — native SwiftUI switchboard, floating mic and adding friends by code, with real cord physics and haptics. *(done; the practice board keeps it)*
2. **The line** — two Macs talking at the same time over LiveKit, with knocks, mute and DND. *(first version; effects and three-way still to come)*
3. **The operator** — accounts, real codes behind ADD, presence lamps (Supabase). *(first version)* Next: notarization, launch at login by default.
