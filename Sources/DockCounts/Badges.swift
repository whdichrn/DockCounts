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
                            contentSize: CGSize(width: ceil(width),
                                                height: ceil(font.ascender - font.descender + 2)),
                            scale: scale)
    }
    var size: CGSize { CGSize(width: contentSize.width + 2, height: contentSize.height + 2) }
}

enum BadgePlacement {
    static func frame(tile: CGRect, size: CGSize, scale: CGFloat) -> CGRect {
        let side = min(tile.width, tile.height) * 0.8
        let icon = CGRect(x: tile.midX - side / 2, y: tile.midY - side / 2, width: side, height: side)
        // WindowServer quantizes borderless window frames to whole points even
        // on Retina. Request representable frames to avoid setting the same
        // half-point frame forever (and invalidating every glass backdrop).
        return CGRect(x: (icon.maxX - size.width + 2).rounded(),
                      y: (icon.minY - 1).rounded(),
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
        .background(BadgeMaterial(reduceTransparency: reduceTransparency))
        .overlay(Capsule().strokeBorder(.primary.opacity(contrast == .increased ? 0.35 : (reduceTransparency ? 0.18 : 0.12)), lineWidth: 1 / m.scale))
        .shadow(color: .black.opacity(0.10), radius: 0.6, y: 0.3)
        .padding(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("共 \(counts.total) 个窗口，已最小化 \(counts.minimized) 个")
    }
}

/// Use system glass on newer systems and an AppKit backdrop on macOS 15.
/// The accessibility setting changes the system's material recipe; we do not
/// replace the backdrop with an opaque SwiftUI rectangle.
struct BadgeMaterial: NSViewRepresentable {
    let reduceTransparency: Bool
    func makeNSView(context: Context) -> NSView {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            let view = CapsuleGlassView()
            view.configure(reduced: reduceTransparency)
            return view
        }
        #endif
        return CapsuleBackdropView()
    }
    func updateNSView(_ view: NSView, context: Context) {
        #if compiler(>=6.2)
        if #available(macOS 26, *), let glass = view as? CapsuleGlassView { glass.configure(reduced: reduceTransparency) }
        #endif
        view.needsLayout = true
    }
}

#if compiler(>=6.2)
@available(macOS 26, *)
private final class CapsuleGlassView: NSGlassEffectView {
    override init(frame: NSRect) { super.init(frame: frame); style = .regular }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(reduced: Bool) {
        // Clear glass retains a blurred backdrop under Reduce Transparency on
        // current macOS. A neutral scrim restores text contrast without flattening it.
        style = reduced ? .clear : .regular
        tintColor = reduced ? NSColor.windowBackgroundColor.withAlphaComponent(0.55) : nil
    }
    override func layout() { super.layout(); cornerRadius = bounds.height / 2 }
}
#endif

private final class CapsuleBackdropView: NSVisualEffectView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .hudWindow; blendingMode = .behindWindow; state = .active
        wantsLayer = true; layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); layer?.cornerRadius = bounds.height / 2 }
}

final class BadgeController {
    private var panels: [pid_t: NSPanel] = [:]
    private var previous: [pid_t: Presentation] = [:]
    private struct Presentation: Equatable { let counts: WindowCounts; let metrics: BadgeMetrics }
    static let collectionBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    func update(_ entries: [DockEntry], visible: Bool, runningPIDs: Set<pid_t>) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let screens = NSScreen.screens
        var displayed = Set<pid_t>()
        for entry in entries {
            guard let counts = entry.counts, counts.total > 0 else { continue }
            let tile = Geometry.appKitRect(entry.frame, primaryHeight: primaryHeight)
            guard tile.width.isFinite, tile.height.isFinite, tile.width > 4, tile.height > 4 else { continue }
            let screen = screens.first { $0.frame.intersects(tile) } ?? screens.first
            let scale = screen?.backingScaleFactor ?? 2
            let metrics = BadgeMetrics.make(counts: counts, tileSide: min(tile.width, tile.height), scale: scale)
            let presentation = Presentation(counts: counts, metrics: metrics)
            let panel: NSPanel
            if let old = panels[entry.pid] { panel = old } else {
                panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.setAccessibilityIdentifier("io.github.whdichrn.DockCounts.badge")
                panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
                panel.hidesOnDeactivate = false; panel.animationBehavior = .none
                panel.ignoresMouseEvents = true
                panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
                panel.collectionBehavior = Self.collectionBehavior
                panels[entry.pid] = panel
                DockTrace.event("panel.create pid=\(entry.pid) number=\(panel.windowNumber)")
            }
            if previous[entry.pid] != presentation {
                let view = CountBadge(counts: counts, metrics: metrics)
                if let host = panel.contentView as? NSHostingView<CountBadge> { host.rootView = view }
                else { panel.contentView = NSHostingView(rootView: view) }
                previous[entry.pid] = presentation
            }
            let frame = BadgePlacement.frame(tile: tile, size: metrics.size, scale: scale)
            // Position first, then reveal. The same window survives desktop transitions.
            if panel.frame != frame {
                panel.setFrame(frame, display: true)
                DockTrace.event("panel.move pid=\(entry.pid) number=\(panel.windowNumber) tile=\(tile) badge=\(frame)")
            }
            if visible && screens.contains(where: { $0.frame.intersects(frame) }) {
                displayed.insert(entry.pid)
                if !panel.isVisible { panel.orderFrontRegardless(); DockTrace.event("panel.show pid=\(entry.pid) number=\(panel.windowNumber)") }
            }
        }
        for (pid, panel) in panels where !displayed.contains(pid) && panel.isVisible {
            panel.orderOut(nil); DockTrace.event("panel.hide pid=\(pid) number=\(panel.windowNumber)")
        }
        for pid in Array(panels.keys) where !runningPIDs.contains(pid) {
            panels.removeValue(forKey: pid)?.close(); previous.removeValue(forKey: pid)
        }
    }
    func hide() { for panel in panels.values where panel.isVisible { panel.orderOut(nil) } }
    func reset() { panels.values.forEach { $0.close() }; panels.removeAll(); previous.removeAll() }
}
