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
        updateMultiCharKeys(at: [])
        resetTimeout()

        Logger.log("Entered Key Tips mode")
    }

    /// Exit Key Tips mode
    func exitKeyTipsMode() {
        isActive = false
        currentSequence = []
        availableKeys = []
        currentLevel = 0
        keyBuffer = ""
        multiCharKeys = []
        cancelTimeout()
        cancelBufferTimer()

        Logger.log("Exited Key Tips mode")
    }

    // MARK: - Key Processing

    /// Process a key press while in Key Tips mode. Returns true if the key was consumed.
    func processKey(_ key: String) -> Bool {
        guard isActive, let tree = shortcutTree else { return false }

        resetTimeout()

        // Append to key buffer
        let newBuffer = keyBuffer + key.uppercased()

        // Check if the buffer matches an exact child key
        let currentNode = currentSequence.isEmpty ? tree.root : tree.lookup(keys: currentSequence)
        guard let node = currentNode else {
            exitKeyTipsMode()
            return false
        }

        // Check if newBuffer exactly matches a child key
        if node.children[newBuffer] != nil {
            cancelBufferTimer()
            keyBuffer = ""
            return advanceSequence(with: newBuffer)
        }

        // Check if newBuffer is a prefix of any multi-char key
        let isPrefixOfMultiChar = multiCharKeys.contains { $0.hasPrefix(newBuffer) && $0 != newBuffer }

        if isPrefixOfMultiChar {
            // Buffer is a prefix of a multi-char key - wait for more input
            keyBuffer = newBuffer

            // Also check if the single key is a valid child (ambiguous case)
            // Use a short timer to resolve ambiguity
            cancelBufferTimer()
            bufferTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.resolveBuffer()
                }
            }
            return true
        }

        // If the single key matches a child, use it
        let singleKey = key.uppercased()
        if node.children[singleKey] != nil {
            cancelBufferTimer()
            keyBuffer = ""
            return advanceSequence(with: singleKey)
        }

        // No match found - exit
        Logger.log("No match for key '\(key)' in sequence \(currentSequence)")
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
            _ = advanceSequence(with: buf)
            return
        }

        // Try the first character
        let firstChar = String(keyBuffer.prefix(1))
        if node.children[firstChar] != nil {
            keyBuffer = ""
            _ = advanceSequence(with: firstChar)
            return
        }

        // Nothing matches
        exitKeyTipsMode()
    }

    /// Advance the sequence with a matched key
    private func advanceSequence(with key: String) -> Bool {
        guard let tree = shortcutTree else { return false }

        currentSequence.append(key)
        currentLevel = currentSequence.count

        guard let node = tree.lookup(keys: currentSequence) else {
            // This shouldn't happen since we checked for the child
            exitKeyTipsMode()
            return true
        }

        // If this node has an action and no children, execute it
        if node.isLeaf {
            executeAction(node.shortcut!)
            return true
        }

        // If this node has an action AND children, and we're past level 2,
        // we need to decide: Mac Excel handles up to 2 levels natively.
        // After level 2, we intercept and execute.
        if node.hasAction && currentLevel >= 2 && node.children.isEmpty {
            executeAction(node.shortcut!)
            return true
        }

        // If this node has children, show them and wait for next key
        if !node.children.isEmpty {
            availableKeys = node.childLabels
            updateMultiCharKeys(at: currentSequence)
            Logger.log("Key Tips: sequence=\(currentSequence), available=\(node.availableKeys)")
            return true
        }

        // Node has action but we got here somehow
        if let shortcut = node.shortcut {
            executeAction(shortcut)
            return true
        }

        exitKeyTipsMode()
        return true
    }

    /// Execute a shortcut action
    private func executeAction(_ shortcut: ParsedShortcut) {
        Logger.log("Executing shortcut: \(shortcut.action)")
        exitKeyTipsMode()

        // Small delay to ensure Key Tips mode cleanup happens first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.actionExecutor.execute(shortcut)
        }
    }

    // MARK: - Multi-Character Key Detection

    /// Update the set of multi-character keys at the current position
    private func updateMultiCharKeys(at sequence: [String]) {
        guard let tree = shortcutTree else {
            multiCharKeys = []
            return
        }

        let node = sequence.isEmpty ? tree.root : tree.lookup(keys: sequence)
        multiCharKeys = Set(node?.children.keys.filter { $0.count > 1 } ?? [])
    }

    // MARK: - Timeout

    /// Reset the timeout timer
    private func resetTimeout() {
        cancelTimeout()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: Constants.keyTipsTimeoutInterval, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                Logger.log("Key Tips timed out")
                self?.exitKeyTipsMode()
            }
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
