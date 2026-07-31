import Foundation

func testBrowserUserAgent() {
    // Chrome's UA reduction freezes everything but the major version, so the string
    // Cloudflare matched cf_clearance against is fully determined by that major.
    T.eq(chromeUserAgent(major: 150),
         "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36",
         "builds the reduced Chrome UA")

    // The installed bundle reports 150.0.7871.187, but sending that verbatim is rejected —
    // only the major survives into the UA.
    T.eq(chromeMajorVersion(fromBundleVersion: "150.0.7871.187"), 150, "major parsed from full bundle version")
    T.eq(chromeMajorVersion(fromBundleVersion: "99"), 99, "major parsed from bare major")
    T.eq(chromeMajorVersion(fromBundleVersion: ""), nil, "empty version rejected")
    T.eq(chromeMajorVersion(fromBundleVersion: "not.a.version"), nil, "garbage version rejected")
    T.eq(chromeMajorVersion(fromBundleVersion: "0.1.2"), nil, "zero major rejected")

    // A previously confirmed major is tried first so the steady state costs one request.
    T.eq(userAgentCandidates(cachedMajor: 148, installedMajor: 150, lookback: 2),
         [148, 150, 149, 151],
         "cached major leads, then installed, then older, then newer")

    // No cache: the pasted cookie can predate a Chrome update, so walk backward.
    T.eq(userAgentCandidates(cachedMajor: nil, installedMajor: 150, lookback: 3),
         [150, 149, 148, 147, 151],
         "installed first, then backward, then one ahead")

    // Chrome missing entirely (uninstalled, or renamed bundle): use the compiled-in default.
    T.eq(userAgentCandidates(cachedMajor: nil, installedMajor: nil, lookback: 1, fallbackMajor: 150),
         [150, 149, 151],
         "falls back to compiled default")

    T.ok(!userAgentCandidates(cachedMajor: nil, installedMajor: 2, lookback: 5).contains(where: { $0 < 1 }),
         "never emits a non-positive major")

    // A challenge is a bot-mitigation 403, which must not be reported as an auth failure.
    T.ok(isCloudflareChallenge(statusCode: 403, cfMitigated: "challenge"), "403 + cf-mitigated is a challenge")
    T.ok(!isCloudflareChallenge(statusCode: 403, cfMitigated: nil), "bare 403 is not a challenge")
    T.ok(!isCloudflareChallenge(statusCode: 200, cfMitigated: nil), "200 is not a challenge")
    T.ok(!isCloudflareChallenge(statusCode: 401, cfMitigated: nil), "401 is not a challenge")
}
