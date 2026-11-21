import AppKit

enum AppArtwork {
    static let appIcon: NSImage = load("AppIcon", extension: "png")
    static let menuBarIcon: NSImage = {
        let image = load("MenuBarTemplate", extension: "pdf")
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()

    private static func load(_ name: String, extension ext: String) -> NSImage {
        let url = Bundle.main.url(forResource: name, withExtension: ext) ?? Bundle.module.url(forResource: name, withExtension: ext)
        guard let url, let image = NSImage(contentsOf: url) else {
            return NSImage(size: NSSize(width: 18, height: 18))
        }
        return image
    }
}
