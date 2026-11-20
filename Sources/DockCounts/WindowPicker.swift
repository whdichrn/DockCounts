import AppKit
import SwiftUI

final class WindowPickerState: ObservableObject {
    let windows: [WindowRecord]
    @Published var selectedIndex: Int?
    private var pointerSelection = false
    init(windows: [WindowRecord]) {
        self.windows = windows
        selectedIndex = nil
    }
    func move(by offset: Int) {
        guard !windows.isEmpty, offset != 0 else { return }
        pointerSelection = false
        guard let selectedIndex else {
            self.selectedIndex = offset > 0 ? 0 : windows.count - 1
            return
        }
        self.selectedIndex = (selectedIndex + offset % windows.count + windows.count) % windows.count
    }
    func select(_ index: Int) {
        guard windows.indices.contains(index) else { return }
        selectedIndex = index
        pointerSelection = true
    }
    func clearHover(_ index: Int) {
        if pointerSelection && selectedIndex == index { selectedIndex = nil }
    }
    var selectedWindow: WindowRecord? {
        guard let selectedIndex, windows.indices.contains(selectedIndex) else { return nil }
        return windows[selectedIndex]
    }
}

enum PickerPlacement {
    static func frame(icon: CGRect, point: CGPoint, size: CGSize, visible: CGRect, edge: String) -> CGRect {
        let width = min(size.width, max(1, visible.width - 8))
        let height = min(size.height, max(1, visible.height - 8))
        var x: CGFloat; var y: CGFloat
        switch edge {
        case "left": x = icon.maxX + 6; y = point.y - height / 2
        case "right": x = icon.minX - width - 6; y = point.y - height / 2
        default: x = point.x - width / 2; y = icon.maxY + 6
        }
        x = max(visible.minX + 4, min(x, visible.maxX - width - 4))
        y = max(visible.minY + 4, min(y, visible.maxY - height - 4))
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

enum WindowPickerMetrics {
    static let rowHeight: CGFloat = 24
    static func size(name: String, windows: [WindowRecord], scale: CGFloat) -> CGSize {
        let font = NSFont.menuFont(ofSize: 0)
        let statusFont = NSFont.systemFont(ofSize: 11)
        let statusWidth = ("已最小化" as NSString).size(withAttributes: [.font: statusFont]).width
        let titleWidth = (name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)]).width + 24
        let rowWidth = windows.map { window in
            (window.title as NSString).size(withAttributes: [.font: font]).width + 34 + (window.minimized ? statusWidth + 12 : 0)
        }.max() ?? 180
        let width = min(360, max(248, max(titleWidth, rowWidth)))
        let height = 34 + 1 / max(1, scale) + (windows.isEmpty ? 30 : min(336, CGFloat(windows.count) * rowHeight))
        return CGSize(width: ceil(width * scale) / scale, height: ceil(height * scale) / scale)
    }
}

private struct NativeMenuMaterial: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .menu
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var cornerRadius: CGFloat = 7
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.isEmphasized = true
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct WindowPickerView: View {
    let name: String
    @ObservedObject var state: WindowPickerState
    let choose: (WindowRecord) -> Void
    @Environment(\.displayScale) private var scale
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .lineLimit(1).padding(.horizontal, 8).frame(height: 22, alignment: .leading)
            Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.55)).frame(height: 1 / scale).padding(.horizontal, 3)
            if state.windows.isEmpty {
                Text("没有可用窗口").font(Font(NSFont.menuFont(ofSize: 0))).foregroundStyle(.secondary).padding(8)
            } else {
                ScrollViewReader { reader in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            ForEach(state.windows.indices, id: \.self) { index in
                                let window = state.windows[index]
                                let selected = state.selectedIndex == index
                                Button { choose(window) } label: {
                                    HStack(spacing: 12) {
                                        Text(window.title).lineLimit(1).truncationMode(.middle)
                                        Spacer(minLength: 0)
                                        if window.minimized {
                                            Text("已最小化").font(.system(size: 11)).fixedSize()
                                                .foregroundStyle(selected ? Color(nsColor: .selectedMenuItemTextColor) : .secondary)
                                        }
                                    }
                                    .font(Font(NSFont.menuFont(ofSize: 0)))
                                    .foregroundStyle(selected ? Color(nsColor: .selectedMenuItemTextColor) : Color.primary)
                                    .padding(.horizontal, 8).frame(height: WindowPickerMetrics.rowHeight)
                                    .background {
                                        if selected {
                                            NativeMenuMaterial(material: .selection, blendingMode: .withinWindow, cornerRadius: 4)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(window.title + (window.minimized ? " — 已最小化" : ""))
                                .accessibilityIdentifier("window-row-\(index)")
                                .help(window.title)
                                .onHover { if $0 { state.select(index) } else { state.clearHover(index) } }
                                .id(index)
                            }
                        }
                    }
                    .onChange(of: state.selectedIndex) { _, index in if let index { reader.scrollTo(index) } }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(4)
        .background(NativeMenuMaterial())
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1 / scale))
    }
}

private final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class WindowPickerController: NSObject, NSWindowDelegate {
    var onChoose: ((WindowRecord) -> Void)?
    var onDismiss: (() -> Void)?
    private var panel: PickerPanel?
    private var state: WindowPickerState?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func present(name: String, windows: [WindowRecord], icon: CGRect, at point: CGPoint) {
        dismiss(notify: false)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let anchor = CGPoint(x: point.x, y: primaryHeight - point.y)
        let iconRect = Geometry.appKitRect(icon, primaryHeight: primaryHeight)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) ?? NSScreen.screens.first else { onDismiss?(); return }
        let size = WindowPickerMetrics.size(name: name, windows: windows, scale: screen.backingScaleFactor)
        let edge = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"
        let frame = PickerPlacement.frame(icon: iconRect, point: anchor, size: size, visible: screen.visibleFrame, edge: edge)
        let state = WindowPickerState(windows: windows)
        let panel = PickerPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = name
        panel.setAccessibilityIdentifier("io.github.whdichrn.DockCounts.window-picker")
        panel.setAccessibilityRole(.window)
        panel.setAccessibilitySubrole(.standardWindow)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: WindowPickerView(name: name, state: state) { [weak self] in self?.choose($0) }.frame(width: frame.width, height: frame.height))
        panel.delegate = self
        self.panel = panel
        self.state = state
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.type == .keyDown, panel.isKeyWindow {
                switch event.keyCode {
                case 53: self.dismiss(); return nil
                case 125: self.state?.move(by: 1); return nil
                case 126: self.state?.move(by: -1); return nil
                case 36, 76:
                    if let window = self.state?.selectedWindow { self.choose(window) }
                    return nil
                default: return event
                }
            }
            self.dismissIfOutside(event)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] in self?.dismissIfOutside($0) }
        panel.makeKeyAndOrderFront(nil)
    }
    func dismiss(notify: Bool = true) {
        guard let panel else { return }
        self.panel = nil
        state = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        panel.delegate = nil
        panel.close()
        if notify { onDismiss?() }
    }
    func windowDidResignKey(_ notification: Notification) { dismiss() }
    private func choose(_ window: WindowRecord) {
        dismiss(notify: false)
        onChoose?(window)
        onDismiss?()
    }
    func dismissIfOutside(at point: CGPoint) {
        guard let panel else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        if !panel.frame.contains(CGPoint(x: point.x, y: primaryHeight - point.y)) { dismiss() }
    }
    private func dismissIfOutside(_ event: NSEvent) {
        guard event.type != .keyDown, let panel else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let point = event.cgEvent.map { CGPoint(x: $0.location.x, y: primaryHeight - $0.location.y) } ?? NSEvent.mouseLocation
        if !panel.frame.contains(point) { dismiss() }
    }
}
