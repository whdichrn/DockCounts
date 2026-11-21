import XCTest
@testable import DockCounts

private final class FakeLoginService: LoginItemService {
    var state = LoginItemState.notRegistered
    var approvalRequired = false
    var fail = false
    var requests: [Bool] = []
    func setEnabled(_ enabled: Bool) throws {
        requests.append(enabled)
        if fail { throw NSError(domain: "LoginTest", code: 1) }
        state = enabled ? (approvalRequired ? .requiresApproval : .enabled) : .notRegistered
    }
}
final class LoginItemTests: XCTestCase {
    func testToggleTracksActualServiceAndCanBeDisabledAgain() {
        let service = FakeLoginService()
        let actual = LoginItemController(service: service)
        XCTAssertEqual(actual.state, .notRegistered)
        actual.setEnabled(true)
        XCTAssertEqual(actual.state, .enabled)
        actual.setEnabled(false)
        XCTAssertEqual(actual.state, .notRegistered)
        XCTAssertEqual(service.requests, [true, false])
    }
    func testRequiresApprovalIsDistinctFromEnabledAndExternalRevocationRefreshes() {
        let service = FakeLoginService(); service.approvalRequired = true
        let controller = LoginItemController(service: service)
        controller.setEnabled(true)
        XCTAssertEqual(controller.state, .requiresApproval)
        XCTAssertTrue(controller.state.isRequested)
        service.state = .notRegistered
        controller.refresh()
        XCTAssertFalse(controller.state.isRequested)
    }
    func testRegistrationFailureDoesNotPretendStartupWasEnabled() {
        let service = FakeLoginService(); service.fail = true
        let controller = LoginItemController(service: service)
        controller.setEnabled(true)
        XCTAssertEqual(controller.state, .notRegistered)
        XCTAssertNotNil(controller.error)
        service.fail = false
        controller.setEnabled(true)
        XCTAssertNil(controller.error)
        XCTAssertEqual(controller.state, .enabled)
    }
}
