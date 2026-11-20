import AppKit
import SwiftUI

struct CountBadge: View {
    let counts: WindowCounts
    var body: some View {
        HStack(spacing: 2) {
            Text("\(counts.total)").foregroundStyle(.white)
            Text("·").foregroundStyle(.white.opacity(0.6))
            Text("\(counts.minimized)").foregroundStyle(Color(red: 1, green: 0.82, blue: 0.35))
        }
        .font(.system(size: 10, weight: .bold, design: .rounded)).monospacedDigit()
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(.black.opacity(0.88), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.45), lineWidth: 0.5))
        .accessibilityLabel("共 \(counts.total) 个窗口，已最小化 \(counts.minimized) 个")
    }
}
final class BadgeController {
    private var panels: [pid_t: NSPanel] = [:]
    private var previousCounts: [pid_t: WindowCounts] = [:]
    func update(_ entries: [DockEntry]) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let screens = NSScreen.screens.map(\.frame)
        var live = Set<pid_t>()
        for entry in entries {
            guard let counts = entry.counts, counts.total > 0 else { continue }
            let rect = Geometry.appKitRect(entry.frame, primaryHeight: primaryHeight)
            guard Geometry.isVisible(rect, screens: screens) else { continue }
            // Hit-test the icon center so hidden Dock / full-screen windows never get floating badges.
            guard AX.dockIsAt(CGPoint(x: entry.frame.midX, y: entry.frame.midY)) else { continue }
            live.insert(entry.pid)
            let panel: NSPanel
            if let old = panels[entry.pid] { panel = old } else {
                panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.setAccessibilityIdentifier("io.github.whdichrn.DockCounts.badge")
                panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
                panel.ignoresMouseEvents = true; panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
                panels[entry.pid] = panel
            }
            if previousCounts[entry.pid] != counts || panel.contentView == nil {
                panel.contentView = NSHostingView(rootView: CountBadge(counts: counts))
                previousCounts[entry.pid] = counts
            }
            let size = panel.contentView!.fittingSize
            panel.setFrame(CGRect(x: rect.maxX - size.width + 2, y: rect.maxY - size.height + 2, width: size.width, height: size.height), display: true)
            panel.orderFrontRegardless()
        }
        for pid in Array(panels.keys) where !live.contains(pid) { panels.removeValue(forKey: pid)?.close(); previousCounts.removeValue(forKey: pid) }
    }
    func hide() { panels.values.forEach { $0.close() }; panels.removeAll(); previousCounts.removeAll() }
}
