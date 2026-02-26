import Cocoa
import SwiftUI

/// A translucent HUD overlay window that displays Key Tips
class HUDOverlayWindow {
    private var window: NSWindow?
    private var appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    /// Show the HUD overlay
    func show() {
        if window == nil {
            createWindow()
        }
        updateContent()
        window?.orderFront(nil)

        // Animate in
        window?.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window?.animator().alphaValue = 1.0
        }
    }

    /// Hide the HUD overlay
    func hide() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            window?.animator().alphaValue = 0
        }, completionHandler: {
            self.window?.orderOut(nil)
        })
    }

    /// Update the HUD content
    func updateContent() {
        guard let window = window else { return }

        let hostingView = NSHostingView(rootView: HUDContentView(appState: appState))
        hostingView.frame = window.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]

        window.contentView?.subviews.forEach { $0.removeFromSuperview() }
        window.contentView?.addSubview(hostingView)

        // Resize window to fit content
        let size = hostingView.fittingSize
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let x = (screenFrame.width - size.width) / 2 + screenFrame.origin.x
        let y = screenFrame.origin.y + screenFrame.height - size.height - 100 // Near top of screen
        window.setFrame(NSRect(x: x, y: y, width: max(size.width, 200), height: max(size.height, 60)), display: true)
    }

    private func createWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false

        self.window = window
    }
}

// MARK: - HUD Content View

struct HUDContentView: View {
    @ObservedObject var appState: AppState

    private var keyTips: KeyTipsManager {
        appState.keyTipsManager
    }

    var body: some View {
        VStack(spacing: 8) {
            // Current sequence display
            if !keyTips.currentSequence.isEmpty {
                HStack(spacing: 4) {
                    Text("Alt")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    ForEach(keyTips.currentSequence, id: \.self) { key in
                        Text(">")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(key)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }
                .padding(.bottom, 2)
            } else {
                Text("Key Tips - Press a letter key")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            // Available keys grid
            let keys = keyTips.availableKeys
            if !keys.isEmpty {
                LazyVGrid(columns: gridColumns(for: keys.count), spacing: 6) {
                    ForEach(keys, id: \.key) { item in
                        KeyTipBadge(key: item.key, label: item.label)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private func gridColumns(for count: Int) -> [GridItem] {
        let cols = min(max(count, 1), 8)
        return Array(repeating: GridItem(.flexible(), spacing: 6), count: cols)
    }
}

// MARK: - Key Tip Badge

struct KeyTipBadge: View {
    let key: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(key)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.8))
                )

            Text(truncatedLabel)
                .font(.system(size: 9, weight: .regular))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 70)
        }
    }

    private var truncatedLabel: String {
        if label.count > 12 {
            return String(label.prefix(11)) + "..."
        }
        return label
    }
}
