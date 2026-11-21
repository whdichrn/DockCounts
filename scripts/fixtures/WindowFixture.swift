import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.regular)
var windows: [NSWindow] = []
let titles = CommandLine.arguments.contains("--single-window") ? ["DockCounts Test Alpha"] : ["DockCounts Test Alpha", "DockCounts Test Beta", "DockCounts Test Gamma"]
for (index, title) in titles.enumerated() {
    let window = NSWindow(contentRect: NSRect(x: 240 + index * 40, y: 260 + index * 35, width: 430, height: 220), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.title = title
    window.isReleasedWhenClosed = false
    let label = NSTextField(labelWithString: title)
    label.frame = NSRect(x: 30, y: 95, width: 380, height: 30)
    label.font = .systemFont(ofSize: 20, weight: .semibold)
    window.contentView?.addSubview(label)
    window.makeKeyAndOrderFront(nil)
    windows.append(window)
}
// A test-only surface lets native automation address screen coordinates below Dock.
// It remains at the normal window level; Dock and its menu stay above it.
final class InputSurface: NSWindow {
    override var canBecomeKey: Bool { true }
}
var inputSurface: NSWindow?
if CommandLine.arguments.contains("--dock-click-surface"), let screen = NSScreen.screens.first {
    let surface = InputSurface(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    surface.title = "DockCounts Input Surface"
    surface.setAccessibilitySubrole(.floatingWindow)
    surface.backgroundColor = .windowBackgroundColor
    let label = NSTextField(labelWithString: "DockCounts 点击验收 · 临时测试界面")
    label.font = .systemFont(ofSize: 24, weight: .semibold)
    label.frame = NSRect(x: 150, y: screen.frame.height / 2, width: 600, height: 40)
    surface.contentView?.addSubview(label)
    surface.makeKeyAndOrderFront(nil)
    inputSurface = surface
}
app.activate()
if windows.count > 1 { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { windows[1].miniaturize(nil) } }
app.run()
