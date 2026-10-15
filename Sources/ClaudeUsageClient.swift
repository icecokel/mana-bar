import Foundation
import LocalAuthentication
import Security

enum ClaudeUsageClient {
    private static let keychainLock = NSLock()
    private nonisolated(unsafe) static var credentialCache = CredentialCache()

    static func fetch(allowUserInteraction: Bool = false) async throws -> [UsageWindow] {
        let token = try await Task.detached { try readAccessToken(allowUserInteraction: allowUserInteraction) }.value
        // shortcut: Claude Code의 비공개 사용량 endpoint에 의존하며, 공식 조회 API가 생기면 교체합니다.
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForResource = 15
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw UsageFailure(message: "Claude 사용량 응답을 확인할 수 없습니다.")
        }
        keychainLock.withLock {
            credentialCache.recordResponse(statusCode: response.statusCode, token: token)
        }
        switch response.statusCode {
        case 200:
            return try parse(data)
        case 401, 403:
            throw UsageFailure(message: "Claude 로그인이 만료되었거나 거부되었습니다. Claude Code에서 다시 로그인한 뒤 연결하세요.")
        case 429:
            throw UsageFailure(message: "Claude 사용량 조회가 제한되었습니다. 잠시 후 다시 시도하세요.")
        default:
            throw UsageFailure(message: "Claude 사용량 조회 실패 (HTTP \(response.statusCode)).")
        }
    }

    static func parse(_ data: Data) throws -> [UsageWindow] {
        struct Payload: Decodable {
            struct Window: Decodable {
                let utilization: Double?
                let resets_at: String?
            }
            let five_hour: Window?
            let seven_day: Window?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw UsageFailure(message: "Claude 사용량 응답 형식을 읽을 수 없습니다.")
        }
        let formatter = ISO8601DateFormatter()
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions.insert(.withFractionalSeconds)
        let windows = try [("five_hour", "5시간", payload.five_hour), ("seven_day", "주간", payload.seven_day)]
            .compactMap { id, label, window -> UsageWindow? in
                guard let window, let usedPercent = window.utilization else { return nil }
                guard usedPercent.isFinite, (0...100).contains(usedPercent) else {
                    throw UsageFailure(message: "Claude 사용량 비율이 유효하지 않습니다.")
                }
                let resetsAt: Date?
                if let value = window.resets_at {
                    guard let date = fractionalFormatter.date(from: value) ?? formatter.date(from: value) else {
                        throw UsageFailure(message: "Claude 초기화 시간을 읽을 수 없습니다.")
                    }
                    resetsAt = date
                } else {
                    resetsAt = nil
                }
                return UsageWindow(id: id, label: label, usedPercent: usedPercent, resetsAt: resetsAt)
            }
        guard !windows.isEmpty else {
            throw UsageFailure(message: "Claude가 조회 가능한 사용 한도를 제공하지 않았습니다.")
        }
        return windows
    }

    private static func readAccessToken(allowUserInteraction: Bool) throws -> String {
        keychainLock.lock()
        defer { keychainLock.unlock() }
        return try credentialCache.accessToken(forceReload: allowUserInteraction) {
            try readKeychainData(allowUserInteraction: allowUserInteraction)
        }
    }

    private static func readKeychainData(allowUserInteraction: Bool) throws -> Data {
        // shortcut: legacy macOS keychains ignore LAContext's UI flag; remove this when SecItem supports it.
        var previousInteraction: DarwinBoolean = false
        guard SecKeychainGetUserInteractionAllowed(&previousInteraction) == errSecSuccess,
              SecKeychainSetUserInteractionAllowed(allowUserInteraction) == errSecSuccess else {
            throw UsageFailure(message: "Claude 키체인 접근 상태를 확인하지 못했습니다.")
        }
        defer { SecKeychainSetUserInteractionAllowed(previousInteraction.boolValue) }
        let authentication = LAContext()
        authentication.interactionNotAllowed = !allowUserInteraction
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: authentication,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecInteractionNotAllowed || status == errSecInteractionRequired || status == errSecAuthFailed {
            throw UsageFailure(message: "Claude 키체인 접근 권한이 없습니다. 연결 버튼을 눌러 키체인 접근을 승인해 주세요.")
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw UsageFailure(message: "Claude Code 로그인 정보를 찾지 못했습니다. Claude Code에 로그인한 뒤 연결하세요.")
        }
        return data
    }

    struct CredentialCache {
        private struct Credentials: Decodable {
            struct OAuth: Decodable {
                let accessToken: String
                let expiresAt: Double?
            }
            let claudeAiOauth: OAuth
        }

        private var credentials: Credentials.OAuth?
        private var loadedAt: Date?

        mutating func accessToken(forceReload: Bool = false, now: Date = Date(),
                                  load: () throws -> Data) throws -> String {
            if !forceReload, let credentials, let loadedAt, let expiresAt = credentials.expiresAt,
               now >= loadedAt, now.timeIntervalSince(loadedAt) < 1800,
               now.timeIntervalSince1970 * 1000 < expiresAt {
                return credentials.accessToken
            }
            credentials = nil
            loadedAt = nil
            let data = try load()
            guard let oauth = (try? JSONDecoder().decode(Credentials.self, from: data))?.claudeAiOauth,
                  !oauth.accessToken.isEmpty, !oauth.accessToken.contains("\r"), !oauth.accessToken.contains("\n") else {
                throw UsageFailure(message: "Claude Code 로그인 정보를 읽을 수 없습니다. Claude Code에서 다시 로그인하세요.")
            }
            guard oauth.expiresAt.map({ $0.isFinite && $0 > now.timeIntervalSince1970 * 1000 }) ?? true else {
                throw UsageFailure(message: "Claude 로그인이 만료되었습니다. Claude Code를 실행해 로그인 정보를 갱신한 뒤 연결하세요.")
            }
            credentials = oauth
            loadedAt = now
            return oauth.accessToken
        }

        mutating func recordResponse(statusCode: Int, token: String) {
            if statusCode == 401, credentials?.accessToken == token {
                credentials = nil
                loadedAt = nil
            }
        }
    }
}
