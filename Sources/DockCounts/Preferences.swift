import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable { case general, windows, badges, about }
enum BadgeSurface: String, Codable, CaseIterable, Identifiable {
    case automatic, glass, clear, frosted, solid
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "自适应"
        case .glass: return "柔和玻璃"
        case .clear: return "清透玻璃"
        case .frosted: return "哑光磨砂"
        case .solid: return "纯色"
        }
    }
}
enum BadgeEdge: String, Codable, CaseIterable, Identifiable {
    case none, hairline, outline
    var id: String { rawValue }
    var title: String { self == .none ? "无描边" : self == .hairline ? "细线" : "轮廓" }
}
enum BadgeTint: String, Codable, CaseIterable, Identifiable {
    case neutral, accent, custom, none
    var id: String { rawValue }
    var title: String {
        switch self { case .neutral: return "中性"; case .accent: return "系统主题色"; case .custom: return "自选颜色"; case .none: return "无染色" }
    }
}
enum BadgeTextColor: String, Codable, CaseIterable, Identifiable {
    case automatic, dark, light
    var id: String { rawValue }
    var title: String { self == .automatic ? "自动" : self == .dark ? "深色" : "浅色" }
}
struct RGBColor: Codable, Equatable {
    var red: Double = 0.20
    var green: Double = 0.48
    var blue: Double = 0.80
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    init(red: Double = 0.20, green: Double = 0.48, blue: Double = 0.80) { self.red = red; self.green = green; self.blue = blue }
    init(_ color: NSColor) {
        let rgb = color.usingColorSpace(.sRGB) ?? .systemBlue
        self.init(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }
    init?(hex: String) {
        let digits = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard digits.count == 6, digits.allSatisfy({ $0.isASCII && $0.isHexDigit }), let number = UInt32(digits, radix: 16) else { return nil }
        self.init(red: Double((number >> 16) & 255) / 255, green: Double((number >> 8) & 255) / 255, blue: Double(number & 255) / 255)
    }
    var hex: String {
        let color = normalized()
        return String(format: "#%02X%02X%02X", Int((color.red * 255).rounded()), Int((color.green * 255).rounded()), Int((color.blue * 255).rounded()))
    }
    func normalized() -> RGBColor { RGBColor(red: red.clampedUnit, green: green.clampedUnit, blue: blue.clampedUnit) }
}
private extension Double {
    var clampedUnit: Double { isFinite ? min(1, max(0, self)) : 0 }
}

struct BadgeAppearance: Codable, Equatable {
    var surface: BadgeSurface = .automatic
    var backgroundOpacity: Double = 1
    var edge: BadgeEdge = .hairline
    var highlights = true
    var shadow = true
    var vivid = false
    var tint: BadgeTint = .neutral
    var tintStrength: Double = 0.55
    var customColor = RGBColor()
    var textColor: BadgeTextColor = .automatic
    init() {}
    enum CodingKeys: String, CodingKey { case surface, backgroundOpacity, edge, highlights, shadow, vivid, tint, tintStrength, customColor, textColor }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        surface = try c.decodeIfPresent(BadgeSurface.self, forKey: .surface) ?? surface
        backgroundOpacity = try c.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? backgroundOpacity
        edge = try c.decodeIfPresent(BadgeEdge.self, forKey: .edge) ?? edge
        highlights = try c.decodeIfPresent(Bool.self, forKey: .highlights) ?? highlights
        shadow = try c.decodeIfPresent(Bool.self, forKey: .shadow) ?? shadow
        vivid = try c.decodeIfPresent(Bool.self, forKey: .vivid) ?? vivid
        tint = try c.decodeIfPresent(BadgeTint.self, forKey: .tint) ?? tint
        tintStrength = try c.decodeIfPresent(Double.self, forKey: .tintStrength) ?? tintStrength
        customColor = try c.decodeIfPresent(RGBColor.self, forKey: .customColor) ?? customColor
        textColor = try c.decodeIfPresent(BadgeTextColor.self, forKey: .textColor) ?? textColor
        self = normalized()
    }
    func normalized() -> Self {
        var result = self
        result.backgroundOpacity = backgroundOpacity.clampedUnit
        result.tintStrength = tintStrength.clampedUnit
        result.customColor = customColor.normalized()
        return result
    }
    func resolvedSurface(reduceTransparency: Bool, supportsGlass: Bool) -> BadgeSurface {
        switch surface {
        case .solid: return .solid
        case .frosted: return .frosted
        case .automatic, .glass, .clear:
            guard supportsGlass && highlights else { return .frosted }
            return surface == .automatic ? (reduceTransparency ? .clear : .glass) : surface
        }
    }
    func tintColor() -> NSColor? {
        let color: NSColor
        switch tint {
        case .none: return nil
        case .neutral: return .windowBackgroundColor
        case .accent: color = .controlAccentColor
        case .custom: color = customColor.nsColor
        }
        guard vivid, let rgb = color.usingColorSpace(.sRGB) else { return color }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(hue: hue, saturation: min(1, saturation * 1.25), brightness: brightness, alpha: 1)
    }
    func usesLightText(reduceTransparency: Bool, supportsGlass: Bool, darkAppearance: Bool) -> Bool {
        if textColor != .automatic { return textColor == .light }
        let resolved = resolvedSurface(reduceTransparency: reduceTransparency, supportsGlass: supportsGlass)
        let base: CGFloat = resolved == .clear ? 0.15 : (darkAppearance ? 0.15 : 0.94)
        guard backgroundOpacity > 0.35, let rgb = tintColor()?.usingColorSpace(.sRGB) else {
            return resolved == .clear && backgroundOpacity > 0.35 ? true : darkAppearance
        }
        let strength = effectiveTintStrength(reduceTransparency: reduceTransparency)
        let r = base * (1-strength) + rgb.redComponent * strength
        let g = base * (1-strength) + rgb.greenComponent * strength
        let b = base * (1-strength) + rgb.blueComponent * strength
        return 0.2126*r + 0.7152*g + 0.0722*b < 0.48
    }
    func effectiveTintStrength(reduceTransparency: Bool) -> CGFloat {
        // Keep the default regular material neutral; tint becomes visible under
        // Reduce Transparency or when the person explicitly chooses a color.
        if tint == .none { return 0 }
        if tint == .neutral && surface == .automatic && !reduceTransparency { return 0 }
        return CGFloat(min(1, tintStrength + (vivid && tint != .neutral ? 0.10 : 0)))
    }
}

struct AppPreferences: Codable, Equatable {
    var enabled = true
    var badgesEnabled = true
    var windowSelectionEnabled = true
    var selectSingleWindow = true
    var appearance = BadgeAppearance()
    init() {}
    enum CodingKeys: String, CodingKey { case enabled, badgesEnabled, windowSelectionEnabled, selectSingleWindow, appearance }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        badgesEnabled = try c.decodeIfPresent(Bool.self, forKey: .badgesEnabled) ?? badgesEnabled
        windowSelectionEnabled = try c.decodeIfPresent(Bool.self, forKey: .windowSelectionEnabled) ?? windowSelectionEnabled
        selectSingleWindow = try c.decodeIfPresent(Bool.self, forKey: .selectSingleWindow) ?? selectSingleWindow
        appearance = (try? c.decodeIfPresent(BadgeAppearance.self, forKey: .appearance)) ?? appearance
    }
    var needsDock: Bool { enabled && (badgesEnabled || windowSelectionEnabled) }
    func selectsWindow(total: Int) -> Bool { enabled && windowSelectionEnabled && total > 0 && (selectSingleWindow || total > 1) }
}

final class PreferencesStore {
    static let key = "preferences.v1"
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load() -> AppPreferences {
        if let data = defaults.data(forKey: Self.key), let preferences = try? JSONDecoder().decode(AppPreferences.self, from: data) { return preferences }
        var preferences = AppPreferences()
        if defaults.object(forKey: "enabled") != nil { preferences.enabled = defaults.bool(forKey: "enabled") }
        return preferences
    }
    func save(_ preferences: AppPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.key)
        defaults.set(preferences.enabled, forKey: "enabled")
    }
}

enum ProjectLinks {
    static let home = URL(string: "https://github.com/whdichrn/DockCounts")!
    static let releases = home.appendingPathComponent("releases")
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发构建" }
}
