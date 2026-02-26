import Cocoa
import SwiftUI

/// Windows-style Key Tips overlay that shows badges on the Excel ribbon area.
/// Level 0 (tab keys): Individual floating badges positioned across the ribbon tab bar.
/// Level 1+ (sub-keys): Compact grid positioned below the ribbon area.
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

        let wasHidden = window?.alphaValue == 0 || !(window?.isVisible ?? false)
        window?.orderFrontRegardless()

        if wasHidden {
            // Only animate in when the window was previously hidden,
            // not when transitioning between levels (which just updates content)
            window?.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                window?.animator().alphaValue = 1.0
            }
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

        let excelFrame = getExcelWindowFrame()

        if level == 0 {
            // Level 0: Individual floating badges across the ribbon tab bar
            let contentView = RibbonTabKeyTipsView(
                keys: keys,
                ribbonWidth: excelFrame?.width ?? 1200
            )
            let hostingView = NSHostingView(rootView: contentView)

            // Size the window to span the ribbon area
            let ribbonWidth = excelFrame?.width ?? 1200
            let contentHeight: CGFloat = 28
            let contentSize = NSSize(width: ribbonWidth, height: contentHeight)

            let overlayFrame = calculateRibbonOverlayFrame(
                contentSize: contentSize,
                excelFrame: excelFrame
            )

            window.contentView?.subviews.forEach { $0.removeFromSuperview() }
            hostingView.frame = NSRect(origin: .zero, size: overlayFrame.size)
            hostingView.autoresizingMask = [.width, .height]
            window.contentView?.addSubview(hostingView)
            window.setFrame(overlayFrame, display: true)
        } else {
            // Level 1+: Compact grid below the ribbon area
            let contentView = SubLevelKeyTipsView(
                keys: keys,
                sequence: sequence
            )
            let hostingView = NSHostingView(rootView: contentView)
            let fittingSize = hostingView.fittingSize

            let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let maxWidth = min(fittingSize.width, screen.width - 40)
            let cappedSize = NSSize(width: max(maxWidth, 200), height: max(fittingSize.height, 30))

            let overlayFrame = calculateSubLevelOverlayFrame(
                contentSize: cappedSize,
                excelFrame: excelFrame
            )

            window.contentView?.subviews.forEach { $0.removeFromSuperview() }
            hostingView.frame = NSRect(origin: .zero, size: overlayFrame.size)
            hostingView.autoresizingMask = [.width, .height]
            window.contentView?.addSubview(hostingView)
            window.setFrame(overlayFrame, display: true)
        }
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

    // MARK: - Frame Calculations

    /// Calculate overlay frame for Level 0: positioned over the ribbon tab bar
    private func calculateRibbonOverlayFrame(contentSize: NSSize, excelFrame: CGRect?) -> NSRect {
        if let excelFrame = excelFrame {
            let screenHeight = NSScreen.main?.frame.height ?? 900
            // Ribbon tab bar is approximately 48-55px from the top of the Excel window
            let ribbonTabOffset: CGFloat = 52
            let topOfOverlay = excelFrame.origin.y + ribbonTabOffset
            let appKitY = screenHeight - topOfOverlay - contentSize.height

            return NSRect(
                x: excelFrame.origin.x,
                y: appKitY,
                width: contentSize.width,
                height: contentSize.height
            )
        }

        // Fallback: top of screen
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(
            x: screen.origin.x,
            y: screen.origin.y + screen.height - contentSize.height - 55,
            width: contentSize.width,
            height: contentSize.height
        )
    }

    /// Calculate overlay frame for Level 1+: positioned below the ribbon area
    private func calculateSubLevelOverlayFrame(contentSize: NSSize, excelFrame: CGRect?) -> NSRect {
        if let excelFrame = excelFrame {
            let screenHeight = NSScreen.main?.frame.height ?? 900
            // Sub-level content appears just below the ribbon (approximately 85-95px from top)
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

// MARK: - Level 0: Ribbon Tab Key Tips (floating badges across the tab bar)

struct RibbonTabKeyTipsView: View {
    let keys: [(key: String, label: String)]
    let ribbonWidth: CGFloat

    // Fixed pixel positions (in points) from the left edge of the Excel window.
    // Unlike fractional positions, these don't drift apart as the window gets wider,
    // matching the actual ribbon tab labels which stay at fixed positions.
    private static let tabPositions: [String: CGFloat] = [
        "F": 46,     // File
        "H": 100,    // Home
        "N": 160,    // Insert
        "P": 280,    // Page Layout
        "M": 370,    // Formulas
        "A": 435,    // Data
        "R": 500,    // Review
        "W": 555,    // View
        "L": 630,    // Developer
        "Q": 710,    // Search / Tell Me
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // Position each badge at its approximate tab location
                ForEach(0..<keys.count, id: \.self) { i in
                    let key = keys[i].key
                    let x = Self.tabPositions[key] ?? fallbackPosition(for: i)

                    FloatingKeyBadge(key: key)
                        .position(x: x, y: geometry.size.height / 2)
                }
            }
        }
    }

    /// Fallback position for keys not in the tab position map
    private func fallbackPosition(for index: Int) -> CGFloat {
        // Space legacy keys (E, O, D, I, T) after the main tabs
        let baseOffset: CGFloat = 750
        let spacing: CGFloat = 55
        return baseOffset + CGFloat(index) * spacing
    }
}

// MARK: - Level 1+: Sub-Level Key Tips (compact grid below ribbon)

struct SubLevelKeyTipsView: View {
    let keys: [(key: String, label: String)]
    let sequence: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Sequence breadcrumb
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
                        .fill(Color(red: 0.2, green: 0.2, blue: 0.2).opacity(0.85))
                )
            }

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

// MARK: - Floating Key Tip Badge (Windows-style, no background panel)

struct FloatingKeyBadge: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white)
            .frame(minWidth: 22, minHeight: 20)
            .padding(.horizontal, 3)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(red: 0.2, green: 0.2, blue: 0.2).opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color(white: 0.5), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Key Tip Badge with Label (for sub-level display)

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
