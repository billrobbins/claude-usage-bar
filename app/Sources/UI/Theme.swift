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
    var captionText: Color   { isDark ? Color(hex: "ebebf5", alpha: 0.72) : Color(hex: "3c3c43", alpha: 0.62) }
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
