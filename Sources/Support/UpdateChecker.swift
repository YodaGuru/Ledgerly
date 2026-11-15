// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import AppKit

/// Checks GitHub Releases for a newer Ledgerly build.
@MainActor
final class UpdateChecker: ObservableObject {
    struct AvailableUpdate: Identifiable, Equatable {
        var id: String { version }
        let version: String
        let downloadURL: URL
        let releasePageURL: URL
        let releaseNotes: String
    }

    enum CheckState: Equatable {
        case idle
        case checking
        case upToDate
        case failed(String)
    }

    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/YodaGuru/Ledgerly/releases/latest")!
    private static let lastCheckKey = "lastUpdateCheckDate"
    static let automaticChecksKey = "automaticUpdateChecks"
    private static let checkInterval: TimeInterval = 60 * 60 * 24

    /// Set when a newer release is found; shows "Update Available" in the sidebar.
    @Published private(set) var availableUpdate: AvailableUpdate?
    /// Set by the sidebar item so Settings opens on About.
    @Published var aboutRevealRequested = false
    @Published private(set) var state: CheckState = .idle
    @Published private(set) var lastCheckDate: Date? = UserDefaults.standard.object(forKey: UpdateChecker.lastCheckKey) as? Date

    private var timer: Timer?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private var automaticChecksEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.automaticChecksKey) == nil ||
            UserDefaults.standard.bool(forKey: Self.automaticChecksKey)
    }

    /// Called at launch: checks if due, then re-checks while the app stays open.
    func start() {
        guard timer == nil else { return }
        checkIfDue()
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
    }

    func checkIfDue() {
        guard automaticChecksEnabled else { return }
        if let lastCheckDate, Date().timeIntervalSince(lastCheckDate) < Self.checkInterval { return }
        Task { await check(userInitiated: false) }
    }

    /// `userInitiated` checks report failures in Settings.
    func check(userInitiated: Bool) async {
        guard state != .checking else { return }
        state = .checking

        var request = URLRequest(url: Self.latestReleaseAPI, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Ledgerly/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            recordCheck()

            let latest = Self.normalizedVersion(release.tagName)
            guard !release.draft, !release.prerelease,
                  Self.isVersion(latest, newerThan: currentVersion) else {
                availableUpdate = nil
                state = .upToDate
                return
            }

            let dmg = release.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
            availableUpdate = AvailableUpdate(
                version: latest,
                downloadURL: dmg?.browserDownloadURL ?? release.htmlURL,
                releasePageURL: release.htmlURL,
                releaseNotes: Self.shortNotes(release.body ?? "")
            )
            state = .idle
        } catch {
            state = userInitiated ? .failed("Couldn't reach GitHub. Check your internet connection and try again.") : .idle
        }
    }

    /// Opens the release's .dmg download (or its release page) in the browser.
    func download(_ update: AvailableUpdate) {
        NSWorkspace.shared.open(update.downloadURL)
    }

    private func recordCheck() {
        let now = Date()
        lastCheckDate = now
        UserDefaults.standard.set(now, forKey: Self.lastCheckKey)
    }

    static func normalizedVersion(_ tag: String) -> String {
        var value = tag.trimmingCharacters(in: .whitespaces)
        if value.lowercased().hasPrefix("v") { value.removeFirst() }
        return value
    }

    /// Numeric comparison of dotted versions, so 3.10.0 is newer than 3.9.2.
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        func parts(_ version: String) -> [Int] {
            version.split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func shortNotes(_ body: String) -> String {
        let lines = body
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .prefix(4)
        let text = lines.joined(separator: "\n")
        return text.count > 400 ? String(text.prefix(400)) + "…" : text
    }
}

private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let htmlURL: URL
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body, draft, prerelease, assets
    }
}
