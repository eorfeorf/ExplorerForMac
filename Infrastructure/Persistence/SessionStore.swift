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
