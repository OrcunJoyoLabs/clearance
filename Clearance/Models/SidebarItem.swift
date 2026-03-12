import Foundation

enum SidebarItem: Identifiable, Equatable {
    case recentEntry(RecentFileEntry)
    case scannedFile(url: URL, modificationDate: Date)

    var id: String { path }

    var path: String {
        switch self {
        case .recentEntry(let entry):
            return entry.path
        case .scannedFile(let url, _):
            return url.standardizedFileURL.path
        }
    }

    var displayName: String {
        switch self {
        case .recentEntry(let entry):
            return entry.displayName
        case .scannedFile(let url, _):
            return url.lastPathComponent
        }
    }

    var sortDate: Date {
        switch self {
        case .recentEntry(let entry):
            return entry.lastOpenedAt
        case .scannedFile(_, let modDate):
            return modDate
        }
    }

    var fileURL: URL {
        switch self {
        case .recentEntry(let entry):
            return entry.fileURL
        case .scannedFile(let url, _):
            return url
        }
    }

    var isScannedOnly: Bool {
        switch self {
        case .recentEntry:
            return false
        case .scannedFile:
            return true
        }
    }

    static func == (lhs: SidebarItem, rhs: SidebarItem) -> Bool {
        lhs.path == rhs.path
    }
}
