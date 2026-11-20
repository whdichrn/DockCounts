import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.regular)
var windows: [NSWindow] = []
for (index, title) in ["DockCounts Test Alpha", "DockCounts Test Beta", "DockCounts Test Gamma"].enumerated() {
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
app.activate()
DispatchQueue.main.asyncAfter(deadline: .now() + 1) { windows[1].miniaturize(nil) }
app.run()
