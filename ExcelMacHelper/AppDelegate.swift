import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var appState = AppState()
    private var hudWindow: HUDOverlayWindow?
    private var cancellables = Set<AnyHashable>()
    private var observers: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.log("ExcelMacHelper starting up...")

        // Set up the menu bar item
        setupStatusItem()

        // Set up HUD overlay window
        setupHUDWindow()

        // Initialize app state and start monitoring
        appState.setup()

        // Observe Key Tips state changes
        setupObservers()

        Logger.log("ExcelMacHelper ready")
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            updateStatusIcon(active: false)
            button.action = #selector(statusBarClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        updateStatusMenu()
    }

    private func updateStatusIcon(active: Bool) {
        guard let button = statusItem?.button else { return }

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if active {
            let image = NSImage(systemSymbolName: "keyboard.fill", accessibilityDescription: "ExcelMacHelper Active")
            button.image = image?.withSymbolConfiguration(config)
            button.contentTintColor = .systemGreen
        } else {
            let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "ExcelMacHelper Inactive")
            button.image = image?.withSymbolConfiguration(config)
            button.contentTintColor = .secondaryLabelColor
        }
    }

    @objc private func statusBarClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            // Right-click: show menu
            statusItem?.menu = createStatusMenu()
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            // Left-click: show menu
            statusItem?.menu = createStatusMenu()
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        }
    }

    private func updateStatusMenu() {
        // Menu is created on-demand in statusBarClicked
    }

    private func createStatusMenu() -> NSMenu {
        let menu = NSMenu()

        // Status
        let statusItem = NSMenuItem(title: appState.statusMessage, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(NSMenuItem.separator())

        // Feature toggles
        let fnToggle = NSMenuItem(title: "Function Key Toggle", action: #selector(toggleFunctionKeys), keyEquivalent: "")
        fnToggle.target = self
        fnToggle.state = appState.functionKeyToggleEnabled ? .on : .off
        menu.addItem(fnToggle)

        let keyTipsToggle = NSMenuItem(title: "Alt-Key Shortcuts", action: #selector(toggleKeyTips), keyEquivalent: "")
        keyTipsToggle.target = self
        keyTipsToggle.state = appState.keyTipsEnabled ? .on : .off
        menu.addItem(keyTipsToggle)

        let hudToggle = NSMenuItem(title: "HUD Overlay", action: #selector(toggleHUD), keyEquivalent: "")
        hudToggle.target = self
        hudToggle.state = appState.hudOverlayEnabled ? .on : .off
        menu.addItem(hudToggle)

        menu.addItem(NSMenuItem.separator())

        // Shortcuts count
        let shortcutsInfo = NSMenuItem(title: "\(appState.shortcutManager.shortcutCount) shortcuts loaded", action: nil, keyEquivalent: "")
        shortcutsInfo.isEnabled = false
        menu.addItem(shortcutsInfo)

        // Reload shortcuts
        let reloadItem = NSMenuItem(title: "Reload Shortcuts", action: #selector(reloadShortcuts), keyEquivalent: "r")
        reloadItem.target = self
        menu.addItem(reloadItem)

        menu.addItem(NSMenuItem.separator())

        // Preferences
        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        // Accessibility
        if !appState.accessibilityManager.isAccessibilityGranted {
            let accessItem = NSMenuItem(title: "Grant Accessibility Access...", action: #selector(openAccessibility), keyEquivalent: "")
            accessItem.target = self
            menu.addItem(accessItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit ExcelMacHelper", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Menu Actions

    @objc private func toggleFunctionKeys() {
        appState.functionKeyToggleEnabled.toggle()
    }

    @objc private func toggleKeyTips() {
        appState.keyTipsEnabled.toggle()
    }

    @objc private func toggleHUD() {
        appState.hudOverlayEnabled.toggle()
    }

    @objc private func reloadShortcuts() {
        appState.shortcutManager.reload()
    }

    @objc private func openPreferences() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    @objc private func openAccessibility() {
        appState.accessibilityManager.requestPermissions()
    }

    @objc private func quitApp() {
        appState.eventTapManager.stop()
        NSApp.terminate(nil)
    }

    // MARK: - HUD Window

    private func setupHUDWindow() {
        hudWindow = HUDOverlayWindow(appState: appState)
    }

    private func setupObservers() {
        // Observe active state for icon
        let activeObserver = appState.$isActive.receive(on: DispatchQueue.main).sink { [weak self] active in
            self?.updateStatusIcon(active: active)
        }

        // Observe Key Tips mode for HUD
        let keyTipsObserver = appState.keyTipsManager.$isActive.receive(on: DispatchQueue.main).sink { [weak self] active in
            guard let self = self, self.appState.hudOverlayEnabled else { return }
            if active {
                self.hudWindow?.show()
            } else {
                self.hudWindow?.hide()
            }
        }

        // Observe available keys for HUD update
        let keysObserver = appState.keyTipsManager.$availableKeys.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.hudWindow?.updateContent()
        }

        // Store observers to keep them alive
        // Using a simple array since we don't need AnyCancellable set here
        observers.append(activeObserver)
        observers.append(keyTipsObserver)
        observers.append(keysObserver)
    }
}

import Combine
