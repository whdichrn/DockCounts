import XCTest
@testable import DockCounts

final class UpdateCheckerTests: XCTestCase {
    func testAppVersionParsingAndSemverOrdering() {
        XCTAssertEqual(AppVersion("v0.5.1"), AppVersion("0.5.1"))
        XCTAssertEqual(AppVersion("0.5.2-rc.1"), AppVersion("0.5.2"))
        XCTAssertEqual(AppVersion("1.0"), AppVersion("1.0.0"))

        XCTAssertLessThan(AppVersion("0.5.1")!, AppVersion("v0.5.2")!)
        XCTAssertLessThan(AppVersion("0.5.2")!, AppVersion("0.5.10")!)
        XCTAssertLessThan(AppVersion("0.9.9")!, AppVersion("1.0.0")!)

        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("开发构建"))
        XCTAssertNil(AppVersion("0.5.x"))
    }

    func testEvaluateHandlesNewerSameDraftAndPrerelease() {
        let url = URL(string: "https://github.com/whdichrn/DockCounts/releases/tag/v0.6.0")!
        let newer = ReleaseInfo(tagName: "v0.6.0", htmlURL: url)
        XCTAssertEqual(
            UpdateChecker.evaluate(currentVersion: "0.5.1", release: newer),
            .available(version: "0.6.0", url: url)
        )
        XCTAssertEqual(
            UpdateChecker.evaluate(currentVersion: "0.6.0", release: newer),
            .upToDate(current: "0.6.0")
        )
        XCTAssertEqual(
            UpdateChecker.evaluate(currentVersion: "0.7.0", release: newer),
            .upToDate(current: "0.7.0")
        )

        let draft = ReleaseInfo(tagName: "v9.9.9", htmlURL: url, draft: true)
        XCTAssertEqual(
            UpdateChecker.evaluate(currentVersion: "0.5.1", release: draft),
            .upToDate(current: "0.5.1")
        )

        let prerelease = ReleaseInfo(tagName: "v9.9.9", htmlURL: url, prerelease: true)
        XCTAssertEqual(
            UpdateChecker.evaluate(currentVersion: "0.5.1", release: prerelease),
            .upToDate(current: "0.5.1")
        )
    }

    @MainActor
    func testCheckHandlesSuccessUpToDateAndHttpError() async {
        let releaseURL = "https://github.com/whdichrn/DockCounts/releases/tag/v0.6.0"
        let jsonNewer = """
        {"tag_name":"v0.6.0","html_url":"\(releaseURL)","draft":false,"prerelease":false}
        """.data(using: .utf8)!
        let okResponse = HTTPURLResponse(
            url: UpdateChecker.latestReleaseAPI,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let checker = UpdateChecker { (jsonNewer, okResponse) }
        await checker.check(currentVersion: "0.5.1")
        XCTAssertEqual(checker.state, .available(version: "0.6.0", url: URL(string: releaseURL)!))

        await checker.check(currentVersion: "0.6.0")
        XCTAssertEqual(checker.state, .upToDate(current: "0.6.0"))

        let errorResponse = HTTPURLResponse(
            url: UpdateChecker.latestReleaseAPI,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )!
        let failingChecker = UpdateChecker { (Data(), errorResponse) }
        await failingChecker.check(currentVersion: "0.5.1")
        XCTAssertEqual(failingChecker.state, .failed)
    }
}
