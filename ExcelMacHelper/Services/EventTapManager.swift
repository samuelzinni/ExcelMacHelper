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
    var onOptionKeyReleased: (() -> Void)?
    var onKeyPressed: ((String, CGEventFlags) -> Bool)?  // Returns true if event should be consumed
    var onEscapePressed: (() -> Void)?
    var shouldRemapFunctionKeys: (() -> Bool)?
    var isInKeyTipsMode: (() -> Bool)?

    // Option key tracking: only activate Key Tips if Option was pressed
    // and released alone (not used as a modifier with another key).
    // This prevents Key Tips from activating after Option+Tab, Option+V, etc.
    private var isOptionDown: Bool = false
    private var wasOptionUsedAsModifier: Bool = false

    // F1-F12 virtual key codes
    private static let functionKeyCodes: Set<CGKeyCode> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]

    // Comprehensive NX media key type to F-key virtual keycode mapping
    // These key types are from NX_SYSDEFINED (type 14) events when "Use F1-F12 as standard
    // function keys" is OFF in System Settings (the macOS default).
    // Key types vary by Mac model — these cover MacBook built-in and common external keyboards.
    private static let mediaKeyToFKey: [Int: CGKeyCode] = [
        // F1/F2: Brightness Down/Up
        3: 122,    // Brightness Down → F1
        2: 120,    // Brightness Up → F2
        // F3: Mission Control / Exposé
        160: 99,   // Mission Control → F3
        // F4: Launchpad / Spotlight
        130: 118,  // Launchpad → F4
        131: 118,  // Spotlight (alternative) → F4
        // F5/F6: Keyboard Brightness / Dictation / DND
        22: 96,    // Keyboard Brightness Down / Dictation → F5
        21: 97,    // Keyboard Brightness Up / Do Not Disturb → F6
        // F7/F8/F9: Media playback
        18: 98,    // Previous Track → F7
        20: 98,    // Rewind → F7 (alternative)
        16: 100,   // Play/Pause → F8
        17: 101,   // Next Track → F9
        19: 101,   // Fast Forward → F9 (alternative)
        // F10/F11/F12: Volume
        7: 109,    // Mute → F10
        1: 103,    // Volume Down → F11
        0: 111,    // Volume Up → F12
    ]

    // Human-readable names for NX media key types (for logging)
    private static let mediaKeyNames: [Int: String] = [
        0: "Volume Up", 1: "Volume Down", 2: "Brightness Up", 3: "Brightness Down",
        7: "Mute", 16: "Play/Pause", 17: "Next Track", 18: "Previous Track",
        19: "Fast Forward", 20: "Rewind", 21: "KB Brightness Up/DND",
        22: "KB Brightness Down/Dictation", 130: "Launchpad", 131: "Spotlight",
        160: "Mission Control",
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

        // Try with NX_SYSDEFINED (type 14) for media key interception
        let fullEventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << 14)  // NX_SYSDEFINED: captures media key events for F-key remapping

        // Fallback mask without NX_SYSDEFINED (in case it causes tap creation to fail)
        let basicEventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let tap: CFMachPort
        if let fullTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: fullEventMask,
            callback: eventTapCallback,
            userInfo: nil
        ) {
            tap = fullTap
            Logger.log("Event tap created with media key support (NX_SYSDEFINED)")
        } else if let basicTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: basicEventMask,
            callback: eventTapCallback,
            userInfo: nil
        ) {
            tap = basicTap
            Logger.log("Event tap created without media key support (fallback)")
        } else {
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

        // Feature 1: Intercept media key events (NX_SYSDEFINED, type 14) and convert to F-keys
        if type.rawValue == 14 {
            if shouldRemapFunctionKeys?() == true {
                return handleMediaKeyEvent(event: event)
            } else {
                // Still log NX_SYSDEFINED events for debugging even when not remapping
                logMediaKeyEvent(event: event)
                return event
            }
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // Track Option key modifier usage: if ANY key is pressed while Option
        // is physically held down, mark Option as used as a modifier so we
        // don't accidentally enter Key Tips mode on Option release.
        if type == .keyDown && isOptionDown {
            wasOptionUsedAsModifier = true
        }

        // Feature 1: Function Key Remapping (for keyboard F-key events that arrive as keyDown)
        if shouldRemapFunctionKeys?() == true {
            if let remapped = handleFunctionKeyRemap(keyCode: keyCode, flags: flags, type: type, event: event) {
                // If an F-key is pressed while Key Tips are showing, dismiss them
                if isInKeyTipsMode?() == true {
                    DispatchQueue.main.async {
                        self.onEscapePressed?()
                    }
                }
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

    /// Log NX_SYSDEFINED media key event details for debugging
    private func logMediaKeyEvent(event: CGEvent) {
        guard let nsEvent = NSEvent(cgEvent: event) else { return }
        guard nsEvent.subtype.rawValue == 8 else { return }

        let data1 = nsEvent.data1
        let keyType = (data1 & 0xFFFF0000) >> 16
        let keyFlags = data1 & 0x0000FFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        let isKeyDown = keyState == 0x0A

        let keyName = Self.mediaKeyNames[keyType] ?? "Unknown"
        let mapped = Self.mediaKeyToFKey[keyType] != nil ? "mapped" : "UNMAPPED"
        Logger.debug("NX_SYSDEFINED: keyType=\(keyType) (\(keyName)) state=\(isKeyDown ? "down" : "up") [\(mapped)]")
    }

    /// Handle NX_SYSDEFINED media key events and convert them to F-key events.
    /// Creates a synthetic keyboard event and posts it past all event taps
    /// (at cgAnnotatedSessionEventTap) so it goes directly to the application
    /// without being re-intercepted by our own tap.
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

        let keyName = Self.mediaKeyNames[keyType] ?? "Unknown(\(keyType))"

        // Map the media key type to an F-key virtual keycode
        guard let fKeyCode = Self.mediaKeyToFKey[keyType] else {
            Logger.debug("NX_SYSDEFINED: Unmapped media key type \(keyType) (\(keyName)), passing through")
            return event
        }

        // Create a synthetic F-key keyboard event
        let source = CGEventSource(stateID: .hidSystemState)
        guard let syntheticEvent = CGEvent(
            keyboardEventSource: source,
            virtualKey: fKeyCode,
            keyDown: isKeyDown
        ) else {
            Logger.error("Failed to create synthetic F-key event for keyType \(keyType)")
            return event
        }

        // Set the fn flag so the system treats it as a standard function key
        syntheticEvent.flags = [.maskSecondaryFn]

        // Post at cgAnnotatedSessionEventTap to bypass our own event tap.
        // This sends the event directly to the frontmost application.
        syntheticEvent.post(tap: .cgAnnotatedSessionEventTap)

        Logger.debug("Converted media key \(keyName) (type \(keyType)) -> F-key code \(fKeyCode)")

        // Return nil to suppress the original media key event
        return nil
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

    /// Handle flags changed events (Option/Alt key press/release).
    /// Only activates Key Tips when Option is pressed and released ALONE
    /// (without any other key being pressed during the hold).
    /// Pressing Alt again while Key Tips are active toggles them off.
    private func handleFlagsChanged(keyCode: CGKeyCode, flags: CGEventFlags, event: CGEvent) -> CGEvent? {
        let optionPressed = flags.contains(.maskAlternate)

        // Option key codes: 58 (left), 61 (right)
        if keyCode == 58 || keyCode == 61 {
            if optionPressed {
                // Option key pressed down — start tracking
                isOptionDown = true
                // If other modifiers (Shift, Cmd, Ctrl) are already held,
                // this is a multi-modifier combo, not a standalone Alt press
                let otherModifiers: CGEventFlags = [.maskShift, .maskCommand, .maskControl]
                wasOptionUsedAsModifier = !flags.intersection(otherModifiers).isEmpty
                return event
            } else {
                // Option key released — check if it was a clean solo press
                let shouldActivate = isOptionDown && !wasOptionUsedAsModifier
                isOptionDown = false
                wasOptionUsedAsModifier = false

                if shouldActivate {
                    if isInKeyTipsMode?() == true {
                        // Alt pressed twice → toggle off (dismiss Key Tips)
                        DispatchQueue.main.async {
                            self.onEscapePressed?()
                        }
                    } else {
                        // Enter Key Tips mode
                        self.onOptionKeyReleased?()
                    }
                }
                return event
            }
        }

        // Any other modifier key change while Option is held → mark as modifier usage
        if isOptionDown {
            wasOptionUsedAsModifier = true
        }

        return event
    }

    /// Handle key down events during Key Tips mode
    private func handleKeyDown(keyCode: CGKeyCode, flags: CGEventFlags, event: CGEvent) -> CGEvent? {
        // Escape key
        if keyCode == 53 {
            if isInKeyTipsMode?() == true {
                DispatchQueue.main.async {
                    self.onEscapePressed?()
                }
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
