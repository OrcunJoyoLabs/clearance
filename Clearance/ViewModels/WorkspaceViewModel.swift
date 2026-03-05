import Foundation

@MainActor
final class WorkspaceViewModel: ObservableObject {
    @Published var activeSession: DocumentSession?
    @Published var errorMessage: String?
    @Published var mode: WorkspaceMode = .view

    let recentFilesStore: RecentFilesStore

    private let openPanelService: OpenPanelServicing

    init(
        recentFilesStore: RecentFilesStore = RecentFilesStore(),
        openPanelService: OpenPanelServicing = OpenPanelService()
    ) {
        self.recentFilesStore = recentFilesStore
        self.openPanelService = openPanelService
    }

    func promptAndOpenFile() {
        guard let url = openPanelService.chooseMarkdownFile() else {
            return
        }

        open(url: url)
    }

    func open(recentEntry: RecentFileEntry) {
        open(url: recentEntry.fileURL)
    }

    func open(url: URL) {
        do {
            let session = try DocumentSession(url: url)
            activeSession = session
            recentFilesStore.add(url: url)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to open \(url.path): \(error.localizedDescription)"
        }
    }
}
