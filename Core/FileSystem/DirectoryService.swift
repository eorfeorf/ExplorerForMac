import Foundation

enum DirectoryServiceError: LocalizedError {
    case invalidFolderName
    case itemAlreadyExists(String)
    case trashFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .invalidFolderName:
            return "フォルダー名を入力してください。名前には「/」を使用できません。"
        case .itemAlreadyExists(let name):
            return "「\(name)」という項目はすでに存在します。"
        case .trashFailed(let name, let reason):
            return "「\(name)」をゴミ箱に入れられませんでした。\n\(reason)"
        }
    }
}

final class DirectoryService {
    private let fileManager: FileManager
    private let workerQueue = DispatchQueue(
        label: "com.example.ExplorerForMac.directory-loader",
        qos: .userInitiated,
        attributes: .concurrent
    )

    init(fileManager: FileManager = Foundation.FileManager.default) {
        self.fileManager = fileManager
    }

    func suggestedFolderName(in directoryURL: URL, baseName: String = "新しいフォルダー") -> String {
        let directory = directoryURL.standardizedFileURL
        var candidate = baseName
        var suffix = 2
        while fileManager.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = "\(baseName) (\(suffix))"
            suffix += 1
        }
        return candidate
    }

    @discardableResult
    func createFolder(named rawName: String, in directoryURL: URL) throws -> URL {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.contains("\0") else {
            throw DirectoryServiceError.invalidFolderName
        }

        let folderURL = directoryURL.standardizedFileURL
            .appendingPathComponent(name, isDirectory: true)
        guard !fileManager.fileExists(atPath: folderURL.path) else {
            throw DirectoryServiceError.itemAlreadyExists(name)
        }
        try fileManager.createDirectory(
            at: folderURL,
            withIntermediateDirectories: false,
            attributes: nil
        )
        return folderURL.standardizedFileURL
    }

    @discardableResult
    func trashItems(at urls: [URL]) throws -> [URL] {
        var resultingURLs: [URL] = []
        for url in urls {
            var resultingURL: NSURL?
            do {
                try fileManager.trashItem(at: url.standardizedFileURL, resultingItemURL: &resultingURL)
            } catch {
                throw DirectoryServiceError.trashFailed(
                    url.lastPathComponent,
                    error.localizedDescription
                )
            }
            if let resultingURL {
                resultingURLs.append(resultingURL as URL)
            }
        }
        return resultingURLs
    }

    func contents(of directoryURL: URL, showsHiddenFiles: Bool) throws -> DirectorySnapshot {
        let normalized = directoryURL.standardizedFileURL
        let resourceKeys: [URLResourceKey] = [
            .isDirectoryKey,
            .isPackageKey,
            .isSymbolicLinkKey,
            .isHiddenKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .localizedTypeDescriptionKey,
            .contentTypeKey
        ]
        let options: FileManager.DirectoryEnumerationOptions = showsHiddenFiles ? [] : [.skipsHiddenFiles]
        let urls = try fileManager.contentsOfDirectory(
            at: normalized,
            includingPropertiesForKeys: resourceKeys,
            options: options
        )
        let items = urls.compactMap { try? FileItem.load(from: $0) }
        return DirectorySnapshot(directoryURL: normalized, items: items, loadedAt: Date())
    }

    func loadContents(
        of directoryURL: URL,
        showsHiddenFiles: Bool,
        completion: @escaping (Result<DirectorySnapshot, Error>) -> Void
    ) {
        workerQueue.async { [weak self] in
            guard let self else { return }
            let result = Result {
                try self.contents(of: directoryURL, showsHiddenFiles: showsHiddenFiles)
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func loadChildDirectories(
        of directoryURL: URL,
        showsHiddenFiles: Bool,
        completion: @escaping ([URL]) -> Void
    ) {
        workerQueue.async { [weak self] in
            guard let self else { return }
            let children: [URL]
            do {
                children = try self.contents(of: directoryURL, showsHiddenFiles: showsHiddenFiles)
                    .items
                    .filter(\.canBrowse)
                    .map(\.url)
                    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            } catch {
                children = []
            }
            DispatchQueue.main.async {
                completion(children)
            }
        }
    }

    func mountedVolumes() -> [URL] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsBrowsableKey]
        return fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []
    }
}
