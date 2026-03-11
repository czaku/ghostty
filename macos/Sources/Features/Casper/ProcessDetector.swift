import Foundation
import Darwin.sys.proc_info

/// Detects running user processes for session save/restore.
///
/// At save time, for each terminal surface we search for a running process
/// whose current working directory matches the surface's cwd and whose name
/// appears on the replayable whitelist. On restore, that process is re-launched
/// automatically so the user lands back in the right tool without manual setup.
///
/// The whitelist supports exact names and simple glob prefixes (e.g. "claude-*").
/// Processes NOT on the list are never auto-replayed — fresh prompt only.
enum ProcessDetector {

    // MARK: - Whitelist

    /// Commands that are safe to auto-replay on session restore.
    /// Add entries here to extend the list; supports "prefix-*" glob syntax.
    static let replayablePatterns: [String] = [
        "claude",      // Claude Code (replay with --continue)
        "claude-*",    // Project-specific Claude wrappers (e.g. claude-edge)
        "nvim",
        "vim",
        "lazygit",
        "hx",          // Helix editor
    ]

    // MARK: - Detection

    /// Searches all running processes for a replayable command whose working
    /// directory matches `cwd`. Returns the process name, or nil if none found.
    ///
    /// Matches by cwd so multiple Claude sessions in different directories are
    /// each correctly identified.
    static func replayableProcess(inDirectory cwd: String) -> String? {
        for pid in allPids() {
            guard let name = processName(for: pid),
                  matches(name, patterns: replayablePatterns),
                  let processCwd = workingDirectory(for: pid),
                  processCwd == cwd
            else { continue }
            return name
        }
        return nil
    }

    // MARK: - Restore command

    /// Returns the shell command string used to restore a process.
    ///
    /// - `claude`     → `claude --continue`  (resumes last conversation in cwd)
    /// - `claude-*`   → the script name as-is (wrapper handles its own setup)
    /// - Everything else → command name with no extra args
    static func restoreCommand(for processName: String) -> String {
        if processName == "claude" {
            return "claude --continue"
        }
        // claude-* wrappers, editors, lazygit: re-run unchanged
        return processName
    }

    // MARK: - Pattern matching

    static func matches(_ name: String, patterns: [String]) -> Bool {
        patterns.contains { pattern in
            if pattern.hasSuffix("*") {
                return name.hasPrefix(String(pattern.dropLast()))
            }
            return name == pattern
        }
    }

    // MARK: - Private macOS proc_info wrappers

    private static func allPids() -> [pid_t] {
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(needed))
        proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, needed)
        return pids.filter { $0 > 0 }
    }

    private static func processName(for pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buf, UInt32(256)) > 0 else { return nil }
        return String(cString: buf)
    }

    private static func workingDirectory(for pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) > 0 else { return nil }
        // vip_path is a fixed-size C array (char[MAXPATHLEN]) — read as bytes
        return withUnsafeBytes(of: info.pvi_cdir.vip_path) { ptr -> String? in
            guard let base = ptr.baseAddress else { return nil }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
    }
}
