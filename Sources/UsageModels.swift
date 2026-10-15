import Foundation

enum Provider: String, CaseIterable, Sendable {
    case claude, codex

    var name: String { self == .claude ? "Claude" : "Codex" }
    var usageURL: URL {
        URL(string: self == .claude
            ? "https://claude.ai/settings/usage"
            : "https://chatgpt.com/codex/settings/usage")!
    }
}

struct UsageWindow: Sendable {
    let id: String
    let label: String
    let usedPercent: Double
    let resetsAt: Date?

    var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
}

struct UsageFailure: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

struct ProviderState {
    var windows: [UsageWindow] = []
    var updatedAt: Date?
    var isLoading = false
    var error: String?

    var representative: UsageWindow? { windows.first }
    var isStale: Bool {
        guard !windows.isEmpty else { return false }
        return error != nil || updatedAt.map { Date().timeIntervalSince($0) > 600 } == true
            || windows.contains { $0.resetsAt.map { $0 <= Date() } == true }
    }

    var menuText: String {
        guard let window = representative else { return "—" }
        return "\(Int(window.remainingPercent.rounded()))%\(isStale ? "*" : "")"
    }
}
