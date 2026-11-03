# Travel journal (Seyahat günlüğü)

> **Status:** Implemented (schema V19, additive)  
> **Placement:** Trips tab → cam segment **Trips | Travels** (TR: **Trip’ler | Seyahatler**). No fifth tab.

A travel journal groups completed trips under one date range so the map can show **every route in that group**. It is a route archive, not a photo diary, social map, or live broadcast.

---

## Two layers (do not mix)

| Layer | Purpose | UI |
|-------|---------|-----|
| **Trip** | One recorded drive | Existing list + `TripDetailView` |
| **Travel journal** | Named group of trips + multi-route map | Segment on Trips tab + `TravelJournalDetailView` |

Adding a trip to a journal does not change category, vehicle, fuel, or Stats rollups. Deleting a journal **nullifies** membership; it does not delete trips.

v1: a trip belongs to **at most one** journal (`Trip.journalID` optional). Moving it reassigns; it is not duplicated.

---

## Product

- User (or an accepted suggestion) creates a **Seyahat** with a title, start/end dates, optional note.
- The journal map draws every member route. Tapping a day-row or a polyline selects that trip (speed-colored); others stay muted brand strokes.
- From trip detail, **Add to travel** sits under the note field.
- Empty state: create the first journal, plus an optional suggestion chip. Nothing is auto-filed.

Out of v1: photos, journal share-poster, CKShare, live travel, clustering of GPS *points* (only route-level overview simplification at far zoom).

---

## Placement (no new tab)

[`AppTab`](../Milehound/Utilities/TabSelection.swift) stays `trips | pairing | stats | year | settings`. Journals live inside the Trips tab.

```
TripListView
  recording card (unchanged)
  TripListFiltersBar
    [Trips | Travels]   ← glass segmented control, filter-bar language
    existing chips (date / category / vehicle / place) when Trips is selected
    journal search + date chips when Travels is selected
  Trip rows  XOR  TravelJournal rows
```

Stats: a **Travel** chip next to the favorite-place filter (same independent-per-tab rule). Place filter already forces the trip-fetch path because rollups have no place dimension; a journal filter does the same.

---

## Data (schema V19, additive)

Journals shipped as **V19** (additive). Live tip schema is **V20** ([`ModelContainerFactory.currentSchemaVersion`](../Milehound/Utilities/ModelContainerFactory.swift)), which also adds smart-category fields. Journals add a model and optional fields only — no store reset, no property rename.

### `TravelJournal` (new)

| Field | Notes |
|-------|--------|
| `id: UUID` | Stable identity |
| `title: String` | User-editable; suggestion may seed it |
| `startedOn: Date` | Calendar day of earliest member (start-of-day) |
| `endedOn: Date` | Calendar day of latest member |
| `coverTripID: UUID?` | Mosaic hero; default = longest member by `distanceMeters` |
| `note: String?` | Optional journal note (separate from `Trip.note`) |
| `tripCount: Int` | Denormalized |
| `distanceMeters: Double` | Denormalized sum of member `distanceMeters` |
| `fuelCost: Double` | Denormalized sum of `dynamicFuelCost ?? estimatedFuelCost ?? 0` |
| `searchIndex: String?` | Lowercased title + note + date range (list search) |
| `trips: [Trip]` | Relationship, `deleteRule: .nullify`, inverse `\Trip.journal` |

List rows **must** read denormalized totals. Do not fault `trips` or `points` while scrolling.

### `Trip` additions

| Field | Notes |
|-------|--------|
| `journalID: UUID?` | Mirror of the relationship for `#Predicate` (same pattern as `vehicleID`) |
| `journal: TravelJournal?` | Optional; nullify on journal delete |

`TripDerivedMetrics` (or a sibling `TravelJournalTotals`) is the **only** writer of journal totals and `searchIndex`. Call it wherever membership or trip fuel/distance/dates change:

- Add / remove / move trip
- `TripRecordingService.stopRecording` (if the user added the new trip in the same session — normally journals only accept `endedAt != nil`)
- `TripMergeService.merge` — see Merge rules
- `TripDetailView` save (trim, fuel edit)
- Trip delete

Existing V18 trips open with `journalID == nil`. Backfill is not required.

Register `TravelJournal.self` in `ModelContainerFactory.liveSchema` and `MilehoundSchemaV19`.

---

## Suggestion rules (pure, opt-in)

Silent auto-folder is forbidden. A chip **Önerilen seyahat** / **Suggested travel** appears above the journal list when `TravelJournalSuggester` returns a candidate the user has not dismissed.

**Away day:** using `startLatitude/Longitude` and `endLatitude/Longitude` only (never `sortedPoints`), a calendar day is *away from home* when **neither** endpoint sits inside any `SavedPlace` with `kind == .home` (`SavedPlace.contains`). Days that start or end at home are commute days and break a chain.

**Candidate:** a run of consecutive away days that is not already covered by an existing journal, and that meets **either**:

- ≥ **2 nights** (calendar days in the run ≥ 3, or first start → last end spans ≥ 2 midnights), or
- total `distanceMeters` of completed trips in the run ≥ **150 km** (`TravelJournalSuggester.minimumDistanceMeters`)

**No home place:** no suggestions (the rule is undefined). Do not invent “away” from work-only places.

**Accept:** creates a `TravelJournal`, assigns those completed trips, seeds `title` from the farthest `startPlaceName` / `endPlaceName` (else the date range). **Dismiss:** store a fingerprint (`startDay|endDay|tripIDs-hash`) in `AppSettings` / UserDefaults so the same run does not nag. Editing trips can produce a new fingerprint.

In-progress recordings (`endedAt == nil`) are ignored.

---

## Screen inventory

### Travels list

Glass cards (`GlassTokens.cardRadius`, `glassRow`):

- Title (headline)
- Date range (`DateFormatters` — same style as trip rows)
- Meta chip row: trip count · distance · `FuelCostCalculator.formatCost(fuelCost)` (hide ₺ when `fuelCost == 0`)
- Mosaic: up to **3** `TripMapSnapshotCache` thumbs (`coverTripID` first, then next-longest), same appearance as the trip list (`cachedImage(for:appearance:)`). Prefetch like `VehiclePhotoStore.prefetch`. Memory hit is scroll-safe; disk/decode stays off the main actor (existing cache contract).
- **No live MapKit** in the list.

Empty: `GlassEmptyState` — title **Create your first travel** / **İlk seyahati oluştur**, `systemImage: "map"`, plus the suggestion chip when one exists.

Create: glass sheet — title, optional note, trip picker (completed, `journalID == nil` or already in this draft). Dates derive from members on Save (draft + Save, same as `VehicleEditorDraft` — no SwiftData write per keystroke).

Search: 250 ms debounce on `searchIndex` (same as trip list). Do not reuse `TripListPage.listPredicate` for journals; that macro is already at the type-checker limit (place + search + category).

Paging: `TravelJournalPage` — `pageSize` 50, `pageLimit + 1` probe, sort `endedOn` descending. Footer load-more section, not last-row trigger ([`docs/PERFORMANCE.md`](PERFORMANCE.md) trip-list rule).

### Travel detail

Same skeleton as trip detail: full-screen MapKit + bottom glass panel. Do not resize the map with panel height; use `MapFitContext.detailOverlay`. Elevation stays **`.flat`**. On the upright Duo, open or the closed cover, the pulled-up sheet stops at half the page (`duoExpandedFraction` 0.5). A taller phone still opens to 0.72.

**Map**

- One polyline per member trip.
- Palette: brand-blue steps from `MilehoundBrandColors` / `StatsChartTheme.distanceSliceColors` (stable by `trip.id`). No rainbow, no recording red.
- **Selected** trip: full speed-colored segments (`SpeedColoredSegmentBuilder.maxColorSegments` = 60) + white casing (same settled look as trip detail).
- **Others:** single brand stroke at **40%** opacity.
- Tap polyline or day-row to select. Selection does not push `TripDetailView` by itself.
- Fit: union bbox of all display pieces + `MapFitContext.detailOverlay`. Toolbar expand/collapse reuses `MilehoundMotion.mapExpand` / `mapCollapse` and frozen glass during the transition.
- Reduce Motion: instant fit, no draw-on, no mosaic crossfade.

**Panel**

- Journal title + note (draft + Save)
- Totals: trips, km, ₺, date range
- Day sections (`TripDateGrouping` / start-of-day) → existing trip row chrome → `navigationDestination(for: Trip.self)` into `TripDetailView`
- Remove-from-journal (swipe) nullifies membership and refreshes totals

**Wide landscape** (phone book and open Duo, `tripDetailStyle == .split`): the member list is the leading pane, top to bottom, on the split’s one atmosphere. No grabber, no second wash, no rounded plate. Trips are visible without pulling the sheet up. The route map fills the trailing pane (top, bottom, and trailing edge). The expand control still opens the map across the window. On the closed Duo cover in landscape (`isClosedCoverLandscape`), the map fills the screen and the journal is the phone sheet at the bottom-trailing corner, at most one third of the screen wide, on the same lightweight atmosphere. It arrives as the summary. Pulling the grabber up lists the trips and the card can fill the screen. Pulling down returns the summary. The route stays in the map above the card. A narrower landscape phone that is not that cover keeps the 380 pt trailing card. iPad landscape keeps the trailing card.

### Trip detail

Under the note field: **Add to travel** / **Seyahate ekle** (`glassRow`). Picker: existing journals + **New travel**. If already a member, show the journal name and **Move** / **Remove**.

In-progress trips: control hidden.

### Stats

Optional journal field on the Stats filter card. When set, `StatsSnapshotLoader` uses the trip-fetch path (not 92-day rollups — they have no journal dimension), same as favorite place. Goal ring stays unfiltered.

---

## Map performance

Multi-route is heavier than trip-detail reveal. Hard rules:

| Budget | Value | Why |
|--------|-------|-----|
| Per-trip display path | `RouteDisplayPath.maxDisplayPoints` (1500) via `TripRoutePathCache` | Unchanged contract |
| **Journal draw budget** | **≤ 4000 points total** on screen | Long weekends stay independent of library size |
| Speed-colored overlays | **Selected trip only**, ≤ 60 segments | 12 trips × 60 overlays would hitch |
| Unselected trips | 1 `MKPolyline` each | Constant overlay count ≈ trip count |
| First paint | Do not fault `sortedPoints` | Async `path(...)` memory → disk → build, same as trip detail |
| List mosaic | `TripMapSnapshotCache` only (appearance-aware) | No MapKit in `List` |

**Adaptive decimation:** if `sum(displayPointCount)` exceeds 4000, raise per-trip tolerance until the cap holds; always keep each path’s endpoints. Pure function `TravelJournalMapBudget.allocate(pointCounts:totalCap:)` — unit-test with 12 and 63 trips. Do **not** replace routes with a bounding rectangle when the journal is large.

**Overlay churn:** swapping selection rebuilds **one** speed-colored set and restyles the previous trip to a muted stroke. Do not `removeOverlay`/`addOverlay` the whole journal. `TravelJournalMapLayer` should be `Equatable` and ignore panel height (copy `TripDetailMapLayer`).

**Reveal:** first open of a journal may draw unselected strokes in a short tick sequence (~12) as a *single* growing overlay group, not per-trip speed colors. Same-session reopen is instant (`TravelJournalRevealSession`). Reduce Motion skips ticks.

Privacy clip: each route uses the same privacy-radius clipping as trip detail / share (`TripShareRoutePrep` / list summary). Journal map is a display path, not a second copy of GPS on disk.

---

## List / Stats performance

- Journal rows never walk `trip.sortedPoints`. km / ₺ come from denormalized fields.
- Recalc totals on `onStoreSave` (existing hop-to-main-if-needed modifier), not in `body` or on scroll.
- Suggestion scan: `startLatitude` + `endLatitude` + `SavedPlace.contains`. Forbidden: `sortedPoints`, `RouteDisplayPath` inside the suggester.
- Travels segment does **not** add `journalID` to `TripListPage.listPredicate`. A second page type keeps the trip predicate from growing.
- Prefetch at most the mosaic’s 3 snapshot IDs per visible card; do not prewarm every member path from the list (that was the trip-row GPS fault).

---

## Theme / motion / a11y

- Shell: `AtmosphericBackground` + `GlassSurface` / `glassRow` / `glassChip`.
- Accent: `MilehoundBrandColors` blues. Recording red/orange only on the live recording card, never on journal chrome.
- Typography: system styles (`.headline` title, `.caption` meta). No custom fonts.
- Motion: `MilehoundMotion.gentle` for list insert; `sheetRise` for create sheet; `mapExpand` / `mapCollapse` on detail. Reduce Motion: `nil` animations, instant map fit, static mosaic.
- VoiceOver: card label is title, dates, trip count, distance, cost. Mosaic images are decorative (`accessibilityHidden`).
- Appearance: follow `AppSettings.appearanceMode`; map style picker on expanded journal map matches trip detail (light/dark override).

---

## Merge, delete, recording

| Event | Journal behavior |
|-------|------------------|
| Merge trips in the **same** journal | Survivor keeps `journalID`; totals refresh; deleted IDs drop from mosaic/cover |
| Merge trips from **different** journals (or mixed nil) | Survivor `journalID = nil`; both journals recalc. User re-adds if they want. Do not silently steal membership. |
| Delete trip | Nullify; recalc; if `tripCount == 0`, keep the empty journal (user deletes it) unless they confirm delete-journal |
| Delete journal | `deleteRule: .nullify` on trips |
| Recording | Cannot join until `endedAt != nil` |

---

## Localization

Primary EN + TR in `Localizable.xcstrings`. Suggested keys:

| Key | EN | TR |
|-----|----|----|
| `trips.segment.trips` | Trips | Trip’ler |
| `trips.segment.travels` | Travels | Seyahatler |
| `journal.empty.title` | Create your first travel | İlk seyahati oluştur |
| `journal.empty.message` | Group trips under one map when you go away. | Uzaktayken trip’leri tek haritada toplayın. |
| `journal.suggest.chip` | Suggested travel | Önerilen seyahat |
| `journal.add` | Add to travel | Seyahate ekle |
| `journal.new` | New travel | Yeni seyahat |
| `journal.remove` | Remove from travel | Seyahatten çıkar |
| `journal.stats.filter` | Travel | Seyahat |

Language follows Settings → Personalization → Language (English, Türkçe, or the iPhone language). Currency still uses `FuelCostCalculator` / `AppSettings` (default ₺).

Share v1: keep per-trip share cards. A multi-snapshot travel poster is explicitly later (expensive, blocks UI if naively composed).

---

## Implementation map (when building)

| Area | Likely files |
|------|----------------|
| Model | `Milehound/Models/TravelJournal.swift`; `Trip.journalID` / `journal`; schema V19 |
| Totals | `TravelJournalTotals` next to `TripDerivedMetrics` |
| Suggest | `Utilities/TravelJournalSuggester.swift` (pure) |
| Map budget | `Utilities/TravelJournalMapBudget.swift` (pure) |
| Paging | `ViewModels/TravelJournalPage.swift` |
| List | `Views/TravelJournalListView.swift` + segment in `TripListFiltersBar` / `TripListView` |
| Detail | `Views/TravelJournalDetailView.swift`, `TravelJournalMapLayer.swift`, `TravelJournalEditPanel.swift` |
| Stats | `StatsSnapshotLoader` request + chip |
| Trip detail | `TripDetailEditPanel` add/move row |
| Tests | `TravelJournalSuggesterTests`, `TravelJournalMapBudgetTests`, membership uniqueness, Stats filter, schema V19 open |

Do not put `@Query` for all journals if the library can grow; page like trips.

---

## Tests

- **Budget:** 12 trips with 1500 display points each allocate ≤ 4000; endpoints preserved.
- **Suggest:** weekday home → work → home does **not** produce a candidate. A Fri–Mon away block with ≥2 nights does. No home place → no candidate.
- **Uniqueness:** assigning trip T to journal B clears journal A; `journalID` matches the relationship.
- **Predicate isolation:** Travels segment does not change `TripListPage` type-checker load (compile + existing list tests still pass).
- **Totals:** fuel uses `dynamicFuelCost ?? estimatedFuelCost ?? 0`; GPS not touched.
- **Merge:** same-journal merge keeps membership; mixed journals clear it.
- **UITest (smoke):** segment → empty state copy visible (EN/TR).

---

## Privacy

Journals are local SwiftData. No network. Privacy-zone clipping on the journal map matches trip detail (display names / clipped paths). If iCloud sync ships later, `TravelJournal` + `journalID` ride the same opt-in store — this plan does not enable CloudKit.

---

## Out of scope (v1)

- Photo / media diary
- Social or public travel map
- Real-time travel broadcast
- A trip in two journals at once
- Fifth tab
- Journal share poster / multi-`MKMapSnapshotter` compose
- CKShare across Apple IDs
- GPS point clustering; realistic MapKit elevation
