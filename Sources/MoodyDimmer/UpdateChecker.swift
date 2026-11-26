import AppKit
import os

private let updateLog = Logger(subsystem: "io.github.roman1kuz.moodydimmer", category: "update")

/// Manual update check, run only when the user picks "Check for Updates…": one request to GitHub for the
/// latest release. Nothing runs in the background and nothing is downloaded or installed; the alert links to
/// the release page, and for Homebrew installs also offers the upgrade command.
enum UpdateChecker {
    static let repository = "roman1kuz/MoodyDimmer"
    /// Cask token in the Homebrew tap. Its Caskroom folder means the app was installed with Homebrew.
    static let caskToken = "moody-dimmer"

    struct Release {
        let version: String
        let page: URL
    }

    enum CheckError: Error {
        case status(Int)
        case badData
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var installedWithHomebrew: Bool {
        ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"].contains {
            FileManager.default.fileExists(atPath: "\($0)/\(caskToken)")
        }
    }

    /// Asks GitHub for the latest release. An ephemeral session: no cookies, no cache, nothing stored.
    static func fetchLatest(repository: String = repository, completion: @escaping (Result<Release, Error>) -> Void) {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!,
                                 timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MoodyDimmer/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: request) { data, response, error in
            defer { session.finishTasksAndInvalidate() }
            if let error { return completion(.failure(error)) }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { return completion(.failure(CheckError.status(status))) }
            struct Payload: Decodable {
                let tag_name: String
                let html_url: URL
            }
            guard let data, let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
                return completion(.failure(CheckError.badData))
            }
            completion(.success(Release(version: normalized(payload.tag_name), page: payload.html_url)))
        }.resume()
    }

    /// "v1.2.0" → "1.2.0".
    static func normalized(_ tag: String) -> String {
        tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
    }

    /// Compares dotted version numbers ("1.10.0" > "1.9.2"); a suffix such as "-beta" is ignored.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            normalized(v).split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Alerts

    /// Shows the result of a check: up to date, a newer version (with download and Homebrew options), or an error.
    static func present(_ result: Result<Release, Error>) {
        NSApp.activate()  // a menu bar app: bring the alert to the front
        let alert = NSAlert()
        switch result {
        case .failure(let error):
            updateLog.error("update check failed: \(String(describing: error), privacy: .public)")
            alert.messageText = L("Couldn't check for updates")
            alert.informativeText = L("Check your internet connection or try again later.")
            alert.runModal()

        case .success(let release) where !isNewer(release.version, than: currentVersion):
            alert.messageText = L("You're up to date")
            alert.informativeText = String(format: L("Moody Dimmer %@ is the latest version."), currentVersion)
            alert.runModal()

        case .success(let release):
            // brew refreshes its taps on its own at most once a day, so update first to see a fresh release.
            let command = "brew update && brew upgrade \(caskToken)"
            let brew = installedWithHomebrew
            alert.messageText = String(format: L("Moody Dimmer %@ is available"), release.version)
            var info = String(format: L("You have version %@."), currentVersion)
            if brew {
                info += "\n\n" + L("Installed with Homebrew. Update with this command or download it manually:")
                info += "\n" + command
                alert.addButton(withTitle: L("Copy Command"))
            }
            alert.informativeText = info
            alert.addButton(withTitle: L("Download"))
            alert.addButton(withTitle: L("Later")).keyEquivalent = "\u{1b}"
            let response = alert.runModal()
            let download: NSApplication.ModalResponse = brew ? .alertSecondButtonReturn : .alertFirstButtonReturn
            if brew && response == .alertFirstButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            } else if response == download {
                NSWorkspace.shared.open(release.page)
            }
        }
    }
}
