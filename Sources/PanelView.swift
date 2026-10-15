import AppKit

@MainActor
private func text(_ value: String, size: CGFloat = 12, color: NSColor = Palette.text,
                  serif: Bool = false) -> NSTextField {
    let label = NSTextField(labelWithString: value)
    label.font = (serif ? PanelFont.heading : .body).at(size)
    label.textColor = color
    label.lineBreakMode = .byTruncatingTail
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return label
}

@MainActor
private func row(_ views: [NSView], spacing: CGFloat = 6) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = spacing
    return stack
}

@MainActor
private func spacer() -> NSView {
    let view = NSView()
    view.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return view
}

@MainActor
final class ActionButton: NSButton {
    private let handler: @MainActor () -> Void

    init(_ title: String, symbol: String? = nil, action: @escaping @MainActor () -> Void) {
        handler = action
        super.init(frame: .zero)
        self.title = title
        target = self
        self.action = #selector(invoke)
        isBordered = false
        controlSize = .small
        font = PanelFont.amount.at(12)
        contentTintColor = Palette.secondary
        if let symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
            imagePosition = .imageOnly
            contentTintColor = Palette.text
        }
        toolTip = title
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    @objc private func invoke() { handler() }

    override var intrinsicContentSize: NSSize {
        image == nil ? NSSize(width: max(44, super.intrinsicContentSize.width + 20), height: 26)
            : NSSize(width: 24, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        let edge = bounds.insetBy(dx: 0.5, dy: 0.5)
        let frame = cutCornerPath(edge)
        NSGradient(starting: Palette.metal.withAlphaComponent(isEnabled ? 1 : 0.35),
                   ending: Palette.line)?.draw(in: frame, angle: -90)
        NSColor.black.setStroke()
        frame.stroke()

        let face = edge.insetBy(dx: 2, dy: 2)
        let inset = cutCornerPath(face)
        NSGradient(starting: isHighlighted ? Palette.background : Palette.line,
                   ending: Palette.background)?.draw(in: inset, angle: -90)
        NSColor.black.withAlphaComponent(0.8).setStroke()
        inset.stroke()

        let bevel = NSBezierPath()
        bevel.move(to: NSPoint(x: face.minX + 3, y: face.maxY - 1))
        bevel.line(to: NSPoint(x: face.maxX - 3, y: face.maxY - 1))
        Palette.text.withAlphaComponent(isEnabled && !isHighlighted ? 0.2 : 0.04).setStroke()
        bevel.stroke()
        if image != nil {
            super.draw(dirtyRect)
            return
        }
        let shadow = NSShadow()
        shadow.shadowColor = .black
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        let label = NSAttributedString(string: title, attributes: [
            .font: font ?? PanelFont.amount.at(12),
            .foregroundColor: isEnabled ? Palette.text : Palette.secondary.withAlphaComponent(0.5),
            .shadow: shadow
        ])
        label.draw(at: NSPoint(x: bounds.midX - label.size().width / 2,
                               y: bounds.midY - label.size().height / 2 - (isHighlighted ? 1 : 0)))
    }

    private func cutCornerPath(_ rect: NSRect) -> NSBezierPath {
        let cut: CGFloat = 3
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX + cut, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX - cut, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY + cut))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - cut))
        path.line(to: NSPoint(x: rect.maxX - cut, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX + cut, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY - cut))
        path.line(to: NSPoint(x: rect.minX, y: rect.minY + cut))
        path.close()
        return path
    }
}

@MainActor
final class PanelView: NSView {
    static let size = NSSize(width: 300, height: 270)

    init(states: [Provider: ProviderState], preview: Bool,
         refresh: @escaping @MainActor () -> Void,
         connectClaude: @escaping @MainActor () -> Void,
         quit: @escaping @MainActor () -> Void) {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.backgroundColor = Palette.background.cgColor
        layer?.cornerRadius = 1

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            root.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            root.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -11)
        ])

        let title = text("MANABAR", size: 14, serif: true)
        title.attributedStringValue = NSAttributedString(string: "MANABAR", attributes: [
            .font: title.font!, .foregroundColor: Palette.text, .kern: 1.4
        ])
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let lastChecked = states.values.compactMap(\.updatedAt).min()
        let timestamp = lastChecked.map { formatter.string(from: $0) } ?? "미연결"
        let checkedTime = text(preview ? "예시 데이터" : timestamp, color: Palette.secondary)
        checkedTime.setAccessibilityLabel(preview ? "예시 데이터" : "마지막 확인 \(timestamp)")
        checkedTime.toolTip = preview ? "실제 계정 값이 아닌 예시 데이터"
            : lastChecked.map { "마지막 확인: \($0.formatted(date: .abbreviated, time: .standard))" } ?? "확인된 사용량 없음"
        let refreshButton = ActionButton(preview ? "실제 연결" : "갱신", symbol: "arrow.clockwise", action: refresh)
        refreshButton.isEnabled = !states.values.contains(where: \.isLoading)
        let quitButton = ActionButton("종료", symbol: "power", action: quit)
        add(row([title, spacer(), checkedTime, refreshButton, quitButton]), to: root)
        add(divider(), to: root, top: 5)

        let left = column(provider: .claude, state: states[.claude] ?? ProviderState(), connectClaude: connectClaude)
        let right = column(provider: .codex, state: states[.codex] ?? ProviderState(), connectClaude: connectClaude)
        let seam = divider(vertical: true)
        let resources = row([left, seam, right], spacing: 12)
        resources.alignment = .top
        resources.distribution = .fill
        left.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true
        resources.heightAnchor.constraint(equalToConstant: 202).isActive = true
        add(resources, to: root, top: 8)

        let flexibleSpace = NSView()
        flexibleSpace.setContentHuggingPriority(.defaultLow, for: .vertical)
        add(flexibleSpace, to: root, top: 2)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func draw(_ dirtyRect: NSRect) {
        GameArt.stone.draw(in: bounds)
    }

    private func add(_ view: NSView, to stack: NSStackView, top: CGFloat = 0, widthRatio: CGFloat = 1) {
        if top > 0, let previous = stack.arrangedSubviews.last { stack.setCustomSpacing(top, after: previous) }
        stack.addArrangedSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: widthRatio).isActive = true
    }

    private func divider(vertical: Bool = false) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = Palette.line.withAlphaComponent(0.7).cgColor
        if vertical {
            view.widthAnchor.constraint(equalToConstant: 1).isActive = true
            view.heightAnchor.constraint(equalToConstant: 194).isActive = true
        } else { view.heightAnchor.constraint(equalToConstant: 1).isActive = true }
        return view
    }

    private func column(provider: Provider, state: ProviderState,
                        connectClaude: @escaping @MainActor () -> Void) -> NSStackView {
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 0
        let name = text(provider.name.uppercased(), size: 12, serif: true)
        name.alignment = .center
        let heading: NSView
        if provider == .claude && state.error != nil && !state.windows.isEmpty {
            let reconnect = ActionButton("연결", action: connectClaude)
            reconnect.isEnabled = !state.isLoading
            heading = row([name, reconnect], spacing: 3)
        } else {
            heading = row([name])
            name.widthAnchor.constraint(equalTo: heading.widthAnchor).isActive = true
        }
        add(heading, to: column)
        heading.heightAnchor.constraint(equalToConstant: 26).isActive = true

        column.setCustomSpacing(3, after: column.arrangedSubviews.last!)
        let orb = ResourceOrb(provider: provider, percent: state.representative?.remainingPercent)
        column.addArrangedSubview(orb)

        if let representative = state.representative {
            let scope = text(state.isStale ? "\(representative.label) · 마지막 값" : representative.label,
                             color: state.isStale ? .systemOrange : Palette.secondary)
            scope.alignment = .center
            scope.toolTip = state.isStale ? state.error ?? "갱신이 필요합니다." : nil
            add(scope, to: column)
            for (index, window) in state.windows.prefix(2).enumerated() {
                if index > 0 {
                    let amount = text("\(window.label) \(Int(window.remainingPercent.rounded()))%")
                    amount.alignment = .center
                    add(amount, to: column, top: 5)
                }
                let reset = text(resetLabel(window.resetsAt), color: Palette.secondary)
                reset.alignment = .center
                reset.toolTip = window.resetsAt?.formatted(date: .complete, time: .shortened)
                add(reset, to: column, top: 3)
            }
        } else {
            let message = state.isLoading ? "사용량을 가져오는 중…"
                : state.error ?? (provider == .claude ? "Claude Code 로그인 후 연결" : "Codex 로그인 확인 필요")
            let status = text(message, color: state.error == nil ? Palette.secondary : .systemOrange)
            status.alignment = .center
            status.toolTip = message
            status.maximumNumberOfLines = 2
            status.lineBreakMode = .byWordWrapping
            add(status, to: column, top: 6)
            let action = provider == .claude
                ? ActionButton("연결", action: connectClaude)
                : ActionButton("사용량 페이지") { NSWorkspace.shared.open(provider.usageURL) }
            action.isEnabled = !state.isLoading
            add(action, to: column, top: 4, widthRatio: provider == .claude ? 0.8 : 1)
        }
        return column
    }

    private func resetLabel(_ date: Date?) -> String {
        guard let date else { return "초기화 정보 없음" }
        guard date > Date() else { return "초기화됨 · 갱신 필요" }
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M/d HH:mm"
        return "\(formatter.string(from: date)) 초기화"
    }
}
