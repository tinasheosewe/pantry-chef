import Foundation

/// Toggles the Kitchen Timeline redesign root. Defaults on for this branch; the
/// legacy app remains one flag away while the redesign is wired to real data.
enum RedesignFlags {
    private static let key = "redesign.useKitchenTimeline"

    static var useRedesign: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
