import AppKit
import Combine
import ServiceManagement

enum LoginItemState: Equatable {
    case notRegistered, enabled, requiresApproval, notFound
    var isRequested: Bool { self == .enabled || self == .requiresApproval }
    var message: String { message() }

    func message(in language: AppLanguage? = nil) -> String {
        switch self {
        case .notRegistered: return L10n.t("未开启开机启动", "Disabled at login", language)
        case .enabled: return L10n.t("已开启，登录 Mac 后自动运行", "Enabled, starts automatically on login", language)
        case .requiresApproval: return L10n.t("已登记，等待在系统登录项中允许", "Registered, pending approval in System Settings", language)
        case .notFound: return L10n.t("请从固定安装位置启动应用后再设置", "Launch the app from /Applications to configure", language)
        }
    }
}
protocol LoginItemService {
    var state: LoginItemState { get }
    func setEnabled(_ enabled: Bool) throws
}
struct SystemLoginItemService: LoginItemService {
    var state: LoginItemState {
        switch SMAppService.mainApp.status {
        case .notRegistered: return .notRegistered
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if !state.isRequested { try SMAppService.mainApp.register() }
        } else if state != .notRegistered && state != .notFound {
            try SMAppService.mainApp.unregister()
        }
    }
}
final class LoginItemController: ObservableObject {
    @Published private(set) var state: LoginItemState
    @Published private(set) var error: String?
    private let service: LoginItemService
    init(service: LoginItemService = SystemLoginItemService()) { self.service = service; state = service.state }
    func refresh() { let next = service.state; if state != next { state = next } }
    func setEnabled(_ enabled: Bool) {
        error = nil
        do { try service.setEnabled(enabled) }
        catch { self.error = L10n.t("无法更新开机启动：", "Unable to update login item: ") + error.localizedDescription }
        refresh()
    }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
