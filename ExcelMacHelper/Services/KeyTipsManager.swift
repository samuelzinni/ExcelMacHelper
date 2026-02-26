import Foundation
import Combine

/// Manages the Key Tips mode state machine
class KeyTipsManager: ObservableObject {
    @Published var isActive: Bool = false
    @Published var currentSequence: [String] = []
    @Published var availableKeys: [(key: String, label: String)] = []
    @Published var currentLevel: Int = 0 // 0 = top level (ribbon tabs), 1+

    /// Multi-character key buffer for keys like "FP", "FF", "FS", etc.
    @Published var keyBuffer: String = ""

    private var shortcutTree: ShortcutTree?
    private var actionExecutor = ActionExecutor()
    private var timeoutTimer: Timer?
    private var bufferTimer: Timer?

    /// Set of known multi-character keys at the current node
    private var multiCharKeys: Set<String> = []

    /// Set of single-character keys at the current node (for fast lookup)
    private var singleCharKeys: Set<String> = []

    /// Set the shortcut tree to use
    func setShortcutTree(_ tree: ShortcutTree) {
        self.shortcutTree = tree
    }

    // MARK: - Key Tips Mode Control

    /// Enter Key Tips mode (triggered by Option key release)
    func enterKeyTipsMode() {
        guard let tree = shortcutTree else {
            Logger.error("No shortcut tree loaded")
            return
        }

        isActive = true
        currentSequence = []
        currentLevel = 0
        keyBuffer = ""

        // Show top-level ribbon tab keys
        availableKeys = tree.getAvailableKeys(after: [])
        updateKeyLookups(at: [])
        resetTimeout()

        Logger.log("Entered Key Tips mode, \(availableKeys.count) keys available")
    }

    /// Exit Key Tips mode
    func exitKeyTipsMode() {
        isActive = false
        currentSequence = []
        availableKeys = []
        currentLevel = 0
        keyBuffer = ""
        multiCharKeys = []
        singleCharKeys = []
        cancelTimeout()
        cancelBufferTimer()

        Logger.log("Exited Key Tips mode")
    }

    // MARK: - Key Processing

    /// Process a key press while in Key Tips mode. Returns true if the key was consumed.
    func processKey(_ key: String) -> Bool {
        guard isActive, let tree = shortcutTree else { return false }

        resetTimeout()
        let upperKey = key.uppercased()

        // Get current node in the tree
        let currentNode = currentSequence.isEmpty ? tree.root : tree.lookup(keys: currentSequence)
        guard let node = currentNode else {
            Logger.log("Current node not found for sequence \(currentSequence), exiting")
            exitKeyTipsMode()
            return false
        }

        // Build the new buffer by appending this key
        let newBuffer = keyBuffer + upperKey

        // PRIORITY 1: Check if newBuffer exactly matches a child key
        if node.children[newBuffer] != nil {
            cancelBufferTimer()
            keyBuffer = ""
            Logger.log("Exact match for '\(newBuffer)' in sequence \(currentSequence)")
            return advanceSequence(with: newBuffer)
        }

        // PRIORITY 2: Check if newBuffer is a prefix of any multi-char key
        let isPrefixOfMultiChar = multiCharKeys.contains { $0.hasPrefix(newBuffer) && $0 != newBuffer }

        if isPrefixOfMultiChar {
            // Buffer might grow into a multi-char key - wait for more input
            keyBuffer = newBuffer
            cancelBufferTimer()

            // If the single key alone is also a valid child, use a short timer
            // to disambiguate (e.g., "F" alone vs "FP", "FF")
            if singleCharKeys.contains(upperKey) && keyBuffer == upperKey {
                bufferTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                    self?.resolveBuffer()
                }
            } else {
                // No ambiguity with a single key, just wait for the next char
                bufferTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
                    self?.resolveBuffer()
                }
            }

            Logger.log("Buffering '\(newBuffer)', waiting for more input")
            return true
        }

        // PRIORITY 3: No multi-char prefix match. Try the single key directly.
        if node.children[upperKey] != nil {
            cancelBufferTimer()
            keyBuffer = ""
            Logger.log("Single key match for '\(upperKey)' in sequence \(currentSequence)")
            return advanceSequence(with: upperKey)
        }

        // PRIORITY 4: If we had a pending buffer and neither combined nor single matched,
        // try resolving the buffer first, then handle the new key
        if !keyBuffer.isEmpty {
            let savedBuffer = keyBuffer
            cancelBufferTimer()
            keyBuffer = ""

            // Try to advance with the first character of the old buffer
            let firstChar = String(savedBuffer.prefix(1))
            if node.children[firstChar] != nil {
                Logger.log("Resolving buffer: advancing with '\(firstChar)', replaying '\(upperKey)'")
                _ = advanceSequence(with: firstChar)
                // Replay the current key in the new context
                return processKey(key)
            }
        }

        // No match found - exit Key Tips mode
        Logger.log("No match for key '\(upperKey)' in sequence \(currentSequence)")
        exitKeyTipsMode()
        return false
    }

    /// Resolve the buffer after timeout
    private func resolveBuffer() {
        guard !keyBuffer.isEmpty, let tree = shortcutTree else { return }

        let currentNode = currentSequence.isEmpty ? tree.root : tree.lookup(keys: currentSequence)
        guard let node = currentNode else {
            exitKeyTipsMode()
            return
        }

        // Try the full buffer first
        if node.children[keyBuffer] != nil {
            let buf = keyBuffer
            keyBuffer = ""
            Logger.log("Buffer resolved: advancing with '\(buf)'")
            _ = advanceSequence(with: buf)
            return
        }

        // Try the first character
        let firstChar = String(keyBuffer.prefix(1))
        if node.children[firstChar] != nil {
            keyBuffer = ""
            Logger.log("Buffer resolved: advancing with first char '\(firstChar)'")
            _ = advanceSequence(with: firstChar)
            return
        }

        // Nothing matches
        Logger.log("Buffer '\(keyBuffer)' could not be resolved, exiting")
        exitKeyTipsMode()
    }

    /// Advance the sequence with a matched key
    private func advanceSequence(with key: String) -> Bool {
        guard let tree = shortcutTree else { return false }

        currentSequence.append(key)
        currentLevel = currentSequence.count

        guard let node = tree.lookup(keys: currentSequence) else {
            // This shouldn't happen since we checked for the child
            Logger.error("Node not found after advancing to \(currentSequence)")
            exitKeyTipsMode()
            return true
        }

        // If this node has an action and no children, execute it
        if node.isLeaf {
            Logger.log("Leaf node reached: executing '\(node.shortcut!.action)'")
            executeAction(node.shortcut!)
            return true
        }

        // If this node has children, show them and wait for next key
        if !node.children.isEmpty {
            availableKeys = node.childLabels
            updateKeyLookups(at: currentSequence)
            Logger.log("Key Tips: sequence=\(currentSequence), \(node.children.count) children available")

            // If the node also has an action (intermediate node with action),
            // we still show children. The user needs to go deeper or wait.
            return true
        }

        // Node has action but no children (shouldn't reach here due to isLeaf check above)
        if let shortcut = node.shortcut {
            executeAction(shortcut)
            return true
        }

        exitKeyTipsMode()
        return true
    }

    /// Execute a shortcut action
    private func executeAction(_ shortcut: ParsedShortcut) {
        Logger.log("Executing shortcut: \(shortcut.action) (\(shortcut.macEquivalent))")
        exitKeyTipsMode()

        // Small delay to ensure Key Tips mode cleanup happens first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.actionExecutor.execute(shortcut)
        }
    }

    // MARK: - Key Lookup Helpers

    /// Update the sets of multi-character and single-character keys at the current position
    private func updateKeyLookups(at sequence: [String]) {
        guard let tree = shortcutTree else {
            multiCharKeys = []
            singleCharKeys = []
            return
        }

        let node = sequence.isEmpty ? tree.root : tree.lookup(keys: sequence)
        if let keys = node?.children.keys {
            multiCharKeys = Set(keys.filter { $0.count > 1 })
            singleCharKeys = Set(keys.filter { $0.count == 1 })
        } else {
            multiCharKeys = []
            singleCharKeys = []
        }

        Logger.debug("Updated key lookups: \(singleCharKeys.count) single, \(multiCharKeys.count) multi")
    }

    // MARK: - Timeout

    /// Reset the timeout timer
    private func resetTimeout() {
        cancelTimeout()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: Constants.keyTipsTimeoutInterval, repeats: false) { [weak self] _ in
            Logger.log("Key Tips timed out")
            self?.exitKeyTipsMode()
        }
    }

    /// Cancel the timeout timer
    private func cancelTimeout() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }

    /// Cancel the buffer timer
    private func cancelBufferTimer() {
        bufferTimer?.invalidate()
        bufferTimer = nil
    }
}
