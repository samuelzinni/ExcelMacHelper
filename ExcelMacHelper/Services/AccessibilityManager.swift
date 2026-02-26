import Cocoa
import ApplicationServices

/// Manages Accessibility permissions required for CGEventTap
class AccessibilityManager: ObservableObject {
    @Published var isAccessibilityGranted: Bool = false

    private var checkTimer: Timer?

    init() {
        checkPermissions()
    }

    /// Check if Accessibility permissions are granted
    func checkPermissions() {
        isAccessibilityGranted = AXIsProcessTrusted()
        Logger.log("Accessibility permissions: \(isAccessibilityGranted ? "granted" : "not granted")")
    }

    /// Request Accessibility permissions (shows system dialog)
    func requestPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        isAccessibilityGranted = trusted
        Logger.log("Accessibility request result: \(trusted)")

        // Start polling for permission changes
        startPolling()
    }

    /// Start polling for accessibility permission changes
    func startPolling() {
        stopPolling()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.checkPermissions()
                if self?.isAccessibilityGranted == true {
                    self?.stopPolling()
                }
            }
        }
    }

    /// Stop polling
    func stopPolling() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    /// Open System Settings to the Accessibility pane
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    deinit {
        stopPolling()
    }
}
