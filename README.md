# ClaudeUsageBar

A macOS menu-bar app that shows live Claude API usage as severity-colored meters, plus Claude service status and threshold notifications.

**Personal fork / redesign — not distributed.**
Based on [Artzainnn/ClaudeUsageBar](https://github.com/Artzainnn/ClaudeUsageBar) (MIT), with a full UI redesign ("Variant A" dark / "Variant C" light, auto light/dark) and expanded functionality.

---

## What it shows

- **Session (5 h)** · **Weekly (7 d)** · **Weekly · Sonnet** usage meters with severity colors (green → amber → red at 70 / 90 %)
- **Claude service status** pulled from the status page (operational / minor / major / critical)
- **Threshold notifications** when usage crosses 25 / 50 / 75 / 90 %
- Menu-bar asterisk color reflects current session severity at a glance

---

## Requirements

- macOS 13 Ventura or later (arm64 / Apple Silicon)
- Swift Command Line Tools — no full Xcode install needed:
  ```
  xcode-select --install
  ```

---

## Build & run

```bash
bash app/build.sh
```

Builds `app/build/ClaudeUsageBar.app`, ad-hoc signs it, and opens it.

**First launch:** macOS may block an ad-hoc binary. Right-click the app → **Open** → **Open** to proceed past Gatekeeper.

Build without launching:

```bash
bash app/build.sh --no-open
```

---

## Tests

```bash
./run-tests.sh
```

Runs the Foundation-only Core unit tests (no simulator / Xcode required). Expected: `44/44 passed`.

---

## Getting the session cookie

The app reads usage data from the claude.ai usage API using your session cookie.

1. Open the app's **Settings** (click the menu-bar item → popover → Settings gear, or right-click the menu-bar item → **Settings…**).
2. In a browser, go to **claude.ai → Settings → Usage**.
3. Open DevTools (`⌥⌘I`) → **Network** tab → refresh the page.
4. Click the `usage` request in the list → **Headers** → copy the full **Cookie** request header value.
5. Paste it into the Settings **Cookie** field → **Save & Fetch**.

Usage is polled every 5 minutes automatically.

---

## Data & storage

Usage data is written to:

```
~/Library/Application Support/ClaudeUsageBar/usage-snapshot.json
```

This JSON file (`schemaVersion`, `session`, `weekly`, `weeklySonnet`, `statusIndicator`, `lastUpdated`) is the integration seam for a planned WidgetKit widget (Phase 2).

---

## Settings

- **Cookie** — claude.ai session cookie for the usage API
- **Notifications** — enable/disable threshold alerts (25 / 50 / 75 / 90 %)
- **Open at login** — launch on startup (best-effort under ad-hoc signing)
- **Services to track** — which Claude services contribute to the status indicator

---

## Roadmap

**Phase 2 — WidgetKit widget.** The `usage-snapshot.json` file above is designed as the data bridge. A widget reading that file requires full Xcode and an Apple ID for the shared App Group entitlement.

---

## Project layout

| Path | Contents |
|------|----------|
| `app/Sources/Core/` | Foundation-only business logic — parsers, models, services. Fully unit-tested. |
| `app/Sources/App/` | AppKit glue — `AppDelegate`, `UsageManager`, `StatusManager`, menu-bar icon. |
| `app/Sources/UI/` | SwiftUI views — `PopoverView`, `SettingsView`, `Theme`. |
| `reference/` | Original fork source + design handoff HTML. Not compiled. |
| `docs/superpowers/` | Specs, task briefs, and implementation plans. |

---

*Fork of [Artzainnn/ClaudeUsageBar](https://github.com/Artzainnn/ClaudeUsageBar) — MIT License.*
