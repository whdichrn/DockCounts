import Foundation

enum ResolvedLanguage: Equatable {
    case zhHans
    case en
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system
    case zhHans
    case en

    var id: String { rawValue }

    var title: String {
        title(in: L10n.resolved)
    }

    func title(in resolved: ResolvedLanguage) -> String {
        switch self {
        case .system: return resolved == .en ? "System" : "跟随系统"
        case .zhHans: return "简体中文"
        case .en: return "English"
        }
    }

    func resolve(preferredLanguages: [String] = Locale.preferredLanguages) -> ResolvedLanguage {
        switch self {
        case .zhHans:
            return .zhHans
        case .en:
            return .en
        case .system:
            if preferredLanguages.first?.lowercased().hasPrefix("zh") == true {
                return .zhHans
            }
            return .en
        }
    }
}

enum L10n {
    private static let lock = NSLock()
    private static var _currentLanguage: AppLanguage = .system

    static var currentLanguage: AppLanguage {
        get {
            lock.withLock { _currentLanguage }
        }
        set {
            lock.withLock { _currentLanguage = newValue }
        }
    }

    static var resolved: ResolvedLanguage {
        currentLanguage.resolve()
    }

    static func t(_ zh: String, _ en: String, _ language: AppLanguage? = nil) -> String {
        let effective = (language ?? currentLanguage).resolve()
        return effective == .en ? en : zh
    }
}
