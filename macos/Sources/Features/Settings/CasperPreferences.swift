import Foundation
import GhosttyKit
import OSLog

/// Reads and writes Casper-specific settings directly in the config file.
///
/// The config file format is `key = value` per line with `#` comments.
/// We parse known keys on init, expose @Published properties for UI binding,
/// and write changed values back on save, then reload the running config.
final class CasperPreferences: ObservableObject {
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CasperPreferences")

    // MARK: - Casper settings

    @Published var appIcon: CasperTheme = .wraith
    @Published var defaultTheme: CasperTheme = .wraith
    @Published var stripCodeFences: Bool = true
    @Published var openInEditor: String = "cursor"
    @Published var askAICommand: String = "claude"
    @Published var startupLayout: String = ""
    @Published var sessionAutoSave: Bool = false
    @Published var sessionAutoSaveInterval: Int = 300
    @Published var sessionMaxScrollback: Int = 10_000
    @Published var sessionRetentionDays: Int = 30
    @Published var sessionReplayCommands: String = "claude,claude-*,nvim,vim,lazygit,hx"

    // MARK: - Config file metadata

    @Published private(set) var configFilePath: String = ""
    private var fileLines: [String] = []

    // MARK: - Init

    init() {
        load()
    }

    // MARK: - Load

    func load() {
        let path = resolveConfigPath()
        configFilePath = path
        guard !path.isEmpty, let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return
        }
        fileLines = content.components(separatedBy: "\n")
        appIcon       = CasperTheme(rawValue: value(for: "app-icon") ?? "wraith") ?? .wraith
        defaultTheme  = CasperTheme(rawValue: value(for: "default-theme") ?? "wraith") ?? .wraith
        stripCodeFences         = bool(for: "strip-code-fences") ?? true
        openInEditor            = value(for: "open-in-editor") ?? "cursor"
        askAICommand            = value(for: "ask-ai-command") ?? "claude"
        startupLayout           = value(for: "startup-layout") ?? ""
        sessionAutoSave         = bool(for: "session-auto-save") ?? false
        sessionAutoSaveInterval = int(for: "session-auto-save-interval") ?? 300
        sessionMaxScrollback    = int(for: "session-max-scrollback") ?? 10_000
        sessionRetentionDays    = int(for: "session-retention-days") ?? 30
        sessionReplayCommands   = value(for: "session-replay-commands") ?? "claude,claude-*,nvim,vim,lazygit,hx"
    }

    // MARK: - Save

    /// Writes changed values back to the config file and notifies the caller to reload.
    func save() {
        set("app-icon",                   to: appIcon.rawValue)
        set("default-theme",              to: defaultTheme.rawValue)
        set("strip-code-fences",          to: stripCodeFences ? "true" : "false")
        set("open-in-editor",             to: openInEditor.trimmingCharacters(in: .whitespaces))
        set("ask-ai-command",             to: askAICommand.trimmingCharacters(in: .whitespaces))
        set("startup-layout",             to: startupLayout.trimmingCharacters(in: .whitespaces))
        set("session-auto-save",          to: sessionAutoSave ? "true" : "false")
        set("session-auto-save-interval", to: "\(max(30, sessionAutoSaveInterval))")
        set("session-max-scrollback",     to: "\(max(100, sessionMaxScrollback))")
        set("session-retention-days",     to: "\(max(1, sessionRetentionDays))")
        set("session-replay-commands",    to: sessionReplayCommands.trimmingCharacters(in: .whitespaces))

        let content = fileLines.joined(separator: "\n")
        let path = configFilePath.isEmpty ? resolveConfigPath() : configFilePath
        guard !path.isEmpty else {
            Self.logger.error("Cannot save: config path is empty")
            return
        }
        do {
            // Ensure the directory exists
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: path).deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            Self.logger.info("Preferences saved to \(path)")
        } catch {
            Self.logger.error("Failed to save preferences: \(error)")
        }
    }

    // MARK: - Parsing helpers

    private func bool(for key: String) -> Bool? {
        guard let raw = value(for: key) else { return nil }
        switch raw.lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return nil
        }
    }

    private func int(for key: String) -> Int? {
        guard let raw = value(for: key) else { return nil }
        return Int(raw.trimmingCharacters(in: .whitespaces))
    }

    private func value(for key: String) -> String? {
        for line in fileLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), trimmed.hasPrefix(key) else { continue }
            let rest = trimmed.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
            guard rest.hasPrefix("=") else { continue }
            return String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private func set(_ key: String, to newValue: String) {
        // Look for an existing uncommented line to update
        for (i, line) in fileLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), trimmed.hasPrefix(key) else { continue }
            let rest = trimmed.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
            guard rest.hasPrefix("=") else { continue }
            fileLines[i] = "\(key) = \(newValue)"
            return
        }
        // Key not found — append it with a blank line separator
        if fileLines.last?.isEmpty == false { fileLines.append("") }
        fileLines.append("\(key) = \(newValue)")
    }

    // MARK: - Config path resolution

    private func resolveConfigPath() -> String {
        // Primary: use the path Ghostty itself resolved (via C API)
        let resolved = Ghostty.AllocatedString(ghostty_config_open_path()).string
        if !resolved.isEmpty { return resolved }

        // Fallback: standard XDG location for Casper
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/casper/config.casper"
    }
}
