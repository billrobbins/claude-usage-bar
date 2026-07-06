# Pace Indicator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show, on every usage row of the popover, how far into the limit window you are (tick on the meter bar) and how your usage pace compares to elapsed time (caption, e.g. `26% of week elapsed · 1.3× pace`).

**Architecture:** A new Foundation-only Core file computes elapsed-window fraction and pace ratio from `resetsAt` and the known window length (`resetsAt − window` = window start; no new API data). `PopoverView` renders a tick over the existing meter bar and a caption beneath it, coloring the pace figure with the existing `SeverityStyle` when over pace.

**Tech Stack:** Swift (swiftc CLI, no Xcode project), SwiftUI popover UI, homegrown `T` test harness compiled by `run-tests.sh`.

**Spec:** `docs/superpowers/specs/2026-07-05-pace-indicator-design.md`

## Global Constraints

- macOS 13 Ventura deployment target; build must stay **warning-free** (`bash app/build.sh --no-open`).
- `app/Sources/Core/` stays Foundation-only (no SwiftUI/AppKit imports) — `run-tests.sh` compiles `Core/*.swift + tests/*.swift` directly.
- Tests use the `T` harness (`T.ok` / `T.eq`), one `testXxx()` free function per file, registered in `tests/main.swift` above `T.finish()`.
- Commit messages: imperative sentence case, no prefix convention (match `git log`).
- Pace thresholds (exact values from spec): ratio suppressed below 0.01 elapsed fraction; neutral < 1.25, amber ≥ 1.25, red ≥ 2.0; display capped at "9.9×+" from 9.95 up.

---

### Task 1: Core pace math (`PaceCalculation.swift`)

**Files:**
- Create: `app/Sources/Core/PaceCalculation.swift`
- Create: `tests/PaceCalculationTest.swift`
- Modify: `tests/main.swift` (register test above `T.finish()`)

**Interfaces:**
- Consumes: `Severity` enum (`app/Sources/Core/Severity.swift`) — cases `.green/.amber/.red`; `T` harness (`tests/Harness.swift`).
- Produces (Task 2 relies on these exact signatures):
  - `enum UsageWindow { static let session: TimeInterval; static let weekly: TimeInterval }`
  - `struct PaceInfo: Equatable { var elapsedPercent: Int; var paceRatio: Double? }`
  - `func paceInfo(utilization: Int, resetsAt: Date?, window: TimeInterval, now: Date) -> PaceInfo?`
  - `func paceSeverity(_ ratio: Double?) -> Severity?`
  - `func formattedPace(_ ratio: Double) -> String`

- [ ] **Step 1: Write the failing test**

Create `tests/PaceCalculationTest.swift`:

```swift
import Foundation

func testPaceCalculation() {
    let now = Date(timeIntervalSince1970: 1_750_000_000)

    // No reset date → no pace info at all
    T.ok(paceInfo(utilization: 35, resetsAt: nil, window: UsageWindow.weekly, now: now) == nil,
         "nil resetsAt → nil")

    // Mid-window: reset is 74% of a week away → 26% elapsed
    let midResets = now.addingTimeInterval(UsageWindow.weekly * 0.74)
    let mid = paceInfo(utilization: 35, resetsAt: midResets, window: UsageWindow.weekly, now: now)
    T.eq(mid?.elapsedPercent, 26, "mid-window elapsed percent")
    T.ok(abs((mid?.paceRatio ?? 0) - 35.0 / 26.0) < 0.001, "mid-window ratio ≈ 1.35")

    // Stale reset date in the past → clamps to 100% elapsed, ratio = util/100
    let stale = paceInfo(utilization: 35, resetsAt: now.addingTimeInterval(-60),
                         window: UsageWindow.weekly, now: now)
    T.eq(stale?.elapsedPercent, 100, "past reset clamps to 100")
    T.ok(abs((stale?.paceRatio ?? 0) - 0.35) < 0.001, "past reset ratio 0.35")

    // Window barely started (0.4% elapsed) → percent 0, ratio suppressed
    let fresh = paceInfo(utilization: 3, resetsAt: now.addingTimeInterval(UsageWindow.weekly * 0.996),
                         window: UsageWindow.weekly, now: now)
    T.eq(fresh?.elapsedPercent, 0, "fresh window elapsed 0")
    T.ok(fresh?.paceRatio == nil, "fresh window ratio suppressed")

    // Session window: 2.5h into 5h at 40% used → 50% elapsed, 0.8× pace
    let sess = paceInfo(utilization: 40, resetsAt: now.addingTimeInterval(UsageWindow.session / 2),
                        window: UsageWindow.session, now: now)
    T.eq(sess?.elapsedPercent, 50, "session half elapsed")
    T.ok(abs((sess?.paceRatio ?? 0) - 0.8) < 0.001, "session ratio 0.8")

    // Severity thresholds
    T.ok(paceSeverity(nil) == nil, "nil ratio → no severity")
    T.ok(paceSeverity(1.24) == nil, "1.24 → neutral")
    T.eq(paceSeverity(1.25), .amber, "1.25 → amber")
    T.eq(paceSeverity(1.99), .amber, "1.99 → amber")
    T.eq(paceSeverity(2.0), .red, "2.0 → red")

    // Display formatting
    T.eq(formattedPace(35.0 / 26.0), "1.3×", "one decimal")
    T.eq(formattedPace(0.8), "0.8×", "under pace format")
    T.eq(formattedPace(9.94), "9.9×", "just under cap")
    T.eq(formattedPace(9.95), "9.9×+", "cap boundary")
    T.eq(formattedPace(47.0), "9.9×+", "way over cap")
}
```

Register it in `tests/main.swift` — add one line above `T.finish()`:

```swift
testPaceCalculation()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./run-tests.sh`
Expected: **compile error** — `cannot find 'paceInfo' in scope` (the harness compiles all files together, so a missing symbol fails at build, not at runtime).

- [ ] **Step 3: Write the implementation**

Create `app/Sources/Core/PaceCalculation.swift`:

```swift
import Foundation

enum UsageWindow {
    static let session: TimeInterval = 5 * 60 * 60
    static let weekly: TimeInterval = 7 * 24 * 60 * 60
}

struct PaceInfo: Equatable {
    var elapsedPercent: Int   // 0–100, clamped
    var paceRatio: Double?    // utilization% ÷ elapsed%; nil near window start
}

/// `resetsAt − window` is the window start; ratio > 1 means usage is ahead of the clock.
func paceInfo(utilization: Int, resetsAt: Date?, window: TimeInterval, now: Date) -> PaceInfo? {
    guard let resetsAt = resetsAt, window > 0 else { return nil }
    let start = resetsAt.addingTimeInterval(-window)
    let fraction = min(1.0, max(0.0, now.timeIntervalSince(start) / window))
    let ratio: Double? = fraction < 0.01 ? nil : Double(utilization) / (fraction * 100)
    return PaceInfo(elapsedPercent: Int((fraction * 100).rounded()), paceRatio: ratio)
}

func paceSeverity(_ ratio: Double?) -> Severity? {
    guard let ratio = ratio else { return nil }
    if ratio >= 2.0 { return .red }
    if ratio >= 1.25 { return .amber }
    return nil
}

func formattedPace(_ ratio: Double) -> String {
    ratio >= 9.95 ? "9.9×+" : String(format: "%.1f×", ratio)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./run-tests.sh`
Expected: `63/63 passed` (44 existing + 19 new), exit 0.

- [ ] **Step 5: Commit**

```bash
git add app/Sources/Core/PaceCalculation.swift tests/PaceCalculationTest.swift tests/main.swift
git commit -m "Add pace calculation: elapsed window fraction, pace ratio, severity, formatting"
```

---

### Task 2: Popover UI — tick on meter bar + pace caption

**Files:**
- Modify: `app/Sources/UI/PopoverView.swift` (state var ~line 10, `usageRows` ~lines 55–66, `usageRow` ~lines 68–104, `meterBar` ~lines 106–116, root VStack ~lines 15–30)

**Interfaces:**
- Consumes (from Task 1): `UsageWindow.session` / `UsageWindow.weekly` (`TimeInterval`), `paceInfo(utilization:resetsAt:window:now:) -> PaceInfo?`, `PaceInfo.elapsedPercent: Int`, `PaceInfo.paceRatio: Double?`, `paceSeverity(_: Double?) -> Severity?`, `formattedPace(_: Double) -> String`. Also existing `SeverityStyle.textColor(_:isDark:)` and `Palette`.
- Produces: UI only — nothing downstream.

- [ ] **Step 1: Add a `now` state var refreshed on popover open**

In `PopoverView`, next to the existing `@State` vars (~line 10):

```swift
@State private var now = Date()
```

On the root `VStack` (before `.frame(width: 300)`), add:

```swift
.onAppear { now = Date() }
```

(The popover's content view appears on every open; the app only polls every 300 s, so this keeps the elapsed tick current.)

- [ ] **Step 2: Pass window length and noun through `usageRows`**

Replace the `usageRows` body:

```swift
private var usageRows: some View {
    VStack(alignment: .leading, spacing: 0) {
        usageRow(title: "Session", pill: "5h", util: usage.sessionUtil,
                 resets: usage.sessionResetsAt, includeDate: false,
                 window: UsageWindow.session, noun: "session")
        usageRow(title: "Weekly", pill: "7d", util: usage.weeklyUtil,
                 resets: usage.weeklyResetsAt, includeDate: true,
                 window: UsageWindow.weekly, noun: "week", lastRow: !usage.hasSonnet)
        if usage.hasSonnet {
            usageRow(title: "Weekly · Sonnet", pill: nil, util: usage.sonnetUtil,
                     resets: usage.sonnetResetsAt, includeDate: true,
                     window: UsageWindow.weekly, noun: "week", lastRow: true)
        }
    }
}
```

- [ ] **Step 3: Compute pace in `usageRow`, nest bar + caption**

Replace `usageRow` with:

```swift
private func usageRow(title: String, pill: String?, util: Int,
                      resets: Date?, includeDate: Bool,
                      window: TimeInterval, noun: String,
                      lastRow: Bool = false) -> some View {
    let sev = Severity(utilization: util)
    let pace = paceInfo(utilization: util, resetsAt: resets, window: window, now: now)
    return VStack(alignment: .leading, spacing: 9) {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(p.primaryText)
                if let pill = pill {
                    Text(pill)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(p.secondaryText)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(RoundedRectangle(cornerRadius: 5).fill(p.pillBg))
                }
            }
            Spacer()
            if let resets = resets {
                Text("resets \(formattedReset(resets, includeDate: includeDate))")
                    .font(.system(size: 12.5))
                    .foregroundStyle(p.secondaryText)
            }
        }
        HStack(spacing: 12) {
            Text("\(util)%")
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(SeverityStyle.textColor(sev, isDark: p.isDark))
                .frame(minWidth: 54, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                meterBar(util: util, severity: sev,
                         tickFraction: pace.map { Double($0.elapsedPercent) / 100.0 })
                if let pace = pace {
                    paceCaption(pace, noun: noun)
                }
            }
        }
    }
    .padding(.horizontal, 16)
    .padding(.top, 6)
    .padding(.bottom, lastRow ? 14 : 10)
}
```

(The bar+caption live in a nested `VStack` so the caption's leading edge aligns with the bar, matching the approved mockup. When `pace` is nil — no reset date — the row renders exactly as before.)

- [ ] **Step 4: Add the tick to `meterBar` and the caption helper**

Replace `meterBar` with:

```swift
private func meterBar(util: Int, severity: Severity, tickFraction: Double?) -> some View {
    GeometryReader { geo in
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4).fill(p.trackBg)
            RoundedRectangle(cornerRadius: 4)
                .fill(SeverityStyle.barGradient(severity, isDark: p.isDark))
                .frame(width: max(0, min(1, Double(util) / 100.0)) * geo.size.width)
            if let tick = tickFraction {
                RoundedRectangle(cornerRadius: 1)
                    .fill(p.primaryText.opacity(0.45))
                    .frame(width: 2, height: 11)
                    .position(x: min(max(tick * geo.size.width, 1), geo.size.width - 1),
                              y: geo.size.height / 2)
            }
        }
    }
    .frame(height: 7)
}
```

Add below `meterBar`:

```swift
private func paceCaption(_ pace: PaceInfo, noun: String) -> some View {
    HStack(spacing: 0) {
        Text("\(pace.elapsedPercent)% of \(noun) elapsed")
            .foregroundStyle(p.faintText)
        if let ratio = pace.paceRatio {
            Text(" · ").foregroundStyle(p.faintText)
            Text("\(formattedPace(ratio)) pace")
                .foregroundStyle(paceSeverity(ratio)
                    .map { SeverityStyle.textColor($0, isDark: p.isDark) } ?? p.faintText)
        }
    }
    .font(.system(size: 11.5))
}
```

- [ ] **Step 5: Verify tests still pass and the app builds warning-free**

Run: `./run-tests.sh`
Expected: `63/63 passed` (UI files aren't compiled by the test runner, but confirm nothing regressed).

Run: `bash app/build.sh --no-open`
Expected: build succeeds with **no warnings**, produces `app/build/ClaudeUsageBar.app`.

- [ ] **Step 6: Visual check**

Run: `bash app/build.sh` (launches the app). Open the popover and confirm:
- Each row shows the tick and a caption like `26% of week elapsed · 1.3× pace`.
- Pace figure is faint gray under 1.25×, amber ≥ 1.25×, red ≥ 2×.
- Popover height grew to fit (hosting controller uses `.preferredContentSize`); nothing clipped in light or dark mode.

- [ ] **Step 7: Commit**

```bash
git add app/Sources/UI/PopoverView.swift
git commit -m "Show elapsed-time tick and pace caption on usage rows"
```

---

### Task 3: README + final verification

**Files:**
- Modify: `README.md` (feature list line 12–15 area; test count line 53)

**Interfaces:**
- Consumes: final behavior from Tasks 1–2. Produces: docs only.

- [ ] **Step 1: Update README**

In the **What it shows** list, add after the usage-meters bullet:

```markdown
- **Pace vs. time** — a tick on each meter marks how much of the window has elapsed, with a caption like `26% of week elapsed · 1.3× pace`; the pace figure turns amber at ≥ 1.25× and red at ≥ 2×
```

In the **Tests** section, change:

```markdown
Runs the Foundation-only Core unit tests (no simulator / Xcode required). Expected: `44/44 passed`.
```

to:

```markdown
Runs the Foundation-only Core unit tests (no simulator / Xcode required). Expected: `63/63 passed`.
```

- [ ] **Step 2: Full verification**

Run: `./run-tests.sh` → Expected: `63/63 passed`.
Run: `bash app/build.sh --no-open` → Expected: warning-free build.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Document pace indicator in README"
```
