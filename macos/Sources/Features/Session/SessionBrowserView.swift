import SwiftUI

// MARK: - Session entry model

struct SessionEntry: Identifiable, Equatable, Hashable {
    var id: URL { url }
    let url: URL
    let name: String
    let savedAt: Date
    let windowCount: Int
    let surfaceCount: Int
    let replayCount: Int  // surfaces with a foreground AI process

    static func == (lhs: SessionEntry, rhs: SessionEntry) -> Bool {
        lhs.url == rhs.url
    }
}

// MARK: - Session Browser View

struct SessionBrowserView: View {
    let ghostty: Ghostty.App
    let onClose: () -> Void

    @State private var entries: [SessionEntry] = []
    @State private var selected: SessionEntry?
    @State private var searchText: String = ""

    private var filtered: [SessionEntry] {
        guard !searchText.isEmpty else { return entries }
        return entries.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search sessions", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.regularMaterial)
            .overlay(alignment: .bottom) {
                Divider()
            }

            // Session list
            if filtered.isEmpty {
                Spacer()
                if entries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No saved sessions")
                            .foregroundStyle(.secondary)
                        Text("Use File > Save Session (⌘⇧S) to save your current layout.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    Text("No sessions match \"\(searchText)\"")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List(filtered, selection: $selected) { entry in
                    SessionRowView(entry: entry)
                        .tag(entry)
                        .onTapGesture(count: 2) {
                            restore(entry)
                        }
                }
                .listStyle(.inset)
            }

            Divider()

            // Bottom toolbar
            HStack {
                if let sel = selected {
                    Button("Delete") {
                        delete(sel)
                    }
                    .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Restore") {
                    if let sel = selected { restore(sel) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected == nil)
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .onAppear { reload() }
    }

    // MARK: - Actions

    private func reload() {
        entries = SessionManager.shared.listSessions().compactMap { nameURL in
            guard let data = try? SessionManager.shared.loadSession(url: nameURL.url) else { return nil }
            let surfaces = data.windows.flatMap { $0.surfaces }
            let replayCount = surfaces.filter { $0.foregroundProcess != nil }.count
            return SessionEntry(
                url: nameURL.url,
                name: nameURL.name,
                savedAt: data.savedAt,
                windowCount: data.windows.count,
                surfaceCount: surfaces.count,
                replayCount: replayCount
            )
        }
        // Pre-select the first entry
        if selected == nil { selected = entries.first }
    }

    private func restore(_ entry: SessionEntry) {
        guard let session = try? SessionManager.shared.loadSession(url: entry.url) else { return }

        // Build summary and confirm
        let surfaces = session.windows.flatMap { $0.surfaces }
        let replay = surfaces.filter { $0.foregroundProcess != nil }.count
        let msg = "\(session.windows.count) window\(session.windows.count == 1 ? "" : "s"), \(surfaces.count) pane\(surfaces.count == 1 ? "" : "s")\(replay > 0 ? " · \(replay) AI session\(replay == 1 ? "" : "s") will relaunch" : "")"

        let alert = NSAlert()
        alert.messageText = "Restore \"\(entry.name)\"?"
        alert.informativeText = msg
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        SessionManager.shared.restoreSession(session, ghostty: ghostty)
        onClose()
    }

    private func delete(_ entry: SessionEntry) {
        let alert = NSAlert()
        alert.messageText = "Delete \"\(entry.name)\"?"
        alert.informativeText = "This cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        try? FileManager.default.removeItem(at: entry.url)
        if selected == entry { selected = nil }
        reload()
    }
}

// MARK: - Row View

private struct SessionRowView: View {
    let entry: SessionEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text("\(entry.savedAt, style: .relative) ago")
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(entry.windowCount)W \(entry.surfaceCount)P")
                    if entry.replayCount > 0 {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Label("\(entry.replayCount) AI", systemImage: "sparkles")
                            .foregroundStyle(.blue)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}
