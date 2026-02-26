import Foundation

// MARK: - JSON Parsing Models

struct ShortcutsFile: Codable {
    let metadata: Metadata?
    let ribbonTabs: [String: String]?
    let shortcuts: [ShortcutEntry]

    enum CodingKeys: String, CodingKey {
        case metadata = "_metadata"
        case ribbonTabs = "ribbon_tabs"
        case shortcuts
    }
}

struct Metadata: Codable {
    let version: String?
    let description: String?
    let note: String?
    let macActionTypes: String?

    enum CodingKeys: String, CodingKey {
        case version, description, note
        case macActionTypes = "mac_action_types"
    }
}

struct ShortcutEntry: Codable {
    // Separator entries
    let category: String?
    let separator: Bool?

    // Shortcut entries
    let keys: String?
    let action: String?
    let macActionType: String?
    let macEquivalent: String?

    enum CodingKeys: String, CodingKey {
        case category, separator, keys, action
        case macActionType = "mac_action_type"
        case macEquivalent = "mac_equivalent"
    }

    var isShortcut: Bool {
        return keys != nil && action != nil
    }
}

// MARK: - Parsed Shortcut

enum MacActionType: String {
    case keystroke
    case menu
    case applescript
}

struct ParsedShortcut {
    let keys: [String]          // e.g., ["H", "V", "V"] (without "Alt")
    let action: String          // e.g., "Paste Values"
    let macActionType: MacActionType
    let macEquivalent: String   // e.g., "Cmd+Shift+V or Cmd+Ctrl+V"
    let category: String?

    /// Parse a shortcut entry from JSON
    static func from(_ entry: ShortcutEntry, category: String? = nil) -> ParsedShortcut? {
        guard let keys = entry.keys,
              let action = entry.action,
              let typeStr = entry.macActionType,
              let macEquiv = entry.macEquivalent else {
            return nil
        }

        let actionType = MacActionType(rawValue: typeStr) ?? .menu

        // Parse key sequence: "Alt+H+V+V" -> ["H", "V", "V"]
        let keyParts = keys.split(separator: "+").map(String.init)
        let filteredKeys = keyParts.filter { $0.uppercased() != "ALT" }

        guard !filteredKeys.isEmpty else { return nil }

        return ParsedShortcut(
            keys: filteredKeys.map { $0.uppercased() },
            action: action,
            macActionType: actionType,
            macEquivalent: macEquiv,
            category: category
        )
    }
}
