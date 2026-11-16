import AppKit
import FeelingsCore
import SwiftUI

/// A click-through speech bubble that pops out under the menu-bar face for a few seconds.
@MainActor
final class BubbleController {
    private var panel: NSPanel?
    private var hide: Task<Void, Never>?

    static let width: CGFloat = 300

    func show(_ text: String, mood: Mood) {
        hide?.cancel()
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let host = NSHostingView(rootView: BubbleView(text: text, mood: mood))
        host.frame.size = host.fittingSize
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        panel.setFrameOrigin(origin(for: host.fittingSize))

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }

        // About as long as it takes to read, between 5 and 12 seconds.
        let seconds = min(12, max(5, Double(text.split(separator: " ").count) * 0.45))
        hide = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let panel = self?.panel else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.35; panel.animator().alphaValue = 0 }) {
                Task { @MainActor in
                    if panel.alphaValue == 0 { panel.orderOut(nil) }
                }
            }
        }
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return p
    }

    /// Under our status item when it can be found, else the top-right corner.
    private func origin(for size: NSSize) -> NSPoint {
        let item = NSApp.windows.first { String(describing: type(of: $0)).contains("NSStatusBarWindow") && $0.isVisible }
        let screen = item?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        var x = visible.maxX - size.width - 12
        if let frame = item?.frame {
            x = frame.midX - size.width + 34
        }
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        return NSPoint(x: x, y: visible.maxY - size.height - 6)
    }
}

private struct BubbleView: View {
    let text: String
    let mood: Mood

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            FaceView(mood: mood, animated: false)
                .frame(width: 40, height: 32)
            Text(text)
                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: BubbleController.width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(mood.screen.opacity(0.9), lineWidth: 2))
        .padding(6)
    }
}
