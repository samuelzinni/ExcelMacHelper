import Foundation

// MARK: - Shortcut Tree Node

/// A tree node for efficient shortcut lookup.
/// Each node represents a key in the sequence. Leaf nodes (or nodes with actions)
/// contain the shortcut to execute.
class ShortcutTreeNode {
    let key: String
    var children: [String: ShortcutTreeNode] = [:]
    var shortcut: ParsedShortcut?

    /// Display label for this key in the HUD
    var displayLabel: String?

    init(key: String = "") {
        self.key = key
    }

    /// Whether this is a leaf node (has a shortcut and no children)
    var isLeaf: Bool {
        return shortcut != nil && children.isEmpty
    }

    /// Whether this node has a shortcut action (may also have children for longer sequences)
    var hasAction: Bool {
        return shortcut != nil
    }

    /// Get available next keys at this node
    var availableKeys: [String] {
        return children.keys.sorted()
    }

    /// Get child labels for HUD display
    var childLabels: [(key: String, label: String)] {
        return children.map { (key: $0.key, label: $0.value.displayLabel ?? $0.value.shortcut?.action ?? $0.key) }
            .sorted { $0.key < $1.key }
    }
}

// MARK: - Shortcut Tree

class ShortcutTree {
    let root = ShortcutTreeNode(key: "ROOT")

    /// Ribbon tab labels for top-level display
    var ribbonTabs: [String: String] = [:]

    /// All parsed shortcuts for reference
    private(set) var allShortcuts: [ParsedShortcut] = []

    /// Build the tree from a shortcuts file
    func build(from file: ShortcutsFile) {
        // Store ribbon tab labels
        ribbonTabs = file.ribbonTabs ?? [:]

        // Set up root children for ribbon tabs
        for (key, label) in ribbonTabs {
            let node = ShortcutTreeNode(key: key.uppercased())
            node.displayLabel = "\(key) - \(label)"
            root.children[key.uppercased()] = node
        }

        // Also add legacy top-level keys not in ribbon tabs
        let legacyKeys = ["E", "O", "D", "I", "T"]
        for key in legacyKeys {
            if root.children[key] == nil {
                let node = ShortcutTreeNode(key: key)
                node.displayLabel = key
                root.children[key] = node
            }
        }

        // Parse and insert all shortcuts
        var currentCategory: String?
        for entry in file.shortcuts {
            if entry.separator == true {
                currentCategory = entry.category
                continue
            }

            guard let shortcut = ParsedShortcut.from(entry, category: currentCategory) else {
                continue
            }

            allShortcuts.append(shortcut)
            insert(shortcut: shortcut)
        }

        Logger.log("ShortcutTree built with \(allShortcuts.count) shortcuts")
    }

    /// Insert a shortcut into the tree
    private func insert(shortcut: ParsedShortcut) {
        var currentNode = root

        for (index, key) in shortcut.keys.enumerated() {
            let upperKey = key.uppercased()

            if let existingChild = currentNode.children[upperKey] {
                currentNode = existingChild
            } else {
                let newNode = ShortcutTreeNode(key: upperKey)
                currentNode.children[upperKey] = newNode
                currentNode = newNode
            }

            // If this is the last key, attach the shortcut
            if index == shortcut.keys.count - 1 {
                currentNode.shortcut = shortcut
                if currentNode.displayLabel == nil {
                    currentNode.displayLabel = shortcut.action
                }
            }
        }
    }

    /// Look up a node for a given key sequence
    func lookup(keys: [String]) -> ShortcutTreeNode? {
        var currentNode = root
        for key in keys {
            let upperKey = key.uppercased()
            guard let child = currentNode.children[upperKey] else {
                return nil
            }
            currentNode = child
        }
        return currentNode
    }

    /// Get the shortcut for an exact key sequence
    func getShortcut(for keys: [String]) -> ParsedShortcut? {
        return lookup(keys: keys)?.shortcut
    }

    /// Get available next keys from a given sequence
    func getAvailableKeys(after keys: [String]) -> [(key: String, label: String)] {
        let node = keys.isEmpty ? root : lookup(keys: keys)
        return node?.childLabels ?? []
    }

    /// Check if a key sequence has a valid continuation
    func hasChildren(for keys: [String]) -> Bool {
        let node = keys.isEmpty ? root : lookup(keys: keys)
        return node != nil && !node!.children.isEmpty
    }
}
