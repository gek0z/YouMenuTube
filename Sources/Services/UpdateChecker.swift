import Foundation
import OSLog
import Observation

private let log = Logger(subsystem: "app.youmenutube", category: "update-check")

/// Polls GitHub's "latest release" endpoint for this repo and reports whether
/// a newer tagged release is available than the version baked into the bundle.
/// `latest` excludes drafts and pre-releases (so the rolling `nightly` tag
/// is correctly ignored).
@Observable
@MainActor
final class UpdateChecker {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case noPublishedRelease
        case failed(String)
    }

    private(set) var state: State = .idle

    /// `<owner>/<repo>` for the GitHub API.
    private let repo: String
    private let session: URLSession

    init(repo: String = "gek0z/YouMenuTube", session: URLSession = .shared) {
        self.repo = repo
        self.session = session
    }

    /// Bundle's `CFBundleShortVersionString`, the value the comparison is
    /// made against. Anything non-semver (e.g. "main-abc1234" from a nightly)
    /// is treated as "older than any tagged release", which is the right
    /// behaviour for users on the rolling channel.
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    func check() async {
        guard state != .checking else { return }
        state = .checking

        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw UpdateError.badResponse("non-HTTP response")
            }
            // 404 from /releases/latest means either no published (non-draft,
            // non-prerelease) release exists yet, or the repo is private and
            // we have no auth. Either way, surface it as a friendlier state
            // than a raw error.
            if http.statusCode == 404 {
                state = .noPublishedRelease
                log.notice("no published release yet (or private repo)")
                return
            }
            guard http.statusCode == 200 else {
                throw UpdateError.badResponse("HTTP \(http.statusCode)")
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latest = release.tagName.trimmingPrefix("v").description
            log.notice(
                "current=\(self.currentVersion, privacy: .public) latest=\(latest, privacy: .public)")
            if Self.compare(current: currentVersion, latest: latest) {
                state = .available(
                    version: release.tagName,
                    url: URL(string: "https://youmenutube.riccardo.lol/")!)
            } else {
                state = .upToDate
            }
        } catch {
            log.error("check failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    /// Returns true if `latest` is newer than `current`. Semver-aware for
    /// dotted numeric versions; falls back to string-different for anything
    /// non-numeric (which means rolling builds like "main-abc1234" always
    /// register an update is available, by design).
    static func compare(current: String, latest: String) -> Bool {
        let curParts = current.split(separator: ".").compactMap { Int($0) }
        let newParts = latest.split(separator: ".").compactMap { Int($0) }
        if curParts.isEmpty || newParts.isEmpty {
            return current != latest
        }
        let len = max(curParts.count, newParts.count)
        for i in 0..<len {
            let c = i < curParts.count ? curParts[i] : 0
            let n = i < newParts.count ? newParts[i] : 0
            if n > c { return true }
            if n < c { return false }
        }
        return false
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
    }
}

private enum UpdateError: LocalizedError {
    case badResponse(String)
    var errorDescription: String? {
        switch self {
        case .badResponse(let why): return "Couldn't reach GitHub: \(why)"
        }
    }
}
