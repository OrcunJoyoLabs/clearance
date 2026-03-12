import AppKit
import SwiftUI

struct RecentFilesSidebar: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let entries: [RecentFileEntry]
    @Binding var selectedPath: String?
    @Binding var sidebarGrouping: SidebarGrouping
    let watchedFolders: [WatchedFolderEntry]
    let scannedFiles: [String: [ScannedFile]]
    let onOpenFile: () -> Void
    let onDropURL: (URL) -> Bool
    let onSelect: (SidebarItem) -> Void
    let onOpenInNewWindow: (SidebarItem) -> Void
    let onRemoveFromSidebar: (SidebarItem) -> Void
    let onRefreshWatchedFolder: (String) -> Void
    let onRemoveWatchedFolder: (String) -> Void

    @State private var expandedSections: [String: Bool] = [:]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("History")
                    .font(.headline)

                Spacer()

                Button(action: onOpenFile) {
                    Label("Open…", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                Spacer()
                Picker("", selection: $sidebarGrouping) {
                    ForEach(SidebarGrouping.allCases) { grouping in
                        Image(systemName: grouping.symbolName)
                            .tag(grouping)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 72)
                .controlSize(.small)
                .help("Sidebar grouping")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            List(selection: $selectedPath) {
                ForEach(groupedEntries) { section in
                    Section(isExpanded: sectionBinding(for: section.id)) {
                        ForEach(section.entries) { item in
                            row(for: item, showDirectory: sidebarGrouping != .byFolder)
                        }
                    } header: {
                        sectionHeader(for: section)
                    }
                }
            }
            .contextMenu(forSelectionType: String.self) { selectedPaths in
                if let path = selectedPaths.first,
                   let item = findItem(byPath: path) {
                    contextMenuActions(for: item)
                }
            }
            .onChange(of: selectedPath) { _, newPath in
                guard let newPath,
                      let item = findItem(byPath: newPath) else {
                    return
                }
                onSelect(item)
            }
            .listStyle(.sidebar)
            .padding(.top, 4)
            .animation(
                accessibilityReduceMotion ? nil : .snappy(duration: 0.26),
                value: groupedEntries.flatMap { $0.entries.map { "\($0.path)|\($0.sortDate.timeIntervalSinceReferenceDate)" } }
            )
        }
        .dropDestination(for: URL.self) { items, _ in
            guard let url = items.first else {
                return false
            }

            return onDropURL(url)
        }
    }

    private func findItem(byPath path: String) -> SidebarItem? {
        for section in groupedEntries {
            if let item = section.entries.first(where: { $0.path == path }) {
                return item
            }
        }
        return nil
    }

    private func sectionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandedSections[id] ?? true },
            set: { newValue in
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    expandedSections[id] = newValue
                }
            }
        )
    }

    @ViewBuilder
    private func sectionHeader(for section: RecentFilesSection) -> some View {
        HStack {
            if let subtitle = section.subtitle {
                VStack(alignment: .leading, spacing: 1) {
                    Text(section.title)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Text(section.title)
            }

            if section.isWatchedFolder {
                Spacer()
                Button {
                    onRefreshWatchedFolder(section.id)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Refresh")
            }
        }
        .contextMenu {
            if section.isWatchedFolder {
                Button("Stop Watching Folder") {
                    onRemoveWatchedFolder(section.id)
                }
            }
        }
    }

    private var groupedEntries: [RecentFilesSection] {
        switch sidebarGrouping {
        case .byDate:
            return entriesGroupedByDate
        case .byFolder:
            return entriesGroupedByFolder
        }
    }

    private var entriesGroupedByDate: [RecentFilesSection] {
        var buckets: [RecentFileBucket: [RecentFileEntry]] = [:]
        for entry in entries {
            buckets[RecentFileBucket.bucket(for: entry.lastOpenedAt), default: []].append(entry)
        }

        return RecentFileBucket.allCases.compactMap { bucket in
            guard let sectionEntries = buckets[bucket], !sectionEntries.isEmpty else {
                return nil
            }

            return RecentFilesSection(
                bucket: bucket,
                entries: sectionEntries
            )
        }
    }

    private static let otherKey = "_other"

    private var entriesGroupedByFolder: [RecentFilesSection] {
        let watchedPaths = Set(watchedFolders.map(\.path))
        var claimedPaths: Set<String> = []
        var sections: [RecentFilesSection] = []

        // 1. Build watched folder sections
        for folder in watchedFolders {
            var items: [SidebarItem] = []
            var seenPaths: Set<String> = []

            // Add manually-opened files under this watched folder (only if file still exists)
            for entry in entries where entry.fileURL.isFileURL {
                if entry.path.hasPrefix(folder.path + "/") {
                    claimedPaths.insert(entry.path)
                    if FileManager.default.fileExists(atPath: entry.path) {
                        items.append(.recentEntry(entry))
                        seenPaths.insert(entry.path)
                    }
                }
            }

            // Add scanned files not already covered by recent entries
            if let scanned = scannedFiles[folder.path] {
                for file in scanned {
                    let filePath = file.url.standardizedFileURL.path
                    if !seenPaths.contains(filePath) {
                        items.append(.scannedFile(url: file.url, modificationDate: file.modificationDate))
                        seenPaths.insert(filePath)
                    }
                }
            }

            items.sort { $0.sortDate > $1.sortDate }

            let components = folder.path.split(separator: "/")
            let displayName = components.last.map(String.init) ?? folder.path

            sections.append(RecentFilesSection(
                id: folder.path,
                title: displayName,
                subtitle: folder.path,
                entries: items,
                isWatchedFolder: true
            ))
        }

        // 2. Group remaining entries by project root (existing logic)
        var folderOrder: [String] = []
        var folderEntries: [String: [SidebarItem]] = [:]

        for entry in entries {
            guard !claimedPaths.contains(entry.path) else { continue }

            let key: String
            if entry.fileURL.isFileURL, let projectRoot = ProjectRootResolver.projectRoot(for: entry.path) {
                if watchedPaths.contains(projectRoot) { continue }
                key = projectRoot
            } else {
                key = Self.otherKey
            }

            if folderEntries[key] == nil {
                folderOrder.append(key)
            }
            folderEntries[key, default: []].append(.recentEntry(entry))
        }

        for folder in folderOrder {
            guard let sectionEntries = folderEntries[folder], !sectionEntries.isEmpty else { continue }

            if folder == Self.otherKey {
                sections.append(RecentFilesSection(
                    id: Self.otherKey,
                    title: "Other",
                    subtitle: nil,
                    entries: sectionEntries
                ))
            } else {
                let components = folder.split(separator: "/")
                let displayName = components.last.map(String.init) ?? folder
                sections.append(RecentFilesSection(
                    id: folder,
                    title: displayName,
                    subtitle: folder,
                    entries: sectionEntries
                ))
            }
        }

        sections.sort { a, b in
            let aMax = a.entries.first?.sortDate ?? .distantPast
            let bMax = b.entries.first?.sortDate ?? .distantPast
            return aMax > bMax
        }

        return sections
    }

    private func row(for item: SidebarItem, showDirectory: Bool = true) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.isScannedOnly ? "doc.text.magnifyingglass" : (item.fileURL.isFileURL ? "doc.text" : "globe"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.body)
                    .lineLimit(1)
                if showDirectory {
                    Text(item.fileURL.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .tag(item.path)
        .contextMenu {
            contextMenuActions(for: item)
        }
        .draggable(item.path)
    }

    @ViewBuilder
    private func contextMenuActions(for item: SidebarItem) -> some View {
        if item.fileURL.isFileURL {
            Button("Open In New Window") {
                selectedPath = item.path
                onOpenInNewWindow(item)
            }

            Divider()

            Button("Reveal in Finder") {
                selectedPath = item.path
                NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
            }

            Button("Copy Path to File") {
                selectedPath = item.path
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(item.path, forType: .string)
            }

            Divider()

            if !item.isScannedOnly {
                Button("Remove from History") {
                    selectedPath = item.path
                    onRemoveFromSidebar(item)
                }
            }
        } else {
            Button("Copy URL") {
                selectedPath = item.path
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(item.fileURL.absoluteString, forType: .string)
            }

            Divider()

            Button("Remove from History") {
                selectedPath = item.path
                onRemoveFromSidebar(item)
            }
        }
    }
}

private struct RecentFilesSection: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let entries: [SidebarItem]
    let isWatchedFolder: Bool

    init(bucket: RecentFileBucket, entries: [RecentFileEntry]) {
        self.id = bucket.rawValue
        self.title = bucket.rawValue
        self.subtitle = nil
        self.entries = entries.map { .recentEntry($0) }
        self.isWatchedFolder = false
    }

    init(id: String, title: String, subtitle: String?, entries: [SidebarItem], isWatchedFolder: Bool = false) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.entries = entries
        self.isWatchedFolder = isWatchedFolder
    }
}

private enum RecentFileBucket: String, CaseIterable {
    case today = "Today"
    case yesterday = "Yesterday"
    case thisWeek = "This Week"
    case lastWeek = "Last Week"
    case thisMonth = "This Month"
    case lastMonth = "Last Month"
    case older = "Older"

    static func bucket(for date: Date, now: Date = .now, calendar: Calendar = .current) -> RecentFileBucket {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday

        let startOfThisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfToday
        let startOfLastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: startOfThisWeek) ?? startOfThisWeek

        let startOfThisMonth = calendar.dateInterval(of: .month, for: now)?.start ?? startOfToday
        let startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: startOfThisMonth) ?? startOfThisMonth

        if date >= startOfToday {
            return .today
        }

        if date >= startOfYesterday && date < startOfToday {
            return .yesterday
        }

        if date >= startOfThisWeek {
            return .thisWeek
        }

        if date >= startOfLastWeek {
            return .lastWeek
        }

        if date >= startOfThisMonth {
            return .thisMonth
        }

        if date >= startOfLastMonth {
            return .lastMonth
        }

        return .older
    }
}
