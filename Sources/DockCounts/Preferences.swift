import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general, enhancement, appearance, about
}

enum WindowTriggerMode: String, Codable, CaseIterable, Identifiable {
    case multipleWindows
    case anyWindow

    var id: String { rawValue }
    var title: String { title(in: L10n.currentLanguage) }
    var summary: String { summary(in: L10n.currentLanguage) }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .multipleWindows: return L10n.t("仅多窗口", "Multiple", language)
        case .anyWindow: return L10n.t("含单窗口", "Any Window", language)
        }
    }

    func summary(in language: AppLanguage) -> String {
        switch self {
        case .multipleWindows:
            return L10n.t(
                "仅在应用有多个窗口时弹出选择菜单，单窗口保留系统原样切回或恢复。",
                "Show the window menu only when an app has multiple windows; single windows keep native Dock behavior.",
                language
            )
        case .anyWindow:
            return L10n.t(
                "只要应用存在窗口，点按即弹出选择菜单。",
                "Show the window menu whenever an app has at least one window.",
                language
            )
        }
    }
}

struct BadgeDisplay: Equatable {
    let showTotal: Bool
    let showMinimized: Bool
    var isVisible: Bool { showTotal || showMinimized }
}

enum BadgeVisibilityMode: String, Codable, CaseIterable, Identifiable {
    case auto
    case always
    case hidden

    var id: String { rawValue }
    var title: String { title(in: L10n.currentLanguage) }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "auto", "smart":
            self = .auto
        case "always":
            self = .always
        case "hidden", "minimizedOnly":
            self = .hidden
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown BadgeVisibilityMode: \(raw)")
            )
        }
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .auto: return L10n.t("自动", "Auto", language)
        case .always: return L10n.t("始终显示", "Always", language)
        case .hidden: return L10n.t("不显示", "Hide", language)
        }
    }

    func display(for counts: WindowCounts) -> BadgeDisplay {
        let showMinimized = counts.minimized > 0
        let showTotal: Bool
        switch self {
        case .auto:
            showTotal = counts.total > 0 && counts.minimized < counts.total
        case .always:
            showTotal = counts.total > 0
        case .hidden:
            showTotal = false
        }
        return BadgeDisplay(showTotal: showTotal, showMinimized: showMinimized)
    }

    func shouldShow(_ counts: WindowCounts) -> Bool {
        display(for: counts).isVisible
    }
}

enum BadgePreset: String, Codable, CaseIterable, Identifiable {
    case glass
    case frosted
    case solid
    case accent

    var id: String { rawValue }
    var title: String { title(in: L10n.currentLanguage) }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .glass: return L10n.t("系统玻璃", "Liquid Glass", language)
        case .frosted: return L10n.t("柔和磨砂", "Soft Frosted", language)
        case .solid: return L10n.t("高对比纯色", "High Contrast", language)
        case .accent: return L10n.t("系统主题色", "Accent Color", language)
        }
    }
}

enum BadgeSize: String, Codable, CaseIterable, Identifiable {
    case compact
    case standard

    var id: String { rawValue }
    var title: String { title(in: L10n.currentLanguage) }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .compact: return L10n.t("紧凑", "Compact", language)
        case .standard: return L10n.t("标准", "Standard", language)
        }
    }
}

enum AppAppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var title: String { title(in: L10n.currentLanguage) }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .system: return L10n.t("跟随系统", "System", language)
        case .light: return L10n.t("浅色", "Light", language)
        case .dark: return L10n.t("深色", "Dark", language)
        }
    }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
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

enum CmdTabMultiMinimizedBehavior: String, Codable, CaseIterable, Identifiable {
    case showPicker
    case restoreRecent

    var id: String { rawValue }
    var title: String { title(in: L10n.currentLanguage) }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .showPicker: return L10n.t("弹出窗口菜单", "Window Menu", language)
        case .restoreRecent: return L10n.t("恢复最近窗口", "Restore Recent", language)
        }
    }
}

enum CmdTabAction: Equatable {
    case none
    case restoreSingle(WindowRecord)
    case restoreFirst(WindowRecord)
    case showPicker([WindowRecord])
    case reopenApp
}

struct AppPreferences: Codable, Equatable {
    var enabled = true
    var badgesEnabled = true
    var badgeVisibility: BadgeVisibilityMode = .auto
    var windowSelectionEnabled = true
    var triggerMode: WindowTriggerMode = .multipleWindows
    var minimizeActiveSingleWindow = true
    var secondClickRunsNativeAction = true
    var cmdTabRestoreMinimized = true
    var cmdTabMultiMinimizedBehavior: CmdTabMultiMinimizedBehavior = .showPicker
    var cmdTabReopenEmptyApp = true
    var appearanceMode: AppAppearanceMode = .system
    var language: AppLanguage = .system
    var appearance = BadgeAppearance()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled, badgesEnabled, badgeVisibility, windowSelectionEnabled, triggerMode, minimizeActiveSingleWindow
        case secondClickRunsNativeAction
        case cmdTabRestoreMinimized, cmdTabMultiMinimizedBehavior, cmdTabReopenEmptyApp, appearanceMode, language, appearance
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
        secondClickRunsNativeAction = try c.decodeIfPresent(Bool.self, forKey: .secondClickRunsNativeAction) ?? secondClickRunsNativeAction
        cmdTabRestoreMinimized = try c.decodeIfPresent(Bool.self, forKey: .cmdTabRestoreMinimized) ?? cmdTabRestoreMinimized
        cmdTabMultiMinimizedBehavior = try c.decodeIfPresent(CmdTabMultiMinimizedBehavior.self, forKey: .cmdTabMultiMinimizedBehavior) ?? cmdTabMultiMinimizedBehavior
        cmdTabReopenEmptyApp = try c.decodeIfPresent(Bool.self, forKey: .cmdTabReopenEmptyApp) ?? cmdTabReopenEmptyApp
        appearanceMode = try c.decodeIfPresent(AppAppearanceMode.self, forKey: .appearanceMode) ?? appearanceMode
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? language
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
        try c.encode(secondClickRunsNativeAction, forKey: .secondClickRunsNativeAction)
        try c.encode(cmdTabRestoreMinimized, forKey: .cmdTabRestoreMinimized)
        try c.encode(cmdTabMultiMinimizedBehavior, forKey: .cmdTabMultiMinimizedBehavior)
        try c.encode(cmdTabReopenEmptyApp, forKey: .cmdTabReopenEmptyApp)
        try c.encode(appearanceMode, forKey: .appearanceMode)
        try c.encode(language, forKey: .language)
        try c.encode(appearance.normalized(), forKey: .appearance)
    }

    var needsDock: Bool { enabled && (badgesEnabled || windowSelectionEnabled) }
    var needsCmdTabEnhancer: Bool { enabled && (cmdTabRestoreMinimized || cmdTabReopenEmptyApp) }
    var needsAnyService: Bool { needsDock || needsCmdTabEnhancer }

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

    func cmdTabAction(
        windows: [WindowRecord],
        onScreenWindowCount: Int,
        spaceChangedRecently: Bool,
        isRegularApp: Bool
    ) -> CmdTabAction {
        guard enabled, isRegularApp, onScreenWindowCount == 0, !spaceChangedRecently else { return .none }
        if !windows.isEmpty {
            guard cmdTabRestoreMinimized,
                  windows.allSatisfy(\.minimized) else {
                return .none
            }
            if windows.count == 1 {
                return .restoreSingle(windows[0])
            }
            switch cmdTabMultiMinimizedBehavior {
            case .showPicker: return .showPicker(windows)
            case .restoreRecent: return .restoreFirst(windows[0])
            }
        }
        guard cmdTabReopenEmptyApp else { return .none }
        return .reopenApp
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
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? L10n.t("开发构建", "Dev Build")
    }
}
