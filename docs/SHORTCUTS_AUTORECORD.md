# Shortcuts auto-record

Milehound starts and stops trips through **Shortcuts Personal Automations**. Apple does not let a third-party app write those automations for you. The in-app wizard remembers the trigger and vehicle, shows the right Shortcuts steps, hands off with `ShortcutsLink`, tests that Milehound handles an external start, and offers a “not working” checklist.

## Where

Pairing tab → **Auto-start with Shortcuts**. The same sheet opens from onboarding (“Open setup guide”) and Settings. There is no fifth tab and no SwiftData “automation status” entity.

## Wizard (one glass card at a time)

1. Trigger — Bluetooth / CarPlay / Wi‑Fi (`UserDefaults.standard` `shortcuts.setup.trigger`). CarPlay copy notes wireless vs wired.
2. Vehicle — `@Query` of `VehicleProfile` (name + avatar only). Named Shortcut must include **Start trip** + **Vehicle** because automations often hide the picker.
3. Silent start — inverted `confirmExternalRecordingStart`. Location Always uses the existing banner.
4. Connect — all seven Shortcuts steps in one card, including Run Shortcut and Ask Before Running.
5. Disconnect — four steps; End trip; Ask Before Running off.
6. Handoff — `ShortcutsLink` + “I’ve finished Shortcuts setup”.
7. Test — same path as `StartTripRecordingIntent` (`ShortcutStartVehicleSelection.apply` + `RecordingControlBridge.requestStartFromControlSurface`). Proves Milehound handles the vehicle start. Does **not** prove the car automation fired. A successful test discards the session (`saveTrip: false`) so empty miles are not saved. Optional 10-minute watch is a stored `Date`, not a timer or GPS listener.
8. Checklist — checkable items in `UserDefaults.standard`. Pairing “Not working” opens this page.

## Storage

| What | Where |
|---|---|
| Trigger, wizard vehicle, checklist, watch, last test | `UserDefaults.standard` (`shortcuts.setup.*`) — widgets do not read these |
| Silent start, recording vehicle, guide completed | App Group (`AppSettings` / recording bridge) |

No schema bump. In-app Bluetooth `pairedRouteUID` stays cleared at launch.

## Performance

See `docs/PERFORMANCE.md` (Shortcuts guide wizard): one live `OnboardingHeroScene`, no stacked connect cards, nested frost tiles instead of extra glass hosts.
