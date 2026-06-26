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
