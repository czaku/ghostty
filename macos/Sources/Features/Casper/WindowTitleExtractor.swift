import Foundation

/// Extracts meaningful titles from terminal output for window labelling
/// and notification context.
enum WindowTitleExtractor {

    // MARK: - Claude Code task description

    /// Scans terminal text for the most recent Claude Code task bullet ("● …").
    /// These lines look like:
    ///   ● Running: git status
    ///   ● Read file src/main.swift
    ///   ● Bash(npm install)
    ///
    /// Returns the text after "●", trimmed, max 80 chars.
    static func claudeTask(from text: String) -> String? {
        let lines = text.components(separatedBy: "\n").reversed()
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Claude Code action bullet
            if trimmed.hasPrefix("●") {
                let content = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                guard !content.isEmpty else { continue }
                let truncated = content.count > 80 ? String(content.prefix(77)) + "…" : content
                return truncated
            }
            // Claude Code conversation title: shown as a dimmed line at session start
            // e.g. "> Task: Fix the login bug"
            if trimmed.hasPrefix("> Task:") || trimmed.hasPrefix("◇") {
                let content = trimmed
                    .drop(while: { "◇>".contains($0) })
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "Task:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                guard !content.isEmpty else { continue }
                return content.count > 80 ? String(content.prefix(77)) + "…" : content
            }
        }
        return nil
    }

    // MARK: - Git context

    /// Runs `git` synchronously in the given directory to get `repo · branch`.
    /// Returns nil if not a git repo or git is unavailable.
    /// Call off the main thread.
    static func gitContext(inDirectory cwd: String) -> String? {
        guard let branch = git(["rev-parse", "--abbrev-ref", "HEAD"], cwd: cwd),
              !branch.isEmpty, branch != "HEAD"
        else { return nil }
        // Repo name from remote or directory name
        let repoName: String
        if let remote = git(["remote", "get-url", "origin"], cwd: cwd) {
            // strip .git suffix and take last path component
            repoName = remote
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "/").last?
                .replacingOccurrences(of: ".git", with: "") ?? URL(fileURLWithPath: cwd).lastPathComponent
        } else {
            repoName = URL(fileURLWithPath: cwd).lastPathComponent
        }
        return "\(repoName) · \(branch)"
    }

    // MARK: - Combined title

    /// Returns the best available title for a window, in priority order:
    /// 1. Claude Code task description (from visible terminal text)
    /// 2. Git repo + branch
    /// 3. nil (caller should keep the existing title)
    static func derivedTitle(terminalText: String, cwd: String?) -> String? {
        if let task = claudeTask(from: terminalText) { return task }
        if let cwd, let git = gitContext(inDirectory: cwd) { return git }
        return nil
    }

    // MARK: - Private

    private static func git(_ args: [String], cwd: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = args
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
