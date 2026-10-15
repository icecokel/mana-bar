import AppKit
import Darwin
import Foundation

enum CodexUsageClient {
    static func fetch() async throws -> [UsageWindow] {
        let applicationURL = await MainActor.run {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")
        }
        // shortcut: 진행 중 취소는 최대 15초까지 기다리며, 장기 조회가 필요해지면 즉시 취소를 구현합니다.
        return try await Task.detached(priority: .utility) {
            try fetchSynchronously(applicationURL: applicationURL)
        }.value
    }

    static func parse(_ data: Data) throws -> [UsageWindow] {
        let response: RateLimitsResponse
        do {
            response = try JSONDecoder().decode(RateLimitsResponse.self, from: data)
        } catch {
            throw UsageFailure(message: "Codex 사용량 응답의 형식이 올바르지 않습니다.")
        }

        let bucket: RateLimitsBucket
        if let buckets = response.rateLimitsByLimitId {
            guard let codex = buckets.codex else {
                throw UsageFailure(message: "Codex 한도 정보가 응답에 없습니다.")
            }
            bucket = codex
        } else if let legacy = response.rateLimits {
            bucket = legacy
        } else {
            throw UsageFailure(message: "Codex 사용량 정보가 없습니다. Codex 로그인을 확인해 주세요.")
        }
        if let limitID = bucket.limitId, limitID != "codex" {
            throw UsageFailure(message: "Codex가 아닌 서비스의 한도 정보가 반환되었습니다.")
        }

        let windows = try [("primary", bucket.primary), ("secondary", bucket.secondary)].compactMap {
            (key, payload) -> UsageWindow? in
            guard let payload else { return nil }
            guard payload.usedPercent.isFinite, (0...100).contains(payload.usedPercent),
                  payload.windowDurationMins.map({ $0 > 0 }) ?? true,
                  payload.resetsAt.map({ $0.isFinite && $0 >= 0 && $0 <= 253402300799 }) ?? true
            else {
                throw UsageFailure(message: "Codex 한도 응답에 유효하지 않은 수치가 있습니다.")
            }

            let label: String
            if let minutes = payload.windowDurationMins {
                if minutes == 10080 {
                    label = "주간"
                } else if minutes.isMultiple(of: 60) {
                    label = "\(minutes / 60)시간"
                } else {
                    label = "\(minutes)분"
                }
            } else {
                label = key == "primary" ? "기본" : "추가"
            }
            return UsageWindow(
                id: "codex.\(key)", label: label, usedPercent: payload.usedPercent,
                resetsAt: payload.resetsAt.map(Date.init(timeIntervalSince1970:))
            )
        }
        guard !windows.isEmpty else {
            throw UsageFailure(message: "Codex의 조회 가능한 한도 정보가 없습니다.")
        }
        return windows
    }

    private static func fetchSynchronously(applicationURL: URL?) throws -> [UsageWindow] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            applicationURL?.appendingPathComponent("Contents/Resources/codex").path,
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "\(home)/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
        ].compactMap { $0 }
        guard let executable = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw UsageFailure(message: "Codex 실행 파일을 찾지 못했습니다. Codex 앱 또는 CLI를 설치해 주세요.")
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            try? output.fileHandleForReading.close()
        }
        do {
            try process.run()
        } catch {
            throw UsageFailure(message: "Codex 사용량 조회 프로세스를 시작하지 못했습니다.")
        }

        let deadline = ProcessInfo.processInfo.systemUptime + 15
        var buffer = Data()
        try send([
            "id": 1, "method": "initialize",
            "params": ["clientInfo": ["name": "mana_bar", "title": "ManaBar", "version": "0.1.0"]],
        ], to: input.fileHandleForWriting)
        _ = try receive(id: 1, from: output.fileHandleForReading, buffer: &buffer, deadline: deadline)
        try send(["method": "initialized"], to: input.fileHandleForWriting)
        try send(["id": 2, "method": "account/rateLimits/read"], to: input.fileHandleForWriting)
        let result = try receive(id: 2, from: output.fileHandleForReading, buffer: &buffer, deadline: deadline)
        return try parse(JSONSerialization.data(withJSONObject: result))
    }

    private static func send(_ message: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        do {
            try handle.write(contentsOf: data)
        } catch {
            throw UsageFailure(message: "Codex 사용량 조회 연결이 끊어졌습니다.")
        }
    }

    private static func receive(
        id: Int, from handle: FileHandle, buffer: inout Data, deadline: TimeInterval
    ) throws -> [String: Any] {
        while ProcessInfo.processInfo.systemUptime < deadline {
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                guard !line.isEmpty else { continue }
                guard let message = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw UsageFailure(message: "Codex 조회 응답을 해석하지 못했습니다.")
                }
                guard (message["id"] as? Int) == id else { continue }
                if let error = message["error"] as? [String: Any] {
                    throw UsageFailure(message: "Codex 조회 실패: \(error["message"] as? String ?? "기존 Codex 로그인을 확인해 주세요.")")
                }
                guard let result = message["result"] as? [String: Any] else {
                    throw UsageFailure(message: "Codex 사용량 조회 결과가 비어 있습니다.")
                }
                return result
            }

            var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let remaining = max(1, Int32((deadline - ProcessInfo.processInfo.systemUptime) * 1000))
            let ready = poll(&descriptor, 1, remaining)
            if ready < 0 {
                if errno == EINTR { continue }
                throw UsageFailure(message: "Codex 조회 연결을 읽지 못했습니다.")
            }
            guard ready > 0 else { break }
            var bytes = [UInt8](repeating: 0, count: 8192)
            let count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else {
                throw UsageFailure(message: "Codex 조회 연결이 종료되었습니다. Codex 로그인을 확인해 주세요.")
            }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count <= 1_048_576 else {
                throw UsageFailure(message: "Codex 조회 응답이 허용 크기를 초과했습니다.")
            }
        }
        throw UsageFailure(message: "Codex 사용량 조회 시간이 초과되었습니다.")
    }
}

private struct RateLimitsResponse: Decodable {
    let rateLimitsByLimitId: CodexBuckets?
    let rateLimits: RateLimitsBucket?

    private enum CodingKeys: String, CodingKey {
        case rateLimitsByLimitId, rateLimits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rateLimitsByLimitId = try container.decodeIfPresent(CodexBuckets.self, forKey: .rateLimitsByLimitId)
        rateLimits = rateLimitsByLimitId == nil
            ? try container.decodeIfPresent(RateLimitsBucket.self, forKey: .rateLimits) : nil
    }
}

private struct CodexBuckets: Decodable {
    let codex: RateLimitsBucket?
}

private struct RateLimitsBucket: Decodable {
    let limitId: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
}

private struct RateLimitWindow: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Double?
}
