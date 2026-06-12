import CoreText
import SwiftUI

/// Registers the bundled display fonts at launch (no Info.plist required).
/// Fraunces is a variable font (OFL); if registration ever fails the Theme falls
/// back to the system serif, so type degrades gracefully rather than breaking.
enum FontLoader {
    private(set) static var frauncesAvailable = false

    static func registerBundledFonts() {
        for name in ["Fraunces", "Fraunces-Italic"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        frauncesAvailable = UIFont(name: "Fraunces", size: 17) != nil
            || UIFont.familyNames.contains(where: { $0.hasPrefix("Fraunces") })
    }
}
