# Claude Usage Popover Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fork `Artzainnn/ClaudeUsageBar` into a personal menu-bar app whose popover matches the Claude Design "Variant A" layout (auto light/dark), with a separate Settings window and a widget-ready snapshot file.

**Architecture:** A `swiftc`-built, ad-hoc-signed `LSUIElement` AppKit app. Pure, Foundation-only logic (parsing, formatting, severity, snapshot, status, thresholds) lives in `app/Sources/Core/` and is unit-tested with a tiny home-grown harness compiled by `swiftc`. AppKit/SwiftUI glue (managers, theme, menu-bar icon, popover, settings) lives in `app/Sources/App/` and `app/Sources/UI/` and is verified by building + running. After every fetch the app writes a `Codable UsageSnapshot` JSON file and calls `WidgetCenter` (the Phase-2 widget seam).

**Tech Stack:** Swift 6.3 (Command Line Tools, no Xcode), SwiftUI, AppKit, UserNotifications, WidgetKit (conditional), ServiceManagement. Built with `swiftc`, ad-hoc signed.

## Global Constraints

- **No Xcode project.** Build only with `swiftc` via `app/build.sh`. Frameworks: `SwiftUI`, `AppKit`, `UserNotifications`, `WidgetKit`, `ServiceManagement`. Do **not** link `WebKit` or `Carbon`.
- **Target:** `arm64-apple-macos13.0`. Ad-hoc sign: `codesign --force --deep --sign -`.
- **`Core/` files import only `Foundation`** (plus the standard library). No `import AppKit`/`SwiftUI` in `Core/` — they must compile in the Foundation-only test runner.
- **Bundle:** `CFBundleName = "Claude Usage"`, `CFBundleIdentifier = com.bill.claudeusagebar`, `LSUIElement = true`.
- **Data source (do not change):** org id from `lastActiveOrg=` cookie value or `https://claude.ai/api/bootstrap` (`account.lastActiveOrgId`); usage from `https://claude.ai/api/organizations/{orgId}/usage`; status from `https://status.claude.com/api/v2/summary.json`. Usage JSON keys: `five_hour`, `seven_day`, `seven_day_sonnet`, each `{ utilization: Number, resets_at: ISO8601 String }`.
- **Severity thresholds (everywhere — icon, meters):** `<70` green, `70–89` amber, `≥90` red.
- **Dropped from original:** ⌘U global hotkey + Carbon + Accessibility prompt; UpdateManager / update banner; "Buy Dev a Coffee" donate link.
- **Reference (not compiled):** original source at `reference/ClaudeUsageBar.original.swift`; design at `reference/design-handoff/project/Claude Usage Popover.dc.html`. Colors/spacing in the UI tasks are copied from that design file.
- **Commits:** end messages with the two trailers used in this repo's first commit (`Co-Authored-By:` and `Claude-Session:`).

---

## File Structure

```
app/
  Info.plist
  build.sh                      # compiles all of Sources/, ad-hoc signs, builds .app
  Sources/
    Core/                       # Foundation-only, unit-tested
      Severity.swift
      ResetFormatting.swift
      UsageParsing.swift
      UsageSnapshot.swift
      StatusModels.swift
      StatusParsing.swift
      StatusContext.swift
      NotificationThresholds.swift
    App/                        # AppKit glue
      main.swift                # @main + NSApplication
      AppDelegate.swift
      UsageManager.swift
      StatusManager.swift
      NotificationService.swift
      SnapshotPersistence.swift
    UI/                         # SwiftUI / AppKit views
      Theme.swift
      MenuBarIcon.swift
      PopoverView.swift
      SettingsView.swift
      PasteableTextField.swift
tests/
  Harness.swift
  main.swift
  <one *Test.swift per Core unit>
run-tests.sh                    # compiles app/Sources/Core/*.swift + tests/*.swift
```

---

## Task 1: Project scaffold — buildable empty menu-bar app + test harness

**Files:**
- Create: `app/Info.plist`, `app/build.sh`, `app/Sources/App/main.swift`, `app/Sources/App/AppDelegate.swift`
- Create: `tests/Harness.swift`, `tests/main.swift`, `run-tests.sh`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `enum T` test harness with `T.ok(_ cond: Bool, _ name: String)`, `T.eq<V: Equatable>(_ a: V, _ b: V, _ name: String)`, `T.finish() -> Never`.
- Produces: `app/build.sh [--no-open]` builds `app/build/ClaudeUsageBar.app`; `run-tests.sh` builds and runs `build/test_runner`.

- [ ] **Step 1: Write `app/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Claude Usage</string>
    <key>CFBundleDisplayName</key>     <string>Claude Usage</string>
    <key>CFBundleIdentifier</key>      <string>com.bill.claudeusagebar</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>CFBundleShortVersionString</key> <string>2.0</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>ClaudeUsageBar</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHumanReadableCopyright</key><string>Personal build. Based on the MIT-licensed ClaudeUsageBar by Artzainnn.</string>
</dict>
</plist>
```

- [ ] **Step 2: Write `app/build.sh`**

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"            # app/

APP_NAME="ClaudeUsageBar.app"
APP_PATH="build/$APP_NAME"

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp Info.plist "$APP_PATH/Contents/"
[ -f ClaudeUsageBar.icns ] && cp ClaudeUsageBar.icns "$APP_PATH/Contents/Resources/" || true

SOURCES=$(find Sources -name '*.swift')
swiftc -parse-as-library \
    -o "$APP_PATH/Contents/MacOS/ClaudeUsageBar" \
    $SOURCES \
    -framework SwiftUI -framework AppKit -framework UserNotifications \
    -framework WidgetKit -framework ServiceManagement \
    -target arm64-apple-macos13.0

echo -n "APPL????" > "$APP_PATH/Contents/PkgInfo"
chmod 755 "$APP_PATH/Contents/MacOS/ClaudeUsageBar"
xattr -cr "$APP_PATH"
find "$APP_PATH" -name '._*' -delete 2>/dev/null || true
codesign --force --deep --sign - "$APP_PATH"
echo "✅ Built $APP_PATH"

if [ "${1:-}" != "--no-open" ]; then open "$APP_PATH"; fi
```

Then `chmod +x app/build.sh`.

- [ ] **Step 3: Write `app/Sources/App/main.swift`**

```swift
import AppKit

@main
struct Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
```

- [ ] **Step 4: Write `app/Sources/App/AppDelegate.swift` (stub — status item only)**

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "asterisk", accessibilityDescription: "Claude Usage")
            button.title = " —%"
            button.target = self
            button.action = #selector(quit)
        }
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
```

- [ ] **Step 5: Write `tests/Harness.swift`**

```swift
import Foundation

enum T {
    static var failures = 0
    static var total = 0

    static func ok(_ cond: Bool, _ name: String, file: StaticString = #file, line: UInt = #line) {
        total += 1
        if cond {
            print("ok   - \(name)")
        } else {
            failures += 1
            print("FAIL - \(name)  (\(file):\(line))")
        }
    }

    static func eq<V: Equatable>(_ a: V, _ b: V, _ name: String, file: StaticString = #file, line: UInt = #line) {
        ok(a == b, "\(name)  [got \(a), want \(b)]", file: file, line: line)
    }

    static func finish() -> Never {
        print("\n\(total - failures)/\(total) passed")
        exit(failures == 0 ? 0 : 1)
    }
}
```

- [ ] **Step 6: Write `tests/main.swift`**

```swift
import Foundation

// Each Core task inserts its test call above this line.
T.finish()
```

- [ ] **Step 7: Write `run-tests.sh`**

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
# Core files are Foundation-only, but UsageSnapshot.swift references WidgetCenter
# behind #if canImport(WidgetKit), so link WidgetKit for the test runner too.
swiftc -o build/test_runner app/Sources/Core/*.swift tests/*.swift -framework WidgetKit
./build/test_runner
```

Then `chmod +x run-tests.sh`. Create `app/Sources/Core/.keep` so the directory exists. Until a real `Core/*.swift` file exists (Task 2), the `Core/*.swift` glob matches nothing — for the Task 1 harness check only, run `swiftc -o build/test_runner tests/*.swift && ./build/test_runner` directly.

- [ ] **Step 8: Update `.gitignore`**

Ensure it contains:
```
build/
app/build/
*.app
.DS_Store
```

- [ ] **Step 9: Build the app**

Run: `bash app/build.sh --no-open`
Expected: `✅ Built build/ClaudeUsageBar.app`, no compiler errors.

- [ ] **Step 10: Launch once to confirm the menu-bar item appears**

Run: `open app/build/ClaudeUsageBar.app`
Expected: an asterisk + ` —%` appears in the menu bar. (Clicking it quits — that's the stub.) Then quit it.

- [ ] **Step 11: Run the test harness**

Run: `./run-tests.sh`
Expected: prints `0/0 passed` and exits 0. (If the `Core/*.swift` glob errors because only `.keep` exists, temporarily compile with `tests/*.swift` only; it will gain Core files in Task 2.)

- [ ] **Step 12: Commit**

```bash
git add -A
git commit -m "Scaffold buildable menu-bar app + swiftc test harness

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QzZeB4uDJg9nJev5afUoU1"
```

---

## Task 2: Severity (Core, TDD)

**Files:**
- Create: `app/Sources/Core/Severity.swift`
- Create: `tests/SeverityTest.swift`
- Modify: `tests/main.swift`

**Interfaces:**
- Produces: `enum Severity { case green, amber, red; init(utilization: Int) }`

- [ ] **Step 1: Write the failing test — `tests/SeverityTest.swift`**

```swift
import Foundation

func testSeverity() {
    T.eq(Severity(utilization: 0),  .green, "0% is green")
    T.eq(Severity(utilization: 15), .green, "15% is green")
    T.eq(Severity(utilization: 69), .green, "69% is green")
    T.eq(Severity(utilization: 70), .amber, "70% is amber")
    T.eq(Severity(utilization: 89), .amber, "89% is amber")
    T.eq(Severity(utilization: 90), .red,   "90% is red")
    T.eq(Severity(utilization: 100), .red,  "100% is red")
}
```

- [ ] **Step 2: Wire the call into `tests/main.swift`**

Replace `T.finish()` with:
```swift
testSeverity()
T.finish()
```

- [ ] **Step 3: Run to verify it fails**

Run: `./run-tests.sh`
Expected: FAIL — `cannot find 'Severity' in scope`.

- [ ] **Step 4: Implement `app/Sources/Core/Severity.swift`**

```swift
import Foundation

enum Severity: Equatable {
    case green, amber, red

    init(utilization: Int) {
        switch utilization {
        case ..<70:   self = .green
        case 70..<90: self = .amber
        default:      self = .red
        }
    }
}
```

Delete `app/Sources/Core/.keep`.

- [ ] **Step 5: Run to verify it passes**

Run: `./run-tests.sh`
Expected: `7/7 passed`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add Severity with usage thresholds (Core, TDD)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QzZeB4uDJg9nJev5afUoU1"
```

---

## Task 3: Reset-time formatting (Core, TDD)

**Files:**
- Create: `app/Sources/Core/ResetFormatting.swift`
- Create: `tests/ResetFormattingTest.swift`
- Modify: `tests/main.swift`

**Interfaces:**
- Produces: `func formattedReset(_ date: Date, includeDate: Bool, locale: Locale, timeZone: TimeZone) -> String` — returns `"2:10 PM"` (time only) or `"Jun 26, 6:00 PM"` (with date). Default `locale = Locale(identifier: "en_US")`, `timeZone = .current`.

Note: the mockup shows "Jun 26, 6 PM" without minutes; we keep minutes for correctness since real reset times are not always on the hour.

- [ ] **Step 1: Write the failing test — `tests/ResetFormattingTest.swift`**

```swift
import Foundation

func testResetFormatting() {
    let tz = TimeZone(identifier: "America/New_York")!
    let loc = Locale(identifier: "en_US")
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let date = cal.date(from: DateComponents(year: 2026, month: 6, day: 26, hour: 14, minute: 10))!

    T.eq(formattedReset(date, includeDate: false, locale: loc, timeZone: tz),
         "2:10 PM", "time only")
    T.eq(formattedReset(date, includeDate: true, locale: loc, timeZone: tz),
         "Jun 26, 2:10 PM", "with date")
}
```

- [ ] **Step 2: Wire into `tests/main.swift`** — replace `T.finish()` with:
```swift
testResetFormatting()
T.finish()
```

- [ ] **Step 3: Run to verify it fails** — `./run-tests.sh` → FAIL `cannot find 'formattedReset'`.

- [ ] **Step 4: Implement `app/Sources/Core/ResetFormatting.swift`**

```swift
import Foundation

func formattedReset(_ date: Date,
                    includeDate: Bool,
                    locale: Locale = Locale(identifier: "en_US"),
                    timeZone: TimeZone = .current) -> String {
    let f = DateFormatter()
    f.locale = locale
    f.timeZone = timeZone
    f.dateFormat = includeDate ? "MMM d, h:mm a" : "h:mm a"
    return f.string(from: date)
}
```

- [ ] **Step 5: Run to verify it passes** — `./run-tests.sh` → `9/9 passed`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add reset-time formatting (Core, TDD)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QzZeB4uDJg9nJev5afUoU1"
```

---

## Task 4: Usage JSON parsing (Core, TDD)

**Files:**
- Create: `app/Sources/Core/UsageParsing.swift`
- Create: `tests/UsageParsingTest.swift`
- Modify: `tests/main.swift`

**Interfaces:**
- Produces: `struct ParsedLimit: Equatable { var utilization: Int; var resetsAt: Date? }`
- Produces: `struct ParsedUsage: Equatable { var session: ParsedLimit?; var weekly: ParsedLimit?; var sonnet: ParsedLimit? }`
- Produces: `func parseUsage(_ data: Data) throws -> ParsedUsage`; `enum UsageParseError: Error { case invalidJSON }`

- [ ] **Step 1: Write the failing test — `tests/UsageParsingTest.swift`**

```swift
import Foundation

func testUsageParsing() {
    let json = """
    {
      "five_hour":  { "utilization": 15.0, "resets_at": "2026-06-26T18:10:00.000000Z" },
      "seven_day":  { "utilization": 65,   "resets_at": "2026-06-26T22:00:00Z" },
      "seven_day_sonnet": { "utilization": 12.0, "resets_at": "2026-06-26T22:00:00Z" }
    }
    """.data(using: .utf8)!

    let u = try! parseUsage(json)
    T.eq(u.session?.utilization, 15, "session util")
    T.eq(u.weekly?.utilization, 65, "weekly util (int form)")
    T.eq(u.sonnet?.utilization, 12, "sonnet util")
    T.ok(u.session?.resetsAt != nil, "session reset parsed (fractional seconds)")
    T.ok(u.weekly?.resetsAt != nil, "weekly reset parsed (no fractional seconds)")

    let noSonnet = """
    { "five_hour": { "utilization": 5, "resets_at": "2026-06-26T18:10:00Z" },
      "seven_day": { "utilization": 5, "resets_at": "2026-06-26T22:00:00Z" } }
    """.data(using: .utf8)!
    let u2 = try! parseUsage(noSonnet)
    T.ok(u2.sonnet == nil, "no sonnet key -> nil")
}
```

- [ ] **Step 2: Wire into `tests/main.swift`** — replace `T.finish()` with:
```swift
testUsageParsing()
T.finish()
```

- [ ] **Step 3: Run to verify it fails** — `./run-tests.sh` → FAIL `cannot find 'parseUsage'`.

- [ ] **Step 4: Implement `app/Sources/Core/UsageParsing.swift`**

```swift
import Foundation

struct ParsedLimit: Equatable {
    var utilization: Int
    var resetsAt: Date?
}

struct ParsedUsage: Equatable {
    var session: ParsedLimit?
    var weekly: ParsedLimit?
    var sonnet: ParsedLimit?
}

enum UsageParseError: Error { case invalidJSON }

func parseUsage(_ data: Data) throws -> ParsedUsage {
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw UsageParseError.invalidJSON
    }

    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let isoNoFrac = ISO8601DateFormatter()
    isoNoFrac.formatOptions = [.withInternetDateTime]

    func limit(_ key: String) -> ParsedLimit? {
        guard let obj = json[key] as? [String: Any] else { return nil }
        let util: Int
        if let d = obj["utilization"] as? Double { util = Int(d) }
        else if let i = obj["utilization"] as? Int { util = i }
        else { util = 0 }
        let resets = (obj["resets_at"] as? String)
            .flatMap { iso.date(from: $0) ?? isoNoFrac.date(from: $0) }
        return ParsedLimit(utilization: util, resetsAt: resets)
    }

    return ParsedUsage(session: limit("five_hour"),
                       weekly: limit("seven_day"),
                       sonnet: limit("seven_day_sonnet"))
}
```

- [ ] **Step 5: Run to verify it passes** — `./run-tests.sh` → `15/15 passed`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add usage JSON parsing (Core, TDD)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QzZeB4uDJg9nJev5afUoU1"
```

---

## Task 5: UsageSnapshot + SnapshotStore (Core, TDD)

**Files:**
- Create: `app/Sources/Core/UsageSnapshot.swift`
- Create: `tests/UsageSnapshotTest.swift`
- Modify: `tests/main.swift`

**Interfaces:**
- Produces: `struct LimitSnapshot: Codable, Equatable { var utilization: Int; var resetsAt: Date?; var hasData: Bool }`
- Produces: `struct UsageSnapshot: Codable, Equatable { var schemaVersion: Int; var session: LimitSnapshot; var weekly: LimitSnapshot; var weeklySonnet: LimitSnapshot?; var statusIndicator: String; var statusSummary: String; var lastUpdated: Date }`
- Produces: `enum SnapshotStore` with `static var fileURL: URL`, `static func encode(_:) throws -> Data`, `static func decode(_:) throws -> UsageSnapshot`, `@discardableResult static func write(_:) throws -> URL`, `static func read() -> UsageSnapshot?`.

- [ ] **Step 1: Write the failing test — `tests/UsageSnapshotTest.swift`**

```swift
import Foundation

func testSnapshotRoundTrip() {
    // whole-second dates so .iso8601 round-trips exactly
    let reset = Date(timeIntervalSince1970: 1_790_000_000)
    let updated = Date(timeIntervalSince1970: 1_789_990_000)
    let snap = UsageSnapshot(
        schemaVersion: 1,
        session: LimitSnapshot(utilization: 15, resetsAt: reset, hasData: true),
        weekly: LimitSnapshot(utilization: 65, resetsAt: reset, hasData: true),
        weeklySonnet: LimitSnapshot(utilization: 12, resetsAt: reset, hasData: true),
        statusIndicator: "none",
        statusSummary: "All Claude services operational",
        lastUpdated: updated)

    let data = try! SnapshotStore.encode(snap)
    let back = try! SnapshotStore.decode(data)
    T.eq(back, snap, "snapshot encode/decode round-trips")

    let s = String(data: data, encoding: .utf8)!
    T.ok(s.contains("\"schemaVersion\""), "json has schemaVersion")
    T.ok(SnapshotStore.fileURL.path.hasSuffix("ClaudeUsageBar/usage-snapshot.json"),
         "file path is correct")
}
```

- [ ] **Step 2: Wire into `tests/main.swift`** — replace `T.finish()` with:
```swift
testSnapshotRoundTrip()
T.finish()
```

- [ ] **Step 3: Run to verify it fails** — `./run-tests.sh` → FAIL `cannot find 'UsageSnapshot'`.

- [ ] **Step 4: Implement `app/Sources/Core/UsageSnapshot.swift`**

```swift
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

struct LimitSnapshot: Codable, Equatable {
    var utilization: Int
    var resetsAt: Date?
    var hasData: Bool
}

struct UsageSnapshot: Codable, Equatable {
    var schemaVersion: Int = 1
    var session: LimitSnapshot
    var weekly: LimitSnapshot
    var weeklySonnet: LimitSnapshot?
    var statusIndicator: String
    var statusSummary: String
    var lastUpdated: Date
}

enum SnapshotStore {
    static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("ClaudeUsageBar", isDirectory: true)
    }
    static var fileURL: URL { directoryURL.appendingPathComponent("usage-snapshot.json") }

    static func encode(_ snapshot: UsageSnapshot) throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(snapshot)
    }

    static func decode(_ data: Data) throws -> UsageSnapshot {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode(UsageSnapshot.self, from: data)
    }

    @discardableResult
    static func write(_ snapshot: UsageSnapshot) throws -> URL {
        try FileManager.default.createDirectory(at: directoryURL,
                                                withIntermediateDirectories: true)
        try encode(snapshot).write(to: fileURL, options: .atomic)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        return fileURL
    }

    static func read() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decode(data)
    }
}
```

Note: `import WidgetKit` is guarded by `#if canImport(WidgetKit)` (true on macOS). `run-tests.sh` already links `-framework WidgetKit` (added in Task 1), so the test build resolves `WidgetCenter`.

- [ ] **Step 5: Run to verify it passes** — `./run-tests.sh` → `18/18 passed`. (`run-tests.sh` already links `-framework WidgetKit`.)

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add UsageSnapshot + SnapshotStore widget seam (Core, TDD)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QzZeB4uDJg9nJev5afUoU1"
```

---

## Task 6: Status models + parsing (Core, TDD)

**Files:**
- Create: `app/Sources/Core/StatusModels.swift`, `app/Sources/Core/StatusParsing.swift`
- Create: `tests/StatusParsingTest.swift`
- Modify: `tests/main.swift`

**Interfaces:**
- Produces: `struct StatusComponent: Identifiable, Equatable { let id, name, status: String }`
- Produces: `struct AffectedComponent: Identifiable, Equatable { let id, name, status: String }`
- Produces: `struct StatusIncident: Identifiable, Equatable { let id, name, status, latestUpdate: String; let updatedAt: Date?; let componentIds: [String] }`
- Produces: `struct ParsedStatus: Equatable { var indicator, description: String; var components: [StatusComponent]; var affected: [AffectedComponent]; var incidents: [StatusIncident] }`
- Produces: `func parseStatusSummary(_ data: Data) throws -> ParsedStatus`; `enum StatusParseError: Error { case invalidJSON }`

- [ ] **Step 1: Write the failing test — `tests/StatusParsingTest.swift`**

```swift
import Foundation

func testStatusParsing() {
    let json = """
    {
      "status": { "indicator": "minor", "description": "Partial Outage" },
      "components": [
        { "id": "c1", "name": "claude.ai", "status": "operational" },
        { "id": "c2", "name": "Claude Code", "status": "degraded_performance" }
      ],
      "incidents": [
        { "id": "i1", "name": "Elevated errors", "status": "investigating",
          "updated_at": "2026-06-26T12:00:00Z",
          "incident_updates": [ { "body": "We are looking into it.", "created_at": "2026-06-26T12:05:00Z" } ],
          "components": [ { "id": "c2" } ] },
        { "id": "i2", "name": "Old thing", "status": "resolved",
          "incident_updates": [] }
      ]
    }
    """.data(using: .utf8)!

    let s = try! parseStatusSummary(json)
    T.eq(s.indicator, "minor", "indicator")
    T.eq(s.description, "Partial Outage", "description")
    T.eq(s.components.count, 2, "two components")
    T.eq(s.affected.count, 1, "one affected (non-operational)")
    T.eq(s.affected.first?.id, "c2", "affected is c2")
    T.eq(s.incidents.count, 1, "resolved incident filtered out")
    T.eq(s.incidents.first?.latestUpdate, "We are looking into it.", "latest update body")
    T.eq(s.incidents.first?.componentIds, ["c2"], "incident component ids")
}
```

- [ ] **Step 2: Wire into `tests/main.swift`** — replace `T.finish()` with:
```swift
testStatusParsing()
T.finish()
```

- [ ] **Step 3: Run to verify it fails** — `./run-tests.sh` → FAIL `cannot find 'parseStatusSummary'`.

- [ ] **Step 4: Implement `app/Sources/Core/StatusModels.swift`**

```swift
import Foundation

struct StatusComponent: Identifiable, Equatable {
    let id: String
    let name: String
    let status: String      // operational | degraded_performance | partial_outage | major_outage | under_maintenance
}

struct AffectedComponent: Identifiable, Equatable {
    let id: String
    let name: String
    let status: String
}

struct StatusIncident: Identifiable, Equatable {
    let id: String
    let name: String
    let status: String      // investigating | identified | monitoring | resolved | postmortem
    let latestUpdate: String
    let updatedAt: Date?
    let componentIds: [String]
}

struct ParsedStatus: Equatable {
    var indicator: String   // none | minor | major | critical
    var description: String
    var components: [StatusComponent]
    var affected: [AffectedComponent]
    var incidents: [StatusIncident]
}
```

- [ ] **Step 5: Implement `app/Sources/Core/StatusParsing.swift`**

```swift
import Foundation

enum StatusParseError: Error { case invalidJSON }

func parseStatusSummary(_ data: Data) throws -> ParsedStatus {
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let status = json["status"] as? [String: Any],
          let indicator = status["indicator"] as? String,
          let desc = status["description"] as? String else {
        throw StatusParseError.invalidJSON
    }

    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let isoNoFrac = ISO8601DateFormatter()
    isoNoFrac.formatOptions = [.withInternetDateTime]

    var incidents: [StatusIncident] = []
    if let raw = json["incidents"] as? [[String: Any]] {
        for inc in raw {
            guard let id = inc["id"] as? String,
                  let name = inc["name"] as? String,
                  let st = inc["status"] as? String else { continue }
            if st == "resolved" || st == "postmortem" { continue }
            let updates = inc["incident_updates"] as? [[String: Any]] ?? []
            let latest = (updates.first?["body"] as? String) ?? ""
            let dateStr = (updates.first?["created_at"] as? String) ?? (inc["updated_at"] as? String)
            let updatedAt = dateStr.flatMap { iso.date(from: $0) ?? isoNoFrac.date(from: $0) }
            let compIds = (inc["components"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            incidents.append(StatusIncident(id: id, name: name, status: st,
                                            latestUpdate: latest, updatedAt: updatedAt,
                                            componentIds: compIds))
        }
    }

    var components: [StatusComponent] = []
    var affected: [AffectedComponent] = []
    if let raw = json["components"] as? [[String: Any]] {
        for c in raw {
            guard let id = c["id"] as? String,
                  let name = c["name"] as? String,
                  let st = c["status"] as? String else { continue }
            components.append(StatusComponent(id: id, name: name, status: st))
            if st != "operational" {
                affected.append(AffectedComponent(id: id, name: name, status: st))
            }
        }
    }

    return ParsedStatus(indicator: indicator, description: desc,
                        components: components, affected: affected, incidents: incidents)
}
```

- [ ] **Step 6: Run to verify it passes** — `./run-tests.sh` → `26/26 passed`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Add status models + summary parsing (Core, TDD)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QzZeB4uDJg9nJev5afUoU1"
```

---

## Task 7: Status context helpers (Core, TDD)

**Files:**
- Create: `app/Sources/Core/StatusContext.swift`
- Create: `tests/StatusContextTest.swift`
- Modify: `tests/main.swift`

**Interfaces:**
- Produces: `func relativeTime(from date: Date, now: Date) -> String`
- Produces: `func shortName(_ raw: String) -> String`
- Produces: `func effectiveIndicator(components: [StatusComponent], tracked: Set<String>) -> String`
- Produces: `func statusContextLine(components: [StatusComponent], affected: [AffectedComponent], tracked: Set<String>, lastChecked: Date?, now: Date) -> String`

- [ ] **Step 1: Write the failing test — `tests/StatusContextTest.swift`**

```swift
import Foundation

func testStatusContext() {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    T.eq(relativeTime(from: now.addingTimeInterval(-30), now: now), "just now", "30s -> just now")
    T.eq(relativeTime(from: now.addingTimeInterval(-180), now: now), "3 mins ago", "3m")
    T.eq(relativeTime(from: now.addingTimeInterval(-60), now: now), "1 min ago", "1m singular")
    T.eq(relativeTime(from: now.addingTimeInterval(-7200), now: now), "2 hours ago", "2h")

    T.eq(shortName("Claude API (api.anthropic.com)"), "Claude API", "strips parens")

    let comps = [
        StatusComponent(id: "a", name: "claude.ai", status: "operational"),
        StatusComponent(id: "b", name: "Claude Code", status: "degraded_performance"),
    ]
    T.eq(effectiveIndicator(components: comps, tracked: ["a"]), "none", "tracking only healthy -> none")
    T.eq(effectiveIndicator(components: comps, tracked: ["a", "b"]), "minor", "tracking degraded -> minor")

    let line = statusContextLine(components: comps, affected: [], tracked: ["a"],
                                 lastChecked: now.addingTimeInterval(-180), now: now)
    T.eq(line, "Tracks claude.ai · checked 3 mins ago", "operational context line")
}
```

- [ ] **Step 2: Wire into `tests/main.swift`** — replace `T.finish()` with:
```swift
testStatusContext()
T.finish()
```

- [ ] **Step 3: Run to verify it fails** — `./run-tests.sh` → FAIL `cannot find 'relativeTime'`.

- [ ] **Step 4: Implement `app/Sources/Core/StatusContext.swift`**

```swift
import Foundation

func relativeTime(from date: Date, now: Date) -> String {
    let elapsed = Int(now.timeIntervalSince(date))
    if elapsed < 60 { return "just now" }
    if elapsed < 3600 {
        let m = elapsed / 60
        return "\(m) min\(m == 1 ? "" : "s") ago"
    }
    if elapsed < 86_400 {
        let h = elapsed / 3600
        return "\(h) hour\(h == 1 ? "" : "s") ago"
    }
    let d = elapsed / 86_400
    return "\(d) day\(d == 1 ? "" : "s") ago"
}

func shortName(_ raw: String) -> String {
    if let paren = raw.range(of: " (") {
        return String(raw[..<paren.lowerBound])
    }
    return raw
}

private func severityRank(forComponentStatus s: String) -> Int {
    switch s {
    case "operational":          return 0
    case "under_maintenance":    return 1
    case "degraded_performance": return 1
    case "partial_outage":       return 2
    case "major_outage":         return 3
    default:                     return 0
    }
}

func effectiveIndicator(components: [StatusComponent], tracked: Set<String>) -> String {
    let tracked = components.filter { tracked.contains($0.id) }
    let max = tracked.map { severityRank(forComponentStatus: $0.status) }.max() ?? 0
    switch max {
    case 0:  return "none"
    case 1:  return "minor"
    case 2:  return "major"
    default: return "critical"
    }
}

func statusContextLine(components: [StatusComponent],
                       affected: [AffectedComponent],
                       tracked: Set<String>,
                       lastChecked: Date?,
                       now: Date) -> String {
    let trackedComps = components.filter { tracked.contains($0.id) }
    let names = trackedComps.prefix(4).map { shortName($0.name) }.joined(separator: ", ")
    let extra = trackedComps.count > 4 ? " +\(trackedComps.count - 4)" : ""
    let summary = trackedComps.isEmpty ? "No services tracked" : "Tracks \(names)\(extra)"

    if effectiveIndicator(components: components, tracked: tracked) == "none" {
        if let last = lastChecked {
            return "\(summary) · checked \(relativeTime(from: last, now: now))"
        }
        return summary
    }

    let filteredAffected = affected.filter { tracked.contains($0.id) }
    if !filteredAffected.isEmpty {
        let a = filteredAffected.prefix(3).map { shortName($0.name) }.joined(separator: ", ")
        let more = filteredAffected.count > 3 ? " +\(filteredAffected.count - 3)" : ""
        return "Affects: \(a)\(more)"
    }
    if let last = lastChecked {
        return "Checked \(relativeTime(from: last, now: now))"
    }
    return ""
}
```

- [ ] **Step 5: Run to verify it passes** — `./run-tests.sh` → `36/36 passed`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add status context helpers (Core, TDD)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QzZeB4uDJg9nJev5afUoU1"
```

---

## Task 8: Notification thresholds (Core, TDD)

**Files:**
- Create: `app/Sources/Core/NotificationThresholds.swift`
- Create: `tests/NotificationThresholdsTest.swift`
- Modify: `tests/main.swift`

**Interfaces:**
- Produces: `func thresholdUpdate(percentage: Int, lastNotified: Int, thresholds: [Int]) -> (toFire: [Int], newLastNotified: Int)` — default `thresholds = [25, 50, 75, 90]`.

- [ ] **Step 1: Write the failing test — `tests/NotificationThresholdsTest.swift`**

```swift
import Foundation

func testNotificationThresholds() {
    let a = thresholdUpdate(percentage: 80, lastNotified: 0)
    T.eq(a.toFire, [25, 50, 75], "80% from 0 fires 25/50/75")
    T.eq(a.newLastNotified, 75, "new last = 75")

    let b = thresholdUpdate(percentage: 95, lastNotified: 0)
    T.eq(b.toFire, [25, 50, 75, 90], "95% fires all")
    T.eq(b.newLastNotified, 90, "new last = 90")

    let c = thresholdUpdate(percentage: 80, lastNotified: 75)
    T.eq(c.toFire, [], "no re-fire when already at 75")
    T.eq(c.newLastNotified, 75, "stays 75")

    let d = thresholdUpdate(percentage: 30, lastNotified: 75)
    T.eq(d.toFire, [], "drop to 30 fires nothing")
    T.eq(d.newLastNotified, 25, "re-arms down to 25")

    let e = thresholdUpdate(percentage: 10, lastNotified: 0)
    T.eq(e.toFire, [], "10% fires nothing")
    T.eq(e.newLastNotified, 0, "stays 0")
}
```

- [ ] **Step 2: Wire into `tests/main.swift`** — replace `T.finish()` with:
```swift
testNotificationThresholds()
T.finish()
```

- [ ] **Step 3: Run to verify it fails** — `./run-tests.sh` → FAIL `cannot find 'thresholdUpdate'`.

- [ ] **Step 4: Implement `app/Sources/Core/NotificationThresholds.swift`**

```swift
import Foundation

func thresholdUpdate(percentage: Int,
                     lastNotified: Int,
                     thresholds: [Int] = [25, 50, 75, 90]) -> (toFire: [Int], newLastNotified: Int) {
    var toFire: [Int] = []
    var last = lastNotified
    for t in thresholds where percentage >= t && last < t {
        toFire.append(t)
        last = t
    }
    if percentage < last {
        last = thresholds.filter { $0 <= percentage }.last ?? 0
    }
    return (toFire, last)
}
```

- [ ] **Step 5: Run to verify it passes** — `./run-tests.sh` → `46/46 passed`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add notification threshold logic (Core, TDD)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QzZeB4uDJg9nJev5afUoU1"
```

---

## Task 9: NotificationService + UsageManager (App)

**Files:**
- Create: `app/Sources/App/NotificationService.swift`, `app/Sources/App/UsageManager.swift`
- Modify: `app/Sources/App/AppDelegate.swift` (instantiate UsageManager; no UI yet)

**Interfaces:**
- Consumes: `parseUsage`, `ParsedUsage`, `Severity`, `thresholdUpdate`.
- Produces: `enum NotificationService { static func requestAuthorization(); static func send(title: String, body: String) }`
- Produces: `final class UsageManager: ObservableObject` with published `sessionUtil: Int`, `weeklyUtil: Int`, `sonnetUtil: Int`, `hasSonnet: Bool`, `sessionResetsAt/weeklyResetsAt/sonnetResetsAt: Date?`, `hasFetchedData: Bool`, `lastUpdated: Date`, `errorMessage: String?`, `isLoading: Bool`; methods `loadCookie()`, `saveCookie(_:)`, `clearCookie()`, `fetchUsage()`; `var onUpdate: (() -> Void)?`; `weak var iconDelegate: MenuBarIconUpdating?`.
- Produces: `protocol MenuBarIconUpdating: AnyObject { func updateStatusIcon(sessionPercent: Int) }`

- [ ] **Step 1: Implement `app/Sources/App/NotificationService.swift`**

```swift
import Foundation
import UserNotifications

enum NotificationService {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
```

- [ ] **Step 2: Implement `app/Sources/App/UsageManager.swift`**

```swift
import Foundation
import Combine

protocol MenuBarIconUpdating: AnyObject {
    func updateStatusIcon(sessionPercent: Int)
}

final class UsageManager: ObservableObject {
    @Published var sessionUtil = 0
    @Published var weeklyUtil = 0
    @Published var sonnetUtil = 0
    @Published var hasSonnet = false
    @Published var sessionResetsAt: Date?
    @Published var weeklyResetsAt: Date?
    @Published var sonnetResetsAt: Date?
    @Published var hasFetchedData = false
    @Published var lastUpdated = Date()
    @Published var errorMessage: String?
    @Published var isLoading = false

    weak var iconDelegate: MenuBarIconUpdating?
    var onUpdate: (() -> Void)?

    private var cookie = ""
    private var lastNotifiedThreshold = 0
    private let usageNotificationsKey = "usage_notifications_enabled"

    init() { loadCookie(); lastNotifiedThreshold = UserDefaults.standard.integer(forKey: "last_notified_threshold") }

    var hasCookie: Bool { !cookie.isEmpty }

    func loadCookie() {
        cookie = UserDefaults.standard.string(forKey: "claude_session_cookie") ?? ""
    }

    func saveCookie(_ value: String) {
        cookie = value.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(cookie, forKey: "claude_session_cookie")
    }

    func clearCookie() {
        cookie = ""
        UserDefaults.standard.removeObject(forKey: "claude_session_cookie")
        sessionUtil = 0; weeklyUtil = 0; sonnetUtil = 0
        hasSonnet = false; hasFetchedData = false; errorMessage = nil
        sessionResetsAt = nil; weeklyResetsAt = nil; sonnetResetsAt = nil
        lastNotifiedThreshold = 0
        UserDefaults.standard.set(0, forKey: "last_notified_threshold")
        iconDelegate?.updateStatusIcon(sessionPercent: 0)
        onUpdate?()
    }

    // MARK: - Fetch

    func fetchUsage() {
        guard !cookie.isEmpty else {
            DispatchQueue.main.async { self.errorMessage = "Session cookie not set" }
            return
        }
        isLoading = true
        errorMessage = nil
        resolveOrgId { [weak self] orgId in
            guard let self = self, let orgId = orgId else {
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.errorMessage = "Could not get org id from cookie"
                }
                return
            }
            self.fetchUsage(orgId: orgId)
        }
    }

    private func resolveOrgId(_ completion: @escaping (String?) -> Void) {
        for part in cookie.components(separatedBy: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("lastActiveOrg=") {
                completion(String(trimmed.dropFirst("lastActiveOrg=".count)))
                return
            }
        }
        guard let url = URL(string: "https://claude.ai/api/bootstrap") else { completion(nil); return }
        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(cookie)", forHTTPHeaderField: "Cookie")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let account = json["account"] as? [String: Any],
                  let orgId = account["lastActiveOrgId"] as? String else { completion(nil); return }
            completion(orgId)
        }.resume()
    }

    private func fetchUsage(orgId: String) {
        guard let url = URL(string: "https://claude.ai/api/organizations/\(orgId)/usage") else { return }
        var request = URLRequest(url: url)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                         forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                if error != nil { self.errorMessage = "Network error"; return }
                guard let http = response as? HTTPURLResponse else { self.errorMessage = "Invalid response"; return }
                guard http.statusCode == 200, let data = data else {
                    self.errorMessage = "HTTP \(http.statusCode)"; return
                }
                self.apply(data)
            }
        }.resume()
    }

    private func apply(_ data: Data) {
        guard let parsed = try? parseUsage(data) else { errorMessage = "Parse error"; return }
        if let s = parsed.session { sessionUtil = s.utilization; sessionResetsAt = s.resetsAt }
        if let w = parsed.weekly { weeklyUtil = w.utilization; weeklyResetsAt = w.resetsAt }
        if let so = parsed.sonnet { hasSonnet = true; sonnetUtil = so.utilization; sonnetResetsAt = so.resetsAt }
        else { hasSonnet = false }
        lastUpdated = Date()
        hasFetchedData = true
        errorMessage = nil
        iconDelegate?.updateStatusIcon(sessionPercent: sessionUtil)
        fireThresholdNotifications()
        onUpdate?()
    }

    private func fireThresholdNotifications() {
        guard UserDefaults.standard.object(forKey: usageNotificationsKey) == nil
                || UserDefaults.standard.bool(forKey: usageNotificationsKey) else { return }
        let result = thresholdUpdate(percentage: sessionUtil, lastNotified: lastNotifiedThreshold)
        for t in result.toFire {
            NotificationService.send(title: "Claude Usage Alert",
                                     body: "You've reached \(sessionUtil)% of your 5-hour session limit")
            _ = t
        }
        lastNotifiedThreshold = result.newLastNotified
        UserDefaults.standard.set(lastNotifiedThreshold, forKey: "last_notified_threshold")
    }
}
```

- [ ] **Step 3: Update `app/Sources/App/AppDelegate.swift` to instantiate it**

Replace the file body with:
```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    let usageManager = UsageManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "asterisk", accessibilityDescription: "Claude Usage")
            button.title = " —%"
            button.target = self
            button.action = #selector(quit)
        }
        NotificationService.requestAuthorization()
        usageManager.fetchUsage()
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
```

- [ ] **Step 4: Build**

Run: `bash app/build.sh --no-open`
Expected: compiles cleanly. (Logic is still covered by `./run-tests.sh` — re-run it; still `46/46 passed`.)

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add UsageManager + NotificationService (App)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QzZeB4uDJg9nJev5afUoU1"
```

---

## Task 10: StatusManager (App)

**Files:**
- Create: `app/Sources/App/StatusManager.swift`
- Modify: `app/Sources/App/AppDelegate.swift` (instantiate + fetch)

**Interfaces:**
- Consumes: `parseStatusSummary`, `ParsedStatus`, `StatusComponent`, `AffectedComponent`, `StatusIncident`, `effectiveIndicator`, `statusContextLine`, `relativeTime`, `NotificationService`.
- Produces: `final class StatusManager: ObservableObject` with published `indicator`, `statusDescription`, `incidents`, `affected: [AffectedComponent]`, `allComponents: [StatusComponent]`, `selectedComponentIds: Set<String>`, `lastUpdated: Date?`, `hasFetched: Bool`; computed `effective: String`, `contextLine(now:) -> String`; methods `fetch()`, `toggleComponent(_:)`, `isTracked(_:) -> Bool`; `var onUpdate: (() -> Void)?`.

- [ ] **Step 1: Implement `app/Sources/App/StatusManager.swift`**

```swift
import Foundation
import Combine

private let defaultTrackedComponents: [StatusComponent] = [
    StatusComponent(id: "c-claude-ai",      name: "claude.ai",                            status: "operational"),
    StatusComponent(id: "c-claude-console", name: "Claude Console (platform.claude.com)", status: "operational"),
    StatusComponent(id: "c-claude-api",     name: "Claude API (api.anthropic.com)",       status: "operational"),
    StatusComponent(id: "c-claude-code",    name: "Claude Code",                          status: "operational"),
    StatusComponent(id: "c-claude-cowork",  name: "Claude Cowork",                        status: "operational"),
    StatusComponent(id: "c-claude-gov",     name: "Claude for Government",                status: "operational"),
]

final class StatusManager: ObservableObject {
    @Published var indicator = "none"
    @Published var statusDescription = "All systems operational"
    @Published var incidents: [StatusIncident] = []
    @Published var affected: [AffectedComponent] = []
    @Published var allComponents: [StatusComponent] = defaultTrackedComponents
    @Published var selectedComponentIds: Set<String> =
        Set(defaultTrackedComponents.map { $0.id }.filter { $0 != "c-claude-gov" })
    @Published var lastUpdated: Date?
    @Published var hasFetched = false

    var onUpdate: (() -> Void)?
    private let endpoint = URL(string: "https://status.claude.com/api/v2/summary.json")!

    init() {
        if let saved = UserDefaults.standard.array(forKey: "tracked_component_ids") as? [String] {
            selectedComponentIds = Set(saved)
        }
    }

    var effective: String { effectiveIndicator(components: allComponents, tracked: selectedComponentIds) }

    func contextLine(now: Date) -> String {
        statusContextLine(components: allComponents, affected: affected,
                          tracked: selectedComponentIds, lastChecked: lastUpdated, now: now)
    }

    func isTracked(_ id: String) -> Bool { selectedComponentIds.contains(id) }

    func toggleComponent(_ id: String) {
        if selectedComponentIds.contains(id) { selectedComponentIds.remove(id) }
        else { selectedComponentIds.insert(id) }
        UserDefaults.standard.set(Array(selectedComponentIds), forKey: "tracked_component_ids")
    }

    func fetch() {
        let request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self, let data = data, let parsed = try? parseStatusSummary(data) else { return }
            DispatchQueue.main.async { self.apply(parsed) }
        }.resume()
    }

    private func apply(_ parsed: ParsedStatus) {
        let wasFirst = !hasFetched
        let previousEffective = UserDefaults.standard.string(forKey: "last_effective_indicator")

        indicator = parsed.indicator
        statusDescription = parsed.description
        incidents = parsed.incidents
        affected = parsed.affected
        if !parsed.components.isEmpty {
            allComponents = parsed.components
            if UserDefaults.standard.array(forKey: "tracked_component_ids") == nil {
                let defaults = parsed.components
                    .filter { !$0.name.localizedCaseInsensitiveContains("Government") }
                    .map { $0.id }
                selectedComponentIds = Set(defaults)
                UserDefaults.standard.set(Array(selectedComponentIds), forKey: "tracked_component_ids")
            }
        }
        lastUpdated = Date()
        hasFetched = true

        let eff = effective
        if !wasFirst, let prev = previousEffective, prev != eff,
           UserDefaults.standard.bool(forKey: "status_notifications_enabled") {
            if eff == "none" {
                NotificationService.send(title: "Claude is back online", body: "All systems operational")
            } else {
                NotificationService.send(title: "Claude status: \(parsed.description)",
                                         body: "Visit status.claude.com for details")
            }
        }
        UserDefaults.standard.set(eff, forKey: "last_effective_indicator")
        onUpdate?()
    }
}
```

- [ ] **Step 2: Update `AppDelegate.swift`** — add the manager and fetch it. Add property and calls:

Add after `let usageManager = UsageManager()`:
```swift
    let statusManager = StatusManager()
```
Add after `usageManager.fetchUsage()` in `applicationDidFinishLaunching`:
```swift
        statusManager.fetch()
```

- [ ] **Step 3: Build** — `bash app/build.sh --no-open` → compiles cleanly. `./run-tests.sh` → still `46/46 passed`.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Add StatusManager (App)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QzZeB4uDJg9nJev5afUoU1"
```

---

## Task 11: Theme (UI)

**Files:**
- Create: `app/Sources/UI/Theme.swift`

**Interfaces:**
- Produces: `extension Color { init(hex: String, alpha: Double) }`
- Produces: `struct Palette { let isDark: Bool; ... color vars ...; static func current(_ scheme: ColorScheme) -> Palette }`
- Produces: `enum SeverityStyle { static func textColor(_ s: Severity, isDark: Bool) -> Color; static func barGradient(_ s: Severity, isDark: Bool) -> LinearGradient }`

- [ ] **Step 1: Implement `app/Sources/UI/Theme.swift`** (hex values copied from the design file)

```swift
import SwiftUI

extension Color {
    init(hex: String, alpha: Double = 1.0) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        self = Color(.sRGB,
                     red: Double((v >> 16) & 0xff) / 255.0,
                     green: Double((v >> 8) & 0xff) / 255.0,
                     blue: Double(v & 0xff) / 255.0,
                     opacity: alpha)
    }
}

struct Palette {
    let isDark: Bool

    var primaryText: Color   { isDark ? Color(hex: "f5f5f7") : Color(hex: "1d1d1f") }
    var secondaryText: Color { isDark ? Color(hex: "ebebf5", alpha: 0.55) : Color(hex: "3c3c43", alpha: 0.55) }
    var faintText: Color     { isDark ? Color(hex: "ebebf5", alpha: 0.50) : Color(hex: "3c3c43", alpha: 0.50) }
    var liveText: Color      { isDark ? Color(hex: "ebebf5", alpha: 0.45) : Color(hex: "3c3c43", alpha: 0.40) }

    var sparkStroke: Color   { isDark ? Color(hex: "e0855f") : Color(hex: "c2613c") }
    var refreshAccent: Color { isDark ? Color(hex: "7fb2ff") : Color(hex: "2563d9") }

    var pillBg: Color        { isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.07) }
    var trackBg: Color       { isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.10) }
    var dividerColor: Color  { isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08) }
    var footerPillBg: Color  { isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.05) }
    var footerPillHover: Color { isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.10) }

    var operationalDot: Color { isDark ? Color(hex: "59d499") : Color(hex: "28b463") }

    static func current(_ scheme: ColorScheme) -> Palette { Palette(isDark: scheme == .dark) }
}

enum SeverityStyle {
    static func textColor(_ s: Severity, isDark: Bool) -> Color {
        switch s {
        case .green: return isDark ? Color(hex: "59d499") : Color(hex: "1f9e63")
        case .amber: return isDark ? Color(hex: "f0b25f") : Color(hex: "d1912f")
        case .red:   return isDark ? Color(hex: "ff6b6b") : Color(hex: "d23f3f")
        }
    }

    static func barGradient(_ s: Severity, isDark: Bool) -> LinearGradient {
        let colors: [Color]
        switch s {
        case .green: colors = isDark ? [Color(hex: "3fae7a"), Color(hex: "59d499")] : [Color(hex: "1f9e63"), Color(hex: "35c07e")]
        case .amber: colors = isDark ? [Color(hex: "e0995a"), Color(hex: "f0b25f")] : [Color(hex: "d1912f"), Color(hex: "e6a942")]
        case .red:   colors = isDark ? [Color(hex: "e0635a"), Color(hex: "ff6b6b")] : [Color(hex: "c23a3a"), Color(hex: "e05050")]
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }
}
```

- [ ] **Step 2: Build** — `bash app/build.sh --no-open` → compiles cleanly.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "Add Theme palette + severity colors (UI)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QzZeB4uDJg9nJev5afUoU1"
```

---

## Task 12: Menu-bar icon (UI/App)

**Files:**
- Create: `app/Sources/UI/MenuBarIcon.swift`
- Modify: `app/Sources/App/AppDelegate.swift` (conform to `MenuBarIconUpdating`)

**Interfaces:**
- Consumes: `Severity`, `MenuBarIconUpdating`.
- Produces: `func sparkStatusImage(forSeverity s: Severity) -> NSImage` (colored asterisk SF Symbol).
- Produces: `AppDelegate.updateStatusIcon(sessionPercent:)` sets the icon color + `" NN%"` title.

- [ ] **Step 1: Implement `app/Sources/UI/MenuBarIcon.swift`**

```swift
import AppKit

func severityNSColor(_ s: Severity) -> NSColor {
    switch s {
    case .green: return NSColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 1.0)
    case .amber: return NSColor(red: 1.00, green: 0.70, blue: 0.20, alpha: 1.0)
    case .red:   return NSColor(red: 1.00, green: 0.23, blue: 0.19, alpha: 1.0)
    }
}

func sparkStatusImage(forSeverity s: Severity) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [severityNSColor(s)]))
    let base = NSImage(systemSymbolName: "asterisk", accessibilityDescription: "Claude Usage")!
    let image = base.withSymbolConfiguration(config) ?? base
    image.isTemplate = false
    return image
}
```

- [ ] **Step 2: Make `AppDelegate` conform to `MenuBarIconUpdating`**

In `AppDelegate.swift`, change the class declaration to:
```swift
final class AppDelegate: NSObject, NSApplicationDelegate, MenuBarIconUpdating {
```
Add this method:
```swift
    func updateStatusIcon(sessionPercent: Int) {
        guard let button = statusItem?.button else { return }
        button.image = sparkStatusImage(forSeverity: Severity(utilization: sessionPercent))
        button.title = " \(sessionPercent)%"
    }
```
In `applicationDidFinishLaunching`, after creating the status item button, set the delegate and a starting icon:
```swift
        usageManager.iconDelegate = self
        updateStatusIcon(sessionPercent: 0)
```
(Remove the temporary `button.image = NSImage(systemSymbolName: "asterisk", ...)` and `button.title = " —%"` lines — `updateStatusIcon` now sets both.)

- [ ] **Step 3: Build + launch** — `bash app/build.sh` → menu bar shows a green asterisk + ` 0%`. Quit it.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Add colored menu-bar asterisk icon (UI/App)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QzZeB4uDJg9nJev5afUoU1"
```

---

## Task 13: PopoverView (UI)

**Files:**
- Create: `app/Sources/UI/PopoverView.swift`

**Interfaces:**
- Consumes: `UsageManager`, `StatusManager`, `Palette`, `SeverityStyle`, `Severity`, `formattedReset`.
- Produces: `struct PopoverView: View` with init `(usage: UsageManager, status: StatusManager, onRefresh: @escaping () -> Void, onOpenSettings: @escaping () -> Void)`. Fixed 300pt content width.

Design values are from `reference/design-handoff/project/Claude Usage Popover.dc.html` (Variant A dark / Variant C light).

- [ ] **Step 1: Implement `app/Sources/UI/PopoverView.swift`**

```swift
import SwiftUI

struct PopoverView: View {
    @ObservedObject var usage: UsageManager
    @ObservedObject var status: StatusManager
    var onRefresh: () -> Void
    var onOpenSettings: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hoverRefresh = false
    @State private var hoverSettings = false

    private var p: Palette { Palette.current(scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if usage.hasFetchedData {
                usageRows
            } else {
                emptyState
            }
            divider
            statusRow
            divider
            footer
        }
        .frame(width: 300)
        .background(scheme == .dark ? Color(hex: "242228", alpha: 0.55) : Color(hex: "fafafc", alpha: 0.55))
    }

    // MARK: Header
    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "asterisk")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(p.sparkStroke)
                Text("Claude Usage")
                    .font(.system(size: 15.5, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(p.primaryText)
            }
            Spacer()
            Text("live")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(p.liveText)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: Usage rows
    private var usageRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            usageRow(title: "Session", pill: "5h", util: usage.sessionUtil,
                     resets: usage.sessionResetsAt, includeDate: false)
            usageRow(title: "Weekly", pill: "7d", util: usage.weeklyUtil,
                     resets: usage.weeklyResetsAt, includeDate: true)
            if usage.hasSonnet {
                usageRow(title: "Weekly · Sonnet", pill: nil, util: usage.sonnetUtil,
                         resets: usage.sonnetResetsAt, includeDate: true, lastRow: true)
            }
        }
    }

    private func usageRow(title: String, pill: String?, util: Int,
                          resets: Date?, includeDate: Bool, lastRow: Bool = false) -> some View {
        let sev = Severity(utilization: util)
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
                meterBar(util: util, severity: sev)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, lastRow ? 14 : 10)
    }

    private func meterBar(util: Int, severity: Severity) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(p.trackBg)
                RoundedRectangle(cornerRadius: 4)
                    .fill(SeverityStyle.barGradient(severity, isDark: p.isDark))
                    .frame(width: max(0, min(1, Double(util) / 100.0)) * geo.size.width)
            }
        }
        .frame(height: 7)
    }

    // MARK: Empty state
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(usage.errorMessage ?? "Set your session cookie to see your usage.")
                .font(.system(size: 13))
                .foregroundStyle(p.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onOpenSettings) {
                Text("Open Settings")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(p.refreshAccent)
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(p.footerPillBg))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: Status
    private var statusRow: some View {
        let isOperational = status.effective == "none"
        return HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(isOperational ? p.operationalDot : statusDotColor(status.effective))
                .frame(width: 8, height: 8)
                .padding(.top, 4)
                .shadow(color: (p.isDark && isOperational) ? Color(hex: "59d499", alpha: 0.6) : .clear, radius: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(isOperational ? "All Claude services operational" : status.statusDescription)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(p.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(status.hasFetched ? status.contextLine(now: Date()) : "Checking status…")
                    .font(.system(size: 11.5))
                    .foregroundStyle(p.faintText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isOperational, let url = URL(string: "https://status.claude.com") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func statusDotColor(_ indicator: String) -> Color {
        switch indicator {
        case "minor":    return Color(hex: "f0b25f")
        case "major":    return Color(hex: "e0995a")
        case "critical": return Color(hex: "ff6b6b")
        default:         return p.operationalDot
        }
    }

    // MARK: Footer
    private var footer: some View {
        HStack {
            Text("Updated \(timeString(usage.lastUpdated))")
                .font(.system(size: 12.5))
                .foregroundStyle(p.faintText)
            Spacer()
            HStack(spacing: 7) {
                pill(label: "↻ Refresh", color: p.refreshAccent, hovering: hoverRefresh) { onRefresh() }
                    .onHover { hoverRefresh = $0 }
                pill(label: "Settings", color: p.primaryText, hovering: hoverSettings) { onOpenSettings() }
                    .onHover { hoverSettings = $0 }
            }
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 12)
    }

    private func pill(label: String, color: Color, hovering: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(color)
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? p.footerPillHover : p.footerPillBg))
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle().fill(p.dividerColor).frame(height: 0.5).padding(.horizontal, 16)
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        return f.string(from: date)
    }
}
```

- [ ] **Step 2: Build** — `bash app/build.sh --no-open` → compiles cleanly. (Wired into the popover in Task 15.)

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "Add PopoverView matching design Variant A/C (UI)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QzZeB4uDJg9nJev5afUoU1"
```

---

## Task 14: Settings window (UI/App)

**Files:**
- Create: `app/Sources/UI/PasteableTextField.swift`, `app/Sources/UI/SettingsView.swift`, `app/Sources/App/SettingsWindowController.swift`

**Interfaces:**
- Consumes: `UsageManager`, `StatusManager`.
- Produces: `struct PasteableTextField: NSViewRepresentable` `(text: Binding<String>, placeholder: String)`.
- Produces: `struct SettingsView: View` `(usage: UsageManager, status: StatusManager)`.
- Produces: `final class SettingsWindowController` with `func show(usage: UsageManager, status: StatusManager)`.

- [ ] **Step 1: Implement `app/Sources/UI/PasteableTextField.swift`** (ported from the original)

```swift
import SwiftUI
import AppKit

final class PasteableNSTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "v": paste(nil); return true
            case "c": copy(nil); return true
            case "x": cut(nil); return true
            case "a": selectAll(nil); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

struct PasteableTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = PasteableNSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 11)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.isRichText = false
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: .greatestFiniteMagnitude)
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? PasteableNSTextView else { return }
        if textView.string != text { textView.string = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PasteableTextField
        init(_ parent: PasteableTextField) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}
```

- [ ] **Step 2: Implement `app/Sources/UI/SettingsView.swift`**

```swift
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var usage: UsageManager
    @ObservedObject var status: StatusManager

    @State private var cookieInput = ""
    @State private var usageNotifications = UserDefaults.standard.object(forKey: "usage_notifications_enabled") as? Bool ?? true
    @State private var statusNotifications = UserDefaults.standard.bool(forKey: "status_notifications_enabled")
    @State private var openAtLogin = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                group("Session cookie") {
                    Text("Paste the full Cookie header from a claude.ai usage request.")
                        .font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. claude.ai → Settings → Usage")
                        Text("2. Open DevTools (⌥⌘I) → Network tab")
                        Text("3. Refresh, click the 'usage' request")
                        Text("4. Copy the full 'Cookie' request header")
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                    PasteableTextField(text: $cookieInput, placeholder: "Paste cookie…")
                        .frame(height: 64)
                    HStack {
                        Button("Save & Fetch") {
                            guard !cookieInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            usage.saveCookie(cookieInput)
                            usage.fetchUsage()
                        }
                        .buttonStyle(.borderedProminent)
                        if usage.hasCookie {
                            Button("Clear") { cookieInput = ""; usage.clearCookie() }
                        }
                    }
                }

                Divider()

                group("Notifications") {
                    Toggle("Usage alerts at 25 / 50 / 75 / 90%", isOn: $usageNotifications)
                        .onChange(of: usageNotifications) { v in
                            UserDefaults.standard.set(v, forKey: "usage_notifications_enabled")
                        }
                    Toggle("Service status alerts", isOn: $statusNotifications)
                        .onChange(of: statusNotifications) { v in
                            UserDefaults.standard.set(v, forKey: "status_notifications_enabled")
                        }
                    Button("Test Notification") {
                        NotificationService.send(title: "Claude Usage Alert",
                                                 body: "Test — you've reached 75% of your session limit")
                    }
                    .controlSize(.small)
                }

                Divider()

                group("General") {
                    Toggle("Open at login", isOn: $openAtLogin)
                        .onChange(of: openAtLogin) { v in setOpenAtLogin(v) }
                }

                Divider()

                group("Status services to track") {
                    Text("Only tracked services trigger status alerts or show in the popover.")
                        .font(.caption2).foregroundStyle(.secondary)
                    ForEach(status.allComponents) { c in
                        Toggle(c.name, isOn: Binding(
                            get: { status.isTracked(c.id) },
                            set: { _ in status.toggleComponent(c.id) }
                        ))
                        .font(.caption)
                    }
                }

                Divider()

                group("About") {
                    Text("Personal build. Based on the MIT-licensed ClaudeUsageBar by Artzainnn.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Button("Original project on GitHub →") {
                        if let url = URL(string: "https://github.com/Artzainnn/ClaudeUsageBar") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                }
            }
            .padding(20)
            .frame(width: 360, alignment: .leading)
        }
        .frame(width: 360, height: 560)
        .onAppear {
            openAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }

    @ViewBuilder
    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private func setOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("open-at-login toggle failed: \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 3: Implement `app/Sources/App/SettingsWindowController.swift`**

```swift
import AppKit
import SwiftUI

final class SettingsWindowController {
    private var window: NSWindow?

    func show(usage: UsageManager, status: StatusManager) {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView(usage: usage, status: status))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Claude Usage Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 4: Build** — `bash app/build.sh --no-open` → compiles cleanly.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add Settings window (cookie, notifications, tracking, about)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QzZeB4uDJg9nJev5afUoU1"
```

---

## Task 15: Wire it all together in AppDelegate

**Files:**
- Modify: `app/Sources/App/AppDelegate.swift`

**Interfaces:**
- Consumes: `PopoverView`, `SettingsWindowController`, `UsageManager`, `StatusManager`, `SnapshotStore`, `UsageSnapshot`, `LimitSnapshot`.

- [ ] **Step 1: Replace `app/Sources/App/AppDelegate.swift` with the full wiring**

```swift
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, MenuBarIconUpdating {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: Any?
    private let settingsWindow = SettingsWindowController()

    let usageManager = UsageManager()
    let statusManager = StatusManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        usageManager.iconDelegate = self
        updateStatusIcon(sessionPercent: 0)

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(
            usage: usageManager,
            status: statusManager,
            onRefresh: { [weak self] in self?.refresh() },
            onOpenSettings: { [weak self] in self?.openSettings() }
        ))

        usageManager.onUpdate = { [weak self] in self?.persistSnapshot() }
        statusManager.onUpdate = { [weak self] in self?.persistSnapshot() }

        NotificationService.requestAuthorization()
        refresh()

        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // MARK: Actions

    private func refresh() {
        usageManager.fetchUsage()
        statusManager.fetch()
    }

    func updateStatusIcon(sessionPercent: Int) {
        guard let button = statusItem?.button else { return }
        button.image = sparkStatusImage(forSeverity: Severity(utilization: sessionPercent))
        button.title = " \(sessionPercent)%"
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ""))
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Quit Claude Usage", action: #selector(quit), keyEquivalent: "q"))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover()
        }
    }

    @objc private func refreshFromMenu() { refresh() }

    private func togglePopover() {
        if popover.isShown { closePopover() } else { openPopover() }
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = eventMonitor { NSEvent.removeMonitor(monitor); eventMonitor = nil }
    }

    @objc private func openSettings() {
        closePopover()
        settingsWindow.show(usage: usageManager, status: statusManager)
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }

    // MARK: Snapshot (widget seam)

    private func persistSnapshot() {
        let snapshot = UsageSnapshot(
            session: LimitSnapshot(utilization: usageManager.sessionUtil,
                                   resetsAt: usageManager.sessionResetsAt,
                                   hasData: usageManager.hasFetchedData),
            weekly: LimitSnapshot(utilization: usageManager.weeklyUtil,
                                  resetsAt: usageManager.weeklyResetsAt,
                                  hasData: usageManager.hasFetchedData),
            weeklySonnet: usageManager.hasSonnet
                ? LimitSnapshot(utilization: usageManager.sonnetUtil,
                                resetsAt: usageManager.sonnetResetsAt, hasData: true)
                : nil,
            statusIndicator: statusManager.effective,
            statusSummary: statusManager.effective == "none"
                ? "All Claude services operational" : statusManager.statusDescription,
            lastUpdated: usageManager.lastUpdated)
        try? SnapshotStore.write(snapshot)
    }
}
```

- [ ] **Step 2: Build + launch** — `bash app/build.sh` → app launches; click the menu-bar item: the new popover appears. Right-click → menu with Refresh / Settings… / Quit. Quit when done.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "Wire popover, settings, snapshot, timers into AppDelegate

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QzZeB4uDJg9nJev5afUoU1"
```

---

## Task 16: Final integration & verification

**Files:**
- Create: `README.md` (build/run/cookie instructions)

- [ ] **Step 1: Full test + build**

Run: `./run-tests.sh` → all Core tests pass.
Run: `bash app/build.sh` → app builds and launches.

- [ ] **Step 2: Empty-state check (no cookie)**

If a cookie was previously saved, clear it (Settings → Clear) or run:
`defaults delete com.bill.claudeusagebar claude_session_cookie 2>/dev/null || true`
Open the popover → it shows the "Set your session cookie…" prompt + "Open Settings" button. Click it → Settings window opens.

- [ ] **Step 3: Live data check (requires Bill's cookie)**

In Settings, paste the claude.ai usage Cookie header → Save & Fetch. Confirm:
- Session / Weekly (and Sonnet if present) show correct %s with severity colors.
- Reset times read "resets 2:10 PM" / "resets Jun 26, 2:00 PM".
- Footer "Updated H:MM" updates; ↻ Refresh re-fetches.
- Menu-bar asterisk color matches session severity.

- [ ] **Step 4: Light/dark check**

System Settings → Appearance → toggle Light/Dark. Reopen the popover → it switches between the dark (Variant A) and light (Variant C) palettes.

- [ ] **Step 5: Snapshot file check**

Run: `cat ~/Library/Application\ Support/ClaudeUsageBar/usage-snapshot.json`
Expected: pretty JSON with `schemaVersion`, `session`/`weekly`(/`weeklySonnet`), `statusIndicator`, `lastUpdated` matching what the popover shows.

- [ ] **Step 6: Notification check**

Settings → Test Notification → a banner appears. (If it doesn't, this is the known macOS-26 notification risk — see the spec; verify the app has Notifications permission in System Settings, or fall back to `NSUserNotification` in `NotificationService`.)

- [ ] **Step 7: Visual compare to the design**

Screenshot the running popover (light and dark) and compare against Variant A / C in `reference/design-handoff/project/Claude Usage Popover.dc.html`. Adjust spacing/colors in `PopoverView.swift`/`Theme.swift` only if something is visibly off.

- [ ] **Step 8: Write `README.md`**

Document: what it is, that it's a personal fork of ClaudeUsageBar, how to build (`bash app/build.sh`), how to get the cookie, the snapshot file location, and that the widget is Phase 2.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "Add README; final integration verification

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QzZeB4uDJg9nJev5afUoU1"
```

---

## Self-Review Notes (for the implementer)

- **Spec coverage:** menu-bar icon (T12), popover Variant A/C (T13, T11), auto light/dark (T11/T13 via `colorScheme`), 3 usage rows + Sonnet optional (T13/T4/T9), status row (T13/T7/T10), footer Refresh/Settings (T13/T15), Settings window with cookie/notifications/open-at-login/tracking/about (T14), 5-min polling (T15), threshold notifications (T8/T9/T15), snapshot widget seam (T5/T15), dropped hotkey/update/donate (absent by construction), severity thresholds (T2, used everywhere). All spec sections map to a task.
- **Type consistency:** `Severity(utilization:)`, `parseUsage→ParsedUsage{session,weekly,sonnet}`, `UsageSnapshot/LimitSnapshot`, `SnapshotStore.write`, `MenuBarIconUpdating.updateStatusIcon(sessionPercent:)`, `UsageManager`/`StatusManager` published names, `PopoverView(usage:status:onRefresh:onOpenSettings:)`, `SettingsWindowController.show(usage:status:)` are used identically across tasks.
- **Known risks (from spec):** macOS-26 notification delivery (T16 step 6 has the fallback), ad-hoc Gatekeeper first-run, open-at-login under ad-hoc signing (may require a signed/installed app — toggle is best-effort), native `NSPopover` chrome stands in for the hand-drawn notch.
