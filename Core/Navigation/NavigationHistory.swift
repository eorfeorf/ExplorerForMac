import Foundation

struct NavigationHistory: Codable, Equatable {
    private(set) var entries: [URL]
    private(set) var currentIndex: Int

    init(initialURL: URL) {
        entries = [initialURL.standardizedFileURL]
        currentIndex = 0
    }

    init(entries: [URL], currentIndex: Int) {
        let normalized = entries.map(\.standardizedFileURL)
        if normalized.isEmpty {
            self.entries = [FileManager.default.homeDirectoryForCurrentUser]
            self.currentIndex = 0
        } else {
            self.entries = normalized
            self.currentIndex = min(max(0, currentIndex), normalized.count - 1)
        }
    }

    var currentURL: URL {
        entries[currentIndex]
    }

    var canGoBack: Bool {
        currentIndex > 0
    }

    var canGoForward: Bool {
        currentIndex < entries.count - 1
    }

    mutating func navigate(to url: URL) {
        let normalized = url.standardizedFileURL
        guard normalized != currentURL else { return }

        if canGoForward {
            entries.removeSubrange((currentIndex + 1)...)
        }
        entries.append(normalized)
        currentIndex = entries.count - 1

        if entries.count > 100 {
            let overflow = entries.count - 100
            entries.removeFirst(overflow)
            currentIndex -= overflow
        }
    }

    mutating func goBack() -> URL? {
        guard canGoBack else { return nil }
        currentIndex -= 1
        return currentURL
    }

    mutating func goForward() -> URL? {
        guard canGoForward else { return nil }
        currentIndex += 1
        return currentURL
    }
}
