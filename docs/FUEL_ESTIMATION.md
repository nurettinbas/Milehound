# Fuel estimation

Milehound shows two fuel figures. Neither is a pump reading.

| Label | Stored field | What it is |
|---|---|---|
| **Avg fuel** | `Trip.estimatedFuelCost` | Catalog cost: `distance × C₀ / 100 × unit price` |
| **Est. fuel** | `Trip.dynamicFuelCost` plus volume / rate / breakdown | The same `C₀`, plus GPS litres for this trip’s speeds, waiting, acceleration, and likely cold start |

`C₀` is the vehicle (or trip-snapshot) consumption in L/100 km or kWh/100 km — the Settings average for **this car**, not a fleet 7.5. Unit price is per litre or per kWh. If `C₀` is missing, Avg and Est. stay empty; the engine does not invent a default.

## What GPS can and cannot do

The app does **not** have vehicle mass, drag area, engine displacement, road grade, cabin HVAC, or a sure engine-on signal. Estimated fuel does **not** claim pump accuracy on day one.

It uses:

1. **Catalog baseline** — `km × C₀ / 100`. This sets the scale for the car.
2. **Additive GPS litres** — speed-shape delta + idle + transient energy + cold-start bolus, each scaled to `C₀`.
3. **Optional measured L/100** — if you change L/100 on a trip and save, that trip is a measurement. It does not replace the vehicle average. Enough measurements learn a bounded per-vehicle bias.

A map **Stop** pin is **not** engine-off. Auto-detected parking sits on the same GPS hole as a traffic queue.

## Additive litres (model v6)

Canonical copy lives on `TripFuelEstimate` in `Milehound/Utilities/TripFuelEstimate.swift`. Keep that comment, this file, and the README formula in step.

```text
Avg            = km × C₀ / 100
baseLitres     = Avg
speedDelta     = km × C₀/100 × (distanceWeightedSpeedFactor − 1)   // signed
idleLitres     = estimatedIdleSeconds / 3600 × idleLph(C₀)
transientDelta = baseLitres × clamp(kTransient × energyIndex, 0, 0.35)
coldLitres     = coldProbability × maxCold(C₀) × warmupProgress

Est litres = base
           + motionConfidence × (speedDelta + idle + transient)
           + thermalConfidence × cold
           [× vehicle bias when ≥5 accepted measurements]

L/100 = 100 × Est litres / km
cost  = Est litres × unit price
```

Traffic score is a **label**, not a multiplier. Stop-go **count** is not a fuel term.

There is no global 10 or 18 L/100 cap. Component limits: speed shape `[0.65, 1.70]`, transient `≤ 35%` of baseline. For `km ≥ 1` only, a corrupt-GPS guard clips `0.5–3.5×C₀`. Below `0.2 km`, volume is kept and L/100 shows as "—".

Unusable GPS (sparse, teleports, distance mismatch) shrinks `motionConfidence` toward 0, so Est. falls back toward catalog plus a cautious cold start.

### Speed curve (1.0 = this car’s C₀)

Petrol knots (L/100 relative to C₀): 10 km/h 1.55 · 30 1.18 · 50 **1.00** · 70 0.90 · 85 0.85 · 100 1.00 · 120 1.25 · 140 1.55.

Diesel damps the low-speed bump; hybrid damps low speed more and high speed slightly; EV uses `0.50 + 0.50×(v/80)²` with no combustion idle or cold start (output is kWh).

LPG uses the petrol knots, idle, cold start, and transient. It is still litres and L/100 km. Absolute volume scales with that vehicle’s C₀ — switching a car to LPG does not invent a higher consumption. Settings shows one price row per fuel type on your vehicles (petrol 65, LPG 35, electric 8.5 per kWh until you change them). Diesel and hybrid keep the petrol liter price until you set their own. A trip that already stored `fuelUnitPrice` keeps that snapshot.

The speed term is on **stored** kilometres. Unobserved distance stays at C₀.

### Idle, transient, cold

- Petrol idle `clamp(0.114×C₀, 0.08–0.20×C₀)` L/h. Diesel 0.75×, hybrid 0.10×, EV 0. Engine-on probability 0.85 / 0.65 / 0.20 for short / medium / long GPS stops.
- Transient is one integral of filtered positive kinetic energy (not a per-event penalty). Hybrid/EV regen is capped at 35% / 55% of traction energy.
- Cold start uses the previous completed trip on the same vehicle (soak + how long/far that trip was). No previous trip → cold is likely, with lower confidence. Max petrol bolus is `1.4 × C₀ / 100` litres (~1.4 km of extra fuel).

### Efficiency and traffic

Efficiency (neutral 80) is from `rate / C₀`, not an absolute L/100. Traffic is Low / Moderate / Heavy / Unknown from GPS only — not live traffic, not a second fuel multiplier.

## Scenario bands (`rate / C₀`)

Warm mixed city + suburban should sit near **0.95–1.10×C₀** (your average on a normal trip). Short stop-go and cold starts sit above; steady 80–85 km/h highway sits **0.80–0.90×C₀**; 120 km/h **1.15–1.40×C₀**. The same GPS trace at C₀=5 and C₀=10 keeps `rate/C₀` and scales litres with C₀.

## Where it is written and read

Written (never touches `estimatedFuelCost` or GPS points):

- trip end, edit save, merge, cleanup, orphan finalize → `TripDerivedMetrics.recomputeFuel` (looks up the previous trip on the same vehicle)
- launch backfill → `TripDerivedBackfillService` (`milehound.derived.dynamicFuelVersion`, currently **6**), in vehicle + `startedAt` order
- opening a completed trip also rewrites that trip’s stored Est. so the detail screen is not waiting on launch backfill
- changing a trip’s time / distance / vehicle, or deleting / merging it, recomputes the **next** completed trip on that car (`TripFuelDependencyService`) so soak stays correct

Read:

- Trip detail Est. fuel (`₺ · litre · L/100` or kWh), driving efficiency, traffic, up to four factor chips
- Stats totals, volume / rate / efficiency when the filter is a single fuel unit, daily Avg/Est. bars
- `TripDailyRollup` volume + breakdown (rebuild version **14**)
- CSV/JSON export `dynamicFuelCost`

**Not** used by month cost forecast, year recap, travel-journal totals, trip-list fuel chip, or widgets — those stay on avg fuel.

Mixed petrol and electric in the same Stats filter: cost still totals; litres and kWh are **not** added together. LPG counts as liquid litres, so it adds with petrol, diesel, and hybrid.

If a fuel-formula refresh is interrupted, the version key is **not** written, so the next launch finishes fuel then rebuilds Stats.

Deleted vehicles: trip `fuelTypeSnapshot` + C₀ + price snapshots keep the original powertrain. An old EV trip does not fall back to petrol curves.

## Measurements and calibration

The trip-edit L/100 field is unchanged on screen. Changing it and saving marks **that trip** as measured (`measuredFuelConsumptionPer100`, `.userMeasured`). Catalog `fuelConsumptionPer100` stays the vehicle average snapshot.

`VehicleFuelCalibration` stores a robust bias (Huber / MAD outliers, WAPE, bounded 0.75–1.30). After 5 accepted samples the bias is applied; after 20 diverse samples, speed / idle / transient / cold weights may move inside 0.5–1.5. Logged pump expenses are not training labels.

## Schema / user data

Schema **V22** adds optional Trip measurement + estimate fields, rollup volume / `fuelUnitKey`, and `VehicleFuelCalibration`. Existing trips, GPS traces, and Avg fuel stay. Opening an existing store is a lightweight add of optional columns and a new table — the production path does **not** reset `Milehound.store`.
