import Foundation

enum FileSystemTools {
    static let metadataKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isRegularFileKey,
        .fileSizeKey,
        .fileAllocatedSizeKey,
        .totalFileAllocatedSizeKey,
        .contentModificationDateKey,
        .localizedNameKey,
        .mayShareFileContentKey
    ]

    static var homeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    static func homePath(_ relativePath: String) -> URL {
        homeDirectory.appending(path: relativePath)
    }

    static func pathExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func displayName(for url: URL) -> String {
        if let values = try? url.resourceValues(forKeys: [.localizedNameKey]),
           let localizedName = values.localizedName,
           !localizedName.isEmpty {
            return localizedName
        }
        return url.lastPathComponent
    }

    static func allocatedSize(of url: URL, maxItems: Int = 200_000) -> Int64 {
        guard pathExists(url) else { return 0 }

        if let direct = regularFileAllocatedSize(of: url) {
            return direct
        }

        var total: Int64 = 0
        var scannedItems = 0
        let keys = Array(metadataKeys)
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        )

        while let child = enumerator?.nextObject() as? URL {
            scannedItems += 1
            if scannedItems > maxItems {
                break
            }
            if let size = regularFileAllocatedSize(of: child) {
                total += size
            }
        }

        return total
    }

    static func regularFileAllocatedSize(of url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: metadataKeys),
              values.isRegularFile == true else {
            return nil
        }

        let allocated = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0
        return Int64(allocated)
    }

    static func logicalFileSize(of url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let size = values.fileSize else {
            return nil
        }
        return Int64(size)
    }

    static func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    static func mayShareFileContent(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.mayShareFileContentKey]))?.mayShareFileContent == true
    }

    static func children(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(metadataKeys),
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    static func isProtectedSystemPath(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if path == "/Applications" || path.hasPrefix("/Applications/") {
            return false
        }
        if path == "/Library" || path.hasPrefix("/Library/") {
            return false
        }
        if path == "/usr/local" || path.hasPrefix("/usr/local/") {
            return false
        }
        return path == "/System"
            || path.hasPrefix("/System/")
            || path == "/bin"
            || path.hasPrefix("/bin/")
            || path == "/sbin"
            || path.hasPrefix("/sbin/")
            || path == "/usr"
            || path.hasPrefix("/usr/")
    }

    static func isProbablyAppleOwned(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleID == "com.apple" || bundleID.hasPrefix("com.apple.")
    }
}

extension Int64 {
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension Date {
    var compactDisplay: String {
        formatted(date: .abbreviated, time: .omitted)
    }
}
