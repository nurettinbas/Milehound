# UI performance notes

Trailhound optimizes frame time in a few hot paths. Use this when profiling regressions.

## Vehicle pairing editor

- Edits use `VehicleEditorDraft` and persist on **Save** only (no SwiftData writes per keystroke).
- Visual chrome matches the rest of the app (`glassListChrome()` / `glassRow()`); draft keeps keyboard work off the model layer.
- Optional vehicle photos are 256 px JPEG/PNG thumbs on disk (`VehiclePhotoStore`); SwiftData stores only `photoFileName`. Decode/resize runs off the main actor; list rows use a memory cache hit when scrolling.
- Identity surfaces (pairing rows, recording capsule, trip/stats vehicle filters, trip-detail picker) reuse `VehicleAvatarView` + `VehiclePhotoStore.prefetch` so thumbs are warm before scroll/chips appear.
- Recording road animation (`RecordingCarAnimationView` in TrailhoundShared) accepts a **pre-decoded** `UIImage?` plus optional `systemImage` from the app. Shared never opens photo files; `drawingGroup` must not do per-frame I/O.

## Cold-launch intro

- The cold-launch intro (`LaunchIntroSceneView`) is the real app icon on a `CALayer`: road, hound, and corner stopwatch. Scale, the stopwatch rock and hands, the hound's joint swings (`LaunchIntroHoundLayerTree` + `LaunchIntroHoundRig`: 11 nested part layers, each sampled 16 times per stride), and the corner close are `CAKeyframeAnimation`s. Nothing writes SwiftUI state per frame, so the first SwiftData fetch and tab build cannot hitch it. The Start control mounts that same tree and loops one stride (`launchIntroGallopStride`); tint changes recolor the parts and do not restart the loop. The display-link ticker only drives the speed streaks under the hound.
- The app hierarchy (onboarding, lock, tabs) is built only after the intro’s first frame is committed (`onStarted`), so the system launch screen waits for one CALayer tree, not every tab. Time before `didFinishLaunching` is the system loading the process; app code before the first intro frame is about 150 ms.
- The system launch screen is `LaunchBackground` (white / black). It cannot follow the theme because it is drawn before app code runs; the intro eases from it into the theme plate.
- No offscreen passes: the close animates the plate’s `bounds` and `cornerRadius` (no full-screen shape mask), and the picture and content fade with `allowsGroupOpacity = false`. The stopwatch body (ring, ticks, button) is one filled shape; only the two hands and the dash phase change per frame, and those stop when the icon lands.
- One `launch.intro` signpost covers the scene. The layer tree is removed when the intro finishes. Low Power and serious thermal drop parallax, particles, and the frame rate (60 Hz, 1.2s). ProMotion uses `CADisableMinimumFrameDurationOnPhone` plus `preferredFrameRateRange` on these animations only; existing `CADisplayLink` clocks keep their own 60 fps cap.
- The intro does not play for UI tests, VoiceOver, an active or pending recording, a deep link, or a notification tap. Face ID and the external-start confirm wait until it finishes.

## Trips list scroll (recording card)

- Trips list hides in-progress recordings with an `endedAt != nil` predicate. Do not add ad-hoc SwiftData schema fields without a versioned migration plan.
- Card frame for stop credits is kept inside `ActiveTripView` (not propagated to `TripListView` on every scroll frame).
- Road + exhaust animation uses `RecordingCarAnimationView`; the `CADisplayLink` ticker (`TrailhoundDisplayLinkTicker`) only runs while recording, unpaused, and the card is on-screen.

## Active recording card

- GPS and persistence still run at full rate; on-screen stats use `RecordingDisplaySampler` (~4 Hz / 250 ms).
- The recording card no longer shows a live mini-map (only the car animation + stats).
- Stop credits still use `LiveBreadcrumbCanvas` briefly.
- The road animation pauses when another tab is selected or the card scrolls off-screen (`isRecordingCardInViewport`).
- The road clock runs only while the animation is active (paused / off-screen = static frame). Do **not** use `TimelineView` (animation or periodic) for this card: iOS pauses those clocks inside a SwiftUI `List`. Drive list-hosted motion with `TrailhoundDisplayLinkTicker` **outside** `.drawingGroup` — a representable inside the rasterizer never mounts, so the car sits still.
- **Live follow map** (`LiveFollowMapView` + `LiveFollowMapKitView`): `CADisplayLink` (capped at 60 fps, `dt` from `targetTimestamp`) drives `LiveFollowCamera`. The same `lastLocation` is not re-ingested every frame (that reset the dead-reckon clock and snapped at ~1 Hz). Camera center is the vehicle so the puck sits at screen center while following; **eye distance grows with speed** (`followDistance`) so a motorway sweep does not read as a lurch. Follow camera stays live during the **open hero flight** (not gated on `openSettled`) so a 120 km/h tick cannot slide the blue trail off the curved landing; pan-to-break waits until the handoff finishes. Motion is **velocity integration** (`speed × dt`) between GPS samples — implied speed/path bearing when Core Location reports `-1` (common in Simulator). The published center aims at where the car should be *now* (last fix advanced by `speed × age`), not the stale GPS point — otherwise the breadcrumb trail draws ahead of the puck and lurches once a second. Two other rules keep that continuous: the fresh window (`maxDeadReckonSeconds`) is well above the ~1 Hz fix interval, and once a fix *is* stale the coast **decays** (`deadReckonDecayTauSeconds`) instead of zeroing speed in one frame. GPS is only a trim on the integrated position: along-track pushes only when the (aged) fix is *ahead*, and a spent coast on a stale fix **holds** rather than rewinding. `LiveFollowSession.camera` is observation-ignored so 60 fps ticks do not rebuild SwiftUI. Camera writes use `map.camera` inside `CATransaction` (actions disabled) **only while following**; after pan, pose/puck keep updating. Follow tiles stay `.flat` with pitch for 3D feel. History is **chunked `MKPolyline`s** of *completed* 240-point blocks (immutable until a chunk fills); the **growing remainder rides in the tip overlay** with the vehicle chord, swapped at most 10 Hz — one solid blue stroke. A breadcrumb therefore never `removeOverlay`/`addOverlay`s history next to the puck. Route geometry is pulled by the coordinator from `LiveFollowSession` (`recordingService` is observation-ignored) on display ticks, so a 1 Hz breadcrumb append cannot rebuild SwiftUI or `updateUIView`. Both use MapKit's *own* vector renderers on purpose: a custom `MKOverlayRenderer` is rasterised flat and then perspective-warped, which fattens the stroke toward the bottom of a 3D view. A tip longer than 120 m, or pointing against the direction of travel, is dropped. While following, the puck artwork stays screen-up (the camera already faces travel). After **Show entire route** / pan, the photo + chevron rotate around the circle centre so the sharp tip still faces travel on a north-up map. Show entire route fits once per tap from the card frame already stored off the SwiftUI graph; it does not enter the display-link camera, and recenter keeps the existing 0.58 s linear flight. While paused, pan/zoom and pitch are locked so the vehicle stays put; Resume, Stop, and close still work. `ScreenIdleLock` keeps the display awake only while the cover is open. Start / pause / trip-stop pins render on the live map. While the cover is open, the card’s road clock stays paused (`!showLiveFollowMap`).
- **Planned route on the live map** (`PlannedRouteStore` owned by `TripRecordingService`, drawn by `LiveFollowMapKitView`): every `PlannedRoutePolyline` (an `MKPolyline` subclass) is inserted at index 0 at `.aboveRoads`, so the plan always sits **under** the history chunks and the tip and never forces the trail to be re-added. `LiveFollowOverlayRole` picks the single planned line (`LiveFollowPlannedRouteStrokeStyle`, the trail's width, no second stroke) vs the solid trail. Each history chunk and the tip also has a `TrailCasingPolyline` added just before it — a white stroke 1.8 pt wider on each side — so the edge is MapKit's own vector renderer (a custom renderer would warp in 3D). That doubles the trail overlay count; chunks stay immutable, so the extra line is uploaded once per chunk, and the tip casing swaps on the same 10 Hz gate as the tip. The route is cut into fixed 32-vertex chunks (`LiveFollowPlannedAhead`), uploaded **once per route** (new route or reroute); chunks the car has passed are only removed, never re-uploaded — an earlier version re-cut one 1500-point overlay every 15 m, which hitched the puck twice a second at motorway speed. A short **lead** line (from the puck to the first chunk at least 80 m ahead, a few dozen points) is the only planned overlay swapped while driving, on the tip's 10 Hz / 0.8 m gate. It starts on the puck and eases onto the route centreline over 80 m, so the plan always leaves the car where the trail ends (a renderer `strokeStart` trim could not fix the lateral gap between Apple's centreline and the GPS lane, and did not reliably hide the driven part). Planned pieces use `.butt` caps so see-through joints never overlap. The search is forward-only and limited to 400 m past the last cut, so a later stretch that runs close by (a U-turn, the other carriageway) cannot jump the cut. When the car is past that window (the map reopened after a long drive, a GPS gap), it falls back to the first stretch ahead within 75 m and continues from there — otherwise the cut stayed at the start and the plan drew beside the driven trail; farther than 75 m from the line, the cut holds. The coordinator reads `PlannedRouteStore.version` (observation-ignored) on display ticks — same pattern as the route stamp — and rebuilds the chunks only when the stamp moves (new route, reroute, clear). Routes are capped to `PlannedRouteStore.maxDisplayPoints` (1500) with `FrequentRouteRoadPathCache.decimate`. Progress per GPS fix is a local equirectangular projection onto the closest segment (`PlannedRouteProgress.measure`) — O(n) over ≤1500 vertices, no MapKit. Remaining distance is rounded to 10 m and travel time to 30 s before they are published, and only `LiveFollowRouteChipHost` reads them, so a 1 Hz fix re-renders the chip, not the live map. MapKit directions are throttled: reroute needs 3 consecutive fixes over 75 m off the line **and** 30 s since the last request; offline skips the request entirely.

### Observation isolation

The card sits above a 40-row `List`, so anything that invalidates its body invalidates it during scrolling too. Two rules:

- **Live counters may only be read inside `ActiveTripLiveStats` or `RecordingCardAccessibilityLabel` — never in the card's body.** Reading `displayElapsedTime`, `displaySpeedMps` or `displayDistanceMeters` from an `@Observable` service in the body subscribes the whole card to the 4 Hz sampler. The VoiceOver label used to do exactly this; the text now comes from the pure `RecordingAccessibility.summary` and is applied through a `ViewModifier`, whose own body absorbs the dependency.
- **No `context.fetch` in a view body.** The vehicle picker resolved the active vehicle with `VehicleResolver.resolveActiveVehicle(in:)`, hitting the store on every pass. Views pass their existing `@Query` array to `resolveActiveVehicle(from:)` instead.

### Scroll invalidation

- The recording card's frame is only needed when Stop or live-follow is pressed, so it lives in `RecordingCardAnchorBox`, a reference box outside the dependency graph. It was previously `@State` with a 12 pt threshold, which a fast scroll clears every frame — so the card was rebuilt every frame.
- The filter bar's `.global` frame preference is only installed while `endCredits != nil`. Otherwise the preference chain ran on every scroll frame for an animation that was not playing.
- `TripListView` computes `visibleTrips` and `firstTripID` once per body pass. `completedTrips` used to be re-filtered inside every row, making the list quadratic in trip count.

### Backgrounds

- `AtmosphericBackground` draws its three glows as `RadialGradient`s rather than `Circle().blur(radius:)`. Every frosted row above them was resampling those blur passes.
- The glows are wider than the screen, so they must stay in an `.overlay` rather than being `ZStack` siblings. As siblings they stretched the layout of every container that puts this behind its content (`ContentView.mainTabs`, `glassListChrome`), pushing toolbar buttons off-screen.
- `TripMapSnapshotCache` resolves its cache directory once and does all disk reads, JPEG decodes and writes off the main actor. Memory and disk are keyed by trip **and** appearance (`{uuid}-light.jpg` / `{uuid}-dark.jpg`). `cachedImage(for:appearance:)` is a memory-only lookup and is safe to call while scrolling. List rows keep the last thumbnail on screen across Light/Dark; MapKit runs only on a miss, through `TripRoutePathCache` (GPS fault stays on the path worker, not the list’s main actor) and **one** `MKMapSnapshotter` at a time. A cancelled row drops out of the render line if work has not started; an already-started render still writes the JPEG. GPS trim, delete, and merge call `remove(for:)` so a clipped route cannot leave a stale thumb. Legacy unstyled `{uuid}.jpg` files are deleted on first cache init and not reused.

## Route rendering

Recorded points are stored at full resolution and are **never** reduced on disk. Post-processing used to replace a finished trip's points with a Douglas-Peucker subset (a 1922-point drive came back as 143), which both destroyed user data and made maps and speed charts look broken. `TripPostProcessorTests` guards against that regressing.

All drawing goes through `RouteDisplayPath`, a pure read-path transform:

- **Display budget.** At most `maxDisplayPoints` (1500) points reach MapKit or `Canvas`, so cost is independent of trip length. Decimation uses a 3 m meter-based tolerance and always keeps both ends.
- **Decimation never fabricates a gap.** After Douglas-Peucker, points are re-inserted wherever a surviving chord would exceed `baseChordLimitMeters` (450 m).
- **Adaptive chord limit, measured locally.** Densely recorded stretches keep the 450 m limit, so a tunnel or signal loss still breaks the line instead of inventing a straight path. Stretches whose stored points are already a simplified polyline (median spacing above 60 m — only legacy trips damaged by the old post-processor) get no distance cap, since Douglas-Peucker guarantees those chords are geometrically accurate. Implausible-speed teleports still break either way, via `RecordingMovementPolicy`.

  The density is judged over a sliding window of `densityWindowRadius` (12) spacings on each side, not over the whole route. A merged trip mixes both kinds, and a single route-wide median let the dense leg outvote the sparse one: every one of the legacy leg's chords then read as a gap, and because `split` drops runs shorter than two points, the entire leg disappeared from the map. `testMergedSparseAndDenseLegsAreJudgedSeparately` covers this.
- **One sub-path per piece.** `TripShareCardRenderer` and `TripMapSnapshotCache` used to stroke a single `UIBezierPath` through every point, bridging real gaps with a false straight line. Each drawable piece is now its own sub-path.
- `speedSegmentCache` still caches speed-colored segments per trip, keyed on the recorded point count, and also carries the display point count.

## Speed chart

`SpeedChartSeries` builds the plotted series, following the same pure-builder pattern as `RouteDisplayPath`. The gap threshold that breaks the chart line is `max(90 s, 6 × median sample interval)` rather than a fixed 90 s, which used to split the chart on sparsely sampled legacy trips.

- **Bucket averaging, not striding.** `maxDrivingSamples` (600) bounds the cost of drawing a long trip. Striding to that budget kept whichever readings happened to land on the stride, including lone spikes, and discarded the neighbours that would have balanced them; the line looked far more jagged than the drive was. Buckets average instead, and a 3-sample moving median runs first to drop single-reading spikes.
- **Buckets never span a real gap.** The series is split into runs at recording gaps before the budget is shared out, so a stop cannot be averaged away by the driving either side of it.
- **Standstills draw as zero.** The recorder writes no points while the car sits at a light, and because the x axis is time that read as missing data rather than as "not moving". When the fixes either side of a gap are within `parkedDriftMeters` (60 m), the gap is filled with zero samples spaced at half the break threshold, so the line dips to zero and comes back. Beyond `maximumDrawnStopSeconds` (45 min) it is a merged trip's seam rather than a pause, so the series still does not invent hours of zero samples. The canvas and share card then drop the stroke to the baseline and run along it (`SpeedChartSeries.strokePoints`), so a merge seam or lost-signal gap is a valley at zero rather than a dashed hole.
- **Axis scaled from plotted data only.** `speedChartMaxKmh` no longer blends in `trip.maxSpeedMps`. One phantom stored maximum pinned the axis at 200 km/h and squashed a whole drive into the bottom third of the chart.
- The built series is cached per trip alongside `speedSegmentCache`, since axis scale, samples and median interval each read it.

## Speed accuracy

`Trip.maxSpeedMps` is written only by the recorder and is never rewritten by a migration, so trips recorded before speeds were vetted still carry their stored value on disk. Reads handle it in two ways, split by what the surface can afford:

- **Trip detail** (points already loaded) derives the honest value with `TripSpeedSummary.maxSpeedMps`: the largest speed that three consecutive samples all reach. Bogus peaks are one sample wide, so requiring a peak to last is enough to reject them.
- **Trip rows, statistics and rollups** must never touch `trip.sortedPoints` — that is the scroll jank fixed earlier — so they only vet the stored value with `believableStoredMaxSpeedMps`. A value above `maximumRecordedSpeedMps` (50 m/s) counts as no reading, and every one of those surfaces already handles nil. Showing nothing beats showing a number the car never reached.

At the source, `RecordingMovementPolicy.trustedGPSSpeedMps` gates Core Location's speed on `speedAccuracy`, horizontal accuracy (65 m), fix age (5 s) and the 50 m/s ceiling, with an acceleration check against the last accepted speed. **Only the speed is discarded; the position is always stored** — tightening the position gate would drop points in tunnels and bring back the broken-looking routes. Rejections are logged with which gate fired.

## Trip detail reveal

`TripDetailRevealPolicy` controls the opening route animation. First open always draws (~12 ticks) unless Reduce Motion; same-session reopen stays instant via `TripDetailRevealSession`. Display point count no longer gates animation.

| Condition | Behavior |
|-------------|----------|
| First open, motion OK | ~12 ticks, single solid polyline while drawing; speed colors + white casing when settled |
| Reduce Motion | Instant reveal (full route + casing) |
| Same process, trip already revealed | Instant reveal |

During ticks MapKit sees one growing fallback stroke — not up to 60 speed-colored overlays — so long/twisty display paths stay smooth.

**Layout (no MapKit resize).** The map stays full-screen. The frosted details panel is a fixed-height overlay with its own atmospheric wash — panel height never applies `padding` to the Map. The card is not user-resizable (no grabber drag / detents). Camera fit still uses `MapFitContext` insets so the route sits in the visible gap above the panel; refit runs on open (and in-place expand/collapse), not on overlay scroll. `TripDetailMapLayer` is `Equatable` and excludes panel height so sheet motion does not rebuild overlays.

**In-place map expand (no sheet).** Toolbar fullscreen is not a second MapKit instance or SwiftUI `.sheet`. `isMapExpanded` slides the existing panel off-screen (`offset` + `opacity`; frame height stays put) and refits the shared `mapCameraBox` on the same beat — `TrailhoundMotion.mapExpand` (1.40s) / `mapCollapse` (1.10s). The toolbar expand/collapse glyph must **snap** on tap (`GlassToolbarSymbol` uses `contentTransition(.identity)` and does not inherit that curve). Do not let SF Symbol replace ride `mapExpand` / `mapCollapse` — the pair morphs through unreadable frames for the whole duration. Do not reintroduce a deferred `scheduleMapRefit` (280ms) on this path; panel and camera must share one curve. Apply the fitted `MKCoordinateRegion` via `MapCameraPosition.region` — do not convert through `MapCamera` + `cameraDistance` (that altitude fudge zooms in and clips the route). Expanded edge padding must clear nav + style picker on top and tab-bar + speed chips on the bottom. Read tab-bar height from the key window (`safeArea.bottom + 49`); `GeometryReader` under `.ignoresSafeArea(.bottom)` reports 0 and buries the chips. When expanded, chrome bottom inset is that tab-bar height so the legend sits on the bar, not under it. Glass stays `frozen` for the transition duration. Style picker fades in after ~750ms expand only. Reduce Motion snaps both directions. Elevation stays `.flat`; expand must not toggle route/pin/stop reveal inputs.

**First paint.** Opening never faults `trip.sortedPoints` on the first frame. The speed chart builds from `displayPieces` (≤1500). Trim steppers wait for a deferred `recordedPointCount`. Heavy form content mounts after `panelRisen`. Original GPS rows are never deleted by these paths — `RouteDisplayPath` / `TripRoutePathCache` remain read-only transforms. List rows do **not** prewarm route paths (that faulted GPS on every scroll recycle). Warmth comes from stop/merge `prewarm` plus detail’s async `path(...)` (memory → disk → build).

Signature open order (first open, motion OK): muted map veil → `mapClear` → frosted panel `sheetRise` → camera refit into the visible gap → start pin → route ticks (single stroke) → end pin + speed colors + casing. The settle veil is a lightweight SwiftUI overlay (not a MapKit style switch). Elevation stays `.flat` for the whole screen (same hitch reason as live follow). Camera fit uses `MapFitContext.detailOverlay(panelFraction:)` so the route sits in the strip above the overlay panel — full-screen MapKit no longer gets physical bottom padding.

While the in-place expand/collapse runs, panel glass uses a solid fill (`glassChrome(frozen:)`) so Material does not resample the live map every frame.

## Share card

- One `MKMapSnapshotter` + SwiftUI `ImageRenderer` compose per share (9:16, trip-detail metric tiles); preview sheet then system share sheet.
- Path prep (`TripShareRoutePrep`: privacy clip → decimate → chart series → `SpeedColoredSegmentBuilder`) runs off the main actor; points are faulted once before the hop. Map strokes and the speed chart share the same clipped samples.
- Preparing overlay is glass chrome (same pattern as Settings export) — do not drive multi-second prep through `ToastPresenter`.
- Brand logo is drawn into the raster at compose time (palette-tinted `TrailhoundLogo`, same fill as the Home Screen icon); map snapshot follows Light/Dark. No ActivityKit / widget images.

## Recording cold-open

- `TripListView` arms `coldOpenArmed` for manual, Shortcuts, and widget deep-link starts; `ActiveTripView.playEntranceReveal` must stay wired to that flag.
- Road `TrailhoundDisplayLinkTicker` remains gated (recording, unpaused, on-screen, LPM 12 FPS). Do not reintroduce a live mini-map on the card.

## Shortcuts guide wizard

- Eight pages, **one** native glass card at a time. Connect (7) and disconnect (4) are numbered frost rows inside that card — never stacked `glassChrome` hosts.
- Trigger choices use `.glassNestedChoice(isSelected:)` (chip fill, not a second Material).
- At most one live `OnboardingHeroScene` `TimelineView` (silent-start / handoff pages only); pause when backgrounded, Reduce Motion, or when the sheet is open over onboarding.
- Test and checklist pages use static SF symbols. `SoftPulseRing` only on step complete — not a continuous road loop while paging.
- Vehicle `@Query` reads `VehicleProfile` name/photo only — do not fault `trips`.
- Optional “watch for a real start” is a `Date` in `UserDefaults.standard`. No timer, `CADisplayLink`, or GPS poll.

## Derived trip fields (schema V10)

Stats, the trip list and search all used to answer questions by faulting in a trip's whole `points`
relationship — reading a start coordinate or a night-driving share pulled every GPS row for that
trip into memory. `Trip` now stores those answers directly:

| Field | Replaces |
|-------|----------|
| `nightDistanceMeters` / `trackedDistanceMeters` | walking every GPS segment in `nightDrivingRatio` |
| `startLatitude` / `startLongitude` / `endLatitude` / `endLongitude` | `sortedPoints.first` / `.last` |
| `searchIndex` | the per-keystroke scan over route summary, note, addresses and place names |

All of them are optional and additive, so existing rows open as `nil` and nothing a user recorded is
touched. Rules for working with them:

- **`TripDerivedMetrics` is the only place that computes them.** It is called wherever a trip's
  points or dates change: `TripRecordingService.stopRecording`, `TripRecoveryService.finalizeOrphan`,
  `TripMergeService.merge`, `TripPostProcessor.process` (after geocoding, so addresses reach the
  search index) and `TripDetailView.saveEdits` (which also covers the GPS trim).
- **Every read path falls back.** `Trip.startCoordinate`, `TripListViewModel.matchesSearch` and
  `StatsViewModel.nightDrivingRatio` use the stored value when present and the old point-walking
  behaviour when it is `nil`, so a partly backfilled library is never wrong, only slower.
- **`TripDerivedBackfillService` fills in old trips** at launch. The work happens on the
  `TripDerivedBackfiller` `@ModelActor`, off the main thread, 25 trips at a time, saving each batch
  and calling `invalidatePointCaches()` between them. It is idempotent and resumes from where an
  interrupted run stopped.

`nightDrivingRatio`'s fallback loop is also cheaper than it was: `StatsViewModel.approximateDistanceMeters`
uses an equirectangular approximation instead of allocating two `CLLocation`s per segment, and the
UTC offset is resolved once per trip instead of calling `Calendar.component(.hour:)` per point.

## Trip list

- Filter uses `debouncedSearchText` (250 ms) so typing does not re-filter the full list every keypress.
- **The list has no `@Query` for trips.** It pages through the store via `TripListPage`, fetching
  `pageLimit + 1` rows so it can tell whether another page exists without a second count query.
  `ModelContext.didSave` stands in for the change tracking `@Query` would have provided, via the
  `onStoreSave` modifier — see "Reacting to saves" below.
- **Trip merge confirm and progress live on the root `deleteConfirmHost`, not on `TripListView`.**
  A system `.alert` from the toolbar arrived late; an `isMerging` overlay in the list body
  invalidated every row and often never painted because the merge worker already held SQLite.
  `DeleteConfirmPresenter` shows a prominent glass confirm, then blocking progress. `TripListView`
  must not `@Bindable` that presenter — it only writes `showProgress` / `hideProgress`.
- **Skip list reloads while merge progress is visible.** Worker `save()` still fires
  `onStoreSave`; rebuilding pages under that lock is the hitch. After merge returns, reload once
  (`reloadTrips` / `reloadJournals` / care) and then hide progress. Week-summary debounce may still
  run.
- **Dense GPS copy yields every 500 points** (`TripMergeCore.pointCopyYieldInterval`) on the
  `@ModelActor` worker, plus once per finished leg, so the first long history cannot monopolize
  the actor until the overlay has had a frame (`Task.yield` + 16 ms in `performMerge` before
  `TripMergeService.merge`).
- What the store can answer exactly — completed-only, category, a date lower bound,
  favorite-place name (start or end), and `searchIndex` matching — lives in the `#Predicate`.
  Place + full search + category in one macro overloads the type checker, so place-active
  predicates keep place/vehicle/category/date in SQLite and re-apply search in memory over the
  page. What the store still cannot answer exactly — date-section boundaries that move with the
  wall clock, plus the legacy search scan for trips still awaiting a `searchIndex` — is also
  refined in memory.
- The list previously filtered entirely in memory to avoid `#Predicate` on `@Model` key paths, which
  warned under `SWIFT_STRICT_CONCURRENCY = complete` ("KeyPath<Trip, …> does not conform to
  Sendable"). That is a Swift 5 language-mode gap rather than a SwiftData limitation: key path
  literals only infer `Sendable` under SE-0418, which Swift 6 enables by default. The project opts
  in with `SWIFT_UPCOMING_FEATURE_INFER_SENDABLE_FROM_CAPTURES`, so `#Predicate` and
  `SortDescriptor` over `@Model` key paths are warning-free. **Keep that setting on** — dropping it
  brings back a warning at every predicate in `TripListPage`, `StatsView`, `TripRollupService` and
  `TripDerivedBackfillService`.
- **The load-more trigger is a footer section, not the last row.** A page whose rows are all
  removed by the in-memory pass would otherwise dead-end with nothing left to trigger the next one.
- Aggregates that need more than the loaded pages have their own queries: `fetchCount` for
  "are there any trips", a week-scoped fetch for the summary line, a `fetchLimit = 1` descriptor for
  the newest trip behind the post-stop morph, and a fetch by ID for merge (a selection made before
  scrolling may include trips no longer resident).
- **Tab appear does not fetch.** `TripListView` loads the library on the first `onAppear` only.
  Switching back to Trips must not call `reloadTrips`, `reloadJournals`, `refreshOrphans`, or
  `notificationStore.reload()`. `TripsTabAppear` (`PerformanceSignposts`) wraps that appear.
  A store save and pull-to-refresh still reload. Returning to the foreground reloads once,
  because a widget or Shortcut may have saved while the process was suspended.
- **Same-day return only regroups when the calendar day changed.** Today / Yesterday headers
  are rebuilt from the rows already in memory. The week summary fetch runs with that regroup,
  not on every tab tap.
- **A save that does not change row display fields does not replace `loadedTrips`.** Replacing
  the array makes SwiftUI diff every row. The stamp covers the fields the row actually shows.
- **Orphan lookup is `endedAt == nil` with `fetchLimit` 8**, newest first. It must not call
  `TripStore.all()`. `scheduleOrphanStaleNotifications(for:)` takes the list already fetched
  so the banner path does not scan twice.
- **Travel suggestion runs on `TravelSuggestionLoader` (`@ModelActor`)** and only while Travels
  is on screen (phone mode or the iPad split). It must not run inside `TripsTabAppear`.
- `TripDateGrouping.groupedSections` runs once per load into `@State`, not once per body pass.

## Inactive tabs

- Stats, Recap, Pairing, and Settings views mount only while their tab is selected (Trips stays mounted for the recording card).

## Stats tab

- **One chrome, collapsing cards.** Phone Stats is a `ScrollView` + `LazyVStack` of `GlassCollapsingCard` so below-fold cards stay deferred. Do not collapse it into a `VStack` of cards. Each title sits on its glass plate. The body scrolls up under the title; the title strip then fades out in place and fades back in on the way down (GeometryReader + disabled-animation state, no extra Material). The filter card stays in the list. Wide/Duo layouts keep the filter card open in the leading rail and collapse headers on the trailing column. Year recap / badges / routes / forecast / year awards live on the Recap tab.
- **Section identity stays stable.** Chart sections must not use `.id(statsFilterFingerprint)` — that rebuilds pagers on every filter change. `Chart` animates the new series.
- **Pager page is local.** `StatsChartPager` keeps the swipe in a local `@State` and writes the parent binding only when the scroll settles (`onScrollPhaseChange` on iOS 18+). `.glassCarouselPage()` is GPU-only.
- **One `Material` per card.** `statsFullCard` / `statsHalfCard` use `glassCard` on a **clear** list-row background. Nested tiles are frost *fills*, not extra `ultraThinMaterial`. Never stack `glassListRow` behind an inner `glassCard`.
- **No `GeometryReader` in the 2-up row.** Half cards use a fixed `StatsCardTokens.halfMinHeight`.
- Chart aggregations build into a `StatsDisplaySnapshot` on filter/store changes, not on every scroll frame.
- Each chart is its own `List` row; `StatsDeferredChart` / `StatsDeferredContent` mount Swift Charts after the row appears (placeholder keeps layout stable). The 2-up hero must not contain Swift Charts.
- **Nothing in the body computes an aggregation.** Goal distance lives on the snapshot as
  `goalDistanceMeters` and is always the **goal calendar month's** total (not the week/custom
  window). Week → current month; month filter → selected month; custom → month of the range end.
- The goal ring is monthly only. `AppSettings` stores a live `monthlyDistanceGoalMeters` plus a
  `"yyyy-MM"` dictionary of frozen targets. The stepper edits only the in-progress month; past
  months show the locked value (or the live fallback when no history exists) and hide the stepper.
- `StatsViewModel.stats(includeNightRatio:)` lets callers that only need distance and duration skip
  the expensive part. The trip list's week summary and the widget sync in `TripStore` both pass `false`.
- **The tab has no `@Query` for trips either.** Fetching happens inside `StatsSnapshotLoader`, which
  loads `selected ∪ previous ∪ goalMonth` so a week view still has the full current month for the ring
  without pulling the whole library.
- **Aggregation runs on a `@ModelActor`.** `StatsSnapshotLoader` owns its own `ModelContext`, maps
  trips/rollups to `TripStatsRow`, and builds the snapshot there. `StatsView` only `await`s the
  result onto the main actor. A plain `Task { }` inside the view is *not* enough — SwiftUI views are
  `@MainActor`, so that task would inherit the main actor and still block the UI.
- Filter changes are debounced (~120 ms) after the first load, and the loader keeps an 8-entry
  request cache cleared whenever `storeVersion` bumps, so week ↔ month ↔ back is instant.
- Category, vehicle, favorite-place, and travel-journal filters scope **trip summary and chart series** together.
  The monthly goal ring stays unfiltered. Place or journal filter forces the trip fetch path (daily rollups
  have neither dimension); without those chips the 92-day rollup path is unchanged.
  The Stats filter card is presentation-only (`StatsFilterMenuField` menus + Clear All); it does not add a fetch.
  While a snapshot is in flight, the summary grid shows packed nested-tile skeletons instead of leaving empty cells.
- **Pager charts mount lazily per slide.** `StatsDeferredChart` / `StatsDeferredContent` take an
  `isPageActive` flag tied to the pager selection, so a `TabView` with five daily slides does not
  build all five Swift Charts when the section first appears — only the visible page (after the row
  scrolls into view). Vehicle cost charts use the same pattern via `VehicleCostSnapshotLoader`.
- **Comparison surfaces stay off the tab-open critical path.** Month-over-month trends are
  `StatsTrend` values on the existing trip/cost snapshots (MTD is a *slice* of the already-fetched
  previous month — the fetch window is still `selected ∪ previous ∪ goalMonth`). Logged vehicle
  expenses are built from `VehicleCompareSeed` + trip distances with `StatsShareBar` (slice color per
  vehicle, scaled to the top spend), not Swift Charts,
  on their **own** List row (below the fold, same cost snapshot — no extra fetch). Cost MoM uses **one** expense fetch covering
  current ∪ previous (`previousTotal` on the same snapshot). Place, journal, or category chips
  **hide** expense MoM and the vehicle $/km list — expenses have no those dimensions, so mixing them
  with scoped trip stats would be wrong. Vehicle filter still scopes the cost snapshot.

## Recap tab

- Mounts only while selected. Does **not** run `StatsSnapshotLoader`.
- Recap / forecast / badges / routes start on appear (`YearRecapSnapshotLoader`, `MonthCostForecastLoader`, achievement/route aggregates). Forecast sparkline is Canvas (`StatsForecastSparklineScene`) — not Swift Charts, no list `TimelineView`.
- `StatsYearAwardsLoader` (`StatsYearAwardsBuild`) loads on appear (first card). Must **not** overlap Recap-tab recap build. Year data is rollups + expenses only.
- Forecast is unfiltered (`selectedVehicleID: nil`).

## Reacting to saves

Dropping `@Query` from the trip list and the stats tab also dropped the change tracking that came
with it, so both reload on `ModelContext.didSave` through the `onStoreSave` modifier. Two things
about that notification make a plain `onReceive` wrong:

- **It is delivered on whichever thread performed the save.** `TripDerivedBackfiller` and
  `TripRollupRebuilder` save from their own `@ModelActor`. SwiftUI's `onReceive` requires the
  publisher itself to emit on the main thread — hopping only the handler still trips
  "Publishing changes from background threads is not allowed".
- **It cannot simply be `receive(on: DispatchQueue.main)` either.** That defers *every* reload by a
  runloop turn, including the main-thread save that a deletion performs. For that one turn the view
  still holds the deleted model in its own fetched array, and rendering a row from it is a crash
  rather than a glitch. `onStoreSave` uses a scheduler that runs immediately when already on main.

## Daily rollups (schema V11+)

`TripDailyRollup` pre-aggregates one row per (day, category, vehicle). A period's cost then scales
with the number of days it covers rather than the number of trips in it, which is what makes a
six-figure library viable.

- It is **derived data**. `Trip` remains the only source of truth, and the table can be regenerated
  from it at any time.
- `TripRollupService` maintains it as deltas at the same write sites that compute derived metrics,
  plus the deletion paths (`TripListView.deleteTrip`, `TripCleanupService`, and the legs consumed by
  a merge). An edit uses `snapshot(of:)` before the change and `update(_:from:)` after, so a trip
  that moved to another day, category or vehicle leaves its old bucket cleanly. A bucket that drops
  to zero trips is deleted rather than left as a zeroed row with a stale `maxSpeedMps`.
- Schema **V15** adds cruise / stop totals on each rollup (`stopDurationSeconds`,
  `cruiseWeightSeconds`, `cruiseSpeedProduct`) fed from matching derived fields on `Trip`. Cruise
  is moving average (metres while moving / moving time); period cruise is the duration-weighted
  mean of each trip's cruise.
  `rebuildVersion` 3 regenerates existing installs after the upgrade; later bumps refresh
  cruise / stop after formula fixes (v7: implied-speed stops; v8: most-common speed on
  rollups, schema V17). `TripDerivedBackfillService.speedProfileVersion` is bumped with the
  same formula so already-filled trips are rewritten.
- `rebuildIfNeeded` builds the table on the first launch that has it (after the derived backfill, on
  which it depends). Settings → Maintenance → *Rebuild statistics cache* runs `rebuildAll` on demand
  if the deltas ever drift. Both go through the `TripRollupRebuilder` `@ModelActor`, since a rebuild
  has to visit every trip and must not do that on the main thread.
- Reads go through the **same** aggregation as trips: `TripStatsRow.init(rollup:)` turns a bucket
  into one synthetic row carrying `tripCount`, which `StatsViewModel.stats` sums instead of counting
  rows. `StatsSnapshotLoader` switches to rollups only when the required window exceeds 92 days, since a week
  or a month holds few enough trips to read directly. The fetch window is
  `selected ∪ previous ∪ goalMonth`; a single calendar month still stays under the threshold.

## Premium derived caches (schema V21)

Year recap, frequent-route overlays, badges, and the month cost forecast all sit on the same
write path as daily rollups. They are **derived**, not a second source of truth: `Trip` (and
`VehicleExpense` for cash costs) still wins, and a rebuild version bump regenerates the tables.

- **Delta hook.** `TripRollupDelta` also runs `PremiumDerivedDelta` on finalize, merge, delete, and
  category/vehicle edits. GPS points are never faulted on that path. Live unlocks notify; a one-time
  `achievementRebuiltVersion` (currently 2) replay walks existing completed trips with `notify: false` so historical
  medals — including trip/hours/dawn/weekend/fleet families added after the first replay — open without inbox or overlay
  (and without wiping frequent-route aggregates). Recap also backfills those families from completed trips when the
  badges card loads, using first-trip progress as a fallback so a 50-trip medal cannot stay locked after 50 trips.
- **Year recap.** `YearRecapSnapshotLoader` reads that year's `TripDailyRollup` rows plus trip
  *endpoint* fields (locality, start/end place names and coordinates, category). GPS `points`
  are never faulted and `invalidatePointCaches` is not called. JSON cache in Application Support
  is stamped with `YearRecapCache.schemaVersion` (currently 6); a `storeVersion` change skips disk and rebuilds.
  Story pages are built before the cover appears; the snapshot is frozen at open; there is no fetch
  on page turn. Scene loops and segment fill each have a `TimelineView` so the Instagram tap overlay
  is not rebuilt every frame (Low Power 12 fps). Recap badges compact card wraps unlocked medals
  in centered rows (no horizontal scroller) and uses `achievementIdleClock`
  (`CADisplayLink` at 12 fps, same host as the recording road) because iOS pauses `TimelineView` and `.task` sleep inside a `List`, which froze medals on a stale tick.
  Gallery overlay uses the same `achievementIdleClock` after the morph (not `withAnimation` 0→1, which parks the 100 km car at opacity 0). Tab switches use `TrailhoundMotion.tabSwitch`.
  Do not put `animation = nil` on `TabView` — that pauses `TimelineView.animation` (recap / onboarding)
  and used to freeze the recording road.   List-hosted clocks (recording road, Start speed streaks, steering-wheel
  badge, stop-credits road) use `TrailhoundDisplayLinkTicker`, not `TimelineView`. The Start hound
  bones are Core Animation on `LaunchIntroHoundLayerTree` and do not write SwiftUI state per frame. Recap / onboarding
  (not inside a List) still use `TrailhoundIndependentClock.periodic`.
  Reduce Motion and UI tests skip idle. Hold / background / Reduce Motion / UI tests freeze `t`. The Recap hub
  teaser may idle-loop at 8 fps while the row is on-screen (frozen for Reduce Motion, Low Power,
  background, and UI tests). Chapter cards under the hub are `RecapChapterEmblemScene` with frozen `RecapChapterBackdrop` — do not add a TimelineView per card. Page changes use
  `TrailhoundMotion.recapPage` (scene push + copy settle). One full-bleed Canvas is the background (no second
  atmosphere layer). The cost page is that same Canvas (dual-hue pumps + pad, hose sway) with frozen `glassCard` amount plates — no extra clock.   Badge orbs and sparkles stay on that Canvas; medals overlay with the same slot frames. Toolbar chrome is 44pt Liquid Glass circles (`GlassNavCircleIcon` / `.glassCircleChrome()` — Close + Share under the
  segment bars), native `glassEffect` in Light and Dark.
  Share JPEG is an `ImageRenderer` still of the **current story page** (same Canvas + copy, frozen `t`), after first frame and again on page change, then `SocialImageShare` writes a temp `.jpg`. Instagram / Facebook omit the caption; WhatsApp / Messages / Mail keep it. Not a separate Core Graphics km poster. Reduce Motion and UI tests disable autoplay.
  The last page keeps the same clock; when the segment fills, the cover dismisses.
- **Frequent-route map.** Stored cap is **40** pairs; the map draws at most **8 habit corridors**
  (count ≥ 2, same metro as the top run). Strokes are **driving polylines** from `MKDirections`,
  cached on disk — not quadratic bezier arcs and never a GPS `points` walk. Heatmap samples follow
  those road paths (≤8 per corridor). Rendering uses `MKPolylineRenderer`. The Stats mini-preview
  frames the featured corridor; the expanded camera fits the visible habit set (clamped to 70 km).
  Expand scales that full-screen map into the card clip — the MKMapView stays screen-sized so MapKit
  does not pan. Edge insets stay 16 pt. A `routeRebuiltVersion` (currently 2) rebuilds
  aggregates with geo-cell + undirected pairing so old street-label drift does not fragment a commute
  (achievements stay on their own replay).
- **Widgets.** Goal ring, last trip, and cost summary read App Group `UserDefaults` plus optional
  `LastTrip.jpg` (kept under 100 KB). The widget extension does not open SwiftData.
  `PremiumWidgetBridge.reloadPremiumWidgetTimelines` runs on stop / finalize / expense / Stats
  refresh — not on every GPS tick. Recording control widgets keep their own home/lock reload path.

## Memory

`Trip.sortedPointsCache` is a `@Transient` array of materialised `TripPoint`s, so anything that
touches `sortedPoints` keeps those rows alive until it is cleared. It is now released at the three
places that used to leak it across a browsing session:

- `TripDetailView.onDisappear` — the detail map is the only screen that needs full resolution.
- `TripMapSnapshotCache` — route coordinates come from `TripRoutePathCache` on a miss, so scrolling the list no longer faults GPS on the main actor or keeps every row’s point history alive.
- `TripDerivedBackfillService` — between batches, so a backfill over a large library stays flat.

## Signposts

`PerformanceSignposts` wraps the two paths that historically blocked the main thread. Profile with
Instruments → os_signpost, subsystem `com.trailhound.app`, category `Performance`:

- `StatsSnapshotBuild` — one interval per snapshot rebuild.
- `StatsYearAwardsBuild` — calendar-year rollup + expense aggregation; must not overlap Recap-tab recap build or Stats tab-open `StatsSnapshotBuild`.
- `NightDistanceWalk` — appears only for trips that have not been backfilled yet. Seeing these
  steadily in a warmed-up app means the backfill is not completing.
- `TripsTabAppear` — one interval per trip-list `onAppear`. After the first load, the interval
  must stay well under a frame. A warmed-up Stats → Trips switch must not show `ModelContext.fetch`
  or `Data(contentsOf:)` inside it.

## Glass (light theme)

- Atmosphere still uses `RadialGradient` overlays, never `Circle().blur`. Light veil is 0.06 — not a milky white wash. Light native cards tint a deeper mid-family mix at ~0.50 **behind** content (0.10 rim) so they read as colored glass, not ice. Clip/mask the **plate** only — never labels in the corners.
- List rows (`glassRow`) and Stats cards use native `glassEffect` on Light iOS 26. Do **not** wrap the `List` in `GlassEffectContainer` — that frosts every row into one milky slab. Nested tiles stay frost fills. Camera, map overlays, and share rasters stay pinned (`allowsNative: false` / `frozen:`).
- Budget: at most eight native glass hosts on a screen (`GlassHostBudget.maxNativeHostsPerScreen`). If trips-list scroll, Stats scroll, or the recording card drops below ~58 fps on an iPhone 12-class device, pin that surface with `allowsNative: false`.
- Recording hero stays on the custom Material recipe so the road clock does not resample Liquid Glass every frame. End-credits in the trip list use the opaque `listSurface`, not a second live Material.
- Trip detail and travel-journal map expand still use `frozen` / solid glass so Material does not sample the live map.
- Trip/Travel detail, Place picker, and Vehicles editor **back / share / map-expand** icon actions use `GlassToolbarCircleButton` / `GlassToolbarBackButton` (44pt `GlassNavCircleIcon`, system shared platter hidden) so the tap target is the whole glass circle, not the SF Symbol. Text actions (Save / Cancel / Done) stay `GlassToolbarTitle` on the system platter. Trip / Travel / Vehicle detail titles use `GlassToolbarNavTitleItem` so the words have no extra title capsule. Light iOS 26 does not apply white `.tint` or `toolbarColorScheme(.light)` (those paint an extra plate). Never hide `_UIBarBackground` / scroll-pocket UIViews — iOS 26 draws Start / merge / bell / back / share in those layers. `.glassNavigationChrome()` hides the bar fill and the iOS 26 top/bottom `scrollEdgeEffect` on first appearance (UIKit transparent `UINavigationBarAppearance` plus SwiftUI edge-hide) so Trip/Travel push does not flash a cream title plate. Trip/Travel maps also use `.glassMapTopEdgeHidden()`. The tab bar is the system iOS 26 `UITabBar` (native Liquid Glass) in Light and Dark, bottom and side. Unselected stays the system ink. The selected tab uses the palette tint for that appearance — do not copy `UITabBarAppearance` or recolor the glass blob. Custom back on iOS 17–18 keeps the system chevron hidden; `NavigationInteractivePopEnabler` re-enables the edge-swipe pop (including over MapKit). On iOS 26, Trip, Travel, Place, and Vehicle detail keep the system back button so edge and full-screen swipe-back stay system-owned. Vehicle detail hides that button only while the embedded editor has unsaved edits, and passes `disabled` so swipe cannot discard silently.
- Stats expand collapse, Year recap Share/Close, and Trip/Travel toolbar icon actions are 44pt Liquid Glass circles (`.glassCircleChrome()` / `GlassNavCircleIcon` / `GlassToolbarCircleButton`) — native `glassEffect(.regular.interactive())` in `Circle()` in Light and Dark. Do not route this through `GlassEngineResolver` in Dark (that paints an opaque Material plate). Compact `.frozen` 36pt is unused on these screens.
- Overlay controls (`GlassToolbarControlBackground` on camera, photo grid, delete / merge confirm) keep `allowsNative` off. Native glass on a camera preview is the same resample trap as the recording hero.
- Nested tiles, field wells, and skeletons are tint fills — never a second `Material`.
- The **Badges gallery** idle cells use native `glassCard` (same Light plate as Stats). The Stats strip **morphs** into that gallery with a frozen outer plate (`frozen: true`) so Material does not resample during the expand. Medal chrome lives only on the round medals (km metals / family enamel). Compact-strip and gallery idle is `achievementIdleClock` (12 fps `CADisplayLink`, not `Task.sleep`). Gallery `playsMotion` stays off until the card-grow spring finishes so idle does not cancel `badgeCardExpand`. The overlay compact snapshot does not play idle. The 100 km one-trip car hill-cruises on that clock (offset + nose pitch, opacity stays 1). Badge share rasters a 9:16 poster (`AchievementShareRenderer`) after the gallery settles (or on tap); `SocialImageShare` exports JPEG (Instagram / Facebook image-only). Do not call `ImageRenderer` from the idle-clock `body`.
- Instruments baseline for this work could not be captured in CI (needs a physical device). Re-run Time Profiler + Core Animation after shipping and compare against the previous session.

## Profiling checklist

1. Instruments → Time Profiler + Core Animation on device.
2. Pairing → edit vehicle name with keyboard — should feel smooth vs list screens.
3. Start recording, scroll trip list, switch tabs — CPU should drop on non-Trips tabs.
4. Open a long trip detail — first frame must not hitch on GPS fault; map stays full-screen while the panel rises. Short trips may run map-clear + panel rise + route ticks; medium/long trips settle instantly. The details card stays at a fixed height (scroll inside; no grabber resize). Toolbar fullscreen must expand in place (panel recedes + camera opens together) — no second map sheet, no black flash.
5. Stats tab with many trips — first viewport (filter + 2-up + summary tiles) must not hitch; chart rows below the fold appear after placeholders. Recap tab recap/forecast must not run `StatsSnapshotBuild`; `StatsYearAwardsBuild` must not overlap Recap-tab recap build.
6. Record a long drive (thousands of points), then open its detail, list thumbnail, and share card — the route must draw as one continuous line except at genuine GPS gaps.
7. With 30+ trips, start recording and scroll the trip list past the card and back. Temporarily add `Self._printChanges()` to `recordingCard`: expect zero lines while idle and zero while scrolling. In Instruments, neither `context.fetch` nor `Data(contentsOf:)` should appear on the main thread.
8. Seed a few thousand trips, then switch to Stats. In the os_signpost instrument, `StatsSnapshotBuild` should stay well under a frame and `NightDistanceWalk` should stop appearing once the backfill finishes. Scroll the trip list to the bottom repeatedly: each page should load without a visible stall, and memory should stay flat rather than climbing with every screen of thumbnails. With 30+ trips, switch Light ↔ Dark and scroll immediately: rows must keep their last map thumb (map icon may sway while the other appearance renders); the list must not empty or hitch from parallel `MKMapSnapshotter`s.
9. With 100+ trips, open Trips once, switch to Stats, then tap Trips five times. In os_signpost, each return's `TripsTabAppear` stays under a frame and contains no `context.fetch` and no notification-archive read. The Hitches track stays clear on that frame. SwiftUI instrument shows no `TripListView` / `TripRowView` body update caused by the tap. If a hitch remains, check the unmount of the tab you left (Stats charts) before pinning trip-row glass.
