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
