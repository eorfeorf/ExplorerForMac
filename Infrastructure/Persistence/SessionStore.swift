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
    private let maximumFolderCount = 50

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
        defaults.set(Array(paths.prefix(maximumFolderCount)), forKey: key)
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

    private func normalizedPath(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
