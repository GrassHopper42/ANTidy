import AppKit
import Foundation

struct TrashDeletionEngine: Sendable {
    func moveToTrash(_ candidates: [CleanupCandidate]) async -> [DeletionResult] {
        let runningBundleIDs = await MainActor.run {
            Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
        }

        return await Task.detached(priority: .userInitiated) {
            var results: [DeletionResult] = []
            let fileManager = FileManager.default

            for candidate in candidates {
                if candidate.isProtected || FileSystemTools.isProtectedSystemPath(candidate.url) {
                    results.append(DeletionResult(
                        candidateID: candidate.id,
                        displayName: candidate.displayName,
                        status: .skipped("Protected system path")
                    ))
                    continue
                }

                if let bundleID = candidate.relatedBundleID?.lowercased(),
                   runningBundleIDs.contains(bundleID) {
                    results.append(DeletionResult(
                        candidateID: candidate.id,
                        displayName: candidate.displayName,
                        status: .skipped("Related app is running")
                    ))
                    continue
                }

                guard fileManager.fileExists(atPath: candidate.url.path) else {
                    results.append(DeletionResult(
                        candidateID: candidate.id,
                        displayName: candidate.displayName,
                        status: .skipped("File no longer exists")
                    ))
                    continue
                }

                do {
                    var resultingURL: NSURL?
                    try fileManager.trashItem(at: candidate.url, resultingItemURL: &resultingURL)
                    results.append(DeletionResult(
                        candidateID: candidate.id,
                        displayName: candidate.displayName,
                        status: .trashed(resultingURL as URL?)
                    ))
                } catch {
                    results.append(DeletionResult(
                        candidateID: candidate.id,
                        displayName: candidate.displayName,
                        status: .failed(error.localizedDescription)
                    ))
                }
            }

            return results
        }.value
    }
}
