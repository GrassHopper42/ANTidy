import Foundation

enum CandidateDeduplicator {
    static func deduplicate(_ candidates: [CleanupCandidate]) -> [CleanupCandidate] {
        let exactWinners = Dictionary(grouping: candidates, by: normalizedPath)
            .compactMap { path, candidates -> IndexedCandidate? in
                guard let candidate = candidates.max(by: { preferenceScore($0) < preferenceScore($1) }) else {
                    return nil
                }
                return IndexedCandidate(candidate: candidate, path: path)
            }

        var kept: [IndexedCandidate] = []
        for item in exactWinners.sorted(by: moreSpecificFirst) {
            let isCoveredByDescendant = kept.contains { descendant in
                isAncestor(item.path, of: descendant.path)
            }
            if !isCoveredByDescendant {
                kept.append(item)
            }
        }

        let keptIDs = Set(kept.map(\.candidate.id))
        return candidates.filter { keptIDs.contains($0.id) }
    }

    private static func normalizedPath(for candidate: CleanupCandidate) -> String {
        candidate.url.standardizedFileURL.path
    }

    private static func moreSpecificFirst(_ lhs: IndexedCandidate, _ rhs: IndexedCandidate) -> Bool {
        if lhs.depth != rhs.depth {
            return lhs.depth > rhs.depth
        }
        return preferenceScore(lhs.candidate) > preferenceScore(rhs.candidate)
    }

    private static func isAncestor(_ parent: String, of child: String) -> Bool {
        guard parent != child else { return false }
        if parent == "/" {
            return child != "/"
        }
        return child.hasPrefix(parent + "/")
    }

    private static func preferenceScore(_ candidate: CleanupCandidate) -> Int {
        riskScore(candidate.risk) * 1_000
            + categoryScore(candidate.category) * 10
            + (candidate.isRecommended ? 1 : 0)
    }

    private static func riskScore(_ risk: CleanupRisk) -> Int {
        switch risk {
        case .blocked: 4
        case .verifyFirst: 3
        case .probablySafe: 2
        case .safe: 1
        }
    }

    private static func categoryScore(_ category: CleanupCategory) -> Int {
        switch category {
        case .orphans: 6
        case .developer: 5
        case .duplicates: 4
        case .caches: 3
        case .system: 2
        case .largeFiles: 1
        }
    }

    private struct IndexedCandidate {
        let candidate: CleanupCandidate
        let path: String

        var depth: Int {
            path.split(separator: "/").count
        }
    }
}
