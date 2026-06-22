import CryptoKit
import Foundation

protocol CleanupScanner: Sendable {
    var id: String { get }
    var title: String { get }
    var category: CleanupCategory { get }
    var defaultEnabled: Bool { get }

    func scan() async throws -> [CleanupCandidate]
}

extension CleanupScanner {
    var defaultEnabled: Bool { true }
}

enum ScannerRegistry {
    static let defaultScanners: [any CleanupScanner] = [
        DeveloperJunkScanner(),
        CacheScanner(),
        SystemJunkScanner(),
        LargeFileScanner(),
        OrphanedAppDataScanner(),
        DuplicateScanner()
    ]
}

private struct KnownPathSpec: Sendable {
    let url: URL
    let displayName: String
    let category: CleanupCategory
    let risk: CleanupRisk
    let reason: String
    let evidence: String
    let scannerID: String
    let relatedBundleID: String?
    let splitChildren: Bool
    let recommended: Bool?
}

struct DeveloperJunkScanner: CleanupScanner {
    let id = "developer-junk"
    let title = "Developer Junk"
    let category = CleanupCategory.developer

    func scan() async throws -> [CleanupCandidate] {
        var candidates: [CleanupCandidate] = []
        let specs = [
            KnownPathSpec(
                url: FileSystemTools.homePath("Library/Developer/Xcode/DerivedData"),
                displayName: "Xcode DerivedData",
                category: .developer,
                risk: .safe,
                reason: "Build products and indexes that Xcode recreates.",
                evidence: "DerivedData is generated per project.",
                scannerID: id,
                relatedBundleID: "com.apple.dt.Xcode",
                splitChildren: true,
                recommended: true
            ),
            KnownPathSpec(
                url: FileSystemTools.homePath("Library/Developer/CoreSimulator/Caches"),
                displayName: "CoreSimulator caches",
                category: .developer,
                risk: .safe,
                reason: "Simulator cache data that can be regenerated.",
                evidence: "Located under CoreSimulator/Caches.",
                scannerID: id,
                relatedBundleID: "com.apple.CoreSimulator.CoreSimulatorService",
                splitChildren: false,
                recommended: true
            ),
            KnownPathSpec(
                url: FileSystemTools.homePath("Library/Caches/org.swift.swiftpm"),
                displayName: "SwiftPM cache",
                category: .developer,
                risk: .safe,
                reason: "Swift Package Manager cache data.",
                evidence: "Packages can be downloaded again.",
                scannerID: id,
                relatedBundleID: nil,
                splitChildren: false,
                recommended: true
            ),
            KnownPathSpec(
                url: FileSystemTools.homePath("Library/Caches/CocoaPods"),
                displayName: "CocoaPods cache",
                category: .developer,
                risk: .safe,
                reason: "Downloaded pod cache data.",
                evidence: "Pods can be fetched again.",
                scannerID: id,
                relatedBundleID: nil,
                splitChildren: false,
                recommended: true
            ),
            KnownPathSpec(
                url: FileSystemTools.homePath(".npm"),
                displayName: "npm cache",
                category: .developer,
                risk: .safe,
                reason: "Package manager cache data.",
                evidence: "npm can repopulate this cache.",
                scannerID: id,
                relatedBundleID: nil,
                splitChildren: false,
                recommended: true
            ),
            KnownPathSpec(
                url: FileSystemTools.homePath(".gradle/caches"),
                displayName: "Gradle caches",
                category: .developer,
                risk: .safe,
                reason: "Gradle dependency and build caches.",
                evidence: "Gradle can resolve dependencies again.",
                scannerID: id,
                relatedBundleID: nil,
                splitChildren: false,
                recommended: true
            )
        ]

        for spec in specs {
            candidates.append(contentsOf: candidatesForKnownPath(spec))
        }

        candidates.append(contentsOf: oldXcodeArchives())
        return candidates.filter { $0.byteCount > 0 }
            .sorted { $0.estimatedReclaimableBytes > $1.estimatedReclaimableBytes }
    }

    private func oldXcodeArchives() -> [CleanupCandidate] {
        let root = FileSystemTools.homePath("Library/Developer/Xcode/Archives")
        guard FileSystemTools.pathExists(root) else { return [] }

        let cutoff = Calendar.current.date(byAdding: .day, value: -180, to: Date()) ?? Date.distantPast
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(FileSystemTools.metadataKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        )

        var results: [CleanupCandidate] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "xcarchive" else { continue }
            let modified = FileSystemTools.modificationDate(of: url)
            guard let modified, modified < cutoff else { continue }
            let size = FileSystemTools.allocatedSize(of: url)
            results.append(CleanupCandidate(
                url: url,
                displayName: url.deletingPathExtension().lastPathComponent,
                category: .developer,
                risk: .probablySafe,
                byteCount: size,
                reason: "Old Xcode archive older than 180 days.",
                evidence: "Archives are distribution artifacts; keep builds you may need for symbolication.",
                scannerID: id,
                modifiedAt: modified,
                relatedBundleID: "com.apple.dt.Xcode",
                isRecommended: false
            ))
        }
        return results
    }
}

struct CacheScanner: CleanupScanner {
    let id = "cache-files"
    let title = "App Caches"
    let category = CleanupCategory.caches

    func scan() async throws -> [CleanupCandidate] {
        let root = FileSystemTools.homePath("Library/Caches")
        guard FileSystemTools.pathExists(root) else { return [] }

        var candidates: [CleanupCandidate] = []
        for child in FileSystemTools.children(of: root) {
            let name = child.lastPathComponent
            let bundleID = BundleIDHeuristics.bundleID(fromCacheName: name)
            let isApple = FileSystemTools.isProbablyAppleOwned(bundleID)
            let size = FileSystemTools.allocatedSize(of: child)
            guard size > 0 else { continue }

            candidates.append(CleanupCandidate(
                url: child,
                displayName: FileSystemTools.displayName(for: child),
                category: .caches,
                risk: isApple ? .verifyFirst : .safe,
                byteCount: size,
                reason: isApple ? "Apple-owned cache. Review before removing." : "Application cache that can usually be regenerated.",
                evidence: "Top-level item in ~/Library/Caches.",
                scannerID: id,
                modifiedAt: FileSystemTools.modificationDate(of: child),
                relatedBundleID: bundleID,
                isRecommended: !isApple
            ))
        }

        return candidates.sorted { $0.estimatedReclaimableBytes > $1.estimatedReclaimableBytes }
            .prefix(250)
            .map { $0 }
    }
}

struct SystemJunkScanner: CleanupScanner {
    let id = "system-junk"
    let title = "Logs & Reports"
    let category = CleanupCategory.system

    func scan() async throws -> [CleanupCandidate] {
        var candidates: [CleanupCandidate] = []

        let logSpecs = [
            KnownPathSpec(
                url: FileSystemTools.homePath("Library/Logs"),
                displayName: "User logs",
                category: .system,
                risk: .safe,
                reason: "User log files and diagnostic output.",
                evidence: "Located under ~/Library/Logs.",
                scannerID: id,
                relatedBundleID: nil,
                splitChildren: true,
                recommended: true
            ),
            KnownPathSpec(
                url: FileSystemTools.homePath("Library/Logs/DiagnosticReports"),
                displayName: "Diagnostic reports",
                category: .system,
                risk: .safe,
                reason: "Crash and diagnostic reports.",
                evidence: "Reports are useful for debugging, but not required for normal app use.",
                scannerID: id,
                relatedBundleID: nil,
                splitChildren: true,
                recommended: true
            )
        ]

        for spec in logSpecs {
            candidates.append(contentsOf: candidatesForKnownPath(spec))
        }

        let backups = FileSystemTools.homePath("Library/Application Support/MobileSync/Backup")
        if FileSystemTools.pathExists(backups) {
            for child in FileSystemTools.children(of: backups) {
                let size = FileSystemTools.allocatedSize(of: child)
                guard size > 0 else { continue }
                candidates.append(CleanupCandidate(
                    url: child,
                    displayName: "iOS backup \(child.lastPathComponent)",
                    category: .system,
                    risk: .verifyFirst,
                    byteCount: size,
                    reason: "Local iPhone or iPad backup.",
                    evidence: "Removing a backup can remove your ability to restore that device snapshot.",
                    scannerID: id,
                    modifiedAt: FileSystemTools.modificationDate(of: child),
                    isRecommended: false
                ))
            }
        }

        return candidates.filter { $0.byteCount > 0 }
            .sorted { $0.estimatedReclaimableBytes > $1.estimatedReclaimableBytes }
    }
}

struct LargeFileScanner: CleanupScanner {
    let id = "large-files"
    let title = "Large Files"
    let category = CleanupCategory.largeFiles

    private let threshold: Int64 = 500 * 1_024 * 1_024

    func scan() async throws -> [CleanupCandidate] {
        let roots = [
            FileSystemTools.homePath("Downloads"),
            FileSystemTools.homePath("Desktop"),
            FileSystemTools.homePath("Documents"),
            FileSystemTools.homePath("Movies")
        ].filter(FileSystemTools.pathExists)

        var candidates: [CleanupCandidate] = []
        let keys = Array(FileSystemTools.metadataKeys)

        for root in roots {
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            )

            var scanned = 0
            while let url = enumerator?.nextObject() as? URL {
                scanned += 1
                if scanned > 20_000 {
                    break
                }
                guard let size = FileSystemTools.regularFileAllocatedSize(of: url), size >= threshold else {
                    continue
                }

                candidates.append(CleanupCandidate(
                    url: url,
                    displayName: FileSystemTools.displayName(for: url),
                    category: .largeFiles,
                    risk: .verifyFirst,
                    byteCount: size,
                    reason: "Large file in a user-owned folder.",
                    evidence: "ANTidy never auto-selects personal files.",
                    scannerID: id,
                    modifiedAt: FileSystemTools.modificationDate(of: url),
                    isRecommended: false
                ))
            }
        }

        return candidates.sorted { $0.estimatedReclaimableBytes > $1.estimatedReclaimableBytes }
            .prefix(300)
            .map { $0 }
    }
}

struct OrphanedAppDataScanner: CleanupScanner {
    let id = "orphaned-app-data"
    let title = "Orphaned Data"
    let category = CleanupCategory.orphans

    func scan() async throws -> [CleanupCandidate] {
        let installedBundleIDs = InstalledApplicationIndex.bundleIDs()
        let roots: [(URL, String)] = [
            (FileSystemTools.homePath("Library/Containers"), "Sandbox container"),
            (FileSystemTools.homePath("Library/Group Containers"), "Group container"),
            (FileSystemTools.homePath("Library/Caches"), "Cache folder"),
            (FileSystemTools.homePath("Library/Preferences"), "Preference file"),
            (FileSystemTools.homePath("Library/Saved Application State"), "Saved application state"),
            (FileSystemTools.homePath("Library/HTTPStorages"), "HTTP storage"),
            (FileSystemTools.homePath("Library/WebKit"), "WebKit data"),
            (FileSystemTools.homePath("Library/Cookies"), "Cookie store")
        ]

        var seenPaths = Set<String>()
        var candidates: [CleanupCandidate] = []

        for (root, evidence) in roots where FileSystemTools.pathExists(root) {
            for child in FileSystemTools.children(of: root) {
                guard seenPaths.insert(child.path).inserted else { continue }
                guard let bundleID = BundleIDHeuristics.bundleID(fromLibraryItemName: child.lastPathComponent) else {
                    continue
                }
                guard !FileSystemTools.isProbablyAppleOwned(bundleID),
                      !installedBundleIDs.contains(bundleID.lowercased()) else {
                    continue
                }

                let size = FileSystemTools.allocatedSize(of: child)
                guard size > 0 || child.pathExtension == "plist" else { continue }

                candidates.append(CleanupCandidate(
                    url: child,
                    displayName: FileSystemTools.displayName(for: child),
                    category: .orphans,
                    risk: .verifyFirst,
                    byteCount: size,
                    reason: "No installed app with bundle identifier \(bundleID) was found.",
                    evidence: evidence,
                    scannerID: id,
                    modifiedAt: FileSystemTools.modificationDate(of: child),
                    relatedBundleID: bundleID,
                    isRecommended: false
                ))
            }
        }

        return candidates.sorted { $0.estimatedReclaimableBytes > $1.estimatedReclaimableBytes }
            .prefix(250)
            .map { $0 }
    }
}

struct DuplicateScanner: CleanupScanner {
    let id = "duplicates"
    let title = "Duplicates"
    let category = CleanupCategory.duplicates
    let defaultEnabled = false

    private let minimumSize: Int64 = 64 * 1_024

    func scan() async throws -> [CleanupCandidate] {
        let roots = [
            FileSystemTools.homePath("Downloads"),
            FileSystemTools.homePath("Desktop"),
            FileSystemTools.homePath("Documents"),
            FileSystemTools.homePath("Pictures")
        ].filter(FileSystemTools.pathExists)

        let files = collectCandidateFiles(roots: roots)
        let bySize = Dictionary(grouping: files, by: \.size)
            .filter { $0.value.count > 1 }

        var bySample: [String: [FileRecord]] = [:]
        for group in bySize.values {
            for record in group {
                guard let fingerprint = try? partialSHA256(of: record.url, size: record.size) else { continue }
                bySample[fingerprint, default: []].append(record)
            }
        }

        var byFullHash: [String: [FileRecord]] = [:]
        for group in bySample.values where group.count > 1 {
            for record in group {
                guard let digest = try? fullSHA256(of: record.url) else { continue }
                byFullHash[digest, default: []].append(record)
            }
        }

        var candidates: [CleanupCandidate] = []
        for (digest, group) in byFullHash where group.count > 1 {
            let sortedGroup = group.sorted { lhs, rhs in
                if lhs.url.pathComponents.count == rhs.url.pathComponents.count {
                    return lhs.url.path < rhs.url.path
                }
                return lhs.url.pathComponents.count < rhs.url.pathComponents.count
            }
            guard let keeper = sortedGroup.first else { continue }
            let groupID = String(digest.prefix(16))

            for duplicate in sortedGroup.dropFirst() {
                let cloneSuspect = FileSystemTools.mayShareFileContent(duplicate.url)
                    && FileSystemTools.mayShareFileContent(keeper.url)
                let reclaimable = cloneSuspect ? Int64(0) : duplicate.size
                candidates.append(CleanupCandidate(
                    url: duplicate.url,
                    displayName: FileSystemTools.displayName(for: duplicate.url),
                    category: .duplicates,
                    risk: cloneSuspect ? .verifyFirst : .probablySafe,
                    byteCount: duplicate.size,
                    estimatedReclaimableBytes: reclaimable,
                    reason: "Byte-identical to \(keeper.url.lastPathComponent).",
                    evidence: cloneSuspect
                        ? "Same SHA-256. APFS reports possible shared blocks, so reclaim estimate is conservative."
                        : "Same size, partial hash, and full SHA-256.",
                    scannerID: id,
                    modifiedAt: duplicate.modifiedAt,
                    duplicateGroupID: groupID,
                    isAPFSCloneSuspect: cloneSuspect,
                    isRecommended: false
                ))
            }
        }

        return candidates.sorted { $0.byteCount > $1.byteCount }
            .prefix(300)
            .map { $0 }
    }

    private func collectCandidateFiles(roots: [URL]) -> [FileRecord] {
        var records: [FileRecord] = []
        let keys = Array(FileSystemTools.metadataKeys)

        for root in roots {
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            )

            var scanned = 0
            while let url = enumerator?.nextObject() as? URL {
                scanned += 1
                if scanned > 15_000 || records.count > 6_000 {
                    break
                }
                guard let size = FileSystemTools.logicalFileSize(of: url), size >= minimumSize else {
                    continue
                }
                records.append(FileRecord(url: url, size: size, modifiedAt: FileSystemTools.modificationDate(of: url)))
            }
        }

        return records
    }

    private func partialSHA256(of url: URL, size: Int64) throws -> String {
        let sampleSize = 64 * 1_024
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let middle = max(0, size / 2 - Int64(sampleSize / 2))
        let end = max(0, size - Int64(sampleSize))
        let offsets = [Int64(0), middle, end]

        var sample = Data()
        for offset in offsets {
            try handle.seek(toOffset: UInt64(offset))
            sample.append(handle.readData(ofLength: sampleSize))
        }

        return sha256Hex(sample)
    }

    private func fullSHA256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 4 * 1_024 * 1_024)
            if chunk.isEmpty {
                break
            }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct FileRecord: Sendable {
    let url: URL
    let size: Int64
    let modifiedAt: Date?
}

private func candidatesForKnownPath(_ spec: KnownPathSpec) -> [CleanupCandidate] {
    guard FileSystemTools.pathExists(spec.url) else { return [] }
    let targets = spec.splitChildren ? FileSystemTools.children(of: spec.url) : [spec.url]

    return targets.compactMap { url in
        let size = FileSystemTools.allocatedSize(of: url)
        guard size > 0 else { return nil }
        let protected = FileSystemTools.isProtectedSystemPath(url)
        return CleanupCandidate(
            url: url,
            displayName: spec.splitChildren ? FileSystemTools.displayName(for: url) : spec.displayName,
            category: spec.category,
            risk: protected ? .blocked : spec.risk,
            byteCount: size,
            reason: spec.reason,
            evidence: spec.evidence,
            scannerID: spec.scannerID,
            modifiedAt: FileSystemTools.modificationDate(of: url),
            relatedBundleID: spec.relatedBundleID,
            isProtected: protected,
            isRecommended: spec.recommended
        )
    }
}

private enum InstalledApplicationIndex {
    static func bundleIDs() -> Set<String> {
        let roots = [
            URL(filePath: "/Applications"),
            URL(filePath: "/System/Applications"),
            FileSystemTools.homePath("Applications")
        ].filter(FileSystemTools.pathExists)

        var ids = Set<String>()
        for root in roots {
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            )

            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "app",
                      let bundle = Bundle(url: url),
                      let id = bundle.bundleIdentifier else {
                    continue
                }
                ids.insert(id.lowercased())
            }
        }
        return ids
    }
}

private enum BundleIDHeuristics {
    static func bundleID(fromCacheName name: String) -> String? {
        bundleID(fromLibraryItemName: name)
    }

    static func bundleID(fromLibraryItemName name: String) -> String? {
        var candidate = name
        let suffixes = [".plist", ".lockfile", ".savedState", ".binarycookies"]
        for suffix in suffixes where candidate.hasSuffix(suffix) {
            candidate.removeLast(suffix.count)
        }
        if candidate.hasPrefix("group.") {
            candidate.removeFirst("group.".count)
        }

        let parts = candidate.split(separator: ".").map(String.init)
        guard parts.count >= 3,
              parts.allSatisfy({ !$0.isEmpty && $0.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil }) else {
            return nil
        }
        return parts.joined(separator: ".").lowercased()
    }
}
