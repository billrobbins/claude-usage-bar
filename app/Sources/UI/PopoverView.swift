import SwiftUI

struct PopoverView: View {
    @ObservedObject var usage: UsageManager
    @ObservedObject var status: StatusManager
    var onRefresh: () -> Void
    var onOpenSettings: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hoverRefresh = false
    @State private var hoverSettings = false
    @State private var now = Date()

    /// Keeps `now` current while the popover is alive. The popover reuses a single
    /// hosting controller, so `.onAppear` fires only once (at launch) and never again
    /// on later opens — without this tick, `now` freezes at launch time. A 7-day window
    /// barely notices, but the 5-hour session pace then reads wildly wrong (often 0%).
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

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
            footer
        }
        .frame(width: 300)
        .background(scheme == .dark ? Color(hex: "242228", alpha: 0.55) : Color(hex: "fafafc", alpha: 0.55))
        .onAppear { now = Date() }
        .onReceive(ticker) { now = $0 }
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
                        .foregroundStyle(p.captionText)
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

    private func paceCaption(_ pace: PaceInfo, noun: String) -> some View {
        HStack(spacing: 0) {
            Text("\(pace.elapsedPercent)% of \(noun) elapsed")
                .foregroundStyle(p.captionText)
            if let ratio = pace.paceRatio {
                Text(" · ").foregroundStyle(p.captionText)
                Text("\(formattedPace(ratio)) pace")
                    .foregroundStyle(paceSeverity(ratio)
                        .map { SeverityStyle.textColor($0, isDark: p.isDark) } ?? p.captionText)
            }
        }
        .font(.system(size: 11.5))
    }

    // MARK: Empty state
    private var emptyStateMessage: String {
        if let error = usage.errorMessage { return error }
        if usage.hasCookie { return "Loading your usage…" }
        return "Set your session cookie to see your usage."
    }

    private var showSettingsButton: Bool {
        usage.errorMessage != nil || !usage.hasCookie
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(emptyStateMessage)
                .font(.system(size: 13))
                .foregroundStyle(p.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if showSettingsButton {
                Button(action: onOpenSettings) {
                    Text("Open Settings")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(p.refreshAccent)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 7).fill(p.footerPillBg))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: Status (compact footer indicator)
    private var statusIsOperational: Bool { status.effective == "none" }

    /// SF Symbol whose shape escalates with severity; a muted glyph until the first fetch.
    private var statusSymbol: String {
        guard status.hasFetched else { return "ellipsis.circle" }
        switch status.effective {
        case "minor":    return "exclamationmark.circle.fill"
        case "major":    return "exclamationmark.triangle.fill"
        case "critical": return "exclamationmark.octagon.fill"
        default:         return "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        guard status.hasFetched else { return p.faintText }
        return statusIsOperational ? p.operationalDot : statusDotColor(status.effective)
    }

    private var statusTooltip: String {
        guard status.hasFetched else { return "Checking status…" }
        let head = statusIsOperational ? "All Claude services operational" : status.statusDescription
        return "\(head) · \(status.contextLine(now: now))"
    }

    private var statusIndicator: some View {
        Image(systemName: statusSymbol)
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(statusColor)
            .frame(width: 22, height: 26)
            .contentShape(Rectangle())
            .onTapGesture {
                if let url = URL(string: "https://status.claude.com") {
                    NSWorkspace.shared.open(url)
                }
            }
            .accessibilityLabel("Claude status")
            .help(statusTooltip)
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
            HStack(spacing: 8) {
                statusIndicator
                iconPill(systemName: "arrow.clockwise", color: p.refreshAccent,
                         hovering: hoverRefresh, label: "Refresh") { onRefresh() }
                    .onHover { hoverRefresh = $0 }
                iconPill(systemName: "gearshape", color: p.secondaryText,
                         hovering: hoverSettings, label: "Settings") { onOpenSettings() }
                    .onHover { hoverSettings = $0 }
            }
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 12)
    }

    private func iconPill(systemName: String, color: Color, hovering: Bool,
                          label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? p.footerPillHover : p.footerPillBg))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    private var divider: some View {
        Rectangle().fill(p.dividerColor).frame(height: 0.5).padding(.horizontal, 16)
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        return f.string(from: date)
    }
}
