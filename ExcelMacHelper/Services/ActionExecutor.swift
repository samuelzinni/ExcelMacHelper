import Cocoa
import Carbon

/// Executes Mac actions for shortcuts (keystroke simulation, menu navigation, AppleScript)
class ActionExecutor {

    // MARK: - Public API

    /// Execute a parsed shortcut's Mac action
    func execute(_ shortcut: ParsedShortcut) {
        Logger.log("Executing: \(shortcut.action) via \(shortcut.macActionType) -> \(shortcut.macEquivalent)")

        switch shortcut.macActionType {
        case .keystroke:
            executeKeystroke(shortcut.macEquivalent)
        case .menu:
            executeMenuNavigation(shortcut.macEquivalent)
        case .applescript:
            executeAppleScript(shortcut.macEquivalent)
        }
    }

    // MARK: - Keystroke Execution

    /// Parse and simulate a keyboard shortcut string like "Cmd+Shift+V"
    private func executeKeystroke(_ keystrokeString: String) {
        // Handle "X then Y" sequences (e.g., "Cmd+Shift+C then Cmd+Shift+V")
        let parts = keystrokeString.components(separatedBy: " then ")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            // Handle "X or Y" alternatives - just use the first one
            let alternatives = trimmed.components(separatedBy: " or ")
            let primary = alternatives.first?.trimmingCharacters(in: .whitespaces) ?? trimmed
            simulateKeyCombo(primary)

            if parts.count > 1 {
                // Small delay between sequential keystrokes
                usleep(100_000) // 100ms
            }
        }
    }

    /// Simulate a single key combination like "Cmd+Shift+V"
    private func simulateKeyCombo(_ combo: String) {
        let components = combo.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }

        var flags: CGEventFlags = []
        var keyString = ""

        for component in components {
            let lower = component.lowercased()
            switch lower {
            case "cmd", "command":
                flags.insert(.maskCommand)
            case "shift":
                flags.insert(.maskShift)
            case "option", "opt", "alt":
                flags.insert(.maskAlternate)
            case "ctrl", "control":
                flags.insert(.maskControl)
            case "fn":
                flags.insert(.maskSecondaryFn)
            default:
                keyString = component
            }
        }

        guard let keyCode = keyCodeFor(keyString) else {
            Logger.error("Unknown key: \(keyString) in combo: \(combo)")
            return
        }

        simulateKey(keyCode: keyCode, flags: flags)
    }

    /// Simulate a key press with modifiers via CGEvent
    private func simulateKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            Logger.error("Failed to create CGEvent for keyCode \(keyCode)")
            return
        }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        Logger.debug("Simulated key: code=\(keyCode) flags=\(flags.rawValue)")
    }

    // MARK: - Menu Navigation

    /// Navigate Excel's menu hierarchy via Accessibility API
    private func executeMenuNavigation(_ menuPath: String) {
        // Parse menu path like "Format > Column > AutoFit Selection"
        let components = menuPath.components(separatedBy: " > ").map { $0.trimmingCharacters(in: .whitespaces) }

        guard components.count >= 2 else {
            Logger.error("Invalid menu path: \(menuPath)")
            // Fall back to AppleScript
            executeMenuViaAppleScript(components)
            return
        }

        // Use AppleScript for reliable menu navigation
        executeMenuViaAppleScript(components)
    }

    /// Execute menu navigation via AppleScript (more reliable than Accessibility API)
    private func executeMenuViaAppleScript(_ menuItems: [String]) {
        guard !menuItems.isEmpty else { return }

        var script: String

        if menuItems.count == 1 {
            script = """
            tell application "System Events"
                tell process "Microsoft Excel"
                    click menu item "\(menuItems[0])" of menu bar 1
                end tell
            end tell
            """
        } else {
            // Build nested menu item click
            var menuClick = "click menu item \"\(menuItems.last!)\""
            for i in stride(from: menuItems.count - 2, through: 0, by: -1) {
                if i == 0 {
                    menuClick += " of menu \"\(menuItems[i])\" of menu bar item \"\(menuItems[i])\" of menu bar 1"
                } else {
                    menuClick += " of menu \"\(menuItems[i])\" of menu item \"\(menuItems[i])\""
                }
            }

            script = """
            tell application "System Events"
                tell process "Microsoft Excel"
                    \(menuClick)
                end tell
            end tell
            """
        }

        runAppleScript(script)
    }

    // MARK: - AppleScript Execution

    /// Execute an AppleScript command string
    private func executeAppleScript(_ scriptString: String) {
        // If it looks like a menu path, use menu navigation
        if scriptString.contains(" > ") {
            let components = scriptString.components(separatedBy: " > ").map { $0.trimmingCharacters(in: .whitespaces) }
            executeMenuViaAppleScript(components)
            return
        }

        runAppleScript(scriptString)
    }

    /// Run an AppleScript
    private func runAppleScript(_ script: String) {
        Logger.debug("Running AppleScript: \(script.prefix(100))...")

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
                if let error = error {
                    Logger.error("AppleScript error: \(error)")
                }
            } else {
                Logger.error("Failed to create NSAppleScript")
            }
        }
    }

    // MARK: - Key Code Mapping

    /// Map key strings to CGKeyCode values
    private func keyCodeFor(_ key: String) -> CGKeyCode? {
        let lower = key.lowercased()

        // Special keys
        let specialKeys: [String: CGKeyCode] = [
            "delete": 51,
            "backspace": 51,
            "return": 36,
            "enter": 36,
            "tab": 48,
            "space": 49,
            "escape": 53,
            "esc": 53,
            "left": 123,
            "right": 124,
            "down": 125,
            "up": 126,
            "f1": 122,
            "f2": 120,
            "f3": 99,
            "f4": 118,
            "f5": 96,
            "f6": 97,
            "f7": 98,
            "f8": 100,
            "f9": 101,
            "f10": 109,
            "f11": 103,
            "f12": 111,
            "home": 115,
            "end": 119,
            "pageup": 116,
            "pagedown": 121,
        ]

        if let code = specialKeys[lower] {
            return code
        }

        // Letter keys (a-z)
        let letterKeys: [String: CGKeyCode] = [
            "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3,
            "g": 5, "h": 4, "i": 34, "j": 38, "k": 40, "l": 37,
            "m": 46, "n": 45, "o": 31, "p": 35, "q": 12, "r": 15,
            "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7,
            "y": 16, "z": 6,
        ]

        if let code = letterKeys[lower] {
            return code
        }

        // Number keys (0-9)
        let numberKeys: [String: CGKeyCode] = [
            "0": 29, "1": 18, "2": 19, "3": 20, "4": 21,
            "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
        ]

        if let code = numberKeys[lower] {
            return code
        }

        // Symbol keys
        let symbolKeys: [String: CGKeyCode] = [
            "`": 50, "-": 27, "=": 24,
            "[": 33, "]": 30, "\\": 42,
            ";": 41, "'": 39, ":": 41,
            ",": 43, ".": 47, "/": 44,
            "<": 43, ">": 47,
            "delete key": 51,
        ]

        if let code = symbolKeys[lower] {
            return code
        }

        Logger.error("No keycode mapping for: '\(key)'")
        return nil
    }
}
