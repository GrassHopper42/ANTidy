import Foundation
import Observation

@MainActor
@Observable
final class CleanupStore {
    let scanners: [any CleanupScanner]
    var enabledScannerIDs: Set<String>
    var scannerStates: [String: ScannerRunState]
    var candidates: [CleanupCandidate] = []
    var selectedCandidateIDs = Set<CleanupCandidate.ID>()
    var focusedCandidateID: CleanupCandidate.ID?
    var activeCategory: CleanupCategory?
    var deletionResults: [DeletionResult] = []
    var isScanning = false
    var isDeleting = false
    var fullDiskAccessGranted = false

    @ObservationIgnored
    private var scanTask: Task<Void, Never>?
    private var activeScanID = UUID()

    init(scanners: [any CleanupScanner] = ScannerRegistry.defaultScanners) {
        self.scanners = scanners
        self.enabledScannerIDs = Set(scanners.filter(\.defaultEnabled).map(\.id))
        self.scannerStates = Dictionary(uniqueKeysWithValues: scanners.map {
            ($0.id, ScannerRunState(id: $0.id))
        })
        self.fullDiskAccessGranted = FullDiskAccessChecker.isLikelyGranted()
    }

    var filteredCandidates: [CleanupCandidate] {
        let filtered = activeCategory.map { category in
            candidates.filter { $0.category == category }
        } ?? candidates

        return filtered.sorted {
            if $0.isRecommended != $1.isRecommended {
                return $0.isRecommended && !$1.isRecommended
            }
            return $0.estimatedReclaimableBytes > $1.estimatedReclaimableBytes
        }
    }

    var selectedCandidates: [CleanupCandidate] {
        candidates.filter { selectedCandidateIDs.contains($0.id) }
    }

    var selectedReclaimableBytes: Int64 {
        selectedCandidates.totalReclaimableBytes
    }

    var totalReclaimableBytes: Int64 {
        candidates.totalReclaimableBytes
    }

    var focusedCandidate: CleanupCandidate? {
        if let focusedCandidateID,
           let candidate = candidates.first(where: { $0.id == focusedCandidateID }) {
            return candidate
        }
        return filteredCandidates.first
    }

    func refreshFullDiskAccessStatus() {
        fullDiskAccessGranted = FullDiskAccessChecker.isLikelyGranted()
    }

    func runScan() {
        scanTask?.cancel()
        let scanID = UUID()
        activeScanID = scanID
        deletionResults = []
        candidates = []
        selectedCandidateIDs = []
        focusedCandidateID = nil
        scannerStates = Dictionary(uniqueKeysWithValues: scanners.map {
            ($0.id, ScannerRunState(id: $0.id))
        })
        isScanning = true

        let enabledScanners = scanners.filter { enabledScannerIDs.contains($0.id) }

        scanTask = Task { [enabledScanners, scanID] in
            var aggregate: [CleanupCandidate] = []

            for scanner in enabledScanners {
                guard activeScanID == scanID else { return }
                if Task.isCancelled {
                    updateScanner(scanner.id) { state in
                        state.status = .cancelled
                        state.message = "Cancelled"
                        state.finishedAt = Date()
                    }
                    break
                }

                updateScanner(scanner.id) { state in
                    state.status = .running
                    state.message = "Scanning"
                    state.startedAt = Date()
                }

                do {
                    let found = try await scanner.scan()
                    try Task.checkCancellation()
                    guard activeScanID == scanID else { return }

                    aggregate.append(contentsOf: found)
                    let deduplicated = CandidateDeduplicator.deduplicate(aggregate)
                    candidates = deduplicated
                    let visibleIDs = Set(deduplicated.map(\.id))
                    selectedCandidateIDs.formUnion(deduplicated.filter(\.isRecommended).map(\.id))
                    selectedCandidateIDs.formIntersection(visibleIDs)
                    if focusedCandidateID == nil {
                        focusedCandidateID = filteredCandidates.first?.id
                    }

                    updateScanner(scanner.id) { state in
                        state.status = .finished
                        state.foundCount = found.count
                        state.message = "\(found.count) items"
                        state.finishedAt = Date()
                    }
                } catch is CancellationError {
                    guard activeScanID == scanID else { return }
                    updateScanner(scanner.id) { state in
                        state.status = .cancelled
                        state.message = "Cancelled"
                        state.finishedAt = Date()
                    }
                    break
                } catch {
                    guard activeScanID == scanID else { return }
                    updateScanner(scanner.id) { state in
                        state.status = .failed
                        state.message = error.localizedDescription
                        state.finishedAt = Date()
                    }
                }
            }

            guard activeScanID == scanID else { return }
            isScanning = false
            refreshFullDiskAccessStatus()
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        activeScanID = UUID()
        isScanning = false
        for id in scannerStates.keys {
            if scannerStates[id]?.status == .running {
                updateScanner(id) { state in
                    state.status = .cancelled
                    state.message = "Cancelled"
                    state.finishedAt = Date()
                }
            }
        }
    }

    func toggleScanner(_ scannerID: String, isEnabled: Bool) {
        if isEnabled {
            enabledScannerIDs.insert(scannerID)
        } else {
            enabledScannerIDs.remove(scannerID)
        }
    }

    func toggleSelection(for candidate: CleanupCandidate) {
        if selectedCandidateIDs.contains(candidate.id) {
            selectedCandidateIDs.remove(candidate.id)
        } else if candidate.risk != .blocked && !candidate.isProtected {
            selectedCandidateIDs.insert(candidate.id)
        }
    }

    func selectRecommended() {
        selectedCandidateIDs = Set(candidates.filter(\.isRecommended).map(\.id))
    }

    func selectVisible() {
        let selectable = filteredCandidates.filter { $0.risk != .blocked && !$0.isProtected }
        selectedCandidateIDs.formUnion(selectable.map(\.id))
    }

    func selectNone() {
        selectedCandidateIDs.removeAll()
    }

    func moveSelectedToTrash() {
        guard !selectedCandidates.isEmpty else { return }
        let targets = selectedCandidates
        isDeleting = true
        deletionResults = []

        Task {
            let results = await TrashDeletionEngine().moveToTrash(targets)
            deletionResults = results
            let trashedIDs = Set(results.compactMap { result -> CleanupCandidate.ID? in
                if case .trashed = result.status {
                    return result.candidateID
                }
                return nil
            })
            candidates.removeAll { trashedIDs.contains($0.id) }
            selectedCandidateIDs.subtract(trashedIDs)
            if let focusedCandidateID, trashedIDs.contains(focusedCandidateID) {
                self.focusedCandidateID = filteredCandidates.first?.id
            }
            isDeleting = false
            refreshFullDiskAccessStatus()
        }
    }

    func count(for category: CleanupCategory) -> Int {
        candidates.filter { $0.category == category }.count
    }

    func reclaimableBytes(for category: CleanupCategory) -> Int64 {
        candidates.filter { $0.category == category }.totalReclaimableBytes
    }

    private func updateScanner(_ id: String, mutate: (inout ScannerRunState) -> Void) {
        var state = scannerStates[id] ?? ScannerRunState(id: id)
        mutate(&state)
        scannerStates[id] = state
    }
}
