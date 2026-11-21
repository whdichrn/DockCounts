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
    var appearance = BadgeAppearance()
    var inWindowBackdrop = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme
    private var supportsGlass: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26, *) { return true }
        #endif
        return false
    }
    var body: some View {
        let m = metrics ?? .make(counts: counts, tileSide: 32, scale: 2)
        let light = appearance.usesLightText(reduceTransparency: reduceTransparency, supportsGlass: supportsGlass, darkAppearance: scheme == .dark)
        let primary: Color = light ? .white : .black
        let ink = primary.opacity(contrast == .increased || appearance.vivid ? 1 : 0.70)
        (Text("\(counts.total)").foregroundColor(primary)
         + Text("·").foregroundColor(ink.opacity(0.75))
         + Text("\(counts.minimized)").foregroundColor(ink))
        .font(.system(size: m.fontSize, weight: .medium)).monospacedDigit()
        .lineLimit(1).minimumScaleFactor(0.55)
        .padding(.horizontal, 2.5)
        .frame(width: m.contentSize.width, height: m.contentSize.height)
        .background(BadgeMaterial(appearance: appearance, reduceTransparency: reduceTransparency, inWindowBackdrop: inWindowBackdrop))
        .overlay {
            if appearance.edge != .none {
                Capsule().strokeBorder(primary.opacity(contrast == .increased || appearance.vivid ? 0.40 : 0.18), lineWidth: appearance.edge == .outline ? 1.25 : 1 / m.scale)
            }
        }
        .overlay {
            if appearance.highlights && appearance.surface != .solid {
                Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(appearance.vivid ? 0.65 : 0.35), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom), lineWidth: 1 / m.scale)
            }
        }
        .shadow(color: .black.opacity(appearance.shadow ? 0.12 : 0), radius: 0.7, y: 0.3)
        .padding(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("共 \(counts.total) 个窗口，已最小化 \(counts.minimized) 个")
    }
}

/// Use system glass on newer systems and an AppKit backdrop on macOS 15.
/// The accessibility setting changes the system's material recipe; we do not
/// replace the backdrop with an opaque SwiftUI rectangle.
struct BadgeMaterial: NSViewRepresentable {
    let appearance: BadgeAppearance
    let reduceTransparency: Bool
    var inWindowBackdrop = false
    @Environment(\.colorScheme) private var scheme
    func makeNSView(context: Context) -> BadgeBackdropView { BadgeBackdropView() }
    func updateNSView(_ view: BadgeBackdropView, context: Context) {
        // Reading the appearance ensures dynamic system/accent colors are resolved
        // again when the host changes between light and dark mode.
        _ = scheme
        view.configure(appearance: appearance, reduced: reduceTransparency, inWindowBackdrop: inWindowBackdrop)
    }
}

final class BadgeBackdropView: NSView {
    private var backing: NSView?
    private var kind: BadgeSurface?
    private let tint = NSView()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.masksToBounds = true
        tint.wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(appearance: BadgeAppearance, reduced: Bool, inWindowBackdrop: Bool = false) {
        var supportsGlass = false
        #if compiler(>=6.2)
        if #available(macOS 26, *) { supportsGlass = true }
        #endif
        let resolved = appearance.resolvedSurface(reduceTransparency: reduced, supportsGlass: supportsGlass)
        if kind != resolved {
            backing?.removeFromSuperview(); tint.removeFromSuperview()
            let view: NSView
            #if compiler(>=6.2)
            if #available(macOS 26, *), resolved == .glass || resolved == .clear {
                let glass = NSGlassEffectView()
                glass.style = resolved == .clear ? .clear : .regular
                view = glass
            } else { view = makeFallback(resolved) }
            #else
            view = makeFallback(resolved)
            #endif
            backing = view; kind = resolved
            addSubview(view); addSubview(tint)
        }
        alphaValue = appearance.backgroundOpacity
        isHidden = appearance.backgroundOpacity <= 0.001
        let color = appearance.tintColor()
        let strength = appearance.effectiveTintStrength(reduceTransparency: reduced)
        tint.layer?.backgroundColor = nil
        #if compiler(>=6.2)
        if #available(macOS 26, *), let glass = backing as? NSGlassEffectView {
            glass.tintColor = color?.withAlphaComponent(strength)
        } else { tint.layer?.backgroundColor = color?.withAlphaComponent(strength).cgColor }
        #else
        tint.layer?.backgroundColor = color?.withAlphaComponent(strength).cgColor
        #endif
        if let effect = backing as? NSVisualEffectView {
            effect.isEmphasized = appearance.vivid
            effect.blendingMode = inWindowBackdrop ? .withinWindow : .behindWindow
        }
        if resolved == .solid { backing?.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor }
        needsLayout = true
    }
    private func makeFallback(_ surface: BadgeSurface) -> NSView {
        if surface == .solid { let view = NSView(); view.wantsLayer = true; return view }
        let view = NSVisualEffectView()
        view.material = .hudWindow; view.blendingMode = .behindWindow; view.state = .active
        return view
    }
    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        backing?.frame = bounds; tint.frame = bounds
        #if compiler(>=6.2)
        if #available(macOS 26, *), let glass = backing as? NSGlassEffectView { glass.cornerRadius = bounds.height / 2 }
        #endif
    }
}

final class BadgeController {
    private var panels: [pid_t: NSPanel] = [:]
    private var previous: [pid_t: Presentation] = [:]
    private struct Presentation: Equatable { let counts: WindowCounts; let metrics: BadgeMetrics; let appearance: BadgeAppearance }
    static let collectionBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    func update(_ entries: [DockEntry], visible: Bool, runningPIDs: Set<pid_t>, appearance: BadgeAppearance = BadgeAppearance()) {
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
            let presentation = Presentation(counts: counts, metrics: metrics, appearance: appearance)
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
                let view = CountBadge(counts: counts, metrics: metrics, appearance: appearance)
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
