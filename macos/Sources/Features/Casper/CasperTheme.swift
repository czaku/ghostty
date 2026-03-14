import AppKit

// MARK: - CasperTheme

/// The three visual themes for Casper. Each theme owns a background color,
/// accent color, and window tint overlay. Themes can be set per-window
/// independently of each other.
enum CasperTheme: String, CaseIterable, Codable {
    case wraith   = "wraith"    // Dark burgundy, amber wolf eyes
    case phantom  = "phantom"   // Deep navy, terminal blue
    case specter  = "specter"   // Deep purple, glowing violet

    // MARK: - Display

    var displayName: String {
        switch self {
        case .wraith:  "Wraith"
        case .phantom: "Phantom"
        case .specter: "Specter"
        }
    }

    // MARK: - Colors

    /// Terminal background hex — injected via OSC 11 when theme is applied.
    var backgroundHex: String {
        switch self {
        case .wraith:  "#0d0203"
        case .phantom: "#0a0e1a"
        case .specter: "#0d0820"
        }
    }

    var backgroundColor: NSColor {
        switch self {
        case .wraith:  NSColor(hex: "#0d0203")!
        case .phantom: NSColor(hex: "#0a0e1a")!
        case .specter: NSColor(hex: "#0d0820")!
        }
    }

    /// Accent used for activity border, action bar dot, and session banner.
    var accentColor: NSColor {
        switch self {
        case .wraith:  NSColor(hex: "#e08010")!   // amber
        case .phantom: NSColor(hex: "#4a8fff")!   // blue
        case .specter: NSColor(hex: "#b060f0")!   // purple
        }
    }

    /// Tint overlay on the window — visible enough to identify the theme at a glance.
    var tintColor: NSColor {
        accentColor.withAlphaComponent(0.18)
    }

    // MARK: - App Icon

    var iconImageName: String {
        "CasperIcons/\(rawValue)"
    }

    var iconImage: NSImage? {
        NSImage(named: iconImageName)
    }
}

// MARK: - CasperThemeManager

/// Manages the app icon and per-window theme assignments.
final class CasperThemeManager {
    static let shared = CasperThemeManager()
    private init() {}

    /// Apply a theme to a specific terminal controller.
    func apply(_ theme: CasperTheme, to controller: TerminalController) {
        controller.casperTheme = theme
    }

    /// Set the macOS app icon. macOS caches dock icons, so we force a refresh.
    func setAppIcon(_ theme: CasperTheme) {
        guard let image = theme.iconImage else { return }
        // Resize to standard icon size before setting
        let icon = NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { rect in
            image.draw(in: rect)
            return true
        }
        icon.setName(theme.iconImageName)
        NSApp.applicationIconImage = icon
        // Persist choice
        UserDefaults.standard.set(theme.rawValue, forKey: "casperAppIcon")
    }

    /// Restore the saved app icon on launch.
    func restoreAppIcon() {
        let saved = UserDefaults.standard.string(forKey: "casperAppIcon") ?? CasperTheme.wraith.rawValue
        let theme = CasperTheme(rawValue: saved) ?? .wraith
        setAppIcon(theme)
    }
}
