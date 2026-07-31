import Foundation

/// Cloudflare binds the `cf_clearance` cookie to the User-Agent of the browser that solved
/// the challenge. Present the same cookie under any other UA and the request is met with a
/// fresh challenge — an HTML 403 rather than the API's JSON.
///
/// Chrome's UA reduction freezes the platform token and the minor/build/patch fields, so the
/// exact string Cloudflare matched against is recoverable from the major version alone.
/// Sending the real bundle version (`150.0.7871.187`) fails; Chrome itself sends `150.0.0.0`.

/// Used only when no Chrome install can be found. Any pinned value goes stale as Chrome
/// ships new majors, so it seeds the search rather than deciding it.
let defaultChromeMajor = 150

private let frozenPlatformToken = "Macintosh; Intel Mac OS X 10_15_7"

func chromeUserAgent(major: Int) -> String {
    "Mozilla/5.0 (\(frozenPlatformToken)) AppleWebKit/537.36 (KHTML, like Gecko) "
        + "Chrome/\(major).0.0.0 Safari/537.36"
}

/// Reduces a Chrome bundle version (`CFBundleShortVersionString`) to the major Chrome puts
/// in its UA. Returns nil for anything unparseable so callers fall back rather than send
/// a malformed UA.
func chromeMajorVersion(fromBundleVersion version: String) -> Int? {
    guard let first = version.split(separator: ".").first,
          let major = Int(first), major > 0 else { return nil }
    return major
}

/// Majors to try, most likely first.
///
/// A cookie is pasted once but Chrome keeps updating underneath it, so the major that issued
/// the clearance is usually the installed one or a slightly older one — hence the backward
/// walk. `+1` covers a beta/canary that outruns the detected stable build.
func userAgentCandidates(cachedMajor: Int?,
                         installedMajor: Int?,
                         lookback: Int = 4,
                         fallbackMajor: Int = defaultChromeMajor) -> [Int] {
    let seed = installedMajor ?? fallbackMajor
    var ordered: [Int] = []
    if let cachedMajor { ordered.append(cachedMajor) }
    ordered.append(seed)
    if lookback > 0 {
        ordered.append(contentsOf: (1...lookback).map { seed - $0 })
    }
    ordered.append(seed + 1)

    var seen = Set<Int>()
    return ordered.filter { $0 > 0 && seen.insert($0).inserted }
}

/// Distinguishes bot mitigation from a genuinely rejected session. Both surface as 403, but
/// only one is fixed by correcting the User-Agent.
func isCloudflareChallenge(statusCode: Int, cfMitigated: String?) -> Bool {
    statusCode == 403 && cfMitigated?.lowercased() == "challenge"
}

/// Major version of the installed Chrome, read from the app bundle so no process is launched.
func installedChromeMajor(
    bundlePath: String = "/Applications/Google Chrome.app"
) -> Int? {
    let plistPath = bundlePath + "/Contents/Info.plist"
    guard let data = FileManager.default.contents(atPath: plistPath),
          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
          let dict = plist as? [String: Any],
          let version = dict["CFBundleShortVersionString"] as? String else { return nil }
    return chromeMajorVersion(fromBundleVersion: version)
}
