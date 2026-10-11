# Relay implementation handoff

## Direction and scope

The owner explicitly requested a redesign of the entire Mac app and selected the 01 Relay microphone look. This supersedes the old brief's restriction against a full visual redesign. Keep the product behavior specified in the original `BRIEF.md` and `source/DECISIONS.md`.

The deliverable is a visual specification plus a connected, simulated HTML prototype. Port the design into the existing native architecture; do not replace the native app with an embedded website. Keep the existing networking work independent of this visual revision.

## Component language

- Original palette only: paper #F1F1EF, shell #D3D4D4, plate #E7E4DD, white #FBFBF9, ink #1B1B1B, orange #E0663A, slate #8B96A3, and existing LCD/neutral tones.
- Orange marks live audio, the existing effect key, card bands, and the active talk key. Ordinary preference and mute switches use neutral materials.
- Jura remains hardware/UI type. Doto remains the LCD type. The large TALKIE wordmark uses Jura Light.
- Outer native window radius: 20 pt, proposed increase from the former 10 pt to echo Relay's shoulders. Inset panel radius: 10–14 pt; keys: 5 pt. These are deliberate new geometry tokens, not a new palette.
- Main outline: 2 pt; inset outline: 1–1.5 pt. Device shadow: ink at 16%, hard 6 × 8 pt, no blur. Keys have a 3 pt solid ink base and depress onto it.
- Use live native text for implementation, not outlined SVG text, so names remain accessible and localizable. SVG text was outlined in static screens for reliable review.
- Main switchboard: 520 × 698 pt. Card file: 800 × 618 pt. Incoming popover: 330 × 349 pt. Effects: 330 × 415 pt. Settings: 520 × 616 pt. First run: 580 × 477 pt.
- Relay SVG master is 140 × 270 units, rendered at a 110 pt footprint. Normalise its outer outlines to 2 pt if redrawing it in SwiftUI. Its body is a distinct handset with a circular front talk key, two side keys, five effect indicators, and an audio meter.

## Feature preservation contract

| Feature | Required native behavior | New surface |
| --- | --- | --- |
| Eight friends | Exactly eight jacks; unassigned slots show + ADD | Individual socket panels |
| Two cords | A orange, B slate; patch either; both create a three-person line | Shared cord well, visible endpoints |
| Instant line | No ringing or answer screen; connection indication settles quickly | LCD and orange jack lamp |
| Full duplex | Transmit and receive can run concurrently | Independent TX/RX states, not one mutually exclusive state |
| Local DND | Stops open audio but leaves patches in place | Deck key, LCD flag, menu-bar state |
| Friend DND | Patch waits in the friend's jack; resumes on availability | Dashed lamp and literal waiting status |
| Private mute | Suppresses selected remote audio locally; sends no mute-status notification to that peer | Incoming-line switch |
| Floating mic | Only available with an open line; visible above other apps/full-screen; movable/flingable and remembers position | Relay handset |
| Put away | Menu-bar click hides mic without disconnecting; last unplug retracts it | Existing menu-bar jack |
| Hold-to-talk | Hold mic/key or global Option + Space; release, cancellation, or lost input capture stops transmission | Front talk key and keyboard affordance |
| Effects | Off, Canyon, Tin can, Helium, Machine; applied before sending | Side key plus full effect picker |
| Buzz | Call tone to everyone on the open line | Grey side key |
| Screen privacy | Floating mic excluded from screen sharing/recording | Native window capture behavior, no browser equivalent |
| Friend codes | Existing one-use semantics; clear own/unknown/used errors | Code field and punch LCD |
| Issued card | Code check creates card in OUT tray | Reader panel |
| Punch | Read progress then accepted/on-board/full result; next free jack | Slot with drag plus keyboard/click alternative |
| Rolodex | Every added friend stays filed; arrows, scroll and keyboard navigation | Front card with depth stack |
| Eject | Removes board assignment, frees a jack, retains card | Eject from board key |
| Presence | Filled = here, hollow = away, dash = DND | Shape plus text in each socket panel |
| Volume and sounds | Master listening volume and short interaction sounds | Deck knob/SND plus audio settings |
| Reduced motion | Follow the Mac setting; no repeated spring motion if reduced | Static settling/short fades |

Do not silently decide the two unresolved product questions: whether ejected people can still reach you, or whether effect self-monitoring exists. Preserve the current baseline behavior until the owner decides. Do not add an iPhone flow.

## Native file mapping

- `Theme.swift`: retain palette, update radii/spacing/type scale and shared inset-panel/key styles.
- `BoardView.swift`: replace board composition, socket panels and LCD; keep existing line and presence state logic.
- `CordsLayer.swift`: retarget dock/socket geometry. Preserve spring behavior and haptics. Cords must avoid names and controls; test every endpoint, not just the Maya/Otto example.
- `MicArt.swift`: implement Relay silhouette and its pressed/input/effect states. Retain floating-window positioning, overlay and capture rules in the owning controller.
- `CardFileView.swift`: use the two-column reader/file layout; retain one-use codes, slot reading, errors, file navigation, and ejection.
- `StatusIcon.swift`: retain idle/live/connecting/DND logic. Use template alpha artwork for idle and DND, blink the idle template during connection, and the signal-orange artwork for live. Verify contrast in both macOS menu-bar appearances.
- Incoming popover and settings view: integrate into their existing owners, or create small native views if they do not yet exist. Audio selectors and login behavior shown here are proposed UI settings; wire them to real platform services.
- First-run coordinator: introductory screen → real mic permission result → code sharing/board. A denial must offer a clear System Settings path and retry. Never advance as if permission were granted after a denial. The prototype advances only to demonstrate the design.

## Behavior details to preserve during implementation

1. Use separate booleans for transmitting and receiving. Both can be true. Multiple peers may be received while transmitting.
2. Derive active audio connections separately from retained cord assignments. DND suspends audio without erasing a patch.
3. Delay/resolve the hold gesture against drag intent. No stuck transmitting state after drag cancellation, app deactivation, lost capture, disconnection, or last unplug.
4. Make every jack/cord/card interaction available without dragging. Ensure tab order, VoiceOver labels and adequate hit areas. Tiny labels in concept artwork must not be the sole affordance for FX or Buzz.
5. Use separate transparent cord, handset and tag layers to preserve cable attachment during dragging. The static geometry is an example, not a physics implementation.
6. A multi-person mic tag must fit both names and indicate simultaneous TX/RX. Truncate long names accessibly; keep the full participant list available.
7. In the card file, retain an issued card after BOARD FULL. Do not consume it visually or lose it when a user frees a jack.
8. Make private mute persist locally without exposing the setting on the other person's board.
9. Persist sound, volume, selected audio devices, startup preference and handset position. Demo settings do not write system configuration.
10. Native text scales and contrast should be checked on a real display. At 110 pt, tiny hardware legends need tooltips and larger menu equivalents.

## Validation for the real build

- Two Macs: establish, talk, receive concurrently, mute privately, DND/resume, buzz, change all effects.
- Three participants: both cords on one board and correct peer routing/levels.
- Eight-jack capacity, duplicate/self/unknown code, reader interruption, full board, ejection and reinsert.
- Mic above full-screen apps, capture exclusion, position persistence and reduced motion.
- Light and dark menu bars, Retina/non-Retina, long names, keyboard and VoiceOver.
- Onboarding permission allow/deny/retry and launch-at-login behavior.

The design package itself has no compiled Swift build verification. Do not describe these native behaviors as shipped until the app has been implemented and tested.
