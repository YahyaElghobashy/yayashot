//
//  AppUpdater.swift
//  YayaShot (sealed build)
//
//  Notify-only update check. Upstream BetterShot downloaded a DMG from GitHub,
//  mounted it and replaced the running app. YayaShot never downloads or
//  installs anything. It reads two public release feeds through NetworkPolicy:
//
//  - YayaShot's own releases (YahyaElghobashy/yayashot): "version X is out".
//  - Upstream BetterShot's releases (KartikLabhshetwar/better-shot): "upstream
//    shipped vX, see what changed", so fixes can be merged into the fork.
//
//  Both show the release title, an excerpt of the notes and a button that opens
//  the release page in the browser. The automatic check at launch is off by
//  default; "Check for Updates…" in Settings > About runs it on demand.
//

import AppKit
import Foundation

@MainActor
@Observable
final class AppUpdater {
    static let shared = AppUpdater()

    struct Release: Equatable {
        let version: String
        let title: String
        let notes: String
        let page: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case available(Release)
        case upToDate
        case failed(String)
    }

    static let ownRepository = "YahyaElghobashy/yayashot"
    static let upstreamRepository = "KartikLabhshetwar/better-shot"
    /// The upstream release this build is based on.
    static let upstreamBaseVersion = "0.5.7"
    static let automaticCheckKey = "ys_checkForUpdatesAutomatically"

    private(set) var state: State = .idle
    /// Newest upstream BetterShot release when it is newer than the base above.
    private(set) var upstreamRelease: Release?
    private(set) var latestAvailableVersion: String?

    static var checksAutomatically: Bool {
        get { UserDefaults.standard.bool(forKey: automaticCheckKey) }
        set { UserDefaults.standard.set(newValue, forKey: automaticCheckKey) }
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private init() {}

    /// Launch-time check. Does nothing unless the user turned it on.
    func checkForUpdatesQuietly() async {
        guard Self.checksAutomatically else { return }
        await check(quiet: true)
    }

    func checkForUpdates() async {
        state = .checking
        await check(quiet: false)
    }

    func openReleasePage(_ release: Release) {
        NSWorkspace.shared.open(release.page)
    }

    private func check(quiet: Bool) async {
        var failure: String?

        do {
            if let own = try await Self.latestRelease(of: Self.ownRepository),
               Self.isNewer(own.version, than: currentVersion) {
                latestAvailableVersion = own.version
                state = .available(own)
                if quiet {
                    ToastWindow.shared.show(
                        title: "Update Available",
                        message: "YayaShot \(own.version) is available",
                        systemIcon: "arrow.down.circle"
                    )
                }
            } else if !quiet {
                state = .upToDate
            }
        } catch {
            failure = error.localizedDescription
        }

        do {
            if let upstream = try await Self.latestRelease(of: Self.upstreamRepository),
               Self.isNewer(upstream.version, than: Self.upstreamBaseVersion) {
                upstreamRelease = upstream
            } else {
                upstreamRelease = nil
            }
        } catch {
            failure = failure ?? error.localizedDescription
        }

        if !quiet, let failure, case .checking = state {
            state = .failed(failure)
        }
    }

    /// The newest published release of `repository`, or nil when there is none.
    private static func latestRelease(of repository: String) async throws -> Release? {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else { return nil }
        let (data, response) = try await NetworkPolicy.get(url)
        if response.statusCode == 404 { return nil }
        guard response.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else {
            throw NetworkPolicy.Refusal.unexpectedResponse
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let title = (json["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? tag
        let body = (json["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = body.count > 600 ? String(body.prefix(600)) + "…" : body
        let fallback = URL(string: "https://github.com/\(repository)/releases")!
        var page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? fallback
        if page.scheme?.lowercased() != "https" || page.host?.lowercased() != "github.com" { page = fallback }
        return Release(version: version, title: title, notes: notes, page: page)
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(lhs.count, rhs.count) {
            let a = index < lhs.count ? lhs[index] : 0
            let b = index < rhs.count ? rhs[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}
