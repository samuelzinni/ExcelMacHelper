import Foundation
import Combine
import SwiftUI

/// Central app state that coordinates all managers
class AppState: ObservableObject {
    // Feature toggles
    @Published var functionKeyToggleEnabled: Bool {
        didSet { UserDefaults.standard.set(functionKeyToggleEnabled, forKey: Constants.functionKeyToggleEnabledKey) }
    }
    @Published var keyTipsEnabled: Bool {
        didSet { UserDefaults.standard.set(keyTipsEnabled, forKey: Constants.keyTipsEnabledKey) }
    }
    @Published var hudOverlayEnabled: Bool {
        didSet { UserDefaults.standard.set(hudOverlayEnabled, forKey: Constants.hudOverlayEnabledKey) }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Constants.launchAtLoginKey)
            updateLaunchAtLogin()
        }
    }

    // Monitored apps for function key toggle
    @Published var monitoredApps: [String] {
        didSet {
            UserDefaults.standard.set(monitoredApps, forKey: Constants.monitoredAppsKey)
            activeAppMonitor.setMonitoredApps(monitoredApps)
        }
    }

    // Status
    @Published var isActive: Bool = false
    @Published var statusMessage: String = "Initializing..."

    // Managers
    let accessibilityManager = AccessibilityManager()
    let activeAppMonitor = ActiveAppMonitor()
    let shortcutManager = ShortcutManager()
    let eventTapManager = EventTapManager()
    let keyTipsManager = KeyTipsManager()

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Load saved preferences
        let defaults = UserDefaults.standard

        // Register defaults
        defaults.register(defaults: [
            Constants.functionKeyToggleEnabledKey: true,
            Constants.keyTipsEnabledKey: true,
            Constants.hudOverlayEnabledKey: true,
            Constants.launchAtLoginKey: false,
            Constants.monitoredAppsKey: Constants.defaultMonitoredApps,
        ])

        self.functionKeyToggleEnabled = defaults.bool(forKey: Constants.functionKeyToggleEnabledKey)
        self.keyTipsEnabled = defaults.bool(forKey: Constants.keyTipsEnabledKey)
        self.hudOverlayEnabled = defaults.bool(forKey: Constants.hudOverlayEnabledKey)
        self.launchAtLogin = defaults.bool(forKey: Constants.launchAtLoginKey)
        self.monitoredApps = defaults.stringArray(forKey: Constants.monitoredAppsKey) ?? Constants.defaultMonitoredApps
    }

    /// Set up all managers and start monitoring
    func setup() {
        // Initialize shortcuts
        shortcutManager.initialize()

        // Set up active app monitor
        activeAppMonitor.setMonitoredApps(monitoredApps)

        // Set up Key Tips manager
        keyTipsManager.setShortcutTree(shortcutManager.shortcutTree)

        // Set up event tap callbacks
        setupEventTapCallbacks()

        // Observe shortcut tree changes
        shortcutManager.$shortcutTree
            .sink { [weak self] tree in
                self?.keyTipsManager.setShortcutTree(tree)
            }
            .store(in: &cancellables)

        // Check accessibility and start if granted
        accessibilityManager.checkPermissions()

        if accessibilityManager.isAccessibilityGranted {
            startEventTap()
        } else {
            statusMessage = "Accessibility permission required"
            accessibilityManager.$isAccessibilityGranted
                .filter { $0 }
                .first()
                .sink { [weak self] _ in
                    self?.startEventTap()
                }
                .store(in: &cancellables)
        }

        // Update status based on active app
        activeAppMonitor.$isExcelFrontmost
            .sink { [weak self] isExcel in
                self?.updateStatus()
            }
            .store(in: &cancellables)
    }

    /// Start the event tap
    private func startEventTap() {
        eventTapManager.start()
        isActive = eventTapManager.isRunning
        updateStatus()
    }

    /// Set up event tap callbacks
    private func setupEventTapCallbacks() {
        // Option key released - enter Key Tips mode
        eventTapManager.onOptionKeyReleased = { [weak self] in
            guard let self = self,
                  self.keyTipsEnabled,
                  self.activeAppMonitor.isExcelFrontmost else { return }
            self.keyTipsManager.enterKeyTipsMode()
        }

        // Key pressed during Key Tips mode
        eventTapManager.onKeyPressed = { [weak self] key, flags in
            guard let self = self,
                  self.keyTipsEnabled else { return false }
            return self.keyTipsManager.processKey(key)
        }

        // Escape pressed
        eventTapManager.onEscapePressed = { [weak self] in
            self?.keyTipsManager.exitKeyTipsMode()
        }

        // Should remap function keys
        eventTapManager.shouldRemapFunctionKeys = { [weak self] in
            guard let self = self else { return false }
            return self.functionKeyToggleEnabled && self.activeAppMonitor.isMonitoredAppFrontmost
        }

        // Is in Key Tips mode
        eventTapManager.isInKeyTipsMode = { [weak self] in
            return self?.keyTipsManager.isActive ?? false
        }
    }

    /// Update the status message
    private func updateStatus() {
        if !accessibilityManager.isAccessibilityGranted {
            statusMessage = "Accessibility permission required"
            isActive = false
        } else if eventTapManager.isRunning {
            if activeAppMonitor.isExcelFrontmost {
                statusMessage = "Active - Excel is frontmost"
            } else {
                statusMessage = "Monitoring - \(shortcutManager.shortcutCount) shortcuts loaded"
            }
            isActive = true
        } else {
            statusMessage = "Event tap not running"
            isActive = false
        }
    }

    /// Update launch at login setting
    private func updateLaunchAtLogin() {
        // Launch at login requires SMAppService on macOS 13+ or a login item helper
        // For simplicity, we use SMAppService if available
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Logger.error("Failed to update launch at login: \(error)")
            }
        }
    }
}

import ServiceManagement
