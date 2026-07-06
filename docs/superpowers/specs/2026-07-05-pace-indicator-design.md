# Pace vs. Time-Elapsed Indicator — Design

**Date:** 2026-07-05
**Status:** Approved

## Problem

The popover shows how much of the session/weekly limit is used, but not how far
into the window you are. 33% of the weekly limit used sounds fine — unless only
10% of the week has passed, in which case you're on track to run out. The user
wants to see usage pace relative to elapsed time, at a glance.

## Behavior

Every usage row (Session, Weekly, Weekly · Sonnet) gains:

1. **A tick on the meter bar** marking how much of the time window has elapsed.
   Fill past the tick = using faster than time is passing.
2. **A caption under the bar**, e.g. `26% of week elapsed · 1.3× pace`.
   The Session row says "of session"; weekly rows say "of week".

Window start is derived from data we already fetch: `resetsAt − windowLength`
(5 hours for session, 7 days for weekly and sonnet). No new API calls.

## Pace math — new Core file `app/Sources/Core/PaceCalculation.swift`

Pure, Foundation-only, testable (matches the other Core files):

```swift
struct PaceInfo: Equatable {
    var elapsedPercent: Int      // 0–100, clamped
    var paceRatio: Double?       // utilization ÷ exact elapsed fraction; nil near window start
}
func paceInfo(utilization: Int, resetsAt: Date?, window: TimeInterval, now: Date) -> PaceInfo?
```

- Returns `nil` when `resetsAt` is nil → the row renders exactly as today.
- Elapsed fraction = `(now − (resetsAt − window)) / window`, clamped to 0…1.
  A stale `resetsAt` in the past reads as 100% elapsed, never negative/overflow.
- `paceRatio` uses the exact (unrounded) elapsed fraction. It is `nil` when the
  elapsed fraction is below 1% of the window, so the ratio never spikes absurdly
  right after a reset.
- Display formatting: one decimal ("1.3×"), values ≥ 10 shown as "9.9×+".
- Pace severity mapping (in the same file), returning `Severity?`:
  ratio < 1.25 → nil (caption stays faint), 1.25 ≤ ratio < 2.0 → `.amber`,
  ratio ≥ 2.0 → `.red`. The UI feeds a non-nil result through the existing
  `SeverityStyle.textColor`.

## UI — `app/Sources/UI/PopoverView.swift`

- **Tick:** 2pt-wide rounded vertical notch overlaying the meter bar at the
  elapsed position, slightly taller than the 7pt bar (~11pt), colored
  `primaryText` at ~45% opacity so it reads over both fill and track in light
  and dark mode. Hidden when `paceInfo` is nil.
- **Caption:** 11.5pt text under the bar in `faintText`. The "N.N× pace"
  segment switches to the amber/red severity text color only when over pace
  (ratio ≥ 1.25); otherwise it stays faint. When `paceRatio` is nil the caption
  shows just the elapsed portion ("0% of week elapsed").
- **Freshness:** the app polls every 300s and does not refetch on popover open,
  so add `@State private var now = Date()` bumped in `.onAppear` — the popover's
  content view appears on each open, keeping the elapsed marker current.

## Testing — `tests/PaceCalculationTest.swift`

Wired into `tests/main.swift` like the other Core tests; `run-tests.sh`
compiles `Core/*.swift + tests/*.swift` so the new file slots in.

- Elapsed percent at known dates (mid-window weekly).
- Clamping: `resetsAt` in the past → 100%; window barely started → 0%.
- Ratio correctness: 35% used at ~26% elapsed ≈ 1.35×.
- Ratio suppression below 1% elapsed.
- `nil` passthrough when `resetsAt` is nil.
- Severity thresholds: 1.24 → neutral, 1.25 → amber, 2.0 → red.
- Display formatting: rounding, "9.9×+" cap.

## Out of scope

- Run-out projections ("limit runs out Thu ~9 PM").
- Any change to the big percentage color or menu-bar icon, which continue to
  track utilization alone.
- Notifications based on pace.
