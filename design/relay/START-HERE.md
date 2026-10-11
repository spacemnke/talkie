# Talkie / Relay Mac app redesign

A complete visual redesign of Talkie's Mac surfaces, based on the approved 01 Relay microphone direction. This is a design package and interaction prototype. It does not contain a newly compiled Mac app or real audio networking.

## Review the app

1. `review/01-The-connected-app.png`: switchboard, Relay mic, incoming line.
2. `review/02-Your-people-on-file.png`: card punch, Rolodex, invite, reader states.
3. `review/03-Controls-with-purpose.png`: settings, effects, private mute.
4. `review/04-First-launch-and-identity.png`: first-run setup, app icon, menu-bar states.
5. Open `Talkie-Relay-Prototype.html` in a desktop browser to explore the connected interactions. Everything is embedded, including fonts. It does not make network requests or use the microphone.

`Screens/` is named `screens/` on disk. It contains the individual screen drawings as SVG and PNG. `assets/` contains the Relay microphone, app icon, and menu-bar artwork. `fonts/` contains the supplied Jura/Doto fonts and licences.

## Try these flows

- Click Maya's jack, then Otto's: two cords create a three-way line.
- Hold the floating mic, or Option + Space; release to stop transmitting. The friend-speaking simulation can overlap your transmission.
- Unplug a cord by clicking the connected jack or its dock. Dragging a cord into a jack is also supported.
- Patch Ruby while she is on DND. Use the review control to make her available and open the waiting line.
- Turn your own DND on: connections wait without losing their cords. Turn it off to resume.
- Open the card file. Check `TLK-ZOE7`, then click or drag the issued card into the slot. `TLK-PIP3` is a second valid demo code.
- With all eight jacks occupied, try adding another friend. Eject someone through the Rolodex, then punch the waiting card. The ejected friend's card remains filed.
- Open Incoming line and mute Maya. The control changes local listening only.
- Explore effects, settings, and the three first-run screens through the review navigation above the app.

The navigation and simulation controls outside the app windows are review tools, not proposed app chrome.

## What changed

Relay's silhouette becomes the shared material language: rounded shoulders, inset plates, horizontal grille slots, circular controls, and short raised keys. The switchboard has a more compact identity panel and eight individual socket panels. The card file groups issuing/punching on one side and the Rolodex on the other. Incoming controls and preferences use the same components.

The colour palette, font families, eight-friend board, two cords, physical interaction metaphor, and underlying features are retained. The original source package remains unchanged.

## Verification and limits

All SVG screen/review exports were rendered to PNG and visually reviewed. JavaScript syntax checks passed. State-logic checks passed for the two-cord limit, three-way connections, DND wait/resume, concurrent transmitting/receiving, release-to-stop, one-time codes, adding cards, board-full handling, ejecting without deleting cards, invalid/self codes, and private mute.

Those state checks used a DOM stub, not a browser. Browser layout, native drag-and-drop, pointer capture, and touch behavior remain unverified in this environment. Audio, permission prompts, account connections, input/output device lists, and call tones are simulated. The prototype is a review aid, not production code. Native cord physics, haptics, screen-share exclusion, global shortcuts, and persistent mic positions must remain in the real implementation.

Read `IMPLEMENTATION-HANDOFF.md` for the native feature contract and implementation order.
