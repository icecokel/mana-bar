import AppKit

@MainActor
enum PanelFont: String {
    case heading = "Cinzel-Regular"
    case body = "Pretendard-Regular"
    case amount = "Pretendard-SemiBold"

    func at(_ size: CGFloat) -> NSFont {
        guard let font = NSFont(name: rawValue, size: size) else {
            preconditionFailure("Missing bundled font: \(rawValue)")
        }
        guard self == .heading else { return font }
        // Cinzel is distributed as a variable font; select its SemiBold weight explicitly.
        let descriptor = font.fontDescriptor.addingAttributes([
            .variation: [NSNumber(value: 0x77676874): NSNumber(value: 600)]
        ])
        guard let semibold = NSFont(descriptor: descriptor, size: size) else {
            preconditionFailure("Could not select Cinzel SemiBold")
        }
        return semibold
    }
}
