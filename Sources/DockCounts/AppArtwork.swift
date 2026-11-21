import AppKit

enum AppArtwork {
    static let appIcon: NSImage = load("AppIcon", extension: "png")
    static let menuBarIcon: NSImage = {
        let image = load("MenuBarTemplate", extension: "pdf")
        image.size = NSSize(width: 20, height: 20)
        image.isTemplate = true
        return image
    }()
    private static func load(_ name: String, extension ext: String) -> NSImage {
        // Installed .app resources are flat; swift run/test uses the SwiftPM bundle.
        let url = Bundle.main.url(forResource: name, withExtension: ext) ?? Bundle.module.url(forResource: name, withExtension: ext)
        guard let url, let image = NSImage(contentsOf: url) else { return NSImage(size: NSSize(width: 20, height: 20)) }
        return image
    }
}
