# Claude Usage — Popover Redesign (Phase 1)

**Date:** 2026-06-26
**Status:** Approved design, pre-implementation
**Owner:** Bill (personal use — not distributed)

## Goal

Fork the open-source [`Artzainnn/ClaudeUsageBar`](https://github.com/Artzainnn/ClaudeUsageBar)
macOS menu-bar app and **replace its popover UI** with a new design (Claude Design
"Variant A — Refined dark", with a matching light variant). Keep all the working
data/auth/notification/status plumbing. Add a real Settings window. Structure the
data layer so a WidgetKit widget can be added later (Phase 2) without rework.

This is a **restyle + light refactor**, not a rewrite. Live usage data must keep
working day one.

## Background

### Data source (unchanged from original)
"Live usage" comes from the **claude.ai usage API**, authenticated with a session
cookie the user pastes in:

1. Org id is read from the `lastActiveOrg=` cookie value, or fetched from
   `https://claude.ai/api/bootstrap` (`account.lastActiveOrgId`).
2. Usage is fetched from `https://claude.ai/api/organizations/{orgId}/usage` with the
   full cookie string in the `Cookie` header (plus `Origin`/`Referer: https://claude.ai`,
   a desktop `User-Agent`, etc.).
3. Response JSON provides three limit objects, each with an integer `utilization`
   (0–100) and ISO-8601 `resets_at`:
   - `five_hour`  → **Session** (5h)
   - `seven_day`  → **Weekly** (7d)
   - `seven_day_sonnet` → **Weekly · Sonnet** (optional; present on some plans)
4. Service status comes from `https://status.claude.com/api/v2/summary.json`.

This maps 1:1 onto the new design's three usage rows. Polling cadence: every 5 minutes.

### Original app architecture
Single 1,880-line `ClaudeUsageBar.swift`, built directly with `swiftc` into a
universal `.app` bundle (no Xcode project). `LSUIElement` accessory app
(`NSApplication.setActivationPolicy(.accessory)`), `NSStatusItem` + `NSPopover`.
Reference copy kept at `reference/ClaudeUsageBar.original.swift`.

## Decisions (from brainstorming)

| Decision | Choice |
|---|---|
| Build approach | Fork & restyle the popover; keep data plumbing |
| Meter style | **Variant A** — horizontal bars (big % + severity bar) |
| Appearance | **Auto** — follow macOS light/dark (Variant A dark / Variant C light) |
| Settings / cookie UI | **Separate Settings window** (keep popover clean & fixed-size) |
| Widget | **Phase it** — popover now (swiftc/no-Xcode); design data layer widget-ready |
| ⌘U global hotkey | **Dropped** (+ Carbon import + Accessibility nag) |
| Update checker / banner | **Dropped** (polled the original author's releases) |
| "Buy Dev a Coffee" donate link | **Dropped**; replaced with an attribution credit to the original repo in Settings/About |

## Architecture

### Build & tooling
- Build with `swiftc` compiling multiple files (no Xcode project). Frameworks:
  `SwiftUI`, `AppKit`, `UserNotifications` (see Notifications risk below), and
  `WidgetKit` (for `WidgetCenter` reload — guarded by `#if canImport(WidgetKit)`).
  **Drop** `WebKit` and `Carbon`.
- **arm64-only** build (target Apple Silicon; this machine is arm64). No `lipo`.
- **Ad-hoc code signing** (`codesign --force --deep --sign -`). For personal local
  use this is fine; first launch may need right-click → Open past Gatekeeper.
- Stable bundle id (e.g. `com.bill.claudeusagebar`), `CFBundleName = "Claude Usage"`,
  `LSUIElement = true`, deployment target macOS 13.0.
- Output `app/build/ClaudeUsageBar.app`, then `open` it.

### File layout
Split the monolith into focused files compiled together (all under `app/Sources/`):

| File | Responsibility |
|---|---|
| `main.swift` | `@main`, `NSApplication` setup, `.accessory` policy |
| `AppDelegate.swift` | status item, popover wiring, 5-min timer, right-click menu (Refresh / Settings / Quit), settings-window controller |
| `MenuBarIcon.swift` | spark icon drawing + `updateStatusIcon(percentage:)` (green/amber/red by session %) |
| `UsageManager.swift` | fetch org id → fetch usage → parse → publish state → write snapshot; threshold notifications |
| `UsageSnapshot.swift` | `Codable` snapshot model + `SnapshotStore` (atomic JSON write + `WidgetCenter` reload) |
| `StatusManager.swift` | service-status fetch/parse, tracked-component filtering, status models |
| `Theme.swift` | adaptive color palettes (dark = Variant A, light = Variant C), severity colors, fonts |
| `PopoverView.swift` | SwiftUI popover content (header, 3 usage rows, status row, footer, empty state) |
| `SettingsView.swift` | SwiftUI settings content (cookie, notifications, open-at-login, status tracking, About) |

Reference files (original source, original build.sh/Info.plist, full design handoff)
live in `reference/` and are not compiled.

### Data flow
```
Timer(5m) / Refresh / Save-cookie
   └─> UsageManager.fetchUsage()
         ├─> publish @Published state  ──> PopoverView re-renders
         ├─> updateStatusIcon()         ──> menu-bar icon color + "NN%"
         ├─> checkNotificationThresholds() ──> 25/50/75/90% session alerts
         └─> SnapshotStore.write(UsageSnapshot)
                 ├─> ~/Library/Application Support/ClaudeUsageBar/usage-snapshot.json
                 └─> #if canImport(WidgetKit) WidgetCenter.shared.reloadAllTimelines()
```

## Components

### Menu-bar item (kept, ~as original)
- `NSStatusItem` (variable length): colored **spark** icon + ` NN%` title.
- Color by **session** %: `<70` green, `70–89` amber, `≥90` red.
- Left-click toggles popover. Right-click menu: **Refresh**, **Settings…**, separator, **Quit**.

### Popover (Variant A dark / Variant C light) — primary deliverable
Native `NSPopover`, `behavior = .transient`, `appearance = nil` (follows system).
Its built-in arrow + vibrancy material stand in for the mockup's hand-drawn notch +
blur — the idiomatic macOS reading of the design. Content laid out in SwiftUI over the
vibrancy; colors/spacing/type matched to the mockup. Fixed **300px** content width;
height fits content.

Palettes are taken verbatim from the design file
(`reference/design-handoff/project/Claude Usage Popover.dc.html`). SwiftUI selects the
set via `@Environment(\.colorScheme)`.

**Layout, top → bottom:**

1. **Header** (padding 14/16/10): spark icon (stroke `#e0855f` dark / `#c2613c` light,
   16pt, weight 2.2) + "Claude Usage" (600, 15.5pt, `#f5f5f7` / `#1d1d1f`,
   letter-spacing −0.2). Right: "live" (500, 11pt, **monospaced**, `rgba(235,235,245,.45)`
   / `rgba(60,60,67,.4)`).

2. **Usage rows** ×3 (Session, Weekly, Weekly · Sonnet), padding 6/16/10 (last row
   bottom 14). Sonnet row rendered only when `hasWeeklySonnet`.
   - Top line: **name** (600, 14.5pt, `#f5f5f7`/`#1d1d1f`) + **duration pill**
     (`5h` / `7d`; none on Sonnet — 600, 10.5pt monospaced, fg `…,.55`, bg
     `rgba(255,255,255,.10)` / `rgba(0,0,0,.07)`, pad 1.5/5, radius 5).
     Right: **reset time** (400, 12.5pt, `…,.55`).
   - Meter line (margin-top 9, gap 12): **% number** (700, 24pt, severity color,
     letter-spacing −0.5, min-width 54) beside **meter bar** (height 7, radius 4,
     track `rgba(255,255,255,.12)` / `rgba(0,0,0,.10)`, fill = severity gradient,
     width = utilization%).

3. **Divider** (0.5px, `rgba(255,255,255,.10)` / `rgba(0,0,0,.08)`, inset 16).

4. **Status row** (padding 12/16/10, gap 9): 8px dot (operational: green `#59d499`
   dark with glow `0 0 8px rgba(89,212,153,.6)` / `#28b463` light no glow; non-operational:
   status color) + title (500, 13pt) "All Claude services operational" (or the incident
   summary) + context line (400, 11.5pt, muted) e.g. "claude.ai · Code · Cowork —
   checked 3m ago". On an active tracked incident the row shows the summary and is
   tappable → opens `https://status.claude.com`.

5. **Divider.**

6. **Footer** (padding 10/14/12): "Updated H:MM AM/PM" (400, 12.5pt, muted) left;
   right = **↻ Refresh** pill (500, 12.5pt, `#7fb2ff` / `#2563d9`) + **Settings** pill
   (`#f5f5f7` / `#1d1d1f`); both pad 5/11, radius 7, bg `rgba(255,255,255,.07)` /
   `rgba(0,0,0,.05)`, hover bg `rgba(255,255,255,.14)` / `rgba(0,0,0,.10)`.
   Refresh → `fetchUsage()` + status fetch. Settings → opens the Settings window.

**Empty / no-cookie state:** when no cookie or no data yet, replace the usage rows
with a friendly prompt ("Set your session cookie to get started") + a button that
opens the Settings window to the cookie field. Header/status/footer still render.

**Severity colors:**

| Level | Threshold | Dark text / bar gradient | Light text / bar gradient |
|---|---|---|---|
| green | util `<70` | `#59d499` / `#3fae7a→#59d499` | `#1f9e63` / `#1f9e63→#35c07e` |
| amber | `70–89` | `#f0b25f` / `#e0995a→#f0b25f` | `#d1912f` / `#d1912f→#e6a942` |
| red | `≥90` | `#ff6b6b` / `#e0635a→#ff6b6b` | `#d23f3f` / `#c23a3a→#e05050` |

(Green/amber come straight from the mockup; red is added to honor the post-it's
green→amber→red intent and align with the menu-bar icon thresholds.)

**Reset-time formatting:** Session = time only ("resets 2:10 PM"); Weekly & Sonnet =
date + time ("resets Jun 26, 6 PM").

### Settings window (separate `NSWindow`)
Standard titled window ("Claude Usage Settings"), opened from the popover footer and
the right-click menu. SwiftUI content, sections:

- **Session cookie:** multiline paste field + **Save & Fetch** + **Clear**, the
  step-by-step tutorial (Settings → Usage on claude.ai → DevTools → Network → copy
  `Cookie` header) and a "View tutorial →" link.
- **Notifications:** usage-notifications toggle, status-notifications toggle, **Test
  Notification**.
- **General:** Open at login.
- **Status alerts:** checkbox list of tracked Claude services.
- **About:** version + attribution credit linking to the original
  `Artzainnn/ClaudeUsageBar` repo (MIT).

### Widget-ready data layer (no widget this phase)
- `UsageSnapshot: Codable` — three `LimitSnapshot { utilization, resetsAt, hasData }`
  (sonnet optional), plus `statusIndicator`, `statusSummary`, `lastUpdated`,
  `schemaVersion`.
- `SnapshotStore.write(_:)` — atomic JSON write to
  `~/Library/Application Support/ClaudeUsageBar/usage-snapshot.json`, then
  `#if canImport(WidgetKit) WidgetCenter.shared.reloadAllTimelines()` (harmless no-op
  until a widget exists). Phase 2 repoints this at an App Group container.

## Kept behaviors
Cookie persistence (UserDefaults `claude_session_cookie`) · 5-min usage+status polling
· threshold notifications at 25/50/75/90% session (with re-arm logic) · open-at-login ·
tracked-service selection for status alerts · right-click Quit.

## Out of scope (Phase 2 — widget)
WidgetKit extension, App Group entitlement, full-Xcode project + Apple ID signing,
multiple widget sizes. The snapshot JSON file is the integration seam; no popover/app
rework expected.

## Risks & assumptions
- **claude.ai usage API** shape is unchanged from the original (`five_hour`/`seven_day`/
  `seven_day_sonnet` with `utilization` + `resets_at`). If it has changed, parsing must
  be re-derived from a live response.
- **Notifications on macOS 26:** the original used the deprecated `NSUserNotification`
  (works without permission for unsigned apps). Prefer `UNUserNotificationCenter` with
  the ad-hoc-signed stable bundle id; if delivery fails during implementation, fall
  back to `NSUserNotification`. Verify by sending a Test Notification.
- **Gatekeeper:** ad-hoc-signed app may need right-click → Open on first launch.
- **Vibrancy fidelity:** native `NSPopover` chrome is used instead of a hand-drawn
  card/notch; content colors are matched but outer chrome is the system's.

## Verification plan
1. `app/build.sh` compiles with no errors; `ClaudeUsageBar.app` is produced and launches.
2. Menu-bar spark + % appears; color tracks session severity.
3. No cookie → popover shows the welcome/empty state with a working "open Settings" button.
4. With Bill's real cookie: popover shows correct Session/Weekly(/Sonnet) %s, severity
   colors, reset times, "Updated" time; status row reflects status.claude.com.
5. Toggle macOS appearance → popover switches between Variant A (dark) and C (light).
6. Settings window: Save & Fetch populates data; Clear resets; toggles persist across
   relaunch; Test Notification delivers.
7. `usage-snapshot.json` is written/updated after each fetch with correct values.
8. Visual check of the running popover against Variant A / C (screenshot the running app).
