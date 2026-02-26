import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ShortcutsSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            AppsSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Apps", systemImage: "app.badge")
                }

            AccessibilitySettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Accessibility", systemImage: "lock.shield")
                }
        }
        .frame(width: 520, height: 420)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section {
                Toggle("Enable Function Key Toggle", isOn: $appState.functionKeyToggleEnabled)
                    .help("When enabled, F1-F12 act as standard function keys in monitored apps")

                Toggle("Enable Alt-Key Shortcuts", isOn: $appState.keyTipsEnabled)
                    .help("When enabled, Windows-style Alt+Key shortcuts work in Excel")

                Toggle("Show HUD Overlay", isOn: $appState.hudOverlayEnabled)
                    .help("Display a visual overlay showing available Key Tips")

                Toggle("Launch at Login", isOn: $appState.launchAtLogin)
                    .help("Automatically start ExcelMacHelper when you log in")
            } header: {
                Text("Features")
            }

            Section {
                HStack {
                    Circle()
                        .fill(appState.isActive ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                    Text(appState.statusMessage)
                        .font(.subheadline)
                }

                HStack {
                    Text("Frontmost App:")
                        .foregroundColor(.secondary)
                    Text(appState.activeAppMonitor.frontmostAppName)
                        .font(.subheadline)
                }

                HStack {
                    Text("Excel is frontmost:")
                        .foregroundColor(.secondary)
                    Text(appState.activeAppMonitor.isExcelFrontmost ? "Yes" : "No")
                        .font(.subheadline)
                        .foregroundColor(appState.activeAppMonitor.isExcelFrontmost ? .green : .secondary)
                }
            } header: {
                Text("Status")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Shortcuts Settings

struct ShortcutsSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var customPath: String = ""
    @State private var showFilePicker = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Shortcuts Loaded:")
                        .foregroundColor(.secondary)
                    Text("\(appState.shortcutManager.shortcutCount)")
                        .font(.headline)
                }

                if let error = appState.shortcutManager.lastError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            } header: {
                Text("Status")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current file:")
                        .foregroundColor(.secondary)
                    Text(appState.shortcutManager.shortcutsFilePath().path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)

                    HStack {
                        TextField("Custom path (leave empty for default)", text: $customPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))

                        Button("Browse...") {
                            browseForFile()
                        }
                    }

                    HStack {
                        Button("Set Custom Path") {
                            appState.shortcutManager.setCustomPath(customPath.isEmpty ? nil : customPath)
                        }

                        Button("Reset to Default") {
                            customPath = ""
                            appState.shortcutManager.setCustomPath(nil)
                        }

                        Spacer()

                        Button(action: {
                            appState.shortcutManager.reload()
                        }) {
                            Label("Reload", systemImage: "arrow.clockwise")
                        }
                    }
                }
            } header: {
                Text("Shortcuts File")
            }

            Section {
                Text("The shortcuts JSON file is stored at:\n~/Library/Application Support/ExcelMacHelper/shortcuts.json\n\nYou can edit this file to add custom shortcuts. Use the Reload button after making changes.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Help")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func browseForFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK {
            if let url = panel.url {
                customPath = url.path
            }
        }
    }
}

// MARK: - Apps Settings

struct AppsSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var newAppName: String = ""

    var body: some View {
        Form {
            Section {
                Text("Function keys (F1-F12) will act as standard function keys instead of media keys when these apps are frontmost.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                List {
                    ForEach(appState.monitoredApps, id: \.self) { app in
                        HStack {
                            Text(app)
                            Spacer()
                            if app != "Microsoft Excel" {
                                Button(action: {
                                    removeApp(app)
                                }) {
                                    Image(systemName: "minus.circle")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(height: 150)

                HStack {
                    TextField("Application name", text: $newAppName)
                        .textFieldStyle(.roundedBorder)

                    Button("Add") {
                        addApp()
                    }
                    .disabled(newAppName.isEmpty)
                }
            } header: {
                Text("Monitored Applications")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func addApp() {
        let trimmed = newAppName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !appState.monitoredApps.contains(trimmed) else { return }
        appState.monitoredApps.append(trimmed)
        newAppName = ""
    }

    private func removeApp(_ app: String) {
        appState.monitoredApps.removeAll { $0 == app }
    }
}

// MARK: - Accessibility Settings

struct AccessibilitySettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: appState.accessibilityManager.isAccessibilityGranted
                          ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(appState.accessibilityManager.isAccessibilityGranted ? .green : .red)
                        .font(.title2)

                    VStack(alignment: .leading) {
                        Text(appState.accessibilityManager.isAccessibilityGranted
                             ? "Accessibility Access Granted"
                             : "Accessibility Access Required")
                            .font(.headline)

                        Text(appState.accessibilityManager.isAccessibilityGranted
                             ? "ExcelMacHelper can intercept keyboard events."
                             : "ExcelMacHelper needs Accessibility access to function.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if !appState.accessibilityManager.isAccessibilityGranted {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Setup Instructions:")
                            .font(.headline)

                        InstructionRow(number: 1, text: "Click \"Open System Settings\" below")
                        InstructionRow(number: 2, text: "Find ExcelMacHelper in the list")
                        InstructionRow(number: 3, text: "Toggle the switch to enable access")
                        InstructionRow(number: 4, text: "If prompted, enter your password")
                        InstructionRow(number: 5, text: "The app will start working automatically")

                        Button("Open System Settings") {
                            appState.accessibilityManager.requestPermissions()
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)

                        Button("Check Again") {
                            appState.accessibilityManager.checkPermissions()
                        }
                        .padding(.top, 4)
                    }
                } header: {
                    Text("Setup")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct InstructionRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.accentColor)
                .frame(width: 20, alignment: .trailing)
            Text(text)
                .font(.body)
        }
    }
}

import UniformTypeIdentifiers
