import Foundation

struct AppVersion: Comparable, Equatable {
    let components: [Int]

    init?(_ raw: String) {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            trimmed.removeFirst()
        }
        if let dash = trimmed.firstIndex(of: "-") {
            trimmed = String(trimmed[..<dash])
        }
        if let plus = trimmed.firstIndex(of: "+") {
            trimmed = String(trimmed[..<plus])
        }
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        var parsed: [Int] = []
        for part in parts {
            guard !part.isEmpty, let value = Int(part), value >= 0 else { return nil }
            parsed.append(value)
        }
        guard !parsed.isEmpty else { return nil }
        self.components = parsed
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let l = index < lhs.components.count ? lhs.components[index] : 0
            let r = index < rhs.components.count ? rhs.components[index] : 0
            if l != r { return false }
        }
        return true
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let l = index < lhs.components.count ? lhs.components[index] : 0
            let r = index < rhs.components.count ? rhs.components[index] : 0
            if l != r { return l < r }
        }
        return false
    }
}

struct ReleaseInfo: Decodable, Equatable {
    let tagName: String
    let htmlURL: URL
    let name: String?
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case name
        case draft
        case prerelease
    }

    init(tagName: String, htmlURL: URL, name: String? = nil, draft: Bool = false, prerelease: Bool = false) {
        self.tagName = tagName
        self.htmlURL = htmlURL
        self.name = name
        self.draft = draft
        self.prerelease = prerelease
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try c.decode(String.self, forKey: .tagName)
        htmlURL = try c.decode(URL.self, forKey: .htmlURL)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        draft = try c.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        prerelease = try c.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
    }

    var displayVersion: String {
        if tagName.hasPrefix("v") || tagName.hasPrefix("V") {
            return String(tagName.dropFirst())
        }
        return tagName
    }
}

enum UpdateCheckState: Equatable {
    case idle
    case checking
    case upToDate(current: String)
    case available(version: String, url: URL)
    case failed
}

final class UpdateChecker: ObservableObject, @unchecked Sendable {
    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/whdichrn/DockCounts/releases/latest")!

    @Published private(set) var state: UpdateCheckState = .idle
    private let fetcher: @Sendable () async throws -> (Data, URLResponse)

    init(fetcher: @escaping @Sendable () async throws -> (Data, URLResponse) = { try await UpdateChecker.defaultFetch() }) {
        self.fetcher = fetcher
    }

    static func defaultFetch() async throws -> (Data, URLResponse) {
        var request = URLRequest(
            url: latestReleaseAPI,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 10
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DockCounts", forHTTPHeaderField: "User-Agent")
        return try await URLSession.shared.data(for: request)
    }

    static func evaluate(currentVersion: String, release: ReleaseInfo) -> UpdateCheckState {
        guard !release.draft, !release.prerelease else {
            return .upToDate(current: currentVersion)
        }
        guard let latest = AppVersion(release.tagName) else {
            return .failed
        }
        if let current = AppVersion(currentVersion) {
            return latest > current
                ? .available(version: release.displayVersion, url: release.htmlURL)
                : .upToDate(current: currentVersion)
        }
        return .available(version: release.displayVersion, url: release.htmlURL)
    }

    @MainActor
    func check(currentVersion: String = ProjectLinks.version) async {
        guard state != .checking else { return }
        state = .checking
        do {
            let (data, response) = try await fetcher()
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                state = .failed
                return
            }
            let release = try JSONDecoder().decode(ReleaseInfo.self, from: data)
            state = Self.evaluate(currentVersion: currentVersion, release: release)
        } catch {
            state = .failed
        }
    }
}
