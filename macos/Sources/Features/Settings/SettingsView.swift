import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var ghostty: Ghostty.App

    var body: some View {
        TabView {
            CasperSettingsTab()
                .tabItem {
                    Label("Casper", systemImage: "sparkles")
                }

            ConfigFileTab()
                .tabItem {
                    Label("Config File", systemImage: "doc.text")
                }
        }
        .frame(minWidth: 480, idealWidth: 480, minHeight: 320, idealHeight: 320)
        .padding()
    }
}

// MARK: - Casper Settings Tab

private struct CasperSettingsTab: View {
    @EnvironmentObject private var ghostty: Ghostty.App
    @StateObject private var prefs = CasperPreferences()

    var body: some View {
        Form {
            // MARK: Appearance
            Section {
                HStack {
                    Text("App icon")
                    Picker("", selection: $prefs.appIcon) {
                        ForEach(CasperTheme.allCases, id: \.self) { theme in
                            HStack {
                                if let img = theme.iconImage {
                                    Image(nsImage: img)
                                        .resizable().frame(width: 20, height: 20)
                                }
                                Text(theme.displayName)
                            }.tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .onChange(of: prefs.appIcon) { newIcon in
                        CasperThemeManager.shared.setAppIcon(newIcon)
                    }
                }
                HStack {
                    Text("Default window theme")
                    Picker("", selection: $prefs.defaultTheme) {
                        ForEach(CasperTheme.allCases, id: \.self) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                Text("Each window can be switched independently using the theme button (W/P/S) in the action bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Appearance").font(.headline)
            }

            Divider()

            // MARK: Clipboard
            Section {
                Toggle("Strip code fences on paste", isOn: $prefs.stripCodeFences)
                Text("When you paste a markdown code block (e.g. copied from Claude), only the inner content is pasted — no backtick lines.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Clipboard").font(.headline)
            }

            Divider()

            // MARK: Editor
            Section {
                HStack {
                    Text("Open files in")
                    Picker("", selection: $prefs.openInEditor) {
                        Text("Cursor").tag("cursor")
                        Text("VS Code").tag("code")
                        Text("Zed").tag("zed")
                        Text("Neovim").tag("nvim")
                        Text("Vim").tag("vim")
                        Text("Default").tag("default")
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                Text("Used when you ⌘+click a file:line reference in the terminal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Editor").font(.headline)
            }

            Divider()

            // MARK: Session Management
            Section {
                Toggle("Auto-save session", isOn: $prefs.sessionAutoSave)

                if prefs.sessionAutoSave {
                    HStack {
                        Text("Save every")
                        TextField(
                            "",
                            value: $prefs.sessionAutoSaveInterval,
                            format: .number
                        )
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                        Text("seconds")
                            .foregroundStyle(.secondary)
                    }
                    Text("Minimum 30 seconds. Session is also saved on quit and window close.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Max scrollback")
                    TextField(
                        "",
                        value: $prefs.sessionMaxScrollback,
                        format: .number
                    )
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                    Text("lines per pane")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Keep sessions for")
                    TextField(
                        "",
                        value: $prefs.sessionRetentionDays,
                        format: .number
                    )
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                    Text("days")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto-replay commands")
                    TextField("e.g. claude,claude-*,nvim", text: $prefs.sessionReplayCommands)
                        .textFieldStyle(.roundedBorder)
                    Text("Comma-separated. Supports prefix wildcards (e.g. claude-*). These processes are automatically relaunched on session restore.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Session Management").font(.headline)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Save") {
                    prefs.save()
                    UserDefaults.standard.set(prefs.defaultTheme.rawValue, forKey: "casperDefaultTheme")
                    ghostty.reloadConfig()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
        }
        .formStyle(.grouped)
        .onAppear { prefs.load() }
    }
}

// MARK: - Config File Tab

private struct ConfigFileTab: View {
    @EnvironmentObject private var ghostty: Ghostty.App
    @StateObject private var prefs = CasperPreferences()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Config File")
                .font(.headline)

            GroupBox {
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                    Text(prefs.configFilePath.isEmpty ? "~/.config/casper/config.casper" : prefs.configFilePath)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Open in Editor") {
                        Ghostty.App.openConfig()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(4)
            }

            Text("All Casper and Ghostty settings can be set in this file. The GUI above manages the most common Casper-specific options. Changes to this file take effect after File > Reload Configuration (⌘⇧R).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GroupBox("Quick Reference") {
                VStack(alignment: .leading, spacing: 4) {
                    configHint("strip-code-fences = true", comment: "strip backtick fences on paste")
                    configHint("open-in-editor = cursor", comment: "cursor | code | zed | nvim | vim | default")
                    configHint("session-auto-save = true", comment: "auto-save session periodically")
                    configHint("session-auto-save-interval = 300", comment: "seconds between saves")
                    configHint("session-max-scrollback = 10000", comment: "lines saved per pane")
                    configHint("session-retention-days = 30", comment: "days to keep session files")
                    configHint("session-replay-commands = claude,claude-*,nvim", comment: "comma-separated, supports prefix-*")
                    configHint("theme = dark", comment: "color theme")
                    configHint("font-size = 14", comment: "font size in points")
                }
                .padding(4)
            }

            Spacer()
        }
        .onAppear { prefs.load() }
    }

    private func configHint(_ code: String, comment: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(code)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
            Text("  # \(comment)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(Ghostty.App())
}
