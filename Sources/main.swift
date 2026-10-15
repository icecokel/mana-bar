import AppKit

@MainActor
final class ManaBarApp: NSObject, NSApplicationDelegate {
    private var preview = CommandLine.arguments.contains("--preview")
        || CommandLine.arguments.contains("--render-preview")
    private var states: [Provider: ProviderState] = [.claude: ProviderState(), .codex: ProviderState()]
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var timer: Timer?
    private var requests: [Provider: Task<Void, Never>] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if preview { loadPreview() }
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentSize = PanelView.size
        popover.contentViewController = NSViewController()

        if let flag = CommandLine.arguments.firstIndex(of: "--render-preview") {
            guard CommandLine.arguments.indices.contains(flag + 1) else { exit(2) }
            render()
            do {
                try savePreview(to: CommandLine.arguments[flag + 1])
                print("Rendered preview.")
                exit(0)
            } catch {
                fputs("Preview rendering failed.\n", stderr)
                exit(1)
            }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        render()
        if !preview { refreshAll() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.preview {
                    for provider in Provider.allCases {
                        if self.states[provider]?.updatedAt.map({ Date().timeIntervalSince($0) >= 300 }) ?? true {
                            self.refresh(provider)
                        }
                    }
                }
                self.render()
            }
        }
        if preview || CommandLine.arguments.contains("--show-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.togglePanel() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        requests.values.forEach { $0.cancel() }
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            render()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func refreshAll() {
        if preview {
            preview = false
            states = [.claude: ProviderState(), .codex: ProviderState()]
        }
        for provider in Provider.allCases { refresh(provider) }
    }

    private func connectClaude() {
        guard !preview else { return }
        refresh(.claude, allowUserInteraction: true)
    }

    private func refresh(_ provider: Provider, allowUserInteraction: Bool = false) {
        guard states[provider]?.isLoading != true else { return }
        states[provider]?.isLoading = true
        render()
        requests[provider] = Task { [weak self] in
            do {
                let windows: [UsageWindow]
                if provider == .codex { windows = try await CodexUsageClient.fetch() }
                else { windows = try await ClaudeUsageClient.fetch(allowUserInteraction: allowUserInteraction) }
                guard let self, !Task.isCancelled else { return }
                self.states[provider] = ProviderState(windows: windows, updatedAt: Date())
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.states[provider]?.isLoading = false
                self.states[provider]?.error = (error as? UsageFailure)?.message ?? "연결하지 못했어요. 다시 시도해 주세요."
            }
            self?.render()
        }
    }

    private func render() {
        let panel = PanelView(states: states, preview: preview,
            refresh: { [weak self] in self?.refreshAll() },
            connectClaude: { [weak self] in self?.connectClaude() },
            quit: { NSApp.terminate(nil) })
        popover.contentViewController?.view = panel
        updateMenuBar()
    }

    private func updateMenuBar() {
        guard let button = statusItem?.button else { return }
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            button.image = MenuBarHUD.image(states: states)
        }
        let description = Provider.allCases.map { provider in
            let state = states[provider] ?? ProviderState()
            let limit = state.representative?.label ?? "미연결"
            return "\(provider.name) \(state.menuText) · \(limit)\(state.isStale ? " · 마지막 확인값" : "")"
        }.joined(separator: "\n")
        button.toolTip = preview ? "미리보기 · 예시 데이터\n\(description)" : description
        button.setAccessibilityLabel("ManaBar. \(description)")
    }

    private func loadPreview() {
        // Preview is opt-in and never substitutes for a failed account request.
        states[.claude] = ProviderState(windows: [
            UsageWindow(id: "five_hour", label: "5시간", usedPercent: 28, resetsAt: Date().addingTimeInterval(3 * 3600 + 720)),
            UsageWindow(id: "seven_day", label: "주간", usedPercent: 39, resetsAt: Date().addingTimeInterval(3 * 86400 + 5 * 3600))
        ], updatedAt: Date())
        states[.codex] = ProviderState(windows: [
            UsageWindow(id: "primary", label: "5시간", usedPercent: 55, resetsAt: Date().addingTimeInterval(2 * 3600 + 480)),
            UsageWindow(id: "secondary", label: "주간", usedPercent: 17, resetsAt: Date().addingTimeInterval(5 * 86400 + 8 * 3600))
        ], updatedAt: Date())
    }

    private func savePreview(to path: String) throws {
        guard let view = popover.contentViewController?.view else { throw UsageFailure(message: "No preview view") }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw UsageFailure(message: "No bitmap context")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw UsageFailure(message: "No PNG data")
        }
        try data.write(to: URL(fileURLWithPath: path))
    }
}

let application = NSApplication.shared
let delegate = ManaBarApp()
application.delegate = delegate
application.run()
