import Foundation

/// Manages loading and saving the shortcuts JSON file
class ShortcutManager: ObservableObject {
    @Published var shortcutTree = ShortcutTree()
    @Published var shortcutCount: Int = 0
    @Published var lastError: String?

    /// Initialize and load shortcuts
    func initialize() {
        ensureAppSupportDirectory()
        copyBundledShortcutsIfNeeded()
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

    /// Copy bundled shortcuts JSON to Application Support on first launch
    private func copyBundledShortcutsIfNeeded() {
        let destination = shortcutsFilePath()

        // Only copy if the file doesn't already exist
        if FileManager.default.fileExists(atPath: destination.path) {
            Logger.log("Shortcuts file already exists at \(destination.path)")
            return
        }

        guard let bundledURL = Bundle.main.url(forResource: Constants.bundledShortcutsFileName, withExtension: "json") else {
            Logger.error("Bundled shortcuts file not found in app bundle")
            return
        }

        do {
            try FileManager.default.copyItem(at: bundledURL, to: destination)
            Logger.log("Copied bundled shortcuts to \(destination.path)")
        } catch {
            Logger.error("Failed to copy bundled shortcuts: \(error)")
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
