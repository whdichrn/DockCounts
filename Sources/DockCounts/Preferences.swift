import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general, appearance, about
}

enum WindowTriggerMode: String, Codable, CaseIterable, Identifiable {
    case multipleWindows
    case anyWindow

    var id: String { rawValue }
    var title: String {
        switch self {
        case .multipleWindows: return "仅多窗口"
        case .anyWindow: return "含单窗口"
        }
    }
    var summary: String {
        switch self {
        case .multipleWindows: return "仅在应用有多个窗口时弹出选择菜单，单窗口保留系统原样切回或恢复。"
        case .anyWindow: return "只要应用存在窗口，左键点击即弹出选择菜单。"
        }
    }
}

enum BadgeVisibilityMode: String, Codable, CaseIterable, Identifiable {
    case smart
    case minimizedOnly
    case always

    var id: String { rawValue }
    var title: String {
        switch self {
        case .smart: return "智能降噪"
        case .minimizedOnly: return "仅含最小化"
        case .always: return "始终显示"
        }
    }

    func shouldShow(_ counts: WindowCounts) -> Bool {
        switch self {
        case .smart: return counts.total > 1 || counts.minimized > 0
        case .minimizedOnly: return counts.minimized > 0
        case .always: return counts.total > 0
        }
    }
}

enum BadgePreset: String, Codable, CaseIterable, Identifiable {
    case glass
    case frosted
    case solid
    case accent

    var id: String { rawValue }
    var title: String {
        switch self {
        case .glass: return "系统玻璃"
        case .frosted: return "柔和磨砂"
        case .solid: return "高对比纯色"
        case .accent: return "系统主题色"
        }
    }
}

enum BadgeSize: String, Codable, CaseIterable, Identifiable {
    case compact
    case standard

    var id: String { rawValue }
    var title: String {
        switch self {
        case .compact: return "紧凑"
        case .standard: return "标准"
        }
    }
}

struct BadgeAppearance: Codable, Equatable {
    var preset: BadgePreset = .glass
    var size: BadgeSize = .compact
    var opacity: Double = 1.0

    init(preset: BadgePreset = .glass, size: BadgeSize = .compact, opacity: Double = 1.0) {
        self.preset = preset
        self.size = size
        self.opacity = opacity
        self = normalized()
    }

    private enum CodingKeys: String, CodingKey {
        case preset, size, opacity
        case surface, tint, backgroundOpacity
    }

    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let decodedPreset = try c.decodeIfPresent(BadgePreset.self, forKey: .preset) {
            preset = decodedPreset
        } else {
            let legacyTint = try c.decodeIfPresent(String.self, forKey: .tint)
            let legacySurface = try c.decodeIfPresent(String.self, forKey: .surface)
            if legacyTint == "accent" {
                preset = .accent
            } else if legacySurface == "solid" {
                preset = .solid
            } else if legacySurface == "frosted" {
                preset = .frosted
            } else {
                preset = .glass
            }
        }
        size = try c.decodeIfPresent(BadgeSize.self, forKey: .size) ?? size
        if let decodedOpacity = try c.decodeIfPresent(Double.self, forKey: .opacity) {
            opacity = decodedOpacity
        } else if let legacyOpacity = try c.decodeIfPresent(Double.self, forKey: .backgroundOpacity) {
            opacity = legacyOpacity
        }
        self = normalized()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let norm = normalized()
        try c.encode(norm.preset, forKey: .preset)
        try c.encode(norm.size, forKey: .size)
        try c.encode(norm.opacity, forKey: .opacity)
    }

    func normalized() -> Self {
        var result = self
        result.opacity = opacity.isFinite ? min(1.0, max(0.4, opacity)) : 1.0
        return result
    }
}

enum DockClickAction: Equatable {
    case passThrough
    case openPicker
    case minimizeSingleWindow
}

struct AppPreferences: Codable, Equatable {
    var enabled = true
    var badgesEnabled = true
    var badgeVisibility: BadgeVisibilityMode = .smart
    var windowSelectionEnabled = true
    var triggerMode: WindowTriggerMode = .multipleWindows
    var minimizeActiveSingleWindow = true
    var appearance = BadgeAppearance()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled, badgesEnabled, badgeVisibility, windowSelectionEnabled, triggerMode, minimizeActiveSingleWindow, appearance
        case selectSingleWindow
    }

    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        badgesEnabled = try c.decodeIfPresent(Bool.self, forKey: .badgesEnabled) ?? badgesEnabled
        badgeVisibility = try c.decodeIfPresent(BadgeVisibilityMode.self, forKey: .badgeVisibility) ?? badgeVisibility
        windowSelectionEnabled = try c.decodeIfPresent(Bool.self, forKey: .windowSelectionEnabled) ?? windowSelectionEnabled
        if let decodedMode = try c.decodeIfPresent(WindowTriggerMode.self, forKey: .triggerMode) {
            triggerMode = decodedMode
        } else if let legacySingle = try c.decodeIfPresent(Bool.self, forKey: .selectSingleWindow) {
            triggerMode = legacySingle ? .anyWindow : .multipleWindows
        }
        minimizeActiveSingleWindow = try c.decodeIfPresent(Bool.self, forKey: .minimizeActiveSingleWindow) ?? minimizeActiveSingleWindow
        appearance = (try? c.decodeIfPresent(BadgeAppearance.self, forKey: .appearance)) ?? appearance
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(badgesEnabled, forKey: .badgesEnabled)
        try c.encode(badgeVisibility, forKey: .badgeVisibility)
        try c.encode(windowSelectionEnabled, forKey: .windowSelectionEnabled)
        try c.encode(triggerMode, forKey: .triggerMode)
        try c.encode(minimizeActiveSingleWindow, forKey: .minimizeActiveSingleWindow)
        try c.encode(appearance.normalized(), forKey: .appearance)
    }

    var needsDock: Bool { enabled && (badgesEnabled || windowSelectionEnabled) }

    func selectsWindow(total: Int) -> Bool {
        enabled && windowSelectionEnabled && (triggerMode == .anyWindow ? total > 0 : total > 1)
    }

    func selectsWindow(counts: WindowCounts) -> Bool {
        selectsWindow(total: counts.total)
    }

    func clickAction(windows: [WindowRecord], isAppActive: Bool) -> DockClickAction {
        guard enabled, windowSelectionEnabled, !windows.isEmpty else { return .passThrough }
        if minimizeActiveSingleWindow,
           isAppActive,
           windows.count == 1,
           let single = windows.first,
           !single.minimized,
           !single.isFullScreen,
           single.canMinimize {
            return .minimizeSingleWindow
        }
        return selectsWindow(total: windows.count) ? .openPicker : .passThrough
    }

    func showsBadge(counts: WindowCounts) -> Bool {
        enabled && badgesEnabled && badgeVisibility.shouldShow(counts)
    }
}

final class PreferencesStore {
    static let key = "preferences.v1"
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load() -> AppPreferences {
        if let data = defaults.data(forKey: Self.key),
           let preferences = try? JSONDecoder().decode(AppPreferences.self, from: data) {
            return preferences
        }
        var preferences = AppPreferences()
        if defaults.object(forKey: "enabled") != nil {
            preferences.enabled = defaults.bool(forKey: "enabled")
        }
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
