import Foundation

func checkClaudeParsing() throws {
    try checkClaudeCredentialCache()
    let windows = try ClaudeUsageClient.parse(Data(#"{"five_hour":{"utilization":28,"resets_at":"2026-10-15T12:00:00.000Z"},"seven_day":{"utilization":55,"resets_at":"2026-10-20T00:00:00Z"}}"#.utf8))
    assert(windows.count == 2)
    assert(windows[0].id == "five_hour" && windows[0].remainingPercent == 72)
    assert(windows[1].id == "seven_day" && windows[1].remainingPercent == 45)
    assert(windows.allSatisfy { $0.resetsAt != nil })

    let partial = try ClaudeUsageClient.parse(Data(#"{"five_hour":null,"seven_day":{"utilization":0,"resets_at":null}}"#.utf8))
    assert(partial.count == 1 && partial[0].remainingPercent == 100 && partial[0].resetsAt == nil)
    let exhausted = try ClaudeUsageClient.parse(Data(#"{"five_hour":{"utilization":100}}"#.utf8))
    assert(exhausted[0].remainingPercent == 0 && exhausted[0].resetsAt == nil)

    for invalid in [
        "{}", "null", "not json",
        #"{"five_hour":null,"seven_day":null}"#,
        #"{"five_hour":{"resets_at":null}}"#,
        #"{"five_hour":{"utilization":-1}}"#,
        #"{"five_hour":{"utilization":101}}"#,
        #"{"five_hour":{"utilization":"28"}}"#,
        #"{"five_hour":{"utilization":28,"resets_at":"invalid"}}"#,
    ] {
        do {
            _ = try ClaudeUsageClient.parse(Data(invalid.utf8))
            assertionFailure("Invalid Claude usage response was accepted")
        } catch is UsageFailure {}
    }
}

private func checkClaudeCredentialCache() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let valid = Data(#"{"claudeAiOauth":{"accessToken":"test-a","expiresAt":1800007200000}}"#.utf8)
    let rotated = Data(#"{"claudeAiOauth":{"accessToken":"test-b","expiresAt":1800007200000}}"#.utf8)
    var cache = ClaudeUsageClient.CredentialCache()
    var loads = 0
    func load() -> Data { loads += 1; return valid }

    let initial = try cache.accessToken(now: now, load: load)
    let reused = try cache.accessToken(now: now.addingTimeInterval(1799), load: load)
    assert(initial == "test-a" && reused == initial && loads == 1)
    _ = try cache.accessToken(now: now.addingTimeInterval(1800), load: load)
    assert(loads == 2)

    let forced = try cache.accessToken(forceReload: true, now: now.addingTimeInterval(1801)) {
        loads += 1
        return rotated
    }
    assert(forced == "test-b" && loads == 3)
    for status in [200, 403, 429, 500, 503] {
        cache.recordResponse(statusCode: status, token: forced)
        let preserved = try cache.accessToken(now: now.addingTimeInterval(1802), load: load)
        assert(preserved == "test-b" && loads == 3)
    }
    cache.recordResponse(statusCode: 401, token: "test-a")
    let preserved = try cache.accessToken(now: now.addingTimeInterval(1802), load: load)
    assert(preserved == "test-b" && loads == 3)
    cache.recordResponse(statusCode: 401, token: forced)
    _ = try cache.accessToken(now: now.addingTimeInterval(1802), load: load)
    assert(loads == 4)

    var expiring = ClaudeUsageClient.CredentialCache()
    let shortLived = Data(#"{"claudeAiOauth":{"accessToken":"test-short","expiresAt":1800000060000}}"#.utf8)
    _ = try expiring.accessToken(now: now) { shortLived }
    var expiryLoads = 0
    let refreshed = try expiring.accessToken(now: now.addingTimeInterval(60)) {
        expiryLoads += 1
        return valid
    }
    assert(refreshed == "test-a" && expiryLoads == 1)

    for missingExpiry in [
        #"{"claudeAiOauth":{"accessToken":"test-unknown"}}"#,
        #"{"claudeAiOauth":{"accessToken":"test-unknown","expiresAt":null}}"#,
    ] {
        var unknown = ClaudeUsageClient.CredentialCache()
        var unknownLoads = 0
        for _ in 0..<2 {
            _ = try unknown.accessToken(now: now) {
                unknownLoads += 1
                return Data(missingExpiry.utf8)
            }
        }
        assert(unknownLoads == 2)
    }

    for invalid in [
        #"{"claudeAiOauth":{"accessToken":"","expiresAt":1800007200000}}"#,
        #"{"claudeAiOauth":{"accessToken":"test-old","expiresAt":1800000000000}}"#,
        #"{"claudeAiOauth":{"accessToken":"test-old","expiresAt":1799999999000}}"#,
        #"{"claudeAiOauth":{"accessToken":"test-bad","expiresAt":"later"}}"#,
        "{}", "not JSON",
    ] {
        var invalidCache = ClaudeUsageClient.CredentialCache()
        do {
            _ = try invalidCache.accessToken(now: now) { Data(invalid.utf8) }
            assertionFailure("Invalid Claude credentials were accepted")
        } catch is UsageFailure {}
    }

    let denied = UsageFailure(message: "test permission denied")
    do {
        _ = try cache.accessToken(forceReload: true, now: now) { throw denied }
        assertionFailure("A credential-loader error was ignored")
    } catch let error as UsageFailure {
        assert(error.message == denied.message)
    }
    _ = try cache.accessToken(now: now, load: load)
    assert(loads == 5)
}
