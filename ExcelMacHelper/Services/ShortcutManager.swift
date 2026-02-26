import Foundation

/// Manages loading and saving the shortcuts JSON file
class ShortcutManager: ObservableObject {
    @Published var shortcutTree = ShortcutTree()
    @Published var shortcutCount: Int = 0
    @Published var lastError: String?

    /// Initialize and load shortcuts
    func initialize() {
        ensureAppSupportDirectory()
        updateBundledShortcutsIfNewer()
        loadShortcuts()
    }

    /// Ensure the Application Support directory exists
    private func ensureAppSupportDirectory() {
        let dir = Constants.appSupportDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                Logger.log("Created Application Support directory at \(dir.path)")
            } catch {
                Logger.error("Failed to create Application Support directory: \(error)")
            }
        }
    }

    /// Copy bundled shortcuts to Application Support, replacing older versions.
    /// The bundled copy is always authoritative unless the user has set a custom path.
    private func updateBundledShortcutsIfNewer() {
        // If a custom path is set, don't overwrite anything
        if let customPath = UserDefaults.standard.string(forKey: Constants.shortcutsFilePathKey),
           !customPath.isEmpty {
            Logger.log("Custom shortcuts path set, skipping bundle update")
            return
        }

        let destination = Constants.shortcutsFilePath

        guard let bundledURL = Bundle.main.url(forResource: Constants.bundledShortcutsFileName, withExtension: "json") else {
            Logger.error("Bundled shortcuts file not found in app bundle")
            return
        }

        // Always overwrite the Application Support copy with the latest bundle version.
        // This ensures shortcut updates in new builds take effect immediately.
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: bundledURL, to: destination)
            Logger.log("Updated shortcuts from bundle to \(destination.path)")
        } catch {
            Logger.error("Failed to update shortcuts from bundle: \(error)")
        }
    }

    /// Get the current shortcuts file path
    func shortcutsFilePath() -> URL {
        if let customPath = UserDefaults.standard.string(forKey: Constants.shortcutsFilePathKey),
           !customPath.isEmpty {
            return URL(fileURLWithPath: customPath)
        }
        return Constants.shortcutsFilePath
    }

    /// Load shortcuts from disk
    func loadShortcuts() {
        let filePath = shortcutsFilePath()
        lastError = nil

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            lastError = "Shortcuts file not found at \(filePath.path)"
            Logger.error(lastError!)
            return
        }

        do {
            let data = try Data(contentsOf: filePath)
            let decoder = JSONDecoder()
            let file = try decoder.decode(ShortcutsFile.self, from: data)

            let tree = ShortcutTree()
            tree.build(from: file)

            DispatchQueue.main.async {
                self.shortcutTree = tree
                self.shortcutCount = tree.allShortcuts.count
                Logger.log("Loaded \(tree.allShortcuts.count) shortcuts from \(filePath.path)")
            }
        } catch {
            lastError = "Failed to parse shortcuts: \(error.localizedDescription)"
            Logger.error(lastError!)
        }
    }

    /// Reload shortcuts from disk
    func reload() {
        Logger.log("Reloading shortcuts...")
        loadShortcuts()
    }

    /// Update the custom shortcuts file path
    func setCustomPath(_ path: String?) {
        if let path = path, !path.isEmpty {
            UserDefaults.standard.set(path, forKey: Constants.shortcutsFilePathKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Constants.shortcutsFilePathKey)
        }
        reload()
    }
}
