import AppKit
import SwiftUI

/// A small, pixel-aligned caption tucked into the icon's lower corner.
/// The upper-right corner stays free for the application's own notification badge.
struct BadgeMetrics: Equatable {
    let fontSize: CGFloat
    let contentSize: CGSize
    let scale: CGFloat
    static func make(counts: WindowCounts, tileSide: CGFloat, scale: CGFloat) -> BadgeMetrics {
        let scale = max(1, scale)
        let fontSize = (min(12, max(7.5, tileSide * 0.25 + 0.5)) * 2).rounded() / 2
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        let text = (counts.label as NSString).size(withAttributes: [.font: font])
        let width = min(text.width + 5, max(12, tileSide - 2))
        return BadgeMetrics(fontSize: fontSize,
                            contentSize: CGSize(width: ceil(width * scale) / scale,
                                                height: ceil((font.ascender - font.descender + 2) * scale) / scale),
                            scale: scale)
    }
    var size: CGSize { CGSize(width: contentSize.width + 2, height: contentSize.height + 2) }
}

enum BadgePlacement {
    static func frame(tile: CGRect, size: CGSize, scale: CGFloat) -> CGRect {
        let side = min(tile.width, tile.height) * 0.8
        let icon = CGRect(x: tile.midX - side / 2, y: tile.midY - side / 2, width: side, height: side)
        let scale = max(1, scale)
        return CGRect(x: ((icon.maxX - size.width + 2) * scale).rounded() / scale,
                      y: ((icon.minY - 1) * scale).rounded() / scale,
                      width: size.width, height: size.height)
    }
}

struct CountBadge: View {
    let counts: WindowCounts
    var metrics: BadgeMetrics? = nil
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        let m = metrics ?? .make(counts: counts, tileSide: 32, scale: 2)
        let ink: Color = contrast == .increased ? .primary : .secondary
        (Text("\(counts.total)").foregroundColor(.primary)
         + Text("·").foregroundColor(ink.opacity(0.75))
         + Text("\(counts.minimized)").foregroundColor(ink))
        .font(.system(size: m.fontSize, weight: .medium)).monospacedDigit()
        .lineLimit(1).minimumScaleFactor(0.55)
        .padding(.horizontal, 2.5)
        .frame(width: m.contentSize.width, height: m.contentSize.height)
        .background {
            Group {
                if reduceTransparency {
                    Capsule().fill(Color(nsColor: .windowBackgroundColor))
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
            .overlay(Capsule().strokeBorder(.primary.opacity(contrast == .increased ? 0.35 : 0.14), lineWidth: 1 / m.scale))
            .shadow(color: .black.opacity(0.13), radius: 0.7, y: 0.3)
        }
        .padding(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("共 \(counts.total) 个窗口，已最小化 \(counts.minimized) 个")
    }
}

final class BadgeController {
    private var panels: [pid_t: NSPanel] = [:]
    private var previous: [pid_t: Presentation] = [:]
    private struct Presentation: Equatable { let counts: WindowCounts; let metrics: BadgeMetrics }
    func update(_ entries: [DockEntry]) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let screens = NSScreen.screens
        let screenFrames = screens.map(\.frame)
        // One visibility probe is enough for the Dock. Avoid a cross-process hit test
        // for every badge on every magnification frame.
        let candidates = entries.filter {
            ($0.counts?.total ?? 0) > 0 && Geometry.isVisible(Geometry.appKitRect($0.frame, primaryHeight: primaryHeight), screens: screenFrames)
        }
        guard let probe = candidates.first, AX.dockIsAt(CGPoint(x: probe.frame.midX, y: probe.frame.midY)) else { hide(); return }
        var live = Set<pid_t>()
        for entry in candidates {
            guard let counts = entry.counts else { continue }
            let tile = Geometry.appKitRect(entry.frame, primaryHeight: primaryHeight)
            let screen = screens.first { $0.frame.intersects(tile) }
            let scale = screen?.backingScaleFactor ?? 2
            let metrics = BadgeMetrics.make(counts: counts, tileSide: min(tile.width, tile.height), scale: scale)
            let presentation = Presentation(counts: counts, metrics: metrics)
            live.insert(entry.pid)
            let panel: NSPanel
            if let old = panels[entry.pid] { panel = old } else {
                panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.setAccessibilityIdentifier("io.github.whdichrn.DockCounts.badge")
                panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
                panel.hidesOnDeactivate = false; panel.animationBehavior = .none
                panel.ignoresMouseEvents = true
                panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
                panels[entry.pid] = panel
            }
            if previous[entry.pid] != presentation {
                let view = CountBadge(counts: counts, metrics: metrics)
                if let host = panel.contentView as? NSHostingView<CountBadge> { host.rootView = view }
                else { panel.contentView = NSHostingView(rootView: view) }
                previous[entry.pid] = presentation
            }
            let frame = BadgePlacement.frame(tile: tile, size: metrics.size, scale: scale)
            if panel.frame != frame { panel.setFrame(frame, display: true) }
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
        for pid in Array(panels.keys) where !live.contains(pid) {
            panels.removeValue(forKey: pid)?.close(); previous.removeValue(forKey: pid)
        }
    }
    func hide() { panels.values.forEach { $0.close() }; panels.removeAll(); previous.removeAll() }
}
