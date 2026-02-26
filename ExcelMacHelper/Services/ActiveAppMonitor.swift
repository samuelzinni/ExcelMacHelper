import Cocoa
import Combine

/// Monitors the frontmost application and reports changes
class ActiveAppMonitor: ObservableObject {
    @Published var frontmostAppName: String = ""
    @Published var frontmostAppBundleID: String = ""
    @Published var isExcelFrontmost: Bool = false
    @Published var isMonitoredAppFrontmost: Bool = false

    private var observer: NSObjectProtocol?
    private var monitoredAppIdentifiers: Set<String> = []
    private var monitoredAppNames: Set<String> = []

    init() {
        updateFrontmostApp()
        startObserving()
    }

    /// Set the list of monitored app names
    func setMonitoredApps(_ apps: [String]) {
        monitoredAppNames = Set(apps.map { $0.lowercased() })
        // Also track known bundle identifiers
        monitoredAppIdentifiers = Set(apps.compactMap { bundleID(for: $0) })
        updateMonitoredStatus()
    }

    /// Start observing frontmost app changes
    private func startObserving() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.updateFrontmostApp()
        }
    }

    /// Update the current frontmost app info
    private func updateFrontmostApp() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }

        let name = app.localizedName ?? ""
        let bundleID = app.bundleIdentifier ?? ""

        frontmostAppName = name
        frontmostAppBundleID = bundleID
        isExcelFrontmost = bundleID == Constants.excelBundleIdentifier
            || name.lowercased().contains("microsoft excel")

        updateMonitoredStatus()

        Logger.debug("Frontmost app: \(name) (\(bundleID))")
    }

    private func updateMonitoredStatus() {
        let nameMatch = monitoredAppNames.contains(frontmostAppName.lowercased())
        let bundleMatch = monitoredAppIdentifiers.contains(frontmostAppBundleID)
        isMonitoredAppFrontmost = nameMatch || bundleMatch || isExcelFrontmost
    }

    /// Map common app names to bundle identifiers
    private func bundleID(for appName: String) -> String? {
        let mapping: [String: String] = [
            "microsoft excel": Constants.excelBundleIdentifier,
            "excel": Constants.excelBundleIdentifier,
        ]
        return mapping[appName.lowercased()]
    }

    deinit {
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
