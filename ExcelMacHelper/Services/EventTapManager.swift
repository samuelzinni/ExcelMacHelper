import Cocoa
import Carbon

/// Manages CGEventTap for intercepting keyboard events.
/// Handles both Feature 1 (function key toggle) and Feature 2 (Key Tips interception).
class EventTapManager: ObservableObject {
    @Published var isRunning: Bool = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // References needed by the C callback
    fileprivate static var shared: EventTapManager?

    // Callbacks
    var onOptionKeyPressed: (() -> Void)?
    var onOptionKeyReleased: (() -> Void)?
    var onKeyPressed: ((String, CGEventFlags) -> Bool)?  // Returns true if event should be consumed
    var onEscapePressed: (() -> Void)?
    var shouldRemapFunctionKeys: (() -> Bool)?
    var isInKeyTipsMode: (() -> Bool)?

    // F1-F12 virtual key codes
    private static let functionKeyCodes: Set<CGKeyCode> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]

    // NX media key type to F-key virtual keycode mapping (standard MacBook layout)
    private static let mediaKeyToFKey: [Int: CGKeyCode] = [
        3: 122,   // Brightness Down → F1
        2: 120,   // Brightness Up → F2
        22: 96,   // Keyboard Brightness Down / Dictation → F5
        21: 97,   // Keyboard Brightness Up / Do Not Disturb → F6
        18: 98,   // Previous Track → F7
        20: 98,   // Rewind → F7 (alternative)
        16: 100,  // Play/Pause → F8
        17: 101,  // Next Track → F9
        19: 101,  // Fast Forward → F9 (alternative)
        7: 109,   // Mute → F10
        1: 103,   // Volume Down → F11
        0: 111,   // Volume Up → F12
    ]

    init() {
        EventTapManager.shared = self
    }

    // MARK: - Start/Stop

    /// Start the event tap
    func start() {
        guard eventTap == nil else {
            Logger.log("Event tap already running")
            return
        }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << 14)  // NX_SYSDEFINED: captures media key events for F-key remapping

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: nil
        ) else {
            Logger.error("Failed to create event tap. Ensure Accessibility permissions are granted.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        Logger.log("Event tap started successfully")
    }

    /// Stop the event tap
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        isRunning = false
        Logger.log("Event tap stopped")
    }

    // MARK: - Event Processing

    /// Process a keyboard event, returns nil to consume the event or the event to pass through
    func processEvent(_ proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> CGEvent? {
        // Handle tap being disabled by the system
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return event
        }

        // Feature 1: Intercept media key events and convert to F-keys
        if shouldRemapFunctionKeys?() == true && type.rawValue == 14 {
            return handleMediaKeyEvent(event: event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // Feature 1: Function Key Remapping (for keyboard F-key events)
        if shouldRemapFunctionKeys?() == true {
            if let remapped = handleFunctionKeyRemap(keyCode: keyCode, flags: flags, type: type, event: event) {
                return remapped
            }
        }

        // Feature 2: Key Tips Mode
        if type == .flagsChanged {
            return handleFlagsChanged(keyCode: keyCode, flags: flags, event: event)
        }

        if type == .keyDown {
            return handleKeyDown(keyCode: keyCode, flags: flags, event: event)
        }

        return event
    }

    // MARK: - Feature 1: Media Key Interception

    /// Handle NX_SYSDEFINED media key events and convert them to F-key events
    private func handleMediaKeyEvent(event: CGEvent) -> CGEvent? {
        guard let nsEvent = NSEvent(cgEvent: event) else { return event }

        // Only handle media key subtype (8 = NX_SUBTYPE_AUX_CONTROL_BUTTON)
        guard nsEvent.subtype.rawValue == 8 else { return event }

        let data1 = nsEvent.data1
        let keyType = (data1 & 0xFFFF0000) >> 16
        let keyFlags = data1 & 0x0000FFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        let isKeyDown = keyState == 0x0A
        let isKeyUp = keyState == 0x0B

        guard isKeyDown || isKeyUp else { return event }

        // Map the media key type to an F-key virtual keycode
        guard let fKeyCode = Self.mediaKeyToFKey[keyType] else { return event }

        // Create a synthetic F-key keyboard event
        let source = CGEventSource(stateID: .hidSystemState)
        guard let syntheticEvent = CGEvent(
            keyboardEventSource: source,
            virtualKey: fKeyCode,
            keyDown: isKeyDown
        ) else { return event }

        syntheticEvent.flags = [.maskSecondaryFn]

        Logger.debug("Converted media key type \(keyType) to F-key \(fKeyCode)")
        return syntheticEvent
    }

    // MARK: - Feature 1: Function Key Remapping

    /// Remap F1-F12 to standard function keys when a monitored app is frontmost
    private func handleFunctionKeyRemap(keyCode: CGKeyCode, flags: CGEventFlags, type: CGEventType, event: CGEvent) -> CGEvent? {
        guard Self.functionKeyCodes.contains(keyCode) else {
            return nil // Not a function key, don't handle
        }

        // If the fn key is NOT pressed, we need to ensure the key acts as a function key
        // by adding the fn flag. This overrides the system's "media key" behavior.
        if !flags.contains(.maskSecondaryFn) {
            event.flags = flags.union(.maskSecondaryFn)
            Logger.debug("Remapped F-key \(keyCode) to standard function key")
        }

        return event // Return the (possibly modified) event
    }

    // MARK: - Feature 2: Key Tips

    /// Handle flags changed events (Option/Alt key press/release)
    private func handleFlagsChanged(keyCode: CGKeyCode, flags: CGEventFlags, event: CGEvent) -> CGEvent? {
        let optionPressed = flags.contains(.maskAlternate)

        // Option key codes: 58 (left), 61 (right)
        if keyCode == 58 || keyCode == 61 {
            if optionPressed {
                // Option key pressed - don't enter Key Tips mode yet, wait for release
                return event
            } else {
                // Option key released
                if isInKeyTipsMode?() == true {
                    // Already in Key Tips mode, ignore
                    return event
                }
                // Enter Key Tips mode synchronously so that subsequent key events
                // in the same RunLoop cycle see the updated state immediately.
                self.onOptionKeyReleased?()
                return event
            }
        }

        return event
    }

    /// Handle key down events during Key Tips mode
    private func handleKeyDown(keyCode: CGKeyCode, flags: CGEventFlags, event: CGEvent) -> CGEvent? {
        // Escape key
        if keyCode == 53 {
            if isInKeyTipsMode?() == true {
                self.onEscapePressed?()
                return nil // Consume the escape key
            }
            return event
        }

        // Only intercept if in Key Tips mode
        guard isInKeyTipsMode?() == true else {
            return event
        }

        // Don't intercept if modifier keys (other than shift) are held
        let hasModifiers = flags.contains(.maskCommand) || flags.contains(.maskControl)
        if hasModifiers {
            return event
        }

        // Convert keycode to character
        guard let keyChar = keyCharacter(for: keyCode) else {
            return event
        }

        // Send to Key Tips handler
        let consumed = onKeyPressed?(keyChar, flags) ?? false

        return consumed ? nil : event
    }

    /// Convert a key code to a character string
    private func keyCharacter(for keyCode: CGKeyCode) -> String? {
        let keyMapping: [CGKeyCode: String] = [
            // Letters
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G",
            6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
            13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
            31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
            38: "J", 40: "K", 45: "N", 46: "M",
            // Numbers
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
            22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        ]
        return keyMapping[keyCode]
    }

    deinit {
        stop()
    }
}

// MARK: - C Callback

/// C-compatible event tap callback function
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let manager = EventTapManager.shared else {
        return Unmanaged.passRetained(event)
    }

    if let processedEvent = manager.processEvent(proxy, type: type, event: event) {
        return Unmanaged.passRetained(processedEvent)
    }

    return nil // Event consumed
}
