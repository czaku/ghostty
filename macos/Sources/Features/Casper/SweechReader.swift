import Foundation

/// Reads Sweech profile configuration from ~/.sweech/config.json.
///
/// Sweech manages multiple Claude/AI CLI profiles. When a `claude-*` process is
/// detected, we look up its profile to enrich the saved session with provider
/// and model metadata, and to resolve the config directory used on restore.
struct SweechProfile: Codable {
    let name: String
    let commandName: String
    let cliType: String
    let provider: String
    let baseUrl: String?
    let model: String?
    let smallFastModel: String?
    let sharedWith: String?
}

enum SweechReader {

    private static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".sweech/config.json")
    }

    /// All profiles from ~/.sweech/config.json, or empty if the file doesn't exist.
    static func profiles() -> [SweechProfile] {
        guard let data = try? Data(contentsOf: configURL) else { return [] }
        return (try? JSONDecoder().decode([SweechProfile].self, from: data)) ?? []
    }

    /// Returns the profile whose `commandName` matches, e.g. "claude-pole".
    static func profile(forCommand commandName: String) -> SweechProfile? {
        profiles().first { $0.commandName == commandName }
    }

    /// Returns the config directory path that the Sweech wrapper injects as
    /// `CLAUDE_CONFIG_DIR`. Sweech places profile dirs at `~/.{commandName}`,
    /// e.g. `~/.claude-pole`. Returns nil if no profile matches.
    static func configDir(forCommand commandName: String) -> String? {
        guard profiles().contains(where: { $0.commandName == commandName }) else { return nil }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".\(commandName)")
            .path
    }
}
