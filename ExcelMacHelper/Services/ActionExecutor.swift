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
            executeMenuViaAppleScript(components)
            return
        }

        // Apply menu path corrections for Mac Excel compatibility
        if let correction = correctMenuPath(menuPath) {
            switch correction {
            case .keystroke(let combo):
                Logger.log("Menu path corrected to keystroke: \(menuPath) -> \(combo)")
                executeKeystroke(combo)
                return
            case .correctedPath(let newPath):
                Logger.log("Menu path corrected: \(menuPath) -> \(newPath)")
                let newComponents = newPath.components(separatedBy: " > ").map { $0.trimmingCharacters(in: .whitespaces) }
                executeMenuViaAppleScript(newComponents)
                return
            case .unsupported(let reason):
                Logger.log("Unsupported menu path: \(menuPath) - \(reason)")
                showUnsupportedNotification(action: menuPath, reason: reason)
                return
            }
        }

        // No correction needed, try the original path
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
        // Handle "mso:CommandId" for ribbon commands via VBA ExecuteMso
        if scriptString.hasPrefix("mso:") {
            let msoId = String(scriptString.dropFirst("mso:".count)).trimmingCharacters(in: .whitespaces)
            executeMsoCommand(msoId)
            return
        }

        // If it looks like a menu path, use menu navigation
        if scriptString.contains(" > ") {
            let components = scriptString.components(separatedBy: " > ").map { $0.trimmingCharacters(in: .whitespaces) }
            executeMenuViaAppleScript(components)
            return
        }

        runAppleScript(scriptString)
    }

    /// Execute an Excel ribbon command via VBA's CommandBars.ExecuteMso.
    /// This triggers the actual ribbon button (e.g., fill color picker, decrease decimal)
    /// rather than a generic fallback like Format Cells.
    private func executeMsoCommand(_ msoId: String) {
        let script = """
        tell application "Microsoft Excel"
            activate
            do Visual Basic "Application.CommandBars.ExecuteMso \\"\(msoId)\\""
        end tell
        """
        Logger.log("Executing MSO command: \(msoId)")
        runAppleScript(script)
    }

    /// Run an AppleScript
    private func runAppleScript(_ script: String) {
        Logger.debug("Running AppleScript: \(script.prefix(200))...")

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
                if let error = error {
                    let errorMsg = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                    Logger.error("AppleScript error: \(errorMsg)")
                    // Show notification for menu errors so user knows the shortcut failed
                    DispatchQueue.main.async {
                        self.showMenuErrorNotification(script: script, error: errorMsg)
                    }
                }
            } else {
                Logger.error("Failed to create NSAppleScript")
            }
        }
    }

    // MARK: - Menu Path Corrections for Mac Excel

    /// Result of a menu path correction
    private enum MenuPathCorrection {
        case keystroke(String)           // Use a keystroke instead
        case correctedPath(String)       // Use a different menu path
        case unsupported(String)         // Not available on Mac, show message
    }

    /// Correct a menu path for Mac Excel compatibility
    private func correctMenuPath(_ path: String) -> MenuPathCorrection? {
        // Pattern 1: "Format > Cells > ..." → Not a real submenu in Mac Excel
        // Mac Excel has "Format > Cells..." which opens a dialog, not submenus
        if path.hasPrefix("Format > Cells > ") || path == "Format > Cells" {
            return .keystroke("Cmd+1")
        }

        // Pattern 2: "Edit > Paste Special > ..." → Dialog options, not submenu items
        if path.hasPrefix("Edit > Paste Special > ") {
            return .keystroke("Cmd+Option+V")
        }

        // Pattern 3: "Formulas > ..." → No Formulas menu in Mac Excel menubar
        if path.hasPrefix("Formulas > ") {
            return correctFormulasPath(path)
        }

        // Pattern 4: "Review > ..." → No Review menu in Mac Excel menubar
        if path.hasPrefix("Review > ") {
            return correctReviewPath(path)
        }

        // Pattern 5: "Developer > ..." → No Developer menu in Mac Excel menubar
        if path.hasPrefix("Developer > ") {
            return correctDeveloperPath(path)
        }

        // Pattern 6: "File > Page Setup > ..." → Opens a dialog, not submenus
        if path.hasPrefix("File > Page Setup > ") {
            return .correctedPath("File > Page Setup")
        }

        // Pattern 7: "Insert > Chart > ..." → Submenu structure differs
        if path.hasPrefix("Insert > Chart > ") {
            return .correctedPath("Insert > Chart")
        }

        // Exact corrections for specific paths
        if let correction = Self.exactCorrections[path] {
            return correction
        }

        return nil
    }

    /// Correct "Formulas > ..." paths (Formulas menu doesn't exist in Mac menubar)
    private func correctFormulasPath(_ path: String) -> MenuPathCorrection {
        // Function category menus → open Insert Function dialog
        let functionCategories = ["Financial", "Logical", "Text", "Date & Time",
                                  "Lookup & Reference", "Math & Trig", "More Functions"]
        for cat in functionCategories {
            if path == "Formulas > \(cat)" {
                return .keystroke("Shift+F3")
            }
        }

        // AutoSum variants → use keyboard shortcut for SUM, dialog for others
        if path.hasPrefix("Formulas > AutoSum") {
            return .keystroke("Cmd+Shift+T")
        }

        // Name management
        if path.contains("Name Manager") || path == "Formulas > Define Name" {
            return .correctedPath("Insert > Name > Define")
        }

        // Auditing tools → Tools menu
        switch path {
        case "Formulas > Trace Dependents":
            return .correctedPath("Tools > Trace Dependents")
        case "Formulas > Trace Precedents":
            return .correctedPath("Tools > Trace Precedents")
        case "Formulas > Remove Arrows":
            return .correctedPath("Tools > Remove All Arrows")
        case "Formulas > Remove Arrows > Precedent":
            return .correctedPath("Tools > Remove Precedent Arrows")
        case "Formulas > Remove Arrows > Dependent":
            return .correctedPath("Tools > Remove Dependent Arrows")
        case "Formulas > Error Checking":
            return .correctedPath("Tools > Error Checking")
        case "Formulas > Evaluate Formula":
            return .correctedPath("Tools > Evaluate Formula")
        case "Formulas > Watch Window":
            return .correctedPath("Tools > Watch Window")
        case "Formulas > Calculation Options":
            return .unsupported("Calculation options are in Excel > Preferences > Calculation")
        default:
            return .keystroke("Shift+F3")
        }
    }

    /// Correct "Review > ..." paths (Review menu doesn't exist in Mac menubar)
    private func correctReviewPath(_ path: String) -> MenuPathCorrection {
        switch path {
        case "Review > Previous Comment":
            return .unsupported("Use ribbon Review tab > Previous Comment")
        case "Review > Next Comment":
            return .unsupported("Use ribbon Review tab > Next Comment")
        case "Review > Show All Comments":
            return .unsupported("Use ribbon Review tab > Show All Comments")
        case "Review > Allow Edit Ranges":
            return .correctedPath("Tools > Protection > Allow Users to Edit Ranges")
        case "Review > Track Changes":
            return .correctedPath("Tools > Track Changes > Highlight Changes")
        default:
            return .unsupported("Review feature not available via menu on Mac")
        }
    }

    /// Correct "Developer > ..." paths (Developer menu doesn't exist in Mac menubar)
    private func correctDeveloperPath(_ path: String) -> MenuPathCorrection {
        switch path {
        case "Developer > View Code":
            return .keystroke("Option+F11")
        case "Developer > Insert", "Developer > Design Mode", "Developer > Properties":
            return .unsupported("Developer feature only available via ribbon Developer tab")
        default:
            return .unsupported("Developer feature not available via menu on Mac")
        }
    }

    /// Exact path corrections for specific menu paths
    private static let exactCorrections: [String: MenuPathCorrection] = [
        // Edit menu
        "Edit > Delete > Entire Column": .correctedPath("Edit > Delete"),
        "Edit > Delete > Entire Row": .correctedPath("Edit > Delete"),
        "Edit > Go To > Special": .correctedPath("Edit > Find > Go To Special"),
        "Edit > Sheet > Move or Copy": .correctedPath("Edit > Sheet > Move or Copy Sheet"),

        // Format menu corrections
        "Format > Format as Table": .correctedPath("Format > AutoFormat"),
        "Format > Cell Styles": .correctedPath("Format > Style"),
        "Format > Merge Across": .keystroke("Cmd+1"),
        "Format > Unmerge Cells": .keystroke("Cmd+1"),

        // Data menu corrections
        "Data > Sort Ascending": .correctedPath("Data > Sort"),
        "Data > Sort Descending": .correctedPath("Data > Sort"),
        "Data > Clear": .correctedPath("Data > Refresh All"),
        "Data > Queries & Connections": .correctedPath("Data > Connections"),
        "Data > Advanced Filter": .correctedPath("Data > Filter > Advanced Filter"),
        "Data > What-If Analysis": .correctedPath("Data > What-If Analysis"),
        "Data > What-If Analysis > Goal Seek": .correctedPath("Tools > Goal Seek"),
        "Data > What-If Analysis > Data Table": .correctedPath("Data > What-If Analysis > Data Table"),
        "Data > What-If Analysis > Scenario Manager": .correctedPath("Tools > Scenarios"),
        "Data > Get Data": .correctedPath("Data > Get External Data"),
        "Data > Subtotals": .correctedPath("Data > Subtotals"),

        // Insert menu corrections
        "Insert > Photo > Picture from File": .correctedPath("Insert > Picture > Picture from File"),
        "Insert > Shape": .correctedPath("Insert > Shapes"),
        "Insert > Sparklines": .unsupported("Sparklines are available via ribbon Insert tab"),
        "Insert > Recommended Charts": .correctedPath("Insert > Recommended Charts"),

        // View corrections
        "View > Zoom > Selection": .correctedPath("View > Zoom"),

        // Window corrections
        "Window > Switch": .unsupported("Use Cmd+` to switch between Excel windows"),
        "Window > Arrange": .correctedPath("Window > Arrange All"),

        // File corrections
        "File > Save As > PDF": .correctedPath("File > Save As"),
        "File > Print Area > Set Print Area": .correctedPath("File > Print Area > Set Print Area"),
        "File > Print Area > Clear Print Area": .correctedPath("File > Print Area > Clear Print Area"),

        // Tools corrections
        "Tools > Macro > Security": .correctedPath("Tools > Macro > Macro Security"),
    ]

    // MARK: - Menu Discovery (for debugging)

    /// Discover and log Mac Excel's actual menu structure
    /// Call this from the menu bar or preferences to enumerate menus
    func discoverExcelMenus() {
        let script = """
        tell application "System Events"
            tell process "Microsoft Excel"
                set menuNames to name of every menu bar item of menu bar 1
                set result to "MENU BAR ITEMS: " & (menuNames as text)

                repeat with menuName in menuNames
                    try
                        set menuItemNames to name of every menu item of menu menuName of menu bar item menuName of menu bar 1
                        set result to result & "\\n\\n" & menuName & " MENU: " & (menuItemNames as text)
                    end try
                end repeat

                return result
            end tell
        end tell
        """

        Logger.log("Discovering Excel menu structure...")

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                let result = appleScript.executeAndReturnError(&error)
                if let error = error {
                    Logger.error("Menu discovery error: \(error)")
                } else {
                    let output = result.stringValue ?? "No output"
                    Logger.log("Excel Menu Structure:\n\(output)")
                }
            }
        }
    }

    /// Discover submenu items for a specific menu
    func discoverSubmenu(menuName: String) {
        let script = """
        tell application "System Events"
            tell process "Microsoft Excel"
                set menuItemNames to name of every menu item of menu "\(menuName)" of menu bar item "\(menuName)" of menu bar 1
                return menuItemNames as text
            end tell
        end tell
        """

        Logger.log("Discovering \(menuName) menu items...")

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                let result = appleScript.executeAndReturnError(&error)
                if let error = error {
                    Logger.error("Submenu discovery error for \(menuName): \(error)")
                } else {
                    let output = result.stringValue ?? "No output"
                    Logger.log("\(menuName) menu items: \(output)")
                }
            }
        }
    }

    // MARK: - Notifications

    /// Show a notification when a shortcut is unsupported
    private func showUnsupportedNotification(action: String, reason: String) {
        DispatchQueue.main.async {
            let notification = NSUserNotification()
            notification.title = "ExcelMacHelper"
            notification.informativeText = "'\(action)' is not available via menu. \(reason)"
            notification.soundName = nil
            NSUserNotificationCenter.default.deliver(notification)
        }
        Logger.log("Unsupported shortcut: \(action) - \(reason)")
    }

    /// Show a notification when a menu action fails
    private func showMenuErrorNotification(script: String, error: String) {
        // Extract the menu item name from the script for a friendlier message
        if error.contains("Can't get menu item") || error.contains("Can't get menu") {
            Logger.error("Menu navigation failed. The menu path may not exist in Mac Excel. Error: \(error)")
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
