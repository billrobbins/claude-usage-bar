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
