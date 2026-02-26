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

        // Cap width to avoid overflowing the screen
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxWidth = min(fittingSize.width, screen.width - 40)
        let cappedSize = NSSize(width: max(maxWidth, 200), height: max(fittingSize.height, 30))

        // Position relative to the Excel window
        let overlayFrame = calculateOverlayFrame(contentSize: cappedSize, level: level)

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

            // Window frame is in CG coordinates (top-left origin)
            // Convert to AppKit bottom-left origin for NSWindow positioning
            let ribbonOffsetFromTop: CGFloat = level == 0 ? 52 : 85
            let topOfOverlay = excelFrame.origin.y + ribbonOffsetFromTop
            let appKitY = screenHeight - topOfOverlay - contentSize.height

            // Center horizontally within the Excel window
            let x = excelFrame.origin.x + (excelFrame.size.width - contentSize.width) / 2

            return NSRect(
                x: x,
                y: appKitY,
                width: contentSize.width,
                height: contentSize.height
            )
        }

        // Fallback: center near top of screen
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(
            x: screen.origin.x + (screen.width - contentSize.width) / 2,
            y: screen.origin.y + screen.height - contentSize.height - 80,
            width: contentSize.width,
            height: contentSize.height
        )
    }

    /// Get the Excel window frame using CGWindowList (CG coordinates: top-left origin)
    private func getExcelWindowFrame() -> CGRect? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for window in windowList {
            guard let ownerName = window[kCGWindowOwnerName as String] as? String,
                  ownerName == "Microsoft Excel",
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary else {
                continue
            }

            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(bounds, &rect) else { continue }

            // Skip tiny windows (toolbars, popovers)
            if rect.width > 200 && rect.height > 200 {
                return rect
            }
        }

        return nil
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
                    ForEach(0..<sequence.count, id: \.self) { i in
                        Text(">")
                            .font(.system(size: 9))
                            .foregroundColor(Color.white.opacity(0.6))
                        Text(sequence[i])
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

            // Key badges in a grid (wraps for large key sets)
            let columns = gridColumns(for: keys.count)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                ForEach(0..<keys.count, id: \.self) { i in
                    KeyTipBadge(key: keys[i].key, label: keys[i].label)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.75))
        )
    }

    private func gridColumns(for count: Int) -> [GridItem] {
        // Use fewer columns for small sets, more for large
        let cols: Int
        if count <= 6 {
            cols = count
        } else if count <= 12 {
            cols = min(count, 8)
        } else {
            cols = min(count, 12)
        }
        return Array(repeating: GridItem(.flexible(minimum: 40), spacing: 6), count: max(cols, 1))
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
