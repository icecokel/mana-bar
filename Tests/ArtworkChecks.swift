import AppKit

@MainActor
func checkMenuBarHUD() throws {
    _ = NSApplication.shared
    func render(_ remaining: Double?, error: String? = nil,
                appearance: NSAppearance.Name = .aqua) throws -> NSBitmapImageRep {
        let windows = remaining.map {
            [UsageWindow(id: "primary", label: "주간", usedPercent: 100 - $0, resetsAt: nil)]
        } ?? []
        var bitmap: NSBitmapImageRep?
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            let state = ProviderState(windows: windows, updatedAt: Date(), error: error)
            let image = MenuBarHUD.image(states: [.claude: state, .codex: state])
            assert(!image.isTemplate)
            assert(image.size.height == 22 && image.size.width > 0 && image.size.width <= 90)
            if let data = image.tiffRepresentation { bitmap = NSBitmapImageRep(data: data) }
        }
        guard let bitmap else {
            throw UsageFailure(message: "Could not render menu bar HUD")
        }
        return bitmap
    }

    func color(_ bitmap: NSBitmapImageRep, x: Int, y: Int) -> NSColor {
        bitmap.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
    }
    func glyphs(_ bitmap: NSBitmapImageRep, half: Int) -> [NSColor] {
        let start = half * bitmap.pixelsWide / 2
        let end = (half + 1) * bitmap.pixelsWide / 2
        return (start..<end).flatMap { x in
            (0..<bitmap.pixelsHigh).map { color(bitmap, x: x, y: $0) }
        }.filter { $0.alphaComponent > 0.2 }
    }
    func mask(_ bitmap: NSBitmapImageRep, half: Int) -> [Bool] {
        let start = half * bitmap.pixelsWide / 2
        let end = (half + 1) * bitmap.pixelsWide / 2
        return (start..<end).flatMap { x in
            (0..<bitmap.pixelsHigh).map { color(bitmap, x: x, y: $0).alphaComponent > 0.2 }
        }
    }
    func transparentEdgesAndGap(_ bitmap: NSBitmapImageRep) {
        for x in 0..<bitmap.pixelsWide {
            assert(color(bitmap, x: x, y: 0).alphaComponent == 0)
            assert(color(bitmap, x: x, y: bitmap.pixelsHigh - 1).alphaComponent == 0)
        }
        for y in 0..<bitmap.pixelsHigh {
            for x in [0, bitmap.pixelsWide / 2, bitmap.pixelsWide - 1] {
                assert(color(bitmap, x: x, y: y).alphaComponent == 0)
            }
        }
    }

    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
        let full = try render(100, appearance: appearance)
        let unknown = try render(nil, appearance: appearance)
        let zero = try render(0, appearance: appearance)
        let stale = try render(100, error: "오프라인", appearance: appearance)
        for bitmap in [full, unknown, zero, stale] { transparentEdgesAndGap(bitmap) }

        for half in 0..<2 {
            for bitmap in [full, unknown, zero, stale] {
                let pixels = glyphs(bitmap, half: half)
                assert(!pixels.isEmpty)
                let red = pixels.reduce(CGFloat.zero) { $0 + $1.redComponent }
                let blue = pixels.reduce(CGFloat.zero) { $0 + $1.blueComponent }
                assert(half == 0 ? red > blue : blue > red)
            }
            assert(mask(unknown, half: half) != mask(zero, half: half))
            assert(mask(stale, half: half) != mask(full, half: half))
            assert(glyphs(stale, half: half).count > glyphs(full, half: half).count)
        }
    }
}
