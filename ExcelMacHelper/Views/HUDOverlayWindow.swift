import Cocoa
import SwiftUI

/// Windows-style Key Tips overlay that shows badges on the Excel ribbon area
class HUDOverlayWindow {
    private var window: NSWindow?
    private var appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    /// Show the Key Tips overlay
    func show() {
        if window == nil {
            createWindow()
        }
        updateContent()
        window?.orderFrontRegardless()

        // Animate in
        window?.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            window?.animator().alphaValue = 1.0
        }
    }

    /// Hide the Key Tips overlay
    func hide() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            window?.animator().alphaValue = 0
        }, completionHandler: {
            self.window?.orderOut(nil)
        })
    }

    /// Update the overlay content and position
    func updateContent() {
        guard let window = window else { return }

        let keys = appState.keyTipsManager.availableKeys
        let sequence = appState.keyTipsManager.currentSequence
        let level = appState.keyTipsManager.currentLevel

        guard !keys.isEmpty else { return }

        let contentView = KeyTipsBadgeView(
            keys: keys,
            sequence: sequence,
            level: level
        )

        let hostingView = NSHostingView(rootView: contentView)
        let fittingSize = hostingView.fittingSize

        // Position relative to the Excel window
        let overlayFrame = calculateOverlayFrame(contentSize: fittingSize, level: level)

        window.contentView?.subviews.forEach { $0.removeFromSuperview() }
        hostingView.frame = NSRect(origin: .zero, size: overlayFrame.size)
        hostingView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(hostingView)
        window.setFrame(overlayFrame, display: true)
    }

    private func createWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 60),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false

        self.window = window
    }

    /// Calculate overlay frame positioned over the Excel ribbon
    private func calculateOverlayFrame(contentSize: NSSize, level: Int) -> NSRect {
        if let excelFrame = getExcelWindowFrame() {
            let screenHeight = NSScreen.main?.frame.height ?? 900

            // AX coordinates use top-left origin; convert to AppKit bottom-left origin
            // Position over the ribbon area of the Excel window
            let ribbonOffsetFromTop: CGFloat = level == 0 ? 52 : 85
            let axOverlayTop = excelFrame.origin.y + ribbonOffsetFromTop
            let appKitY = screenHeight - axOverlayTop - contentSize.height

            // Center horizontally within the Excel window
            let x = excelFrame.origin.x + (excelFrame.size.width - contentSize.width) / 2

            return NSRect(
                x: x,
                y: appKitY,
                width: max(contentSize.width, 200),
                height: max(contentSize.height, 30)
            )
        }

        // Fallback: center near top of screen
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(
            x: screen.origin.x + (screen.width - contentSize.width) / 2,
            y: screen.origin.y + screen.height - contentSize.height - 80,
            width: max(contentSize.width, 200),
            height: max(contentSize.height, 30)
        )
    }

    /// Get the Excel window frame using the Accessibility API (AX coordinates: top-left origin)
    private func getExcelWindowFrame() -> NSRect? {
        guard let excelApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.microsoft.Excel"
        ).first else { return nil }

        let appElement = AXUIElementCreateApplication(excelApp.processIdentifier)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              let mainWindow = windows.first else {
            return nil
        }

        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(mainWindow, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(mainWindow, kAXSizeAttribute as CFString, &sizeRef) == .success else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionRef as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)

        return NSRect(origin: position, size: size)
    }
}

// MARK: - Windows-Style Key Tips Badge View

struct KeyTipsBadgeView: View {
    let keys: [(key: String, label: String)]
    let sequence: [String]
    let level: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Sequence breadcrumb (shown when navigating deeper levels)
            if !sequence.isEmpty {
                HStack(spacing: 3) {
                    Text("Alt")
                        .font(.system(size: 10, weight: .semibold))
                    ForEach(Array(sequence.enumerated()), id: \.offset) { _, key in
                        Text(">")
                            .font(.system(size: 9))
                            .foregroundColor(Color.white.opacity(0.6))
                        Text(key)
                            .font(.system(size: 10, weight: .bold))
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.black.opacity(0.7))
                )
            }

            // Key badges in a horizontal flow
            FlowLayoutView(keys: keys)
        }
        .padding(6)
    }
}

// MARK: - Flow Layout for Badges

/// Horizontal flow layout that wraps badges to the next line when needed
struct FlowLayoutView: View {
    let keys: [(key: String, label: String)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(keys, id: \.key) { item in
                KeyTipBadge(key: item.key, label: item.label)
            }
        }
    }
}

// MARK: - Individual Key Tip Badge (Windows-style)

struct KeyTipBadge: View {
    let key: String
    let label: String

    var body: some View {
        VStack(spacing: 1) {
            // Key badge - small gray square like Windows
            Text(key)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .frame(minWidth: 20, minHeight: 18)
                .padding(.horizontal, 3)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(white: 0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color(white: 0.55), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 1.5, x: 0, y: 1)

            // Label below the badge
            if !label.isEmpty {
                Text(truncatedLabel)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .frame(maxWidth: 60)
            }
        }
    }

    private var truncatedLabel: String {
        if label.count > 12 {
            return String(label.prefix(11)) + "..."
        }
        return label
    }
}
