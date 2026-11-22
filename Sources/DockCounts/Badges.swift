import AppKit
import SwiftUI

/// Compact, legible Dock badge positioned in the lower-right corner,
/// keeping the upper-right corner reserved for system notification badges.
struct BadgeMetrics: Equatable {
    let fontSize: CGFloat
    let contentSize: CGSize
    let scale: CGFloat

    static func make(
        counts: WindowCounts,
        tileSide: CGFloat,
        scale: CGFloat,
        size: BadgeSize = .compact
    ) -> BadgeMetrics {
        let scale = max(1, scale)
        let factor: CGFloat = size == .compact ? 0.88 : 1.0
        let rawFont = max(7.0, min(10.5, tileSide * 0.21 * factor))
        let fontSize = (rawFont * 2).rounded() / 2
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
        let maxHeight = max(11, floor(tileSide * 0.36))
        let height = min(max(11, ceil(font.ascender - font.descender + 2.5)), maxHeight)

        let totalWidth = ("\(counts.total)" as NSString).size(withAttributes: [.font: font]).width
        let rawWidth: CGFloat
        if counts.minimized == 0 {
            rawWidth = max(height, ceil(totalWidth + 5.5))
        } else {
            let minWidth = ("\(counts.minimized)" as NSString).size(withAttributes: [.font: font]).width
            let arrowWidth = ceil(fontSize * 0.72)
            rawWidth = ceil(totalWidth + arrowWidth + minWidth + 6.5)
        }
        let maxWidth = max(12, floor(tileSide * 0.74))
        let width = min(rawWidth, maxWidth)

        return BadgeMetrics(
            fontSize: fontSize,
            contentSize: CGSize(width: width, height: height),
            scale: scale
        )
    }

    var size: CGSize {
        CGSize(width: contentSize.width + 2, height: contentSize.height + 2)
    }
}

enum BadgePlacement {
    static func frame(tile: CGRect, size: CGSize, scale: CGFloat) -> CGRect {
        let side = min(tile.width, tile.height) * 0.80
        let icon = CGRect(x: tile.midX - side / 2, y: tile.midY - side / 2, width: side, height: side)
        // WindowServer quantizes borderless window frames to whole points.
        let x = min(tile.maxX - size.width, max(tile.minX, (icon.maxX - size.width + 1).rounded()))
        let y = max(tile.minY, min(tile.midY - size.height / 2, icon.minY.rounded()))
        return CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
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

    var body: some View {
        let isDark = scheme == .dark
        let m = metrics ?? .make(counts: counts, tileSide: 44, scale: 2, size: appearance.size)
        let (primary, secondary) = textColors(isDark: isDark)

        Group {
            if counts.minimized == 0 {
                Text("\(counts.total)")
                    .foregroundColor(primary)
            } else {
                HStack(spacing: 1) {
                    Text("\(counts.total)")
                        .foregroundColor(primary)
                    Image(systemName: "arrow.down")
                        .font(.system(size: m.fontSize * 0.68, weight: .bold))
                        .foregroundColor(secondary)
                    Text("\(counts.minimized)")
                        .foregroundColor(secondary)
                }
            }
        }
        .font(.system(size: m.fontSize, weight: .semibold))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.65)
        .padding(.horizontal, counts.minimized == 0 ? 2 : 3)
        .frame(width: m.contentSize.width, height: m.contentSize.height)
        .background(
            BadgeMaterial(
                appearance: appearance,
                reduceTransparency: reduceTransparency,
                isDark: isDark,
                inWindowBackdrop: inWindowBackdrop
            )
        )
        .overlay {
            Capsule().strokeBorder(borderColor(isDark: isDark), lineWidth: 1 / m.scale)
        }
        .shadow(color: .black.opacity(isDark ? 0.32 : 0.14), radius: 1.4, y: 0.5)
        .padding(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("共 \(counts.total) 个窗口，已最小化 \(counts.minimized) 个")
    }

    private func textColors(isDark: Bool) -> (Color, Color) {
        if appearance.preset == .accent {
            return (.white, .white.opacity(0.86))
        }
        if isDark {
            let primary = Color(nsColor: NSColor(srgbRed: 0.96, green: 0.97, blue: 0.98, alpha: 1))
            let amber = Color(nsColor: NSColor(srgbRed: 1.0, green: 0.70, blue: 0.25, alpha: 1))
            return (primary, amber)
        } else {
            let primary = Color(nsColor: NSColor(srgbRed: 0.08, green: 0.09, blue: 0.10, alpha: 1))
            let amber = Color(nsColor: NSColor(srgbRed: 0.76, green: 0.37, blue: 0.0, alpha: 1))
            return (primary, amber)
        }
    }

    private func borderColor(isDark: Bool) -> Color {
        let boosted = contrast == .increased
        if appearance.preset == .accent {
            return .white.opacity(boosted ? 0.45 : 0.26)
        }
        if isDark {
            return .white.opacity(boosted ? 0.38 : 0.18)
        }
        return .black.opacity(boosted ? 0.32 : 0.11)
    }
}

struct BadgeMaterial: NSViewRepresentable {
    let appearance: BadgeAppearance
    let reduceTransparency: Bool
    let isDark: Bool
    var inWindowBackdrop = false

    func makeNSView(context: Context) -> BadgeBackdropView { BadgeBackdropView() }

    func updateNSView(_ view: BadgeBackdropView, context: Context) {
        view.configure(
            appearance: appearance,
            reduced: reduceTransparency,
            isDark: isDark,
            inWindowBackdrop: inWindowBackdrop
        )
    }
}

final class BadgeBackdropView: NSView {
    private enum BackingKind: Equatable {
        case glass, visualEffect, solid
    }

    private var backing: NSView?
    private var kind: BackingKind?
    private let tint = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        tint.wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(appearance: BadgeAppearance, reduced: Bool, isDark: Bool, inWindowBackdrop: Bool = false) {
        self.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)

        var supportsGlass = false
        #if compiler(>=6.2)
        if #available(macOS 26, *) { supportsGlass = true }
        #endif

        let targetKind: BackingKind
        switch appearance.preset {
        case .glass:
            targetKind = (supportsGlass && !inWindowBackdrop) ? .glass : .visualEffect
        case .frosted:
            targetKind = .visualEffect
        case .solid, .accent:
            targetKind = .solid
        }

        if kind != targetKind {
            backing?.removeFromSuperview()
            tint.removeFromSuperview()
            let view: NSView
            switch targetKind {
            case .glass:
                #if compiler(>=6.2)
                if #available(macOS 26, *) {
                    view = NSGlassEffectView()
                } else {
                    view = makeVisualEffect()
                }
                #else
                view = makeVisualEffect()
                #endif
            case .visualEffect:
                view = makeVisualEffect()
            case .solid:
                let solidView = NSView()
                solidView.wantsLayer = true
                view = solidView
            }
            backing = view
            kind = targetKind
            addSubview(view)
            addSubview(tint)
        }

        alphaValue = appearance.opacity
        tint.layer?.backgroundColor = nil
        backing?.layer?.backgroundColor = nil

        switch appearance.preset {
        case .glass:
            if !inWindowBackdrop {
                #if compiler(>=6.2)
                if #available(macOS 26, *), let glass = backing as? NSGlassEffectView {
                    glass.style = reduced ? .clear : .regular
                    glass.tintColor = isDark
                        ? NSColor(srgbRed: 0.11, green: 0.12, blue: 0.15, alpha: reduced ? 0.82 : 0.56)
                        : NSColor(white: 0.98, alpha: reduced ? 0.85 : 0.58)
                } else {
                    configureVisualEffect(isDark: isDark, inWindowBackdrop: inWindowBackdrop, frosted: false)
                }
                #else
                configureVisualEffect(isDark: isDark, inWindowBackdrop: inWindowBackdrop, frosted: false)
                #endif
            } else {
                configureVisualEffect(isDark: isDark, inWindowBackdrop: inWindowBackdrop, frosted: false)
            }
        case .frosted:
            configureVisualEffect(isDark: isDark, inWindowBackdrop: inWindowBackdrop, frosted: true)
        case .solid:
            let bg = isDark
                ? NSColor(srgbRed: 0.118, green: 0.129, blue: 0.157, alpha: 1)
                : NSColor(srgbRed: 0.973, green: 0.976, blue: 0.984, alpha: 1)
            backing?.layer?.backgroundColor = bg.cgColor
        case .accent:
            backing?.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            tint.layer?.backgroundColor = NSColor(white: isDark ? 0.0 : 1.0, alpha: isDark ? 0.14 : 0.06).cgColor
        }

        needsLayout = true
    }

    private func makeVisualEffect() -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    private func configureVisualEffect(isDark: Bool, inWindowBackdrop: Bool, frosted: Bool) {
        if let effect = backing as? NSVisualEffectView {
            effect.material = (frosted && isDark) ? .hudWindow : .popover
            effect.blendingMode = inWindowBackdrop ? .withinWindow : .behindWindow
            effect.isEmphasized = false
            effect.state = .active
        }
        let overlay = isDark
            ? NSColor(srgbRed: 0.12, green: 0.13, blue: 0.16, alpha: frosted ? 0.66 : 0.58)
            : NSColor(white: 0.98, alpha: frosted ? 0.68 : 0.60)
        tint.layer?.backgroundColor = overlay.cgColor
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        backing?.frame = bounds
        tint.frame = bounds
        #if compiler(>=6.2)
        if #available(macOS 26, *), let glass = backing as? NSGlassEffectView {
            glass.cornerRadius = bounds.height / 2
        }
        #endif
    }
}

final class BadgeController {
    private var panels: [pid_t: NSPanel] = [:]
    private var previous: [pid_t: Presentation] = [:]

    private struct Presentation: Equatable {
        let counts: WindowCounts
        let metrics: BadgeMetrics
        let appearance: BadgeAppearance
    }

    static let collectionBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

    func update(
        _ entries: [DockEntry],
        visible: Bool,
        runningPIDs: Set<pid_t>,
        visibilityMode: BadgeVisibilityMode = .smart,
        appearance: BadgeAppearance = BadgeAppearance()
    ) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let screens = NSScreen.screens
        var displayed = Set<pid_t>()

        for entry in entries {
            guard let counts = entry.counts, visibilityMode.shouldShow(counts) else { continue }
            let tile = Geometry.appKitRect(entry.frame, primaryHeight: primaryHeight)
            guard tile.width.isFinite, tile.height.isFinite, tile.width > 4, tile.height > 4 else { continue }
            let screen = screens.first { $0.frame.intersects(tile) } ?? screens.first
            let scale = screen?.backingScaleFactor ?? 2
            let metrics = BadgeMetrics.make(counts: counts, tileSide: min(tile.width, tile.height), scale: scale, size: appearance.size)
            let presentation = Presentation(counts: counts, metrics: metrics, appearance: appearance)

            let panel: NSPanel
            if let old = panels[entry.pid] {
                panel = old
            } else {
                panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.setAccessibilityIdentifier("io.github.whdichrn.DockCounts.badge")
                panel.backgroundColor = .clear
                panel.isOpaque = false
                panel.hasShadow = false
                panel.hidesOnDeactivate = false
                panel.animationBehavior = .none
                panel.ignoresMouseEvents = true
                panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
                panel.collectionBehavior = Self.collectionBehavior
                panels[entry.pid] = panel
                DockTrace.event("panel.create pid=\(entry.pid) number=\(panel.windowNumber)")
            }

            if previous[entry.pid] != presentation {
                let view = CountBadge(counts: counts, metrics: metrics, appearance: appearance)
                if let host = panel.contentView as? NSHostingView<CountBadge> {
                    host.rootView = view
                } else {
                    panel.contentView = NSHostingView(rootView: view)
                }
                previous[entry.pid] = presentation
            }

            let frame = BadgePlacement.frame(tile: tile, size: metrics.size, scale: scale)
            if panel.frame != frame {
                panel.setFrame(frame, display: true)
                DockTrace.event("panel.move pid=\(entry.pid) number=\(panel.windowNumber) tile=\(tile) badge=\(frame)")
            }

            if visible && screens.contains(where: { $0.frame.intersects(frame) }) {
                displayed.insert(entry.pid)
                if !panel.isVisible {
                    panel.orderFrontRegardless()
                    DockTrace.event("panel.show pid=\(entry.pid) number=\(panel.windowNumber)")
                }
            }
        }

        for (pid, panel) in panels where !displayed.contains(pid) && panel.isVisible {
            panel.orderOut(nil)
            DockTrace.event("panel.hide pid=\(pid) number=\(panel.windowNumber)")
        }

        for pid in Array(panels.keys) where !runningPIDs.contains(pid) {
            panels.removeValue(forKey: pid)?.close()
            previous.removeValue(forKey: pid)
        }
    }

    func hide() {
        for panel in panels.values where panel.isVisible { panel.orderOut(nil) }
    }

    func reset() {
        panels.values.forEach { $0.close() }
        panels.removeAll()
        previous.removeAll()
    }
}
