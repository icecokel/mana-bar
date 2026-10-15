import Foundation

func checkCodexParsing() throws {
    func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw UsageFailure(message: "Codex parser check failed: \(message)") }
    }
    func parse(_ json: String) throws -> [UsageWindow] {
        try CodexUsageClient.parse(Data(json.utf8))
    }
    func reject(_ json: String) throws {
        var failed = false
        do { _ = try parse(json) } catch { failed = true }
        try require(failed, "invalid data was accepted: \(json)")
    }

    let current = try parse("""
        {"rateLimitsByLimitId": {
          "codex": {"limitId":"codex",
            "primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1800000000},
            "secondary":{"usedPercent":62.5,"windowDurationMins":10080,"resetsAt":1800500000}},
          "other":"unrelated data is ignored"},
         "rateLimits":"legacy data is ignored when the Codex map exists"}
        """)
    try require(current.count == 2, "both windows must be retained")
    try require(current[0].id == "codex.primary", "only the Codex bucket must be selected")
    try require(current[0].remainingPercent == 75, "usage must convert to remaining quota")
    try require(current[1].remainingPercent == 37.5, "fractional percentages must be retained")
    try require(current[0].label == "5시간" && current[1].label == "주간", "window labels")
    try require(current[0].resetsAt == Date(timeIntervalSince1970: 1800000000), "reset timestamp")

    let legacy = try parse("""
        {"rateLimits":{"primary":{"usedPercent":0},"secondary":{"usedPercent":100}}}
        """)
    try require(legacy[0].remainingPercent == 100 && legacy[1].remainingPercent == 0, "0 and 100 are valid")
    try require(legacy[0].resetsAt == nil, "missing reset must remain unknown")
    let nullable = try parse("""
        {"rateLimitsByLimitId":null,"rateLimits":{"limitId":"codex","primary":{"usedPercent":50}}}
        """)
    try require(nullable.count == 1, "legacy fallback when multi-bucket data is null")
    try require(legacy[0].label == "기본" && legacy[1].label == "추가", "unknown durations must not be labeled as five-hour limits")

    for (bucket, expectedID, label) in [
        (#""primary":{"usedPercent":40,"windowDurationMins":10080}"#, "codex.primary", "주간"),
        (#""primary":{"usedPercent":40,"windowDurationMins":10080},"secondary":null"#, "codex.primary", "주간"),
        (#""secondary":{"usedPercent":40,"windowDurationMins":10080}"#, "codex.secondary", "주간"),
        (#""primary":null,"secondary":{"usedPercent":40,"windowDurationMins":10080}"#, "codex.secondary", "주간"),
        (#""primary":{"usedPercent":40,"windowDurationMins":300}"#, "codex.primary", "5시간"),
        (#""primary":{"usedPercent":40,"windowDurationMins":300},"secondary":null"#, "codex.primary", "5시간"),
        (#""secondary":{"usedPercent":40,"windowDurationMins":300}"#, "codex.secondary", "5시간"),
        (#""primary":null,"secondary":{"usedPercent":40,"windowDurationMins":300}"#, "codex.secondary", "5시간"),
    ] {
        let windows = try parse("{\"rateLimitsByLimitId\":{\"codex\":{\(bucket)}}}")
        try require(windows.count == 1 && windows[0].id == expectedID, "absent or null windows must be omitted")
        try require(windows[0].label == label, "a single limit must use its reported duration")
        let state = ProviderState(windows: windows, updatedAt: Date())
        try require(state.representative?.label == label && state.menuText == "60%", "the available limit must represent the account")
    }

    let weeklyPrimary = try parse("""
        {"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":10080},
                       "secondary":{"usedPercent":70,"windowDurationMins":300}}}
        """)
    try require(weeklyPrimary.map(\.label) == ["주간", "5시간"], "window labels must follow durations rather than primary/secondary positions")
    try require(weeklyPrimary.map(\.id) == ["codex.primary", "codex.secondary"], "the server's primary limit must remain first")

    for invalid in [
        "{}", "not JSON", "[]", "{\"error\":{\"message\":\"Unauthorized\"}}",
        "{\"rateLimits\":{}}", "{\"rateLimits\":{\"primary\":{}}}",
        #"{"rateLimits":{"primary":null}}"#,
        #"{"rateLimits":{"secondary":null}}"#,
        #"{"rateLimits":{"primary":null,"secondary":null}}"#,
        "{\"rateLimitsByLimitId\":{}}",
        "{\"rateLimitsByLimitId\":{\"other\":{\"primary\":{\"usedPercent\":5}}}}",
        "{\"rateLimits\":{\"limitId\":\"other\",\"primary\":{\"usedPercent\":5}}}",
        "{\"rateLimits\":{\"primary\":{\"usedPercent\":-1}}}",
        "{\"rateLimits\":{\"primary\":{\"usedPercent\":101}}}",
        "{\"rateLimits\":{\"primary\":{\"usedPercent\":true}}}",
        "{\"rateLimits\":{\"primary\":{\"usedPercent\":\"25\"}}}",
        "{\"rateLimits\":{\"primary\":{\"usedPercent\":1e999}}}",
        "{\"rateLimits\":{\"primary\":{\"usedPercent\":25,\"windowDurationMins\":0}}}",
        "{\"rateLimits\":{\"primary\":{\"usedPercent\":25,\"resetsAt\":-1}}}",
    ] {
        try reject(invalid)
    }
}
