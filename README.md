# Trailhound

[![iOS Tests](https://github.com/nurettinbas/Trailhound/actions/workflows/ios-tests.yml/badge.svg)](https://github.com/nurettinbas/Trailhound/actions/workflows/ios-tests.yml)

**Privacy-first trip recorder for iOS** — track drives with GPS, estimate fuel cost, and keep every mile on your device. No account, no cloud, no third-party SDKs.

Trailhound is a native SwiftUI app built with SwiftData. It records routes locally, works offline, and can start/stop automatically via **Shortcuts Personal Automations** (Bluetooth, CarPlay, or Wi‑Fi) — or manually from the app, widget, Live Activity, and Siri.

---

## Features

- **Cold-launch intro**: each fresh launch shows the icon’s road, hound, and corner stopwatch large on the theme color. The road matches the icon and its dashes move; the hound gallops in place, legs gathering and stretching with a flexing back. The stopwatch’s crown is pressed, its hands sweep a little fast, and it rocks like a watch held in the hand. Everything then coasts to rest as the theme plate closes from the corners into the app icon, which lands with a soft haptic and fades out. About 1.7 seconds in all. Tap anywhere to skip. It does not replay when returning from the background, and it is skipped for Shortcut or widget starts, deep links, and VoiceOver. Reduce Motion shows a still mark. Settings → About → **Play launch intro** plays it again. The **Start** control on every tab uses that same in-place gallop

### Recording
- Manual start/stop, pause/resume. **Start** (with the vehicle picker) sits on every tab and returns to the Trips recording card. Its hound runs in place with the same jointed gallop as the launch intro. It hides while a trip is already recording or paused. The notification bell stays while a trip is recording. Once the recording card scrolls off screen, the steering-wheel control stays in the Trips bar and returns to that card, including landscape when the card scrolls with the list. A wide landscape iPhone keeps that card on the leading side, so the control stays hidden. On that short screen the Trailhound title hides while recording, the road uses the compact scene, and duration, speed, distance, and average sit on one row, so Pause and Stop stay above the tab bar. Rotating does not flash that control while the card is still at the top of the list
- **Eyes on the road**: the first manual Start shows a one-time reminder not to use the phone while driving (a passenger uses the map and controls). Shortcut and automation starts record on their own and never show it
- **Shortcuts auto-start / auto-stop**: Create a named Shortcut per vehicle (*Start trip* + **Vehicle**), then a Personal Automation that **Run Shortcut**s it on Bluetooth / CarPlay / Wi‑Fi connect (automations often hide the Vehicle picker). The **Pairing** setup wizard remembers the trigger and vehicle, shows every Shortcuts step (including Run Shortcut), tests that Trailhound handles an external start, and includes a not-working checklist. Apple cannot let Trailhound create the automation for you. See [Shortcuts auto-record](docs/SHORTCUTS_AUTORECORD.md)
- Vehicle profiles with fuel/EV cost per trip
- **Avg fuel**: catalog cost from `distance × consumption × price`, shown as currency · litres (or kWh) like Estimated fuel. Trip detail **Avg fuel calculate** (with ?) edits consumption and unit price; the live line is **Avg fuel estimate**. Defaults from the vehicle and Settings
- **Estimated fuel**: starts from this vehicle’s average (`C₀`), then adds GPS litres for this trip. Short stop-go is usually above your average; a steady highway trip is usually below. Shown as currency · litres (or kWh) · L/100 on trip detail, with driving efficiency, traffic, and factor chips; Stats totals match after backfill. A Stop pin is not engine-off. Not a pump reading.

  ```
  Avg  = km × C₀ / 100

  Est litres = Avg
             + speedDelta      // km × C₀/100 × (distance-weighted speed factor − 1)
             + idle            // idle hours × idle L/h(C₀)
             + transient       // acceleration energy, ≤ 35% of Avg
             + cold start      // previous trip soak, scaled to C₀

  L/100 = 100 × Est litres / km
  cost  = Est litres × unit price
  ```

  Traffic is a label, not a multiplier. Same GPS trace at C₀=5 vs C₀=12 keeps `rate/C₀`. Engine: `TripFuelEstimate` (v6). Details: [Fuel estimation](docs/FUEL_ESTIMATION.md)
- **Vehicle avatar photos**: choose Library or Camera, then an in-app ~70% gallery/camera overlay and frame the crop before save (shown in recording / Live Activity)
- Siri Shortcuts: *Start trip*, *Pause trip*, *Resume trip*, *End trip*
- Widget + Live Activity controls
- Extra Home Screen widgets: **goal ring**, **last trip** (privacy-clipped thumbnail, optional), **monthly cost forecast**. Goal opens Stats; forecast opens Recap; last trip opens the trip. Recording Pause/Stop stay on the original control widget (and on the last-trip medium family while a session is active)
- **CarPlay Live Activity** (iOS 18+): while recording, the dashboard tile shows the vehicle icon plus duration, distance, and speed (same type size, shrink together when values get long; non-interactive; Lock Screen / Dynamic Island controls unchanged). The tile uses CarPlay’s native Liquid Glass like Maps / Now Playing — clear snapshot, no extra frost plate. Phone-call snapshot stacking is skipped while the in-call UI owns the dashboard
- Optional confirmation before widget/shortcut/deep-link recording start
- **Live follow map** (optional): Maps-style 3D/2D follow with the vehicle mark locked to screen center while following — the camera **and the blue trail** glide between GPS fixes (no 1 Hz hitch or chunky path updates) and **pull back as you speed up**; opening the map at speed keeps the curved vehicle→puck flight on the moving mark; a single blue traveled path fills in behind you at constant thickness in 2D and 3D; **Show entire route** pulls the camera back just enough to fit the traveled path into the clear map — above the recording card on a phone, beside it on a landscape cover and open Duo — north-up, on a short smooth zoom, while the vehicle photo and heading chevron still face the direction of travel; screen stays awake while open; start/pause pins on the map; Duration, speed, and distance stack in the leading bottom corner. The 2D/3D switch and the overview/follow switch sit side by side in the bottom center, at 1.5× the old compact size. Pause and Stop stay bricks in the trailing bottom corner (icon above the word). Pause is warning orange, title and icon. Stop’s title and icon are red. The destination chip sits on that same bottom edge, between the two columns. A back chevron sits in the leading corner; the map does not repeat Trip started. Swiping in from the leading edge leaves the map. Stop’s icon stays red; the plate does not. Pause and Stop stay available; while **paused**, the map cannot pan/zoom and 2D/3D / overview tools are locked so the vehicle stays put — Resume, Stop, and back still work; road animation pauses while the map is open
- **Planned route on the live map**: tap **Destination** on the live map and pick a saved place, one of up to four **nearby places** listed under the empty search field, or search for one, including while the trip is moving. Apple Maps driving directions draw ahead of the car as one solid line in a lighter shade of the theme colour, the same width as the driven trail. The part already driven stays the solid trail, and the plan is never drawn beside it. The chip shows remaining distance, a red countdown of the remaining minutes, and the estimated arrival time, with a finish pin. A longer estimate says the route is being calculated, then shows the new minutes and clock. Missing a turn does not drag the line back to that turn: two short notes say the turn was missed and a new route is being calculated, and the first miss recalculates immediately (a further miss waits 8 s). The next turn from that same Apple reply shares one card with the destination under the back button. The card's collapse button folds it into a small glass chip with the next-turn icon, the minutes left, and the distance, so the whole map shows; tapping the chip widens it back into the card. The card is 15% narrower than a full-width bar and 25% taller than the old bottom card. The destination button is on top. The instruction sits underneath, with an icon for the turn (left, right, slight, U-turn, straight, exit, merge, roundabout, or arrival), white in Dark and the theme colour in Light. It hides while the route is being recalculated. Arriving clears it; offline or "no route" show a clear note. Search stays available while the car is moving. The destination survives closing the map and is cleared when the trip ends; it is never saved. Works on phone, landscape, the closed and open Duo, and iPad (centered form on the open Duo and iPad)

### Privacy & data
- All trips stored locally with **SwiftData** (file protection on store)
- Offline-first recording; geocoding retries when online
- Home/work saved places with privacy radius (route clipping)
- Optional Face ID app lock (device passcode required)
- Optional blur of coordinates on export
- Configurable auto-delete (Never, or 30/90/365 days)
- Export: JSON, CSV, GPX, KML
- **Report a problem** from Settings → About (optional): you can mail a sanitized diagnostic log to support. No analytics, no automatic upload, no Dev Log tab; on-device logs expire after 30 days. See [Privacy](docs/PRIVACY.md) and [Support](docs/SUPPORT.md)
- In-app **Privacy Policy** under Settings → About (same text as [docs/PRIVACY.md](docs/PRIVACY.md)). A Turkish UI opens the Turkish policy and KVKK notice ([docs/PRIVACY_TR.md](docs/PRIVACY_TR.md)). Both list your GDPR / KVKK rights, legal basis, retention, international transfer, and where to complain
- **Acknowledgements** under Settings → About credit the CC BY-SA 3.0 trip start and stop sounds (Edvvc, Wikimedia Commons). See [docs/ACKNOWLEDGEMENTS.md](docs/ACKNOWLEDGEMENTS.md)
- **Support the developer**: Settings → About → Support the developer offers three optional tips through Apple In-App Purchase, on every App Store storefront. A tip unlocks nothing, and Apple handles the payment. Trailhound never sees your card or account
- Settings → About ends with **Developed by Nurettin Baş**

### Appearance
- Settings → **Appearance**: **System** (default, follows the iPhone), **Light**, or **Dark**, plus a **20-color shell palette** (Sky, Ocean, Teal, Mint, Forest, Lime, Gold, Sunset, Orange, Coral, Rose, Pink, Magenta, Purple, Violet, Indigo, Slate, Graphite, Sand, Ember). Default color is Sky. Phone Settings is one form (Recording through About). On the open book, and on a landscape iPhone wider than the closed Duo cover, the section list is glass rows and the checkmark follows the visible form section. When the Duo hinge is fully open that list is 40% of the content and the form is 60%. That wide iPhone uses the same 40/60, and the form does not paint a second background behind the split. The section list uses short rows; only the form is the long scroller. A partially open hinge keeps the seam on the fold. The closed cover and a narrower phone keep one column
- **Liquid Glass** (iOS 26 native `glassEffect`, Material fallback on iOS 17/18): frosted cards over the selected hue so the atmosphere shows through. Light uses native glass with a mid-family tint — not a dark chrome plate or milky white card. The glass plate clips to the card; labels in the corners are not sliced. Reduce Transparency uses an opaque mid-family fill. Dark is a deep shade of the same color. The trips-list recording card, follow path, and vehicle puck use the same hue; **Stop** on that card stays solid red. The live-map HUD (duration, speed, distance, Destination, 2D/3D, Pause, Stop) is a compact cluster of theme-tinted Liquid Glass plates in Light and Dark, rendered as one glass group so it stays light on battery; only the Stop icon is red. The tab bar is the system iOS 26 Liquid Glass bar in Light and Dark, bottom and side. Unselected items stay the system ink. The selected tab uses that appearance’s palette tint. Map toolbars stay frozen circles so MapKit is not resampled
- The **Home Screen icon** follows the selected color (Sky keeps the Liquid Glass icon; other hues use a matching light/dark pair). iOS shows one confirmation when the icon changes. Home Screen light/dark still follows the iPhone, not the in-app Light/Dark picker. See [Design system](docs/DESIGN_SYSTEM.md) and [Appearance (wiki)](https://github.com/nurettinbas/Trailhound/wiki/Appearance)
- **Confirmation toasts** rise from the bottom, above the tab bar (or the bottom safe area on a sheet). Each one is a Liquid Glass card with a larger animated emblem and a haptic that matches the action: save, delete, merge, warning, Shortcuts automation, or a personal record. Reduce Motion keeps the fade and skips the icon motion

### Maps & analytics
- MapKit route polylines with speed-colored segments
- Trip detail: full-screen map with a fixed details card (scroll to edit; toolbar expands the map in place). Narrow phone landscape, including the closed Duo cover and iPhone SE, rests that card on the bottom edge of the screen and frames the route in the map above it. A landscape iPhone wider than that cover matches the open book: details on the leading half, the route map on the trailing half. After a turn, fold, or unfold, the route glides back to the center of the map that is still visible
- Trip summary cards pack left-to-right in a 3-column grid (no leftover empty slots mid-grid) and include **travel time** (moving minutes, excluding pauses) next to **duration**, **cruise speed** (average while moving — excludes stops), **most common** (mode of driving pace, not queue crawl) / **median** speeds, and **stop time** alongside average/max
- Trip stops (dwell detection), route thumbnails with vehicle photo/icon badge — list, travel-mosaic maps, and share cards follow Light/Dark and the selected palette. Switching Light/Dark keeps the last thumbnail visible until the matching map image is ready, so the trip list does not flash empty while scrolling
- Swift Charts stats, trends, monthly distance goals — including daily **cruise speed**, **most common** speed, **stop time**, **night driving** share, and dual **avg / estimated** fuel charts
- **Stats comparison** (same tab, no extra load on open): one glass-card language — 2-up goal + hero numbers, nested summary tiles with previous-period lines, polarity-aware arrows, a **Logged vehicle expenses** card (sums Pairing expenses, not trip GPS fuel; `?` explains the source) with cost/km, and swipeable chart pagers. The goal card carries **Summary**. The hero card and the metrics grid carry the period inside the glass. Chart section titles sit on each card and stay pinned while that card shortens (Daily, Weekday, Split, Vehicles, Categories). The filter card stays in the list with period chips, titled fields (category, vehicle, place, travel), and **Clear All**. An in-progress month compares against the same days last month. Place, journal, or category chips hide expense MoM and vehicle $/km (those filters have no expense dimension); the goal ring stays unfiltered. Summary tiles show a packed skeleton while the filtered snapshot loads, so the grid does not leave empty holes. When the Duo hinge is fully open, the summary column is 45% of the content and the distribution charts are 55%. A landscape iPhone wider than the closed Duo cover uses that same 45/55. A partially open hinge keeps that seam on the fold. The closed cover and a narrower phone stay one column
- **Recap tab** (Trips → Vehicles → Statistics → **Recap** → Settings; EN Recap / TR Yıllık): year awards, badges, frequent routes, month forecast, and the year recap story. Same glass cards as Stats. Phone Recap pins each section title on its glass card while the card shortens from the top; the year picker stays on the awards card. Upright Duo and iPad portrait, including iPad mini, pack those four hubs into two equal columns from the top (Year in Review then Frequent routes, Badges then This month’s forecast) so a short card does not leave a hole above the next one; the year recap story stays full width under them. Expanded badges, routes, and forecast shrink back onto the card when you swipe in from the leading edge. Unfiltered year / all vehicles — not the Stats chips. When the Duo hinge is fully open, the leading card column is 45% of the content and the trailing column is 55%. A landscape iPhone wider than the closed Duo cover, and iPad landscape, pack the same cards into those 45/55 columns. iPad has no hinge. A partially open hinge keeps that seam on the fold. The closed cover, a narrower phone, and iPad portrait stay one column under the hub grid
- **Year awards** first on Recap: unfiltered calendar-year medal grid (distance, night owl, goal months, busiest day, costliest vehicle / month). Recap is the story; awards are the grid
- Category filters, trip merge (select completed trips on the list; there is no split)
- **Share card** from trip detail — 9:16 JPEG (same canvas as recap / badge stories) with the trip-detail glass metric grid (3 columns, icon + title + value). Instagram Stories fills edge-to-edge; Instagram / Facebook get the image only; WhatsApp / Messages / Mail keep the caption. Privacy-clipped route snapshot, Light/Dark palette, matching app icon
- **Year recap** last on the Recap tab: compact poster hub (scene fills the glass plate, Get your Recap chip never truncates) opens a cinematic full-screen story. On iPhone that story stays upright even when the phone is already sideways; the open book and iPad keep the vertical 9:16 column. A horizontal chapter rail under the poster sits on the tab atmosphere and jumps into that story page. The first page is a title card (kicker + huge year + whisper on a vanishing-road bloom — no clipart). A purpose page names the year’s dominant category (built-in or custom) when there is a real winner, then lists every category’s share of the year’s km (percent + name + distance) — not a business-vs-personal table. A cost page shows estimated driving fuel and logged pump fuel as two separate glass cards under dual-hue pumps — never summed. Palette Canvas pages fill the cover with looping scenes, tap the left third of the screen (including the edge) to go back and the rest to go forward like Instagram (no Next), segment bars tuck under the Dynamic Island, Close and Share sit under them as Liquid Glass circles. Share exports the page you’re on (same scene and copy, 9:16 JPEG). Instagram / Facebook get the image only; WhatsApp / Messages / Mail keep that page’s title as the caption — not a leftover km poster or a bare Trailhound string. The badges page sits medals inside the glowing orbs (sparkles on the story), copy overlays the scene, Liquid Glass Share/Close. Badges unlocked that year show as the same 3D medals as the Recap gallery. The last page wraps the year (not a slogan); its segment fills like the others, then the story closes. Hold to pause. January plays the previous year; other months are year-to-date. Corridor counts are for that year only. Estimated driving fuel and logged pump fuel stay on separate lines. Replay any time. In January a 7-day full-screen invitation (Close or Get your Recap) replaces the old Dec/Jan autoplay; inbox / recap deep link still opens the story. A local notification + inbox row opens the story when last year’s recap has trips and you have not watched it yet
- **Badges**: cumulative km (100 silver, 1,000 gold, 10,000 teal platinum, 100,000 lavender diamond — each km medal runs a different motion on the S; the full km ladder stays in the gallery even while locked), plus business / streak / cities / night / corridor ladders and trips, hours, long haul, dawn, weekend, fleet, and countries — each family has its own color, icon, and idle. Recap compact card wraps every unlocked medal in centered rows and grows down (no sideways scroll); expand is a plain toolbar glyph on the card, then a circled collapse once expanded; the card grows into a glass gallery with 3D round medals (unlocked first); locked badges show formatted progress (km or counts) without spoiling the next non-km tier. Share on an unlocked medal is a compact palette-tint chip and exports a 9:16 JPEG story card (atmosphere, Trailhound mark, glass plate, 3D medal + copy). Instagram / Facebook get the image only; WhatsApp / Messages / Mail keep the badge caption — not a title string. Newly unlocked badges celebrate on Recap (3 s each, then the next) and also land in the notifications inbox with a local banner (tap opens the gallery)
- **Frequent-routes map** (Recap card expands as the MapKit map itself) — road polylines + heatmap; privacy-safe home/work labels; habit corridors in the same city as your top run)
- **Month cost forecast** on Recap: Recap-style poster hub (Canvas sparkline, title chip, amount on a bottom atmosphere gradient — no whitish veil) with driving fuel estimate + this month’s installments and other expenses (logged pump fuel is a separate line, never double-counted into the hero total); expand mix bar uses the shell tint for estimated fuel and rotated hues for installments / other; the hub card grows into a full-screen poster and frost breakdown like Badges (atmosphere + glass, not a grouped list)
- **Favorite place filter** on Trips and Stats (start or end matches a saved place); charts and summary follow the same filters independently per tab

### Vehicle care & costs
- **Reminders** — inspection, insurance, comprehensive cover, service due dates with staged local push + inbox (service: 30 days → 1 week → due day → one overdue; insurance: 1 week → due day → one overdue). Service and inspection can also use kilometres: every N km, or whichever of the date and the kilometre comes first. The interval is per vehicle (1 000 km, 4 000 km, 15 000 km, or any step). **Add reminder** is the same row button, at the top of the section, above the rows. Mark done from the row (Done) to log cost and roll the next due date
- **Odometer** — optional current reading on the vehicle profile. Later trips add to it. A typed reading always wins. Reminders that use kilometres stay on the date until a reading exists. Kilometre notifications are sent after a trip is saved or when the app opens, never while a trip is recording or paused
- **Expenses** — **Add expense** is the same row button, at the top of the section, above the rows. Log fuel, traffic insurance, casco, service, inspection, repair, accessory, road toll, parking, vehicle tax, and other costs separately from reminders; split a purchase into **monthly installments** (up to 24) so each month’s share appears on Stats in that month
- **Receipt photo** on an expense — take a photo or pick one from the library, see a thumbnail in the form, and open it full screen with pinch and double-tap zoom. A receipt glyph marks expenses that have one; every slice of an installment plan shares the same receipt
- **Read Amount** from a receipt (optional) — Apple’s on-device text recognition (Vision) finds the total line (GENEL TOPLAM, ÖDENECEK, TOPLAM, TOTAL…, skipping ARA TOPLAM / KDV / change), outlines it on the photo, and lets you pick another amount it found. Nothing fills in until you tap **Use This Amount**, and the sheet warns that text recognition can make mistakes. Works offline; the photo and its text never leave the iPhone and no AI service is involved
- One vehicle detail screen under the **Pairing** tab: profile → reminders → expenses; cost charts live on **Stats**. Profile Save sits under the vehicle card, not in the nav bar. The closed Duo cover and a phone narrower than that cover, including iPhone SE, stay one list in landscape, the same column as portrait, so the shortcuts card and saved vehicles use the width. On the open book, on a landscape iPhone wider than that cover, and on iPad landscape, the focused vehicle’s photo or icon sits beside its name, with the fuel line under the name and “Default” above it only when that vehicle is the default. When the Duo hinge is fully open, the Vehicles list takes 60% of the content and that focus pane 40%. On that same pose, vehicle detail puts the profile at 40% and Tracking & reminders plus expenses at 60%. A partially open hinge keeps both seams on the fold. On the open book, on that wide landscape iPhone, and on iPad landscape, the profile stays on the leading side and Tracking & reminders plus expenses scroll together on the trailing side. The wide iPhone and iPad landscape use those same 40/60 shares. iPad has no hinge. Add reminder and Add expense slide in from the trailing edge and fill that pane; back and Save slide it back out. The Shortcuts card keeps the setup copy above the guide
- Overdue care also shown as an in-app banner; push fires once when overdue (no daily spam)

### Organization
- Personal / business categories (+ custom)
- **Smart category** (optional): suggests Personal or Business from frequent routes, Home/Work places, and weekday work hours; swipe the list row to accept — nothing is applied automatically
- **Travel journal** — phone portrait uses the Trips tab segment **Trips | Travels**. On the widest open book (Duo landscape), on a landscape iPhone wider than the closed Duo cover, and on iPad landscape, both libraries sit side by side: Trips leading, Travels trailing. Turning that Duo upright fades Travels out, then the Trips list widens in place; turning back narrows the list, then fades Travels in. On that wide iPhone the system tab bar stays on the bottom. The closed cover and a narrower phone stay one list. Group completed drives under a Seyahat, all member routes on one map, optional suggestion chip, **Add to travel** on trip detail, Stats **Travel** filter. Opening a Seyahat on that wide landscape, and on the open book, fills the leading half with the member trips and the trailing half with the route map, edge to edge. A narrower landscape phone keeps the bottom sheet. iPad landscape keeps the trailing card. On the closed landscape cover the travel opens as one corner card on the map; pull it up to see the member trips, then collapse it back. Deleting a journal unassigns trips; it does not delete them
- Vehicle management (petrol, diesel, LPG, hybrid, EV)
- In-app notifications inbox (trips, vehicle care, badge unlocks, January recap) opens as its own page from the bell on every tab. On a phone, choosing a row closes the inbox first, then opens the matching screen. On the open book, on a wide landscape iPhone, and on iPad in both orientations, choosing a row stays in the inbox and shows that notice beside the list. Both sides share one atmosphere. The list and the preview use the saved place names, not the coordinates stored on the notice. The preview card adds distance, duration, and speed side by side, with vehicle, category, top speed, and fuel in two columns, and it fits the pane without scrolling. Every inbox row is the same two-line height: the title and time, then the place or route with distance and duration. Open closes the inbox and goes to the matching screen. A started or ended trip notification opens that trip on the Trips tab, read or unread. If the trip was deleted, the inbox stays open and says the trip could not be found. A trip never opens inside the inbox. The bell and the Trips merge or new-travel button stay in their own trailing capsule, side by side, whenever the tab bar is along the bottom, including the upright Duo, a normal phone, and iPad. When the Duo tab bar is a vertical column, they leave that row and stack in one vertical capsule on the same center as the tab, above the icons: bell on top, then merge or new travel. On the cover, where the punch hole sits at the top of that column, the capsule rests just above the icons so the hole does not cover the bell. The landscape book stacks the bell, plus, and merge there. If that spot does not fit, they stay in the trailing capsule. On the split Trips | Travels book that capsule is the bell, plus, and merge together, so a rotation cannot leave an empty circle beside the side tab. Start stays in its own leading capsule. Rotating does not show a second copy
- Turkish & English UI (Localizable.xcstrings). Premium surfaces also ship Arabic, German, and Italian copy

---

## Platform support

| Platform | Minimum version | Status |
|----------|-----------------|--------|
| **iPhone (iOS)** | **17.0** | ✅ Portrait and landscape. Landscape wider than the closed Duo cover (iPhone 16, 17, Plus, Pro Max) uses the open-book panes on every tab: Trips and Travels, Vehicles, Statistics, Recap, and Settings. The system tab bar stays on the bottom. Vehicles is 60/40, vehicle detail is 40/60, Statistics and Recap are 45/55, and Settings is 40/60, the same as the fully flat Duo. Trips and Travels split the content in half. One atmosphere covers both panes. iPhone SE and any landscape narrower than that cover stay one column |
| **iPhone Duo** | 17.0 | ✅ Closed and open: Badges, Frequent routes, and month-forecast close circles sit on the leading side so they clear the camera and status cluster. Open landscape: the Badges gallery is four columns, and Recap cards break on the fold rather than in equal halves, so the side tab does not pull the seam off the notch. Idle on the open landscape book: Trips on the leading half, Travels on the trailing half. Turning upright fades Travels, then widens Trips; turning back does that in reverse. Closed landscape stays one list and keeps the recording card in that list so it scrolls with the trips. Closed landscape Pairing stays that same list, so the shortcuts card and saved vehicles use the width. The default-vehicle pane is the open book. Open landscape centers the recording card vertically in the leading half and puts the trip list on the trailing half. The card stays as tall as its contents, so the road shadow sits above the timers and the card does not stretch to fill that pane. Open portrait: the recording card sits on the horizontal fold and the trip list stays below it. Upright trip detail matches the phone: the map fills the screen and the info sheet sits below it. With the fold vertical, detail cards fill the leading screen and the route map fills the trailing screen. Turning either way keeps the open trip on screen. That page has no sheet grabber. Statistics chart dates shrink to fit each half. The fold gutter stays empty |
| **iPadOS** | 17.0 | ✅ The tab bar stays the system Liquid Glass tab bar. Portrait and landscape Trips show Trips and Travels side by side. While a trip is recording, the card sits beside the list. Vehicles keeps the list and the focused vehicle side by side on one atmosphere in both orientations. Settings keeps the section list beside the form in both orientations. In portrait the list is 30% and the form is 70%. Vehicle detail is 40/60 (profile, then tracking and expenses). Recap packs cards into the same 45/55 columns as the flat Duo. Lists, stats, and settings use the wide canvas. Maps use a side panel. Narrow Split View and Slide Over stay the phone layout. iPad portrait keeps the hub grid on Recap and one column on vehicle detail |
| **Widget (Home / Lock)** | iOS 17.0+ | ✅ Home Screen & Lock Screen widgets |
| **Live Activity + CarPlay tile** | iOS 18.0+ | ✅ Lock Screen, Dynamic Island, CarPlay Dashboard (icon + duration, distance, speed) |
| **Siri / Shortcuts** | iOS 17.0+ | ✅ App Intents + Personal Automations |
| **macOS / visionOS / tvOS** | — | ❌ Not supported |

### Why iOS 17?

Trailhound uses **SwiftData**, **App Intents**, **Live Activities**, and modern **WidgetKit** APIs that require iOS 17. The project does not build for iOS 16 or earlier. The **CarPlay Dashboard Live Activity** layout (vehicle icon plus duration, distance, and speed) needs **iOS 18** (`activityFamily.small`); on iOS 17 the Home Screen widgets still work, but the Live Activity presentation targets iOS 18+.

### Device & permissions

| Requirement | Used for |
|-------------|----------|
| GPS (Always / When In Use) | Route recording and background trips |
| Notifications | Trip started/ended alerts; vehicle care due reminders; badge unlocks; January year recap |
| Face ID (optional) | App lock |
| Shortcuts (system) | Auto-start/stop Personal Automations |

**Physical iPhone recommended** for real-world testing (GPS, background recording, Shortcuts automations). Simulator is fine for UI and basic location simulation.

---

## Requirements (development)

| | |
|---|---|
| **Xcode** | 15.0+ (iOS 17 SDK); CI uses **Xcode 26.5** on `macos-26` |
| **Swift** | 5.0 (strict concurrency enabled) |
| **iOS deployment target** | 17.0 |
| **Dependencies** | None (Apple frameworks only) |
| **Bundle IDs** | `com.trailhound.app` · `com.trailhound.app.widget` |
| **App Group** | `group.com.trailhound.app` |

---

## Getting started

```bash
git clone https://github.com/nurettinbas/Trailhound.git
cd Trailhound
open Trailhound.xcodeproj
```

1. Select an **iPhone** simulator or device
2. Update **Signing & Capabilities** with your Team (bundle ID: `com.trailhound.app`)
3. Ensure App Group `group.com.trailhound.app` is enabled for app + widget targets
4. Press **⌘R** to run

### Simulator quick test

1. Tap **Start** in the app
2. **Features → Location → Freeway Drive**
3. Stop after 1–2 minutes

### Automated tests

Run the full unit + UI smoke suite locally:

```bash
chmod +x scripts/run_tests.sh scripts/ci_pick_simulator.sh
DESTINATION="$(./scripts/ci_pick_simulator.sh)" ./scripts/run_tests.sh
```

Unit tests only (faster):

```bash
INCLUDE_UI_TESTS=0 ./scripts/run_tests.sh
```

UI tests only:

```bash
ONLY_UI_TESTS=1 ./scripts/run_tests.sh
```

Override the simulator destination if needed:

```bash
DESTINATION='platform=iOS Simulator,name=iPhone 17,OS=26.5' ./scripts/run_tests.sh
```

Build once, then run tests without rebuilding (what CI does):

```bash
XCODEBUILD_ACTION=build-for-testing ./scripts/run_tests.sh
XCODEBUILD_ACTION=test-without-building INCLUDE_UI_TESTS=0 ./scripts/run_tests.sh
```

CI runs the same script via GitHub Actions (`.github/workflows/ios-tests.yml`): unit tests on every pull request to `main`, unit + UI tests on every push to `main`.

### Siri Shortcuts & auto-recording

Requires **iOS 17+** and **Siri / Shortcuts** available. After first launch:

1. Open **Pairing** in Trailhound → follow **Auto-start with Shortcuts**
2. Or open **Shortcuts** → search **Trailhound** and add: **Start trip**, **Pause trip**, **Resume trip**, **End trip**
3. For hands-free start/stop: create a named Shortcut with **Start trip** + **Vehicle**, then a Personal Automation that uses **Run Shortcut** on Bluetooth / CarPlay / Wi‑Fi connect (and **End trip** on disconnect). Automations often hide the Vehicle picker if you add Start trip directly.

**Siri examples:** *“Start trip in Trailhound”*, *“Pause trip in Trailhound”* (Turkish phrases are also registered for TR Siri language)

> Siri language and system language can differ. Shortcuts list follows system language; voice phrases follow Siri language.
>
> In-app Bluetooth audio-route auto-start was removed. Auto-record now relies on Shortcuts Personal Automations (more reliable across iOS versions and CarPlay).

---

## Project structure

```
Trailhound/
├── App/              # App entry, runtime bootstrap, scene lifecycle
├── Models/           # SwiftData models (Trip, VehicleProfile, …)
├── Services/         # Location, recording, geocoding, export, pairing
├── Views/            # SwiftUI screens (incl. Pairing Shortcuts guide)
├── Intents/          # App Intents & Siri Shortcuts
├── Utilities/        # L10n, migrations
TrailhoundShared/        # App Group bridge (widget, Live Activity, deep links)
TrailhoundWidget/        # WidgetKit + Live Activity extension
TrailhoundTests/         # Unit + integration tests
TrailhoundUITests/       # UI smoke tests (XCUITest)
scripts/              # CI simulator pick + xcodebuild test runner
docs/                 # Battery, design system, Stats, TestFlight, privacy, support
```

**Stack:** SwiftUI · SwiftData · MapKit · CoreLocation · App Intents · WidgetKit · ActivityKit

---

## Documentation

- [Battery optimization](docs/BATTERY_OPTIMIZATION.md)
- [Design system](docs/DESIGN_SYSTEM.md) — Liquid Glass, 20-color shell palette, engine rules, tokens
- [Appearance (wiki)](https://github.com/nurettinbas/Trailhound/wiki/Appearance) — Settings theme, palette, Home Screen icon, share cards
- [UI performance notes](docs/PERFORMANCE.md) — live follow map camera, route drawing, trip-list scroll, Stats cards, glass budget
- [Fuel estimation](docs/FUEL_ESTIMATION.md) — Avg vs estimated fuel, additive GPS litres, backfill v6 / rollup 14
- [Fuel estimation (wiki)](https://github.com/nurettinbas/Trailhound/wiki/Fuel-Estimation) — Avg vs estimated, not a pump reading
- [Stats tab](docs/STATS_TAB.md) — filter card, card spans, nested tiles, deferred charts
- [Recap tab](docs/YEAR_TAB.md) — year awards first, badges, frequent routes, Recap-style month forecast, year recap last
- [Stats (wiki)](https://github.com/nurettinbas/Trailhound/wiki/Stats) — glass cards, filters, comparison
- [Recap (wiki)](https://github.com/nurettinbas/Trailhound/wiki/Recap) — Recap tab, year awards, story, badges, routes, forecast
- [Architecture (wiki)](https://github.com/nurettinbas/Trailhound/wiki/Architecture) — schema **V23**, models, premium derived caches
- [Device support (wiki)](https://github.com/nurettinbas/Trailhound/wiki/Device-Support) — iPhone, wide landscape book, Duo, iPad pane shares
- [Notifications (wiki)](https://github.com/nurettinbas/Trailhound/wiki/Notifications) — inbox, book preview, trip deep links
- [Live follow map](https://github.com/nurettinbas/Trailhound/wiki/Live-Follow) — product flow and MapKit drawing (wiki)
- [Shortcuts auto-record](docs/SHORTCUTS_AUTORECORD.md) — Personal Automation wizard, honest test, checklist
- [Shortcuts (wiki)](https://github.com/nurettinbas/Trailhound/wiki/Shortcuts) — Pairing wizard, named Shortcut + Run Shortcut
- [TestFlight release checklist](docs/TESTFLIGHT_RELEASE.md)
- [Vehicle care & expenses](docs/VEHICLE_CARE_PLAN.md) — reminders vs costs, monthly installments, UI layout, notification rules
- [Travel journal](docs/TRAVEL_JOURNAL_PLAN.md) — Seyahat grouping, suggestion rules, schema V19
- [Privacy policy](docs/PRIVACY.md) — on-device data, receipt photos and on-device text recognition, optional diagnostic reports, GDPR / KVKK rights
- [Gizlilik Politikası ve KVKK Aydınlatma Metni](docs/PRIVACY_TR.md) — Turkish privacy policy and KVKK notice
- [Acknowledgements](docs/ACKNOWLEDGEMENTS.md) — third-party sound credits (CC BY-SA 3.0)
- [Support](docs/SUPPORT.md) — contact and Report a problem

---

## Contributing

Issues and pull requests are welcome. Please open an issue before large changes.

---

## License

[MIT](LICENSE) — see [LICENSE](LICENSE) for details.

---

## Support the developer

Trailhound is free. There are no ads and no account. Support is optional and does not unlock any feature.

- **In the app:** Settings → About → Support the developer. Three tips through Apple In-App Purchase; Apple handles the payment and refunds.
- **Bank transfer (outside the app):** if you prefer, send a transfer from your own bank. The app does not show or link to these details.
  - **Name:** Nurettin Baş
  - **IBAN:** *(add before release)*
  - **SWIFT/BIC:** *(add before release)*
  - **Bank:** *(add before release)*

---

<p align="center">
  <sub>Built with Swift · No analytics · No tracking · Your roads, your data.</sub>
</p>
