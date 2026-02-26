import Cocoa
import SwiftUI

/// Windows-style Key Tips overlay that shows available shortcut keys.
/// Displays as a compact panel below the Excel ribbon area for all levels.
class HUDOverlayWindow {
    private var window: NSWindow?
    private var appState: AppState
    private var hostingView: NSHostingView<KeyTipsPanelView>?

    init(appState: AppState) {
        self.appState = appState
    }

    /// Show the Key Tips overlay
    func show() {
        if window == nil {
            createWindow()
        }
        updateContent()

        // Cancel any in-progress hide animation
        window?.animator().alphaValue = 1.0
        window?.orderFrontRegardless()
    }

    /// Hide the Key Tips overlay
    func hide() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            self.window?.animator().alphaValue = 0
        }, completionHandler: {
            self.window?.orderOut(nil)
        })
    }

    /// Update the overlay content and position
    func updateContent() {
        guard let window = window else { return }

        let keys = appState.keyTipsManager.availableKeys
        let sequence = appState.keyTipsManager.currentSequence

        guard !keys.isEmpty else { return }

        let excelFrame = getExcelWindowFrame()

        let contentView = KeyTipsPanelView(
            keys: keys,
            sequence: sequence
        )

        // Reuse existing hosting view to avoid visual flash on level transitions
        if let existing = hostingView {
            existing.rootView = contentView
        } else {
            let hv = NSHostingView(rootView: contentView)
            hv.autoresizingMask = [.width, .height]
            window.contentView?.addSubview(hv)
            hostingView = hv
        }

        let fittingSize = hostingView!.fittingSize
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxWidth = min(fittingSize.width, screen.width - 40)
        let cappedSize = NSSize(width: max(maxWidth, 200), height: max(fittingSize.height, 30))

        let overlayFrame = calculateOverlayFrame(
            contentSize: cappedSize,
            excelFrame: excelFrame
        )

        hostingView!.frame = NSRect(origin: .zero, size: overlayFrame.size)
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

    // MARK: - Frame Calculation

    /// Calculate overlay frame: centered horizontally below the ribbon area
    private func calculateOverlayFrame(contentSize: NSSize, excelFrame: CGRect?) -> NSRect {
        if let excelFrame = excelFrame {
            let screenHeight = NSScreen.main?.frame.height ?? 900
            // Position just below the ribbon (approximately 85-95px from top of Excel window)
            let ribbonBottomOffset: CGFloat = 90
            let topOfOverlay = excelFrame.origin.y + ribbonBottomOffset
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
            y: screen.origin.y + screen.height - contentSize.height - 95,
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

// MARK: - Key Tips Panel View (used for all levels)

struct KeyTipsPanelView: View {
    let keys: [(key: String, label: String)]
    let sequence: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Sequence breadcrumb
            HStack(spacing: 3) {
                Text("Alt")
                    .font(.system(size: 10, weight: .semibold))
                if !sequence.isEmpty {
                    ForEach(0..<sequence.count, id: \.self) { i in
                        Text(">")
                            .font(.system(size: 9))
                            .foregroundColor(Color.white.opacity(0.6))
                        Text(sequence[i])
                            .font(.system(size: 10, weight: .bold))
                    }
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(red: 0.2, green: 0.2, blue: 0.2).opacity(0.85))
            )

            // Key badges in a compact grid
            let columns = gridColumns(for: keys.count)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                ForEach(0..<keys.count, id: \.self) { i in
                    KeyTipBadgeWithLabel(key: keys[i].key, label: keys[i].label)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(red: 0.2, green: 0.2, blue: 0.2).opacity(0.85))
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        )
    }

    private func gridColumns(for count: Int) -> [GridItem] {
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

// MARK: - Key Tip Badge with Label

struct KeyTipBadgeWithLabel: View {
    let key: String
    let label: String

    var body: some View {
        VStack(spacing: 1) {
            // Key badge
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
