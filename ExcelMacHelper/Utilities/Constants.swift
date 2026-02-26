import Foundation

enum Constants {
    static let appName = "ExcelMacHelper"
    static let bundleIdentifier = "com.excelmachelper.app"

    // Application Support paths
    static let appSupportDirectoryName = "ExcelMacHelper"
    static let shortcutsFileName = "shortcuts.json"
    static let bundledShortcutsFileName = "excel_alt_shortcuts"

    // Default monitored apps
    static let defaultMonitoredApps = ["Microsoft Excel"]

    // Excel bundle identifier
    static let excelBundleIdentifier = "com.microsoft.Excel"

    // Key Tips
    static let keyTipsTimeoutInterval: TimeInterval = 3.0

    // UserDefaults keys
    static let monitoredAppsKey = "monitoredApps"
    static let shortcutsFilePathKey = "shortcutsFilePath"
    static let hudOverlayEnabledKey = "hudOverlayEnabled"
    static let functionKeyToggleEnabledKey = "functionKeyToggleEnabled"
    static let keyTipsEnabledKey = "keyTipsEnabled"
    static let launchAtLoginKey = "launchAtLogin"

    /// Returns the Application Support directory for this app
    static var appSupportDirectory: URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(appSupportDirectoryName)
    }

    /// Returns the full path to the shortcuts JSON file
    static var shortcutsFilePath: URL {
        return appSupportDirectory.appendingPathComponent(shortcutsFileName)
    }
}
