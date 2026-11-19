import AppKit
import CryptoKit
import Darwin
import Foundation

final class AppUpdater: NSObject, NSMenuItemValidation {
    private static let repository = "eorfeorf/ExplorerForMac"
    private static let helperArgument = "--install-downloaded-update"
    private static let stagingPrefix = ".explorer-update-"
    private var isBusy = false

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let digest: String?
            let size: Int
        }

        let tagName: String
        let assets: [Asset]
    }

    private enum UpdateError: LocalizedError {
        case invalidRelease, invalidArchive, invalidApp, installationFailed

        var errorDescription: String? {
            switch self {
            case .invalidRelease: return "GitHub Releaseから有効な更新情報を取得できませんでした。"
            case .invalidArchive: return "ダウンロードしたZIPを検証できませんでした。"
            case .invalidApp: return "ZIPに含まれるアプリのバージョンまたは署名を確認できませんでした。"
            case .installationFailed: return "アプリを置き換えられませんでした。アプリのあるフォルダーに書き込めるか確認してください。"
            }
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.title = isBusy ? "アップデート処理中…" : "アップデートを確認…"
        return !isBusy
    }

    @objc func checkForUpdates(_ sender: Any?) {
        guard !isBusy else { return }
        isBusy = true
        Task { @MainActor in
            defer { isBusy = false }
            do {
                try await check()
            } catch {
                Self.showAlert("アップデートできませんでした", detail: error.localizedDescription)
            }
        }
    }

    @MainActor
    private func check() async throws {
        let bundle = Bundle.main
        guard let current = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let currentVersion = Self.versionParts(current) else { throw UpdateError.invalidApp }

        let endpoint = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.invalidRelease }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let release = try decoder.decode(Release.self, from: data)
        let version = String(release.tagName.dropFirst())
        guard release.tagName.hasPrefix("v"), let latestVersion = Self.versionParts(version) else {
            throw UpdateError.invalidRelease
        }
        guard currentVersion.lexicographicallyPrecedes(latestVersion) else {
            Self.showAlert("最新版を使用しています", detail: "現在のバージョンは \(current) です。")
            return
        }
        let archiveName = "Explorer-for-Mac-\(version)-macOS-universal.zip"
        guard let asset = release.assets.first(where: { $0.name == archiveName }),
              let digest = asset.digest, digest.hasPrefix("sha256:"), digest.count == 71,
              asset.size > 0, asset.size <= 100 * 1024 * 1024 else {
            throw UpdateError.invalidRelease
        }

        let alert = NSAlert()
        alert.messageText = "Explorer for Mac \(version) にアップデートしますか？"
        alert.informativeText = "現在のバージョンは \(current) です。更新をダウンロードし、インストール後にアプリを再起動します。"
        alert.addButton(withTitle: "アップデートして再起動")
        alert.addButton(withTitle: "キャンセル").keyEquivalent = "\u{1b}"
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let url = URL(string: "https://github.com/\(Self.repository)/releases/download/\(release.tagName)/\(archiveName)")!
        let app = bundle.bundleURL
        let stage = try await Self.prepareUpdate(from: url, asset: asset, digest: digest, version: version, app: app)
        do {
            guard let executable = bundle.executableURL else { throw UpdateError.invalidApp }
            let helper = Process()
            helper.executableURL = executable
            helper.arguments = [Self.helperArgument, String(getpid()), stage.path]
            let ready = Pipe()
            helper.standardOutput = ready
            try helper.run()
            try? ready.fileHandleForWriting.close()
            guard try ready.fileHandleForReading.read(upToCount: 1) == Data([1]) else {
                throw UpdateError.installationFailed
            }
        } catch {
            try? FileManager.default.removeItem(at: stage)
            throw error
        }
        NSApp.terminate(nil)
    }

    private static func prepareUpdate(
        from url: URL, asset: Release.Asset, digest: String, version: String, app: URL
    ) async throws -> URL {
        let (download, response) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: download) }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              try download.resourceValues(forKeys: [.fileSizeKey]).fileSize == asset.size else {
            throw UpdateError.invalidArchive
        }
        let bytes = try Data(contentsOf: download, options: .mappedIfSafe)
        let actual = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard digest == "sha256:\(actual)" else { throw UpdateError.invalidArchive }

        let stage = app.deletingLastPathComponent().appendingPathComponent(stagingPrefix + UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        } catch {
            throw UpdateError.installationFailed
        }
        do {
            do {
                try run("/usr/bin/ditto", ["-x", "-k", download.path, stage.path])
            } catch {
                throw UpdateError.invalidArchive
            }
            let candidate = stage.appendingPathComponent("Explorer for Mac.app")
            guard let info = NSDictionary(contentsOf: candidate.appendingPathComponent("Contents/Info.plist")),
                  info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
                  info["CFBundleShortVersionString"] as? String == version,
                  (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false else {
                throw UpdateError.invalidApp
            }
            do {
                try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", candidate.path])
            } catch {
                throw UpdateError.invalidApp
            }
            return stage
        } catch {
            try? FileManager.default.removeItem(at: stage)
            throw error
        }
    }

    static func runInstallerIfRequested() {
        let arguments = CommandLine.arguments
        guard arguments.count == 4, arguments[1] == helperArgument, let parent = Int32(arguments[2]),
              parent == getppid() else { return }
        let app = Bundle.main.bundleURL.standardizedFileURL
        let stage = URL(fileURLWithPath: arguments[3], isDirectory: true).standardizedFileURL
        let candidate = stage.appendingPathComponent("Explorer for Mac.app")
        guard stage.deletingLastPathComponent().path == app.deletingLastPathComponent().path,
              stage.lastPathComponent.hasPrefix(stagingPrefix) else { Darwin.exit(EXIT_FAILURE) }
        FileHandle.standardOutput.write(Data([1]))

        // The running app saves its session during normal termination.
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        while getppid() == parent && ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard getppid() != parent else { Darwin.exit(EXIT_FAILURE) }

        do {
            try swap(app, candidate)
            do {
                try run("/usr/bin/open", ["-n", app.path])
            } catch {
                try swap(app, candidate)
                throw error
            }

            // The directory now holds the previous bundle.
            if let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
                let backups = support.appendingPathComponent("Explorer for Mac Backups", isDirectory: true)
                if (try? FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)) != nil {
                    try? FileManager.default.moveItem(at: stage, to: backups.appendingPathComponent("update-" + UUID().uuidString))
                }
            }
        } catch {
            try? run("/usr/bin/open", ["-n", app.path])
            NSApplication.shared.setActivationPolicy(.accessory)
            NSApp.activate(ignoringOtherApps: true)
            showAlert("アップデートを完了できませんでした", detail: "\(error.localizedDescription)\n\(stage.path)")
            Darwin.exit(EXIT_FAILURE)
        }
        Darwin.exit(EXIT_SUCCESS)
    }

    private static func swap(_ left: URL, _ right: URL) throws {
        guard renameatx_np(AT_FDCWD, left.path, AT_FDCWD, right.path, UInt32(RENAME_SWAP)) == 0 else {
            throw UpdateError.installationFailed
        }
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.installationFailed }
    }

    static func versionParts(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else {
            return nil
        }
        let values = parts.compactMap { Int($0) }
        return values.count == 3 ? values : nil
    }

    private static func showAlert(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }
}
