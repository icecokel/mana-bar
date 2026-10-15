import AppKit
import CoreText

@MainActor
func checkPanelFonts() throws {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Assets/Fonts", isDirectory: true)
    let fonts = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { ["ttf", "otf"].contains($0.pathExtension.lowercased()) }
    assert(fonts.count >= 3)
    for url in fonts {
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            let registrationError = error?.takeRetainedValue()
            guard registrationError.map({ CFErrorGetCode($0) }) == CTFontManagerError.alreadyRegistered.rawValue else {
                throw UsageFailure(message: "Could not register bundled font: \(url.lastPathComponent)")
            }
        }
    }

    let heading = PanelFont.heading.at(14)
    assert(heading.familyName == "Cinzel")
    let variations = CTFontCopyVariation(heading as CTFont) as? [NSNumber: NSNumber]
    assert(variations?[NSNumber(value: 0x77676874)]?.doubleValue == 600)

    let body = PanelFont.body.at(12)
    assert(body.fontName == "Pretendard-Regular")
    assert(PanelFont.amount.at(18).fontName == "Pretendard-SemiBold")
    let characters = Array("주간 초기화 연결0123456789%".utf16)
    var glyphs = [CGGlyph](repeating: 0, count: characters.count)
    assert(CTFontGetGlyphsForCharacters(body as CTFont, characters, &glyphs, characters.count))
    assert(glyphs.allSatisfy { $0 != 0 })
}
