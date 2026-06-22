import Foundation

enum CleanupCategory: String, CaseIterable, Identifiable, Sendable {
    case developer
    case caches
    case system
    case largeFiles
    case orphans
    case duplicates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .developer: "Developer"
        case .caches: "Caches"
        case .system: "System"
        case .largeFiles: "Large Files"
        case .orphans: "Orphans"
        case .duplicates: "Duplicates"
        }
    }

    var subtitle: String {
        switch self {
        case .developer: "Xcode, simulators, package caches"
        case .caches: "Regenerated app data"
        case .system: "Logs, reports, device backups"
        case .largeFiles: "Big user-owned files"
        case .orphans: "Data from removed apps"
        case .duplicates: "Byte-identical files"
        }
    }

    var symbolName: String {
        switch self {
        case .developer: "hammer.fill"
        case .caches: "externaldrive.badge.timemachine"
        case .system: "gearshape.2.fill"
        case .largeFiles: "tray.full.fill"
        case .orphans: "app.badge.checkmark"
        case .duplicates: "doc.on.doc.fill"
        }
    }
}

enum CleanupRisk: String, CaseIterable, Identifiable, Sendable {
    case safe
    case probablySafe
    case verifyFirst
    case blocked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .safe: "Safe"
        case .probablySafe: "Review"
        case .verifyFirst: "Verify"
        case .blocked: "Blocked"
        }
    }

    var defaultSelected: Bool {
        switch self {
        case .safe: true
        case .probablySafe, .verifyFirst, .blocked: false
        }
    }
}

struct CleanupCandidate: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let displayName: String
    let category: CleanupCategory
    let risk: CleanupRisk
    let byteCount: Int64
    let estimatedReclaimableBytes: Int64
    let reason: String
    let evidence: String
    let scannerID: String
    let modifiedAt: Date?
    let relatedBundleID: String?
    let duplicateGroupID: String?
    let isAPFSCloneSuspect: Bool
    let isProtected: Bool
    let isRecommended: Bool

    init(
        id: UUID = UUID(),
        url: URL,
        displayName: String,
        category: CleanupCategory,
        risk: CleanupRisk,
        byteCount: Int64,
        estimatedReclaimableBytes: Int64? = nil,
        reason: String,
        evidence: String,
        scannerID: String,
        modifiedAt: Date? = nil,
        relatedBundleID: String? = nil,
        duplicateGroupID: String? = nil,
        isAPFSCloneSuspect: Bool = false,
        isProtected: Bool = false,
        isRecommended: Bool? = nil
    ) {
        self.id = id
        self.url = url
        self.displayName = displayName
        self.category = category
        self.risk = risk
        self.byteCount = byteCount
        self.estimatedReclaimableBytes = estimatedReclaimableBytes ?? byteCount
        self.reason = reason
        self.evidence = evidence
        self.scannerID = scannerID
        self.modifiedAt = modifiedAt
        self.relatedBundleID = relatedBundleID
        self.duplicateGroupID = duplicateGroupID
        self.isAPFSCloneSuspect = isAPFSCloneSuspect
        self.isProtected = isProtected
        self.isRecommended = isRecommended ?? (risk.defaultSelected && !isProtected)
    }
}

enum ScannerStatus: Equatable, Sendable {
    case pending
    case running
    case finished
    case failed
    case cancelled
}

struct ScannerRunState: Identifiable, Equatable, Sendable {
    let id: String
    var status: ScannerStatus
    var foundCount: Int
    var message: String
    var startedAt: Date?
    var finishedAt: Date?

    init(id: String, status: ScannerStatus = .pending, foundCount: Int = 0, message: String = "") {
        self.id = id
        self.status = status
        self.foundCount = foundCount
        self.message = message
    }
}

enum DeletionStatus: Equatable, Sendable {
    case trashed(URL?)
    case skipped(String)
    case failed(String)
}

struct DeletionResult: Identifiable, Equatable, Sendable {
    let id = UUID()
    let candidateID: CleanupCandidate.ID
    let displayName: String
    let status: DeletionStatus
}

extension Sequence where Element == CleanupCandidate {
    var totalByteCount: Int64 {
        reduce(0) { $0 + $1.byteCount }
    }

    var totalReclaimableBytes: Int64 {
        reduce(0) { $0 + $1.estimatedReclaimableBytes }
    }
}
