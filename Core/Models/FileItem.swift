import AppKit
import Foundation
import UniformTypeIdentifiers

struct FileItem: Hashable, Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let isPackage: Bool
    let isSymbolicLink: Bool
    let isHidden: Bool
    let size: Int64?
    let modifiedAt: Date?
    let kind: String

    var canBrowse: Bool {
        isDirectory && !isPackage
    }

    static func load(from url: URL) throws -> FileItem {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isPackageKey,
            .isSymbolicLinkKey,
            .isHiddenKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .localizedTypeDescriptionKey,
            .contentTypeKey
        ]
        let values = try url.resourceValues(forKeys: keys)
        let isDirectory = values.isDirectory ?? false
        let isPackage = values.isPackage ?? false
        let fallbackKind: String

        if isPackage {
            fallbackKind = "アプリケーション"
        } else if isDirectory {
            fallbackKind = "フォルダー"
        } else if let contentType = values.contentType {
            fallbackKind = contentType.localizedDescription ?? contentType.identifier
        } else {
            fallbackKind = "ファイル"
        }

        return FileItem(
            url: url.standardizedFileURL,
            name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
            isDirectory: isDirectory,
            isPackage: isPackage,
            isSymbolicLink: values.isSymbolicLink ?? false,
            isHidden: values.isHidden ?? url.lastPathComponent.hasPrefix("."),
            size: isDirectory ? nil : values.fileSize.map(Int64.init),
            modifiedAt: values.contentModificationDate,
            kind: values.localizedTypeDescription ?? fallbackKind
        )
    }
}

struct DirectorySnapshot: Sendable {
    let directoryURL: URL
    let items: [FileItem]
    let loadedAt: Date
}
