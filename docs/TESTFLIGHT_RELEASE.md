# TestFlight and App Store release checklist

## Prerequisites

- Apple Developer Program membership
- App icon (1024×1024)
- Privacy policy URL: `https://github.com/nurettinbas/Trailhound/blob/main/docs/PRIVACY.md`
- Support URL: `https://github.com/nurettinbas/Trailhound/blob/main/docs/SUPPORT.md`

## Automated tests (CI / local)

- [ ] `./scripts/run_tests.sh` green (unit + UI smoke)
- [ ] GitHub Actions `iOS Tests` workflow green
- [ ] Every feature merged since the last release passed the main feature gate (unit, snapshot, and UI tests; security review; App Review check) — see `.cursor/skills/main-feature-gate/SKILL.md`

## Xcode setup

1. Bundle ID: `com.trailhound.app`
2. Widget: `com.trailhound.app.widget`
3. Signing: Automatic + select Team
4. Capabilities: App Groups, Background Modes (location)

## App Store Connect

1. Create a new app
2. Include privacy manifest: `PrivacyInfo.xcprivacy`
3. Location usage description: trip recording
4. Screenshots: list, detail map, stats, recap, settings
5. Privacy Policy URL: `https://github.com/nurettinbas/Trailhound/blob/main/docs/PRIVACY.md` (the app opens `PRIVACY_TR.md`, the KVKK notice, when its language is Turkish)
6. Support URL: `https://github.com/nurettinbas/Trailhound/blob/main/docs/SUPPORT.md`
7. App Privacy (nutrition label), aligned with `PrivacyInfo.xcprivacy` and `docs/PRIVACY.md`: **Data Not Collected**. Location, photos, and receipts stay on the device. A diagnostic report leaves only when the user sends Mail or the share sheet themselves, which is not app collection. Do not also declare Precise Location as collected.
8. App Review Notes: Kilometre service reminders are local notifications sent after a trip is saved or when the app opens. They are not sent while a trip is recording or paused, and the app never asks for the odometer during a drive. Report a problem opens system Mail or the share sheet only after the user confirms. There is no automatic upload, analytics, or tracking. The attachment has no coordinates, names, or photos. Reviewer devices without Apple Mail should use the share-sheet fallback. Settings → About → Support the developer opens three optional consumable tips (In-App Purchase). They unlock nothing. Say that in the notes so the row is documented, not hidden from review. The first manual Start shows a one-time “Eyes on the road” alert (don’t use the phone while driving; a passenger uses the map and controls); Shortcut and automation starts record on their own without UI. Settings → About → Acknowledgements credits the CC BY-SA trip sounds. Planned route: start a trip, open the live map (map button on the recording card), tap **Destination** just above the recording card and pick a saved place (add one first under Settings → Favorite places) — Apple Maps driving directions draw as a lighter line ahead of the car with remaining distance and arrival time; tap the chip again → **Remove route**. Typing a place search is locked while the car is moving (over about 7 km/h) unless the trip is paused; saved places stay one tap so the driver never types. Directions come from Apple MapKit only; Trailhound has no server and never saves the destination.
9. Privacy manifest warning: if an upload returns **ITMS-91053** for `NSPrivacyAccessedAPICategoryFileTimestamp`, add that category with reason `C617.1` to both `PrivacyInfo.xcprivacy` files. Today `attributesOfItem` reads only file size (`DevLog`, `ModelContainerFactory`), so it is not declared.

## TestFlight

1. Archive → Distribute → App Store Connect
2. Internal testing group
3. Complete the **physical device** checklist below (not automatable in CI)

## Physical device test checklist

These items are also mirrored in code as `DeviceTestChecklist` (`DeviceTestChecklistTests`).

- [ ] **30+ min real drive** — distance and duration advance
- [ ] **Background** — background the app, wait 5 min: recording continues
- [ ] **Shortcuts auto-start** — recording starts when connecting to the car (Bluetooth / CarPlay / Wi‑Fi automation)
- [ ] **Shortcuts wizard test** — Pairing guide “Test start in Trailhound”; session discards on “This was a test, stop”
- [ ] **Shortcuts vehicle pick** — separate CarPlay vs Bluetooth automations assign different vehicles on Start trip
- [ ] **Shortcuts auto-stop** — recording stops when leaving the car
- [ ] **Orphan recovery** — force-quit → reopen → orphan banner / recovery
- [ ] **Map** — detail map route looks realistic (does not cross water)

Optional smoke:

- [ ] **Manual recording** — start / pause / end from the app
- [ ] **Live follow map** — recording card map button → heading follow → pan then recenter → **Show entire route** pulls back just enough that the traveled path stays readable above the recording card (phone, landscape cover, open Duo; follow glide unchanged) → pause: map and 2D/3D tools lock, vehicle stays put, Resume/Stop/close still work
- [ ] **Live follow map feel** — vehicle mark at screen center while following; single blue path appears immediately (no blank window); fills in behind you with no duplicate stroke, no 1 Hz “chunk” at the puck, and never draws ahead of the puck; pan keeps puck + trail updating
- [ ] **Live follow open at speed** — open while moving fast: curved vehicle→puck flight lands on the puck; blue path does not race ahead of a frozen camera during the fade
- [ ] **Live follow map stroke** — path thickness identical in 2D and 3D, and uniform end-to-end while panning a pitched (3D) camera; motion glides with no per-second stall/surge (camera, vehicle mark, and blue path together); camera pulls back at highway speed
- [ ] **Live map planned route** — Destination → saved place: see-through route line only ahead of the car (nothing beside the driven trail), finish pin, chip shows distance · ~arrival; drive off route → re-plans within ~30 s; close and reopen the map → route still there; airplane mode before picking → “Offline” chip; arrive within 50 m → route clears; moving → search shows “Search when stopped”; Stop trip → Destination chip is back next trip. Check phone, landscape, closed/open Duo and iPad (centered form)
- [ ] **Widget / Siri** — start / stop recording via widget or Siri shortcut
- [ ] **Export** — JSON, CSV, GPX, or KML
- [ ] **Report a problem** — Settings → About → Report a problem; confirm disclosure; Mail or share sheet attaches `trailhound-debug.txt`; no Dev Log tab

## Vehicle care & expenses (V13)

- [ ] **Schema upgrade** — open with an existing store; no trip/vehicle loss
- [ ] **Add due date** — service (30/7/1) and insurance/casco (7/1) reminders are scheduled
- [ ] **Overdue banner** — red warning above Trips; dismiss lasts until next day
- [ ] **Add expense** — amount + category; Stats → Vehicle costs chart updates
- [ ] **Delete vehicle** — schedule/expense cascade + care notifications cancelled
- [ ] **Recording scroll** — Trips scrolling stays smooth while a trip is active (no banner regression)

## Installments (V14)

- [ ] **Schema upgrade** — existing one-shot expenses stay one-shot; no trip/vehicle/expense loss
- [ ] **Six installments** — add a 1 200 expense as 6; list shows this month’s 200 + Upcoming for the rest
- [ ] **Stats month** — current month Vehicle costs shows only that month’s share
- [ ] **Edit plan** — change total or count from any slice; all siblings update
- [ ] **Delete** — delete one installment vs delete entire plan

## Travel journal (V19)

- [ ] **Create travel** — Trips tab → Travels → create a journal, pick completed trips; map shows every member route
- [ ] **Suggestion chip** — away-from-home run appears as Suggested travel; Accept files trips, Dismiss does not nag the same fingerprint
- [ ] **Add to travel** — trip detail under the note; Move / Remove does not delete the trip

## Share card

- [ ] **Share from trip detail** — preview then system share; 9:16 JPEG fills Instagram Stories; metric tiles match trip detail (3-column glass, not tiny squares); Share capsule follows Appearance palette (not a fixed sky blue); icon follows Appearance palette; home/work privacy radius clips the route; Instagram Stories gets the image without caption text; WhatsApp / Messages keep the caption

## Smart category (V20)

- [ ] **Suggestion** — Settings toggle on; a completed commute/work-hours trip shows a pending category on the list row; swipe accepts; nothing applies automatically

## Premium Stats (V21)

- [ ] **Year recap** — Recap tab: year awards first, badges, frequent-routes map, month cost forecast, recap poster last + Get your Recap + chapter rail (pump fuel on its own line). January invitation overlay for 7 days.
- [ ] **Year recap share** — story Share circle exports the visible 9:16 JPEG; Instagram Stories opens the page image; WhatsApp / Messages keep the page title caption
- [ ] **Badge share** — unlocked gallery chip is a compact palette-tint Share control; the sheet gets a 9:16 medal JPEG (icon + glass card + Trailhound mark), not title text; Instagram Stories gets the image without caption text
- [ ] **Widgets** — goal ring, last trip, cost summary; Last Trip route preview toggle under Settings → Privacy
- [ ] **Schema upgrade** — existing journal + smart-category data survive; locality/caches backfill without store reset

## Auto-record with Shortcuts

- Auto start/stop is set up via **Shortcuts** (wizard under the Pairing tab): named Shortcut with **Vehicle**, then Personal Automation → **Run Shortcut**.
- On **Start trip**, set **Vehicle** in that named Shortcut (Personal Automations often hide the picker).
- In-app test proves Trailhound handles the external start; it does **not** prove the car automation fired. Stop the test session so an empty trip is not saved.
- “Not working” checklist: Ask Before Running off, Run Shortcut (not a bare Start trip), Location Always, silent start.
- In-app Bluetooth audio-route matching was removed; no extra Bluetooth entitlement is required.
- Location + background location mode are used only during an active recording.

## App Store submission

- [ ] **Paid Apps Agreement** — signed in App Store Connect → Business, with banking and tax forms complete. Tips do not load without it
- [ ] **Tips** — create the consumables `com.trailhound.app.tip.small`, `.medium`, and `.large` (names and prices as in `Trailhound/TrailhoundTips.storekit`). Add a review screenshot of the Support sheet to each and submit them with this version
- [ ] **Small Business Program** — enroll (later) for 15% instead of 30% commission
- [ ] **Marketing URL** — `https://github.com/nurettinbas/Trailhound#support-the-developer` (the README section, not the in-app Privacy or Support pages)
- [ ] **Store text** — description, screenshots, creative assets, and What’s New do not mention the IBAN or bank transfer
- [ ] **Age rating** — answer the current App Store Connect questionnaire
- [ ] **Screenshots** — iPhone set plus 13-inch iPad (the app supports iPad; widgets are iPhone and iPad)
- [ ] **Privacy** — label is Data Not Collected, matching both `PrivacyInfo.xcprivacy` files (app and widget, UserDefaults reasons `CA92.1` and `1C8F.1`)
- [ ] **Export compliance** — `ITSAppUsesNonExemptEncryption` is `false` in `Trailhound/Info.plist`, so the upload question should not repeat
- [ ] **EU DSA** — selling In-App Purchases makes you a trader on EU storefronts; enter the trader contact details, or leave EU storefronts off
- [ ] **Review notes** — Shortcuts automation, background location (attach a short video), Live Activity and CarPlay tile, the Settings → About → Support the developer row (tips unlock nothing), the one-time driving safety alert, and Acknowledgements
- [ ] **KVKK / GDPR** — `docs/PRIVACY.md` and `docs/PRIVACY_TR.md` list rights, legal basis, transfer, and complaint routes; confirm VERBİS exemption (individual developer, under the employee and balance-sheet thresholds, no special-category data)
- [ ] **Encryption / permissions** — purpose strings name the trip or photo use and say location stays on the iPhone

## Release order (summary)

1. Automated tests green
2. Upload TestFlight internal build
3. Physical device checklist (core 6 items)
4. Archive → App Store Connect
