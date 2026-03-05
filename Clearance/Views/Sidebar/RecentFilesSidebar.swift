import SwiftUI

struct RecentFilesSidebar: View {
    let entries: [RecentFileEntry]
    let onSelect: (RecentFileEntry) -> Void
    let onPopOut: (RecentFileEntry) -> Void

    var body: some View {
        List(entries) { entry in
            Button {
                onSelect(entry)
            } label: {
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
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Pop Out In New Window") {
                    onPopOut(entry)
                }
            }
            .draggable(entry.path)
        }
        .listStyle(.sidebar)
    }
}
