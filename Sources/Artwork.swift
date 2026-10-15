import AppKit

@MainActor
enum Palette {
    static let background = NSColor(srgbRed: 14 / 255, green: 15 / 255, blue: 13 / 255, alpha: 1)
    static let text = NSColor(srgbRed: 220 / 255, green: 212 / 255, blue: 190 / 255, alpha: 1)
    static let secondary = NSColor(srgbRed: 183 / 255, green: 180 / 255, blue: 166 / 255, alpha: 1)
    static let line = NSColor(srgbRed: 73 / 255, green: 65 / 255, blue: 55 / 255, alpha: 1)
    static let metal = NSColor(srgbRed: 113 / 255, green: 100 / 255, blue: 83 / 255, alpha: 1)

}

@MainActor
enum GameArt {
    static let stone = image("panel-stone")
    static let emptyOrb = image("orb-empty")
    static let ember = image("orb-ember")
    static let mana = image("orb-mana")

    private static func image(_ name: String) -> NSImage {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing bundled artwork: \(name)")
        }
        return image
    }
}

@MainActor
final class ResourceOrb: NSView {
    let provider: Provider
    let percent: Double?

    init(provider: Provider, percent: Double?) {
        self.provider = provider
        self.percent = percent
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: 105.8), heightAnchor.constraint(equalToConstant: 101.2)])
        setAccessibilityElement(true)
        setAccessibilityLabel("\(provider.name) 잔여 사용량")
        setAccessibilityValue(percent.map { "\(Int($0.rounded()))퍼센트" } ?? "미연결")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func draw(_ dirtyRect: NSRect) {
        // Source sprite coordinates keep the ornaments at 60% and the globe at 110% independently.
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.scaleX(by: bounds.width / 113, yBy: bounds.height / 109)
        transform.concat()
        GameArt.emptyOrb.draw(in: NSRect(x: 6.9, y: 51.4, width: 15, height: 41.4),
                              from: NSRect(x: 0, y: 40, width: 25, height: 69), operation: .sourceOver, fraction: 1)
        GameArt.emptyOrb.draw(in: NSRect(x: 90.1, y: 51.4, width: 15.6, height: 41.4),
                              from: NSRect(x: 87, y: 40, width: 26, height: 69), operation: .sourceOver, fraction: 1)
        GameArt.emptyOrb.draw(in: NSRect(x: 37.4, y: 11.9, width: 37.2, height: 24),
                              from: NSRect(x: 25, y: 0, width: 62, height: 40), operation: .sourceOver, fraction: 1)

        let imageFrame = NSRect(x: -5.6, y: -8.1, width: 124.3, height: 119.9)
        let globe = NSRect(x: 21.9, y: 35.9, width: 68.2, height: 68.2)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: globe.insetBy(dx: -4.4, dy: -4.4)).addClip()
        GameArt.emptyOrb.draw(in: imageFrame)
        NSGraphicsContext.restoreGraphicsState()
        let sphere = NSBezierPath(ovalIn: globe)

        if let percent {
            NSGraphicsContext.saveGraphicsState()
            sphere.addClip()
            let liquid = NSRect(x: globe.minX, y: globe.minY, width: globe.width,
                                height: globe.height * max(0, min(1, percent / 100)))
            if !liquid.isEmpty {
                NSBezierPath(rect: liquid).addClip()
                (provider == .claude ? GameArt.ember : GameArt.mana).draw(in: imageFrame)
            }
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.saveGraphicsState()
            sphere.addClip()
            GameArt.emptyOrb.draw(in: imageFrame, from: .zero, operation: .screen, fraction: 0.5)
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.restoreGraphicsState()
        let interior = NSRect(x: globe.minX * bounds.width / 113, y: globe.minY * bounds.height / 109,
                              width: globe.width * bounds.width / 113, height: globe.height * bounds.height / 109)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        let label = NSAttributedString(string: percent.map { "\(Int($0.rounded()))%" } ?? "—", attributes: [
            .font: PanelFont.amount.at(18),
            .foregroundColor: NSColor(white: 0.97, alpha: 1), .shadow: shadow,
        ])
        let size = label.size()
        label.draw(at: NSPoint(x: interior.midX - size.width / 2, y: interior.midY - size.height / 2))
    }
}

@MainActor
enum MenuBarHUD {
    static func image(states: [Provider: ProviderState]) -> NSImage {
        let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let labels = Provider.allCases.map { provider in
            let state = states[provider] ?? ProviderState()
            let color: NSColor
            if provider == .claude {
                color = dark
                    ? NSColor(srgbRed: 0.95, green: 0.65, blue: 0.43, alpha: 1)
                    : NSColor(srgbRed: 0.60, green: 0.28, blue: 0.11, alpha: 1)
            } else {
                color = dark
                    ? NSColor(srgbRed: 0.54, green: 0.72, blue: 0.95, alpha: 1)
                    : NSColor(srgbRed: 0.13, green: 0.37, blue: 0.62, alpha: 1)
            }
            return NSAttributedString(string: state.menuText, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: color,
            ])
        }
        let slotWidth: CGFloat = 42
        let gap: CGFloat = 4
        let image = NSImage(size: NSSize(width: 90, height: 22), flipped: false) { _ in
            for (index, label) in labels.enumerated() {
                let size = label.size()
                label.draw(at: NSPoint(x: 1 + CGFloat(index) * (slotWidth + gap) + (slotWidth - size.width) / 2,
                                       y: (22 - size.height) / 2))
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
