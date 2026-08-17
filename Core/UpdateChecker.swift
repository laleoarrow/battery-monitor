import Foundation

struct UpdateVersion: Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ rawValue: String) {
        let value = rawValue.hasPrefix("v") ? String(rawValue.dropFirst()) : rawValue
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]) else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: UpdateVersion, rhs: UpdateVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

struct UpdateRelease: Equatable {
    let version: String
    let pageURL: URL
}

enum UpdateCheckOutcome: Equatable {
    case upToDate(currentVersion: String)
    case updateAvailable(UpdateRelease)
}

enum UpdateCheckError: LocalizedError, Equatable {
    case invalidResponse
    case invalidCurrentVersion
    case invalidReleaseVersion
    case invalidReleaseURL
    case unsupportedRelease

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub returned an invalid update response."
        case .invalidCurrentVersion:
            return "Wattson could not read its installed version."
        case .invalidReleaseVersion:
            return "The latest release has an invalid version."
        case .invalidReleaseURL:
            return "The latest release link is not trusted."
        case .unsupportedRelease:
            return "GitHub returned a draft or prerelease build."
        }
    }
}

final class UpdateChecker {
    typealias Loader = (URLRequest, @escaping (Result<Data, Error>) -> Void) -> Void

    static let shared = UpdateChecker()

    private static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/laleoarrow/battery-monitor/releases/latest"
    )!

    private let currentVersion: () -> String
    private let loader: Loader
    private var completions: [(Result<UpdateCheckOutcome, Error>) -> Void] = []

    convenience init() {
        self.init(
            currentVersion: {
                Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleShortVersionString"
                ) as? String ?? ""
            },
            loader: Self.load
        )
    }

    init(
        currentVersion: @escaping () -> String,
        loader: @escaping Loader
    ) {
        self.currentVersion = currentVersion
        self.loader = loader
    }

    func check(
        completion: @escaping (Result<UpdateCheckOutcome, Error>) -> Void
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.check(completion: completion)
            }
            return
        }

        completions.append(completion)
        guard completions.count == 1 else { return }

        var request = URLRequest(
            url: Self.latestReleaseURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 10
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Wattson/\(currentVersion())", forHTTPHeaderField: "User-Agent")
        loader(request) { [weak self] result in
            DispatchQueue.main.async {
                self?.finish(result)
            }
        }
    }

    static func evaluate(
        data: Data,
        currentVersion: String
    ) throws -> UpdateCheckOutcome {
        struct Payload: Decodable {
            let tagName: String
            let pageURL: String
            let draft: Bool
            let prerelease: Bool

            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case pageURL = "html_url"
                case draft
                case prerelease
            }
        }

        guard let installed = UpdateVersion(currentVersion) else {
            throw UpdateCheckError.invalidCurrentVersion
        }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw UpdateCheckError.invalidResponse
        }
        guard !payload.draft, !payload.prerelease else {
            throw UpdateCheckError.unsupportedRelease
        }
        guard let latest = UpdateVersion(payload.tagName) else {
            throw UpdateCheckError.invalidReleaseVersion
        }
        guard let pageURL = URL(string: payload.pageURL),
              pageURL.scheme == "https",
              pageURL.host == "github.com",
              pageURL.path.hasPrefix(
                "/laleoarrow/battery-monitor/releases/tag/"
              ) else {
            throw UpdateCheckError.invalidReleaseURL
        }

        guard latest > installed else {
            return .upToDate(currentVersion: installed.description)
        }
        return .updateAvailable(
            UpdateRelease(version: latest.description, pageURL: pageURL)
        )
    }

    private func finish(_ loaded: Result<Data, Error>) {
        let result: Result<UpdateCheckOutcome, Error>
        switch loaded {
        case let .success(data):
            result = Result {
                try Self.evaluate(data: data, currentVersion: currentVersion())
            }
        case let .failure(error):
            result = .failure(error)
        }

        let callbacks = completions
        completions.removeAll()
        callbacks.forEach { $0(result) }
    }

    private static func load(
        _ request: URLRequest,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let response = response as? HTTPURLResponse,
                  response.statusCode == 200,
                  let data else {
                completion(.failure(UpdateCheckError.invalidResponse))
                return
            }
            completion(.success(data))
        }.resume()
    }
}

final class UpdateLaunchController {
    typealias Check = (
        @escaping (Result<UpdateCheckOutcome, Error>) -> Void
    ) -> Void

    private let shouldCheck: () -> Bool
    private let check: Check
    private let present: (UpdateRelease) -> Void

    init(
        shouldCheck: @escaping () -> Bool,
        check: @escaping Check,
        present: @escaping (UpdateRelease) -> Void
    ) {
        self.shouldCheck = shouldCheck
        self.check = check
        self.present = present
    }

    func start() {
        guard shouldCheck() else { return }
        check { [weak self] result in
            guard case let .success(.updateAvailable(release)) = result else { return }
            self?.present(release)
        }
    }
}
