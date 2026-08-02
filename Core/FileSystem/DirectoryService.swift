import Foundation

final class DirectoryService {
    private let fileManager: FileManager
    private let workerQueue = DispatchQueue(
        label: "com.example.ExplorerForMac.directory-loader",
        qos: .userInitiated,
        attributes: .concurrent
    )

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
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
