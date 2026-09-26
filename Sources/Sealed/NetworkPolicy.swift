//
//  NetworkPolicy.swift
//  YayaShot (sealed build)
//
//  The only place in YayaShot that is allowed to talk to the network.
//
//  Policy:
//  - HTTPS GET only. No uploads, no POST/PUT/DELETE, no cookies, no cache.
//  - Static host allowlist below. Anything else is refused before a socket opens.
//  - The one caller is the notify-only update check (AppUpdater), which reads
//    public release metadata for YayaShot and for upstream BetterShot.
//
//  `Tools/check-sealed.sh` fails the build if URLSession, URLRequest, sockets,
//  or process launches of network tools appear anywhere else in the tree.
//

import Foundation

enum NetworkPolicy {
    /// Hosts YayaShot may contact. Keep this list in step with README.md.
    static let allowedHosts: Set<String> = ["api.github.com"]

    enum Refusal: LocalizedError {
        case notHTTPS
        case hostNotAllowed(String)
        case unexpectedResponse

        var errorDescription: String? {
            switch self {
            case .notHTTPS: "Only HTTPS requests are allowed."
            case .hostNotAllowed(let host): "\(host) is not on YayaShot's network allowlist."
            case .unexpectedResponse: "The server returned an unexpected response."
            }
        }
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpAdditionalHeaders = ["User-Agent": "YayaShot"]
        return URLSession(configuration: configuration)
    }()

    /// Performs an allowlisted HTTPS GET and returns the body and status.
    static func get(_ url: URL, accept: String = "application/vnd.github+json") async throws -> (Data, HTTPURLResponse) {
        guard url.scheme?.lowercased() == "https" else { throw Refusal.notHTTPS }
        guard let host = url.host?.lowercased(), allowedHosts.contains(host) else {
            throw Refusal.hostNotAllowed(url.host ?? "unknown host")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(accept, forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Refusal.unexpectedResponse }
        return (data, http)
    }
}
