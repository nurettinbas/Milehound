# Stats tab

Product layout and the performance contract for Milehound’s Stats tab. Chrome follows the selected **shell palette** (`GlassContrast` / `StatsChartTheme`) — not a fixed brand-blue skin. No extra fetch on tab open.

## Card language

One chrome (`StatsCard.swift`):

| Span | Use |
|---|---|
| **Half** | Goal ring + stepper, beside hero numbers (distance, duration, expenses — or trips when expense MoM is hidden) |
| **Full** | Filter, nested summary tiles, each chart pager, logged vehicle expenses |
| **Nested tile** | Remaining summary metrics inside the summary card; palette-tinted frost fill, radius 16 — not a second glass card |
| **Nested panel** | Same frost fill as nested tiles, variable height (`.statsNestedPanel()`) |

List rows use a **clear** background. The card is `glassCard` only (native Light `glassEffect` behind content). Mixing `glassListRow` / `GlassRowPosition.first` with a floating chart card is forbidden. Swift Charts axis ticks and Y-axis units (`km`, hours, currency) use `StatsChartTheme.axisLabelInk` / `.chartStatsYAxisUnit` so they stay white on Light — never the Charts default primary (black).

Year recap, badges, frequent routes, month forecast, and year awards live on the [Recap tab](YEAR_TAB.md).

On an open Duo the summary column leads and the charts trail. Daily distance is a titled card on that trailing side in both the upright fold and the landscape book — not an untitled plate under the summary. When the hinge is fully open the summary column is 45% of the content and the charts are 55%. A partially open hinge keeps the seam on the fold.

Deep link `milehound://stats/goal` opens this tab. Recap / forecast / routes / achievements URLs open Recap.

See [PERFORMANCE.md](PERFORMANCE.md) Stats tab section.

## Sticky navigation

Phone Stats puts **Summary** on the goal card and the period (Last 7 days, month, or custom range) on the hero card and on the metrics grid. Chart sections use the same in-card title. As you scroll, the title stays on the card and the body slides up under it. Once only the title strip is left, that strip fades out where it sits and fades back in when you scroll down. Horizontal chart pagers use `.glassCarouselPage()` and do not rebuild `StatsView` mid-swipe.

The filter card stays at the top of the phone list (period chips, month picker, custom dates, menus, Clear All). Wide/Duo layouts keep that card open in the leading rail.

## Filter card

On phone and wide layouts the filter row is one full-width `glassCard` — no extra fetch, no `GeometryReader`. Layout:

- **Period chips** keep the same compact expanding capsules (Last 7 days / Month / Custom). Light selected chips are a mid-family wash with white type; unselected chips are frost plus white. Dark uses the selected palette tint. Month stepper and custom start/end dates stay on the same card.
- **Category, vehicle, place, travel** are equal selection fields: title, one-line truncated value, chevron. Long names do not wrap onto neighbouring fields. Vehicle keeps its avatar. Active fields use a brand stroke in dark and a white stroke in light.
- **Two columns** at standard Dynamic Type; **one column** at accessibility sizes. Each field’s tap target is at least 44 pt.
- **Clear All** appears only when something is not the default. It clears category / vehicle / place / travel, sets the period back to Last 7 days, and restores the default month and custom dates. Reduce Motion skips the reveal animation.

VoiceOver reads each field’s title and current value. Identifiers: `stats.filters.card`, `stats.filters.clear`, `stats.filters.period.{week|month|custom}`, `stats.filters.{category|vehicle|place|journal}`, `stats.section.{summary|daily|weekday|mix|vehicles|categories}`.

## Summary skeleton

Filter changes can move tiles between the hero and the summary grid (trips vs expenses). Until `StatsSnapshotLoader` returns, the summary card shows packed nested-tile skeletons (`StatsSummaryTileSkeleton`) at the destination count — no empty grid holes, no extra fetch. Reduce Motion keeps the bars static. VoiceOver reads **Loading summary**.

Previous-period values from comparison live on the hero and on tiles that have a `StatsPeriodCompareRow` (trips, distance, duration, expenses, estimated fuel) plus extra nested tiles (average trip distance, moving time, night km, driving days). The old spreadsheet strip is not a separate card.

Summary nested tiles also include average trip distance (beside average duration), moving time (beside total stop), night km (beside the night-distance percent), driving days (`12 / 30`), and busiest day (`14 Sep · 42 km`). Driving days counts calendar days with at least one trip over the days shown on the daily charts. Last 7 days is today plus the previous six calendar days — not a 7×24h window (which spans eight dates).

Daily pager pages include trip count and, when the period has any night km, a night-distance bar. Two more full-width pagers sit after Daily trends, before vehicle compare:

- **By weekday** — Mon–Sun distance and duration bars (`firstWeekday` order). Hidden when every weekday is zero.
- **Split** — night vs day km, moving vs stopped time, and fuel-factor volume donuts (same `statsDonutPage` chrome as vehicle/category). Hidden when the period has no tracked km, duration, or fuel-factor volumes. Mixed litre+kWh filters hide the fuel-factor page.

Hour-of-day heatmaps and single-trip “longest trip” are out of scope: daily rollups have no hour or per-trip identity. Frequent routes stay on Recap.

Estimated fuel on the summary tile and the daily dual Avg / Est. chart is the GPS-adjusted `dynamicFuelCost` (see [Fuel estimation](FUEL_ESTIMATION.md)). After a formula change, launch backfill rewrites stored trip values first; daily rollups rebuild only when that walk has finished. Avg fuel, month forecast, and year recap stay on catalog `estimatedFuelCost`.

When the filter is a single fuel unit, Stats also shows estimated volume (litres or kWh), distance-weighted L/100 or kWh/100 km, and driving efficiency. Petrol and electric in the same filter are not added together.

Logged vehicle expenses (Capsule bars, not Swift Charts) is its **own** full-width card, with a `?` that explains the sum. Each vehicle uses the donut `sliceColor` (stable per vehicle id) and `StatsShareBar` scaled to the top spend — not identical bucket-green fills. Vehicle donut charts stay in the following pager card. Both still use the same cost snapshot — no extra fetch.

## What stays deferred

- `StatsSnapshotLoader` / `VehicleCostSnapshotLoader` on `@ModelActor`. Fetch window remains `selected ∪ previous ∪ goalMonth`.
- `StatsDeferredChart` / `StatsDeferredContent` + `isPageActive` — only the visible pager slide mounts Swift Charts (daily, weekday, split, vehicle, category).

See [PERFORMANCE.md](PERFORMANCE.md) Stats tab section.
