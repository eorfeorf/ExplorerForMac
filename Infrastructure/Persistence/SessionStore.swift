import Foundation

struct PersistedSession: Codable, Equatable {
    var tabs: [NavigationHistory]
    var selectedTabIndex: Int
    var showsHiddenFiles: Bool
}

final class SessionStore {
    private let defaults: UserDefaults
    private let key = "ExplorerForMac.session.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PersistedSession? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PersistedSession.self, from: data)
    }

    func save(_ session: PersistedSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: key)
    }
}

final class PinnedFoldersStore {
    static let shared = PinnedFoldersStore()
    static let didChangeNotification = Notification.Name("ExplorerForMac.pinnedFoldersDidChange")

    private let defaults: UserDefaults
    private let key = "ExplorerForMac.pinnedFolders.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var urls: [URL] {
        (defaults.stringArray(forKey: key) ?? []).map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
        }
    }

    func contains(_ url: URL) -> Bool {
        let path = normalizedPath(for: url)
        return urls.contains { $0.path == path }
    }

    @discardableResult
    func pin(_ url: URL) -> Bool {
        let normalized = url.standardizedFileURL
        guard !contains(normalized) else { return false }
        var paths = urls.map(\.path)
        paths.append(normalized.path)
        defaults.set(paths, forKey: key)
        notifyChange()
        return true
    }

    @discardableResult
    func unpin(_ url: URL) -> Bool {
        let path = normalizedPath(for: url)
        var paths = urls.map(\.path)
        let originalCount = paths.count
        paths.removeAll { $0 == path }
        guard paths.count != originalCount else { return false }
        defaults.set(paths, forKey: key)
        notifyChange()
        return true
    }

    func relocate(from source: URL, to destination: URL) {
        let oldPath = normalizedPath(for: source)
        let newPath = normalizedPath(for: destination)
        guard oldPath != newPath else { return }
        var seen = Set<String>()
        let paths = urls.map(\.path).map { path -> String in
            if path == oldPath { return newPath }
            if path.hasPrefix(oldPath + "/") { return newPath + path.dropFirst(oldPath.count) }
            return path
        }.filter { seen.insert($0).inserted }
        guard paths != urls.map(\.path) else { return }
        defaults.set(paths, forKey: key)
        notifyChange()
    }

    private func normalizedPath(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
