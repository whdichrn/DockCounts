import AppKit
import SwiftUI

final class WindowPickerState: ObservableObject {
    @Published var windows: [WindowRecord]
    @Published var selectedIndex: Int?
    private var pointerSelection = false

    static func ordered(_ windows: [WindowRecord]) -> [WindowRecord] {
        let active = windows.filter { !$0.minimized }
        let main = active.filter(\.isMain)
        let normal = active.filter { !$0.isMain }
        let minimized = windows.filter(\.minimized)
        return main + normal + minimized
    }

    init(windows: [WindowRecord], sorted: Bool = true) {
        self.windows = sorted ? Self.ordered(windows) : windows
        self.selectedIndex = nil
    }

    var activeIndices: [Int] {
        windows.indices.filter { !windows[$0].minimized }
    }

    var minimizedIndices: [Int] {
        windows.indices.filter { windows[$0].minimized }
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

    func windowForShortcut(_ digit: Int) -> WindowRecord? {
        guard (1...9).contains(digit), windows.indices.contains(digit - 1) else { return nil }
        return windows[digit - 1]
    }

    func removeWindow(at index: Int) {
        guard windows.indices.contains(index) else { return }
        windows.remove(at: index)
        if windows.isEmpty {
            selectedIndex = nil
        } else if let selectedIndex {
            if selectedIndex == index {
                self.selectedIndex = nil
            } else if selectedIndex > index {
                self.selectedIndex = selectedIndex - 1
            }
        }
    }

    func toggleMinimizedLocally(at index: Int) {
        guard windows.indices.contains(index) else { return }
        let w = windows[index]
        windows[index] = WindowRecord(element: w.element, title: w.title, minimized: !w.minimized, isMain: !w.minimized ? false : w.isMain, pid: w.pid)
        windows = Self.ordered(windows)
        selectedIndex = nil
    }
}

enum PickerPlacement {
    static func frame(icon: CGRect, point: CGPoint, size: CGSize, visible: CGRect, edge: String) -> CGRect {
        let width = min(size.width, max(1, visible.width - 8))
        let height = min(size.height, max(1, visible.height - 8))
        var x: CGFloat
        var y: CGFloat
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
    static let rowHeight: CGFloat = 28
    static let headerHeight: CGFloat = 36
    static let sectionHeaderHeight: CGFloat = 20

    static func size(name: String, windows: [WindowRecord], scale: CGFloat) -> CGSize {
        let font = NSFont.menuFont(ofSize: 0)
        let titleWidth = (name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).width + 132
        let rowWidth = windows.map { window in
            (window.title as NSString).size(withAttributes: [.font: font]).width + 92
        }.max() ?? 180
        let width = min(360, max(240, max(titleWidth, rowWidth)))

        let hasActive = windows.contains { !$0.minimized }
        let hasMinimized = windows.contains { $0.minimized }
        let sectionExtra: CGFloat = (hasActive && hasMinimized) ? sectionHeaderHeight : 0
        let listHeight: CGFloat = windows.isEmpty ? 34 : min(364, CGFloat(windows.count) * rowHeight + sectionExtra)
        let height = 8 + headerHeight + (1 / max(1, scale)) + 4 + listHeight
        return CGSize(width: ceil(width * scale) / scale, height: ceil(height * scale) / scale)
    }
}

private struct PickerSurfaceBackground: NSViewRepresentable {
    var cornerRadius: CGFloat = 10

    func makeNSView(context: Context) -> NSView {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = cornerRadius
            return glass
        }
        #endif
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.isEmphasized = true
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

private struct SelectionMaterial: NSViewRepresentable {
    var cornerRadius: CGFloat = 6
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .selection
        view.blendingMode = .withinWindow
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
    let appIcon: NSImage?
    @ObservedObject var state: WindowPickerState
    let choose: (WindowRecord) -> Void
    let activateAll: ([WindowRecord]) -> Void
    let toggleMinimize: (Int, WindowRecord) -> Void
    let closeWindow: (Int, WindowRecord) -> Void

    @Environment(\.displayScale) private var scale
    @State private var hoveredIndex: Int?

    var body: some View {
        let minimizedCount = state.windows.filter(\.minimized).count
        let activeIndices = state.activeIndices
        let minimizedIndices = state.minimizedIndices

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 18, height: 18)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(minimizedCount > 0 ? "\(state.windows.count) 个 · \(minimizedCount) 已最小化" : "\(state.windows.count) 个窗口")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if state.windows.count > 1 || minimizedCount > 0 {
                    Button {
                        activateAll(state.windows)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "macwindow.on.rectangle")
                                .font(.system(size: 10.5))
                            Text("展开全部")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .help("展开并前置全部窗口")
                    .accessibilityIdentifier("picker-activate-all")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: WindowPickerMetrics.headerHeight)

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.45))
                .frame(height: 1 / scale)
                .padding(.horizontal, 4)

            if state.windows.isEmpty {
                Text("没有可用窗口")
                    .font(Font(NSFont.menuFont(ofSize: 0)))
                    .foregroundStyle(.secondary)
                    .padding(10)
            } else {
                ScrollViewReader { reader in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(activeIndices, id: \.self) { index in
                                windowRow(index: index)
                            }
                            if !activeIndices.isEmpty && !minimizedIndices.isEmpty {
                                HStack(spacing: 6) {
                                    Text("已最小化")
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    Rectangle()
                                        .fill(Color(nsColor: .separatorColor).opacity(0.35))
                                        .frame(height: 1 / scale)
                                }
                                .padding(.horizontal, 8)
                                .frame(height: WindowPickerMetrics.sectionHeaderHeight)
                            }
                            ForEach(minimizedIndices, id: \.self) { index in
                                windowRow(index: index)
                            }
                        }
                    }
                    .onChange(of: state.selectedIndex) { _, index in
                        if let index { reader.scrollTo(index) }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(4)
        .background(PickerSurfaceBackground(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1 / scale)
        )
    }

    @ViewBuilder
    private func windowRow(index: Int) -> some View {
        let window = state.windows[index]
        let selected = state.selectedIndex == index
        let hovering = hoveredIndex == index

        HStack(spacing: 4) {
            Button {
                choose(window)
            } label: {
                HStack(spacing: 8) {
                    statusIndicator(for: window, selected: selected)
                        .frame(width: 14, height: 14)
                    Text(window.title)
                        .font(.system(size: 13, weight: window.isMain && !window.minimized ? .medium : .regular))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(selected ? Color(nsColor: .selectedMenuItemTextColor) : Color.primary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(window.title + (window.minimized ? " — 已最小化" : ""))
            .accessibilityIdentifier("window-row-\(index)")
            .help(window.title)

            if hovering {
                HStack(spacing: 2) {
                    Button {
                        toggleMinimize(index, window)
                    } label: {
                        Image(systemName: window.minimized ? "arrow.up.circle" : "minus.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(selected ? Color(nsColor: .selectedMenuItemTextColor) : .secondary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(window.minimized ? "恢复窗口" : "最小化窗口")
                    .accessibilityIdentifier("window-minimize-\(index)")

                    Button {
                        closeWindow(index, window)
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(selected ? Color(nsColor: .selectedMenuItemTextColor) : .secondary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("关闭窗口")
                    .accessibilityIdentifier("window-close-\(index)")
                }
            } else if index < 9 {
                Text("\(index + 1)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(selected ? AnyShapeStyle(Color(nsColor: .selectedMenuItemTextColor).opacity(0.85)) : AnyShapeStyle(.tertiary))
                    .frame(width: 18, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: WindowPickerMetrics.rowHeight)
        .background {
            if selected {
                SelectionMaterial(cornerRadius: 6)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering in
            if isHovering {
                hoveredIndex = index
                state.select(index)
            } else {
                if hoveredIndex == index { hoveredIndex = nil }
                state.clearHover(index)
            }
        }
        .id(index)
    }

    @ViewBuilder
    private func statusIndicator(for window: WindowRecord, selected: Bool) -> some View {
        if window.minimized {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(selected ? Color(nsColor: .selectedMenuItemTextColor) : Color(nsColor: .systemOrange))
        } else if window.isMain {
            Circle()
                .fill(selected ? Color(nsColor: .selectedMenuItemTextColor) : Color.accentColor)
                .frame(width: 6, height: 6)
        } else {
            Circle()
                .strokeBorder(selected ? Color(nsColor: .selectedMenuItemTextColor).opacity(0.85) : Color.secondary.opacity(0.5), lineWidth: 1.2)
                .frame(width: 6, height: 6)
        }
    }
}

private final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class WindowPickerController: NSObject, NSWindowDelegate {
    var onChoose: ((WindowRecord) -> Void)?
    var onActivateAll: (([WindowRecord]) -> Void)?
    var onToggleMinimize: ((WindowRecord) -> Void)?
    var onCloseWindow: ((WindowRecord) -> Void)?
    var onDismiss: (() -> Void)?

    private var panel: PickerPanel?
    private var state: WindowPickerState?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func present(name: String, appURL: URL? = nil, windows: [WindowRecord], icon: CGRect, at point: CGPoint) {
        dismiss(notify: false)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let anchor = CGPoint(x: point.x, y: primaryHeight - point.y)
        let iconRect = Geometry.appKitRect(icon, primaryHeight: primaryHeight)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) ?? NSScreen.screens.first else {
            onDismiss?()
            return
        }

        let state = WindowPickerState(windows: windows)
        let size = WindowPickerMetrics.size(name: name, windows: state.windows, scale: screen.backingScaleFactor)
        let edge = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"
        let frame = PickerPlacement.frame(icon: iconRect, point: anchor, size: size, visible: screen.visibleFrame, edge: edge)
        present(name: name, appURL: appURL, state: state, frame: frame)
    }

    func presentCentered(name: String, appURL: URL? = nil, windows: [WindowRecord]) {
        dismiss(notify: false)
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main ?? NSScreen.screens.first else {
            onDismiss?()
            return
        }
        let state = WindowPickerState(windows: windows)
        let size = WindowPickerMetrics.size(name: name, windows: state.windows, scale: screen.backingScaleFactor)
        let visible = screen.visibleFrame
        let width = min(size.width, max(1, visible.width - 16))
        let height = min(size.height, max(1, visible.height - 16))
        let rawX = visible.midX - width / 2
        let rawY = visible.midY - height / 2 + 40
        let x = max(visible.minX + 8, min(rawX, visible.maxX - width - 8))
        let y = max(visible.minY + 8, min(rawY, visible.maxY - height - 8))
        let frame = CGRect(x: x.rounded(), y: y.rounded(), width: width, height: height)
        present(name: name, appURL: appURL, state: state, frame: frame)
    }

    private func present(name: String, appURL: URL?, state: WindowPickerState, frame: CGRect) {
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

        let appIcon = appURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
        let rootView = WindowPickerView(
            name: name,
            appIcon: appIcon,
            state: state,
            choose: { [weak self] in self?.choose($0) },
            activateAll: { [weak self] all in
                self?.dismiss(notify: false)
                self?.onActivateAll?(all)
                self?.onDismiss?()
            },
            toggleMinimize: { [weak self, weak state] index, window in
                self?.onToggleMinimize?(window)
                if window.minimized {
                    self?.dismiss(notify: false)
                    self?.onDismiss?()
                } else {
                    state?.toggleMinimizedLocally(at: index)
                }
            },
            closeWindow: { [weak self, weak state] index, window in
                self?.onCloseWindow?(window)
                state?.removeWindow(at: index)
                if state?.windows.isEmpty == true {
                    self?.dismiss()
                }
            }
        ).frame(width: frame.width, height: frame.height)

        panel.contentView = NSHostingView(rootView: rootView)
        panel.delegate = self
        self.panel = panel
        self.state = state

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.type == .keyDown, panel.isKeyWindow {
                switch event.keyCode {
                case 53:
                    self.dismiss()
                    return nil
                case 125:
                    self.state?.move(by: 1)
                    return nil
                case 126:
                    self.state?.move(by: -1)
                    return nil
                case 36, 76:
                    if let window = self.state?.selectedWindow { self.choose(window) }
                    return nil
                default:
                    if event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                       let chars = event.charactersIgnoringModifiers,
                       chars.count == 1,
                       let digit = Int(chars),
                       let window = self.state?.windowForShortcut(digit) {
                        self.choose(window)
                        return nil
                    }
                    return event
                }
            }
            self.dismissIfOutside(event)
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] in
            self?.dismissIfOutside($0)
        }
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
