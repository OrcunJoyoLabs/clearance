import AppKit
import SwiftUI

struct RecentFilesSidebar: View {
    let entries: [RecentFileEntry]
    @Binding var selectedPath: String?
    let onSelect: (RecentFileEntry) -> Void
    let onOpenInNewWindow: (RecentFileEntry) -> Void

    var body: some View {
        List(selection: $selectedPath) {
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(.body)
                        .lineLimit(1)
                    Text(entry.directoryPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .tag(entry.path)
                .onTapGesture {
                    selectedPath = entry.path
                    onSelect(entry)
                }
                .contextMenu {
                    contextMenuActions(for: entry)
                }
                .draggable(entry.path)
            }
        }
        .contextMenu(forSelectionType: String.self) { selectedPaths in
            if let path = selectedPaths.first,
               let entry = entries.first(where: { $0.path == path }) {
                contextMenuActions(for: entry)
            }
        }
        .onChange(of: selectedPath) { _, newPath in
            guard let newPath,
                  let entry = entries.first(where: { $0.path == newPath }) else {
                return
            }

            onSelect(entry)
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func contextMenuActions(for entry: RecentFileEntry) -> some View {
        Button("Open In New Window") {
            selectedPath = entry.path
            onOpenInNewWindow(entry)
        }

        Divider()

        Button("Show in Finder") {
            selectedPath = entry.path
            NSWorkspace.shared.activateFileViewerSelecting([entry.fileURL])
        }

        Button("Copy Path") {
            selectedPath = entry.path
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(entry.path, forType: .string)
        }
    }
}
