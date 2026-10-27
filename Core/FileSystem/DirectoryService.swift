import Foundation

enum DirectoryServiceError: LocalizedError {
    case invalidFolderName
    case invalidFileName
    case invalidDestination
    case itemAlreadyExists(String)
    case trashFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .invalidFolderName:
            return "フォルダー名を入力してください。名前には「/」を使用できません。"
        case .invalidFileName:
            return "ファイル名を入力してください。名前には「/」を使用できません。"
        case .invalidDestination:
            return "フォルダーを自分自身またはその中に配置することはできません。"
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

    @discardableResult
    func renameItem(at source: URL, to rawName: String) throws -> URL {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            throw DirectoryServiceError.invalidFileName
        }
        let original = source.standardizedFileURL
        let destination = original.deletingLastPathComponent().appendingPathComponent(name)
        if original.path == destination.path { return original }
        try fileManager.moveItem(at: original, to: destination)
        return destination.standardizedFileURL
    }

    @discardableResult
    func transferItem(at source: URL, to directory: URL, moving: Bool) throws -> URL {
        let source = source.standardizedFileURL
        let directory = directory.standardizedFileURL
        let resolvedSource = source.resolvingSymlinksInPath().path
        let resolvedDirectory = directory.resolvingSymlinksInPath().path
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue,
           (resolvedDirectory == resolvedSource || resolvedDirectory.hasPrefix(resolvedSource == "/" ? "/" : resolvedSource + "/")) {
            throw DirectoryServiceError.invalidDestination
        }
        var destination = directory.appendingPathComponent(source.lastPathComponent)
        if destination.standardizedFileURL.path == source.path {
            if moving { return source }
            let ext = source.pathExtension
            let stem = ext.isEmpty ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
            var suffix = 1
            repeat {
                let numbered = suffix == 1 ? "コピー" : "コピー (\(suffix))"
                let name = "\(stem) - \(numbered)" + (ext.isEmpty ? "" : ".\(ext)")
                destination = directory.appendingPathComponent(name)
                suffix += 1
            } while fileManager.fileExists(atPath: destination.path) || (try? fileManager.destinationOfSymbolicLink(atPath: destination.path)) != nil
        }
        if moving {
            try fileManager.moveItem(at: source, to: destination)
        } else {
            try fileManager.copyItem(at: source, to: destination)
        }
        return destination.standardizedFileURL
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

    func suggestedTextFileName(in directoryURL: URL) -> String {
        let base = "新しいテキスト ドキュメント"
        var name = "\(base).txt"
        var suffix = 2
        while fileManager.fileExists(atPath: directoryURL.appendingPathComponent(name).path) {
            name = "\(base) (\(suffix)).txt"
            suffix += 1
        }
        return name
    }

    @discardableResult
    func createTextFile(named rawName: String, in directoryURL: URL) throws -> URL {
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            throw DirectoryServiceError.invalidFileName
        }
        if !name.lowercased().hasSuffix(".txt") { name += ".txt" }
        let url = directoryURL.standardizedFileURL.appendingPathComponent(name)
        do {
            try Data().write(to: url, options: .withoutOverwriting)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
            throw DirectoryServiceError.itemAlreadyExists(name)
        }
        return url.standardizedFileURL
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
