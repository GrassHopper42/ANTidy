import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(CleanupStore.self) private var store

    var body: some View {
        ZStack {
            AppBackground()
            HStack(spacing: 18) {
                SidebarView()
                    .frame(width: 260)

                DashboardView()
            }
            .padding(22)
        }
        .background(WindowConfigurator())
        .task {
            store.refreshFullDiskAccessStatus()
        }
    }
}

struct SidebarView: View {
    @Environment(CleanupStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "ant.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white, .teal)
                        .symbolRenderingMode(.palette)
                    Text("ANTidy")
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                }
                Text("Tiny workers for safe cleanup")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            VStack(spacing: 8) {
                SidebarButton(
                    title: "Overview",
                    subtitle: "\(store.candidates.count) items",
                    symbol: "square.grid.2x2.fill",
                    tint: .primary,
                    count: store.candidates.count,
                    bytes: store.totalReclaimableBytes,
                    isSelected: store.activeCategory == nil
                ) {
                    store.activeCategory = nil
                }

                ForEach(CleanupCategory.allCases) { category in
                    SidebarButton(
                        title: category.title,
                        subtitle: category.subtitle,
                        symbol: category.symbolName,
                        tint: category.accentColor,
                        count: store.count(for: category),
                        bytes: store.reclaimableBytes(for: category),
                        isSelected: store.activeCategory == category
                    ) {
                        store.activeCategory = category
                    }
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                Label(
                    store.fullDiskAccessGranted ? "Full Disk Access ready" : "Full Disk Access limited",
                    systemImage: store.fullDiskAccessGranted ? "checkmark.seal.fill" : "lock.shield.fill"
                )
                .foregroundStyle(store.fullDiskAccessGranted ? .green : .orange)
                .font(.callout.weight(.semibold))

                Button {
                    FullDiskAccessChecker.openSystemSettings()
                } label: {
                    Label("Privacy Settings", systemImage: "gear")
                }
                .liquidGlassButton()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassPanel(cornerRadius: 20, tint: .white.opacity(0.04))
        }
        .padding(18)
        .liquidGlassPanel(cornerRadius: 30, tint: .white.opacity(0.06), interactive: true)
    }
}

struct SidebarButton: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let count: Int
    let bytes: Int64
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(isSelected ? .white : tint)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(isSelected ? tint : tint.opacity(0.12))
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(count == 0 ? subtitle : bytes.formattedFileSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if count > 0 {
                    Text("\(count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(tint.opacity(0.15))
            }
        }
    }
}

struct DashboardView: View {
    @Environment(CleanupStore.self) private var store
    @State private var showTrashConfirmation = false

    var body: some View {
        HStack(spacing: 18) {
            VStack(spacing: 16) {
                HeaderView(showTrashConfirmation: $showTrashConfirmation)
                PermissionBanner()
                SummaryStrip()
                ScannerControlStrip()
                CandidateListView()
            }
            .frame(minWidth: 620)

            if store.focusedCandidate != nil {
                CandidateDetailView()
                    .frame(width: 330)
            }
        }
        .confirmationDialog(
            "Move selected items to Trash?",
            isPresented: $showTrashConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move \(store.selectedCandidates.count) Items to Trash", role: .destructive) {
                store.moveSelectedToTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Items are moved to the macOS Trash so they can be restored.")
        }
    }
}

struct HeaderView: View {
    @Environment(CleanupStore.self) private var store
    @Binding var showTrashConfirmation: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.activeCategory?.title ?? "Overview")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("\(store.filteredCandidates.count) candidates / \(store.totalReclaimableBytes.formattedFileSize) potential")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if store.isScanning {
                Button {
                    store.cancelScan()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .liquidGlassButton()
            }

            Button {
                store.runScan()
            } label: {
                Label(store.isScanning ? "Scanning" : "Scan", systemImage: "waveform.path.ecg.magnifyingglass")
            }
            .disabled(store.isScanning || store.isDeleting || store.enabledScannerIDs.isEmpty)
            .liquidGlassButton(prominent: true)

            Button {
                showTrashConfirmation = true
            } label: {
                Label("Trash", systemImage: "trash.fill")
            }
            .disabled(store.selectedCandidates.isEmpty || store.isScanning || store.isDeleting)
            .liquidGlassButton()
        }
        .padding(20)
        .liquidGlassPanel(cornerRadius: 28, tint: .white.opacity(0.08), interactive: true)
    }
}

struct PermissionBanner: View {
    @Environment(CleanupStore.self) private var store

    var body: some View {
        if !store.fullDiskAccessGranted {
            HStack(spacing: 14) {
                Image(systemName: "lock.shield")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Protected folders are limited")
                        .font(.headline)
                    Text("Grant Full Disk Access to scan Safari, Mail, Messages, and other TCC-protected Library data.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button {
                    FullDiskAccessChecker.openSystemSettings()
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                }
                .liquidGlassButton()
            }
            .padding(16)
            .liquidGlassPanel(cornerRadius: 22, tint: .orange.opacity(0.10))
        }
    }
}

struct SummaryStrip: View {
    @Environment(CleanupStore.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            SummaryTile(
                title: "Potential",
                value: store.totalReclaimableBytes.formattedFileSize,
                symbol: "internaldrive.fill",
                tint: .cyan
            )
            SummaryTile(
                title: "Selected",
                value: store.selectedReclaimableBytes.formattedFileSize,
                symbol: "checkmark.circle.fill",
                tint: .green
            )
            SummaryTile(
                title: "Candidates",
                value: "\(store.candidates.count)",
                symbol: "list.bullet.rectangle.fill",
                tint: .purple
            )
            SummaryTile(
                title: "Ready",
                value: "\(store.selectedCandidates.count)",
                symbol: "ant.circle.fill",
                tint: .orange
            )
        }
    }
}

struct SummaryTile: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .liquidGlassPanel(cornerRadius: 22, tint: tint.opacity(0.08), interactive: true)
    }
}

struct ScannerControlStrip: View {
    @Environment(CleanupStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Scanners")
                    .font(.headline)
                Spacer()
                Button("Recommended") {
                    store.selectRecommended()
                }
                .liquidGlassButton()
                Button("Visible") {
                    store.selectVisible()
                }
                .liquidGlassButton()
                Button("None") {
                    store.selectNone()
                }
                .liquidGlassButton()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.scanners, id: \.id) { scanner in
                        ScannerToggle(scanner: scanner)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .liquidGlassPanel(cornerRadius: 24, tint: .white.opacity(0.05), interactive: true)
    }
}

struct ScannerToggle: View {
    @Environment(CleanupStore.self) private var store
    let scanner: any CleanupScanner

    var body: some View {
        let isEnabled = store.enabledScannerIDs.contains(scanner.id)
        Button {
            store.toggleScanner(scanner.id, isEnabled: !isEnabled)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isEnabled ? scanner.category.accentColor : .secondary)
                Text(scanner.title)
                    .font(.callout.weight(.semibold))
                statusIcon
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isEnabled ? scanner.category.accentColor.opacity(0.12) : .white.opacity(0.06))
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch store.scannerStates[scanner.id]?.status {
        case .running:
            ProgressView()
                .controlSize(.small)
        case .finished:
            Text("\(store.scannerStates[scanner.id]?.foundCount ?? 0)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }
}

struct CandidateListView: View {
    @Environment(CleanupStore.self) private var store

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Review")
                    .font(.headline)
                Spacer()
                if store.isScanning {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scanning")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
            .padding(.horizontal, 4)

            if store.filteredCandidates.isEmpty {
                EmptyCandidatesView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.filteredCandidates) { candidate in
                            CandidateRow(candidate: candidate)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity)
        .liquidGlassPanel(cornerRadius: 28, tint: .white.opacity(0.05), interactive: true)
    }
}

struct EmptyCandidatesView: View {
    @Environment(CleanupStore.self) private var store

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: store.isScanning ? "magnifyingglass" : "sparkle.magnifyingglass")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(store.isScanning ? "Scanning selected areas" : "No candidates yet")
                .font(.title3.weight(.semibold))
            Text(store.isScanning ? "Results appear as scanners finish." : "Run a scan to inspect reclaimable local files.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct CandidateRow: View {
    @Environment(CleanupStore.self) private var store
    let candidate: CleanupCandidate

    private var isSelected: Bool {
        store.selectedCandidateIDs.contains(candidate.id)
    }

    private var isFocused: Bool {
        store.focusedCandidateID == candidate.id
    }

    var body: some View {
        HStack(spacing: 13) {
            Button {
                store.toggleSelection(for: candidate)
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? candidate.category.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(candidate.risk == .blocked || candidate.isProtected)

            Image(systemName: candidate.category.symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(candidate.category.accentColor)
                .frame(width: 34, height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(candidate.category.accentColor.opacity(0.12))
                }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(candidate.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    RiskPill(risk: candidate.risk)
                    if candidate.isAPFSCloneSuspect {
                        Image(systemName: "square.stack.3d.forward.dottedline")
                            .foregroundStyle(.orange)
                            .help("APFS reports possible shared content blocks.")
                    }
                }
                Text(candidate.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(candidate.byteCount.formattedFileSize)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                if candidate.estimatedReclaimableBytes != candidate.byteCount {
                    Text("\(candidate.estimatedReclaimableBytes.formattedFileSize) reclaim")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(13)
        .contentShape(Rectangle())
        .onTapGesture {
            store.focusedCandidateID = candidate.id
        }
        .liquidGlassPanel(
            cornerRadius: 18,
            tint: isFocused ? candidate.category.accentColor.opacity(0.16) : .white.opacity(0.03),
            interactive: true
        )
    }
}

struct RiskPill: View {
    let risk: CleanupRisk

    var body: some View {
        Text(risk.title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(risk.tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                Capsule()
                    .fill(risk.tint.opacity(0.12))
            }
    }
}

struct CandidateDetailView: View {
    @Environment(CleanupStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let candidate = store.focusedCandidate {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: candidate.category.symbolName)
                            .font(.title)
                            .foregroundStyle(candidate.category.accentColor)
                        Spacer()
                        RiskPill(risk: candidate.risk)
                    }

                    Text(candidate.displayName)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .lineLimit(2)

                    Text(candidate.reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Divider()

                DetailMetric(title: "Size", value: candidate.byteCount.formattedFileSize, symbol: "internaldrive")
                DetailMetric(title: "Reclaim", value: candidate.estimatedReclaimableBytes.formattedFileSize, symbol: "arrow.down.circle")
                DetailMetric(title: "Category", value: candidate.category.title, symbol: candidate.category.symbolName)
                if let modified = candidate.modifiedAt {
                    DetailMetric(title: "Modified", value: modified.compactDisplay, symbol: "calendar")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Evidence")
                        .font(.headline)
                    Text(candidate.evidence)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(candidate.url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(4)
                }

                if !store.deletionResults.isEmpty {
                    DeletionResultsView()
                }

                Spacer()

                HStack {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([candidate.url])
                    } label: {
                        Label("Reveal", systemImage: "finder")
                    }
                    .liquidGlassButton()

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(candidate.url.path, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .liquidGlassButton()
                }
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "sidebar.trailing")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Select an item")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(20)
        .liquidGlassPanel(cornerRadius: 30, tint: .white.opacity(0.06), interactive: true)
    }
}

struct DetailMetric: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.callout)
    }
}

struct DeletionResultsView: View {
    @Environment(CleanupStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trash Log")
                .font(.headline)
            ForEach(store.deletionResults.prefix(4)) { result in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: symbol(for: result.status))
                        .foregroundStyle(color(for: result.status))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.displayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(message(for: result.status))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(12)
        .liquidGlassPanel(cornerRadius: 16, tint: .white.opacity(0.04))
    }

    private func symbol(for status: DeletionStatus) -> String {
        switch status {
        case .trashed: "checkmark.circle.fill"
        case .skipped: "minus.circle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private func color(for status: DeletionStatus) -> Color {
        switch status {
        case .trashed: .green
        case .skipped: .orange
        case .failed: .red
        }
    }

    private func message(for status: DeletionStatus) -> String {
        switch status {
        case .trashed: "Moved to Trash"
        case .skipped(let reason): reason
        case .failed(let error): error
        }
    }
}
