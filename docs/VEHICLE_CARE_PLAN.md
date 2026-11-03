# Vehicle care & expenses

> **Status:** Shipped (schema V14) — installments + UI layering; receipt photos + on-device amount reading (schema V23); odometer anchor (schema V24)  
> **Placement:** Vehicles tab → single detail screen

---

## Two layers (do not mix)

| Layer | Purpose | UI |
|-------|---------|-----|
| **Tracking & reminders** | Inspection, insurance, casco, service due dates + push | `VehicleSchedule` |
| **Expenses** | Amount paid (separate ledger) | `VehicleExpense` |

Adding a reminder is not logging an expense. **Mark done** on a schedule closes/rolls the due date and writes an expense (optionally split into installments). **Add expense** only writes a cost row.

---

## Installments (cash-basis)

A purchase can be **pay in full** or **2–24 monthly installments**.

| Rule | Behavior |
|------|----------|
| Amount | Total of the purchase. Milehound splits it into equal monthly shares (leftover kuruş on the last slice). |
| Date | First payment. Later slices are the same calendar day in following months (31 Jan → 28/29 Feb). |
| Ledger | Each slice is a real `VehicleExpense` on its due date, sharing `installmentGroupID`. |
| Expenses list | Due/past slices only. Future slices sit under **Upcoming installments** until that day. |
| Stats | Existing `occurredAt` aggregation — August shows only August’s share; a longer range shows every month in range. |
| Edit | Opening any slice edits the whole plan (total, count, first date). |
| Delete | One slice, or the entire plan. |

Existing V13 expenses stay one-shot (`installment*` fields `nil`). Additive V14 only — no store reset.

**Mark done:** the visible checkmark (Done) on the reminder row opens the completion sheet; leading swipe is the same action as a shortcut.

---

## Receipts (V23)

An expense can carry one receipt photo. Reading the amount from it is optional and always needs the user's confirmation.

| Rule | Behavior |
|------|----------|
| Storage | JPEG in Application Support `ExpenseReceipts/` (`ExpenseReceiptStore`), long edge ≤ 1600 px, file protection until first unlock. SwiftData stores only `VehicleExpense.receiptFileName`, never image bytes. |
| Source | **Add Receipt** opens the same Library / Camera sheet as vehicle photos (`VehiclePhotoFlowSheet` with `PhotoSourceCopy.receipt`). No framing step. |
| Form | Thumbnail opens a full-screen viewer (pinch, double-tap). **Read Amount**, **Replace Photo**, **Remove Receipt**. A new file is kept only after Save; Cancel or swipe-dismiss deletes it. A removed saved receipt is deleted only after Save. |
| Installments | Every slice of one plan points at the same file. Deleting one slice keeps the file while any expense still references it. Deleting the plan or the vehicle removes it. |
| Expenses list | A receipt glyph after the date marks rows with a photo. |
| Read Amount | Apple Vision `VNRecognizeTextRequest` (`.accurate`, tr-TR / en-US when supported, language correction off so digits stay raw) on the device. No network, no AI model, no third-party SDK. |
| Parser | `ReceiptAmountParser` — fixed rules. Total labels in priority order: GENEL TOPLAM, ÖDENECEK (TUTAR), TOPLAM TUTAR, GRAND TOTAL, AMOUNT DUE, TOTAL DUE, TOPLAM, TOTAL. Skips ARA TOPLAM, SUBTOTAL, TOPKDV / KDV / VAT / TAX, NAKİT / CASH, PARA ÜSTÜ / CHANGE, İNDİRİM / DISCOUNT (`TOPLAM (KDV DAHİL)` still counts as the total). Reads `1.234,56`, `1234,56`, `1,234.56`, `*1.234,56`, `TL` / `₺`; dates and times are not amounts. A label with the value on the next row is joined. With no label, the largest amount is offered as a guess. Up to four other amounts are offered as chips. |
| Confirm | The sheet outlines the matched row on the photo, shows the amount large, and warns that text recognition can make mistakes. **Use This Amount** fills the field in whole units (1.234,56 → 1.235, as the field takes whole units). **Not Right** leaves the field alone. |

**Limits:** thermal paper glare, crumpled or faded receipts, and handwriting read poorly. Receipts with several totals (tip, split payment) may highlight the wrong row. That is why nothing is written without confirmation.

**Migration:** V23 only adds the optional `receiptFileName` column. Existing expenses open with `nil`; amounts, dates, and installments are untouched. Verified by opening a copy of a real V22 simulator store (`VehicleCareMigrationTests.testRealV22StoreOpensUnderV23WithoutDataLoss`).

---

## Screen order

1. **Vehicle info** — profile draft. Save sits under that card, not in the nav bar, so it is not confused with an expense or reminder save (`PairingVehicleEditorForm` embedded)
2. **Tracking & reminders** — Add reminder is the same row button as before, at the top of the section, above the due list. Done stays on each row
3. **Expenses** — Add expense is the same row button, at the top of the section, above the list. On the open book, the profile stays on the leading side and Tracking & reminders plus expenses scroll together on the trailing side. When the Duo hinge is fully open, the profile is 40% and that trailing side is 60%. A partially open hinge keeps the seam on the fold. Add reminder and Add expense slide in from the trailing edge and fill that half; back and Save slide it back out. They do not open as a sheet and do not take over the vehicle navigation bar. Other widths keep one list and a sheet

Cost charts live only on **Stats** (`VehicleCostSnapshotLoader` / Vehicle costs).

---

## Expense categories (picker)

Fuel · Traffic insurance · Casco · Service · Inspection · Repair · Accessory · Road toll · Parking · Vehicle tax (MTV) · Other

Legacy raw values (`insurance` → traffic insurance, `tax` → MTV, `parts` → accessory) map on read. Stored `parking` is the parking case. Category is a string (`categoryRaw`), so new cases do not bump the store. The live store is **V24** for the odometer anchor fields.

---

## Odometer (V24)

The vehicle profile has an optional **Odometer** field (0...2,000,000, digits only). Saving a new number sets the anchor. Trips that start at or after that moment add their distance. Trips before it do not. Clearing the field turns kilometre reminders off; date reminders stay.

`currentOdometerKm` is the cached total (anchor + whole kilometres since the anchor). Deleting or editing a trip adjusts that cache. Merging trips recomputes it from the trips that remain. A typed reading, including one entered when a service is marked done, replaces the anchor.

V24 only adds `odometerAnchorKm`, `odometerAnchorAt`, and `odometerTripMetersSinceAnchor`. Existing rows open with `nil`. The first launch copies a stored `currentOdometerKm` into the anchor and does not add old trips.

## Kilometre reminders

A service or inspection interval can be months, years, kilometres, or whichever comes first. The first target (`nextDueOdometerKm`) can differ from the repeating interval (a scooter’s first service at 1 000 km, then every 4 000). Quick picks are 1 000, 4 000, 6 000, 10 000, and 15 000; the stepper runs from 500 to 50 000.

The “soon” window is 15% of the interval, clamped to 300...1 500 km. Whichever-first uses the more urgent of the date and the kilometres. With no odometer, only the date is used.

Pushes: one early, one at the target, one overdue, per target kilometre. They fire after a trip is saved or when the app becomes active. They do not fire while a trip is recording or paused. Marking the service done moves the target, so the next cycle can notify again.

## Notifications

Staged ladder (each stage at most once; no spam):

- Service / inspection / custom: 30 days → 1 week → due day → morning after due (single overdue)
- Insurance / casco: 1 week → due day → overdue (single)
- OS push + in-app inbox; tap (banner or inbox row) opens that vehicle’s care screen
- Overdue catch-up: if the due date already passed when the app opens, one notification (UserDefaults prevents repeats)
- Red in-app banner also surfaces urgent dues

---

## Performance

- Profile: draft + Save
- Due: `VehicleCareSummaryStore`
- Mini chart: 120 ms debounce; do not fault trip GPS points
- Glass / brand colors; no rainbow charts
