import Combine
import Foundation

@MainActor
final class WorkspaceViewModel: NSObject, ObservableObject {
    @Published var activeSession: DocumentSession? {
        didSet {
            bindActiveSession()
        }
    }
    @Published var errorMessage: String?
    @Published var mode: WorkspaceMode
    @Published private(set) var windowTitle: String
    @Published private(set) var externalChangeDocumentName: String?

    let recentFilesStore: RecentFilesStore

    private let openPanelService: OpenPanelServicing
    private let appSettings: AppSettings
    private var activeSessionCancellables: Set<AnyCancellable> = []
    private var externalChangeTimer: Timer?
    private weak var monitoredSession: DocumentSession?

    init(
        recentFilesStore: RecentFilesStore = RecentFilesStore(),
        openPanelService: OpenPanelServicing = OpenPanelService(),
        appSettings: AppSettings = AppSettings()
    ) {
        self.recentFilesStore = recentFilesStore
        self.openPanelService = openPanelService
        self.appSettings = appSettings
        mode = appSettings.defaultOpenMode
        windowTitle = "Clearance"
        super.init()
    }

    func promptAndOpenFile() {
        guard let url = openPanelService.chooseMarkdownFile() else {
            return
        }

        open(url: url)
    }

    @discardableResult
    func open(recentEntry: RecentFileEntry) -> DocumentSession? {
        open(url: recentEntry.fileURL)
    }

    @discardableResult
    func open(url: URL) -> DocumentSession? {
        do {
            let session = try DocumentSession(url: url)
            activeSession = session
            recentFilesStore.add(url: url)
            mode = appSettings.defaultOpenMode
            errorMessage = nil
            return session
        } catch {
            errorMessage = "Failed to open \(url.path): \(error.localizedDescription)"
            return nil
        }
    }

    func reloadActiveFromDisk() {
        guard let session = activeSession else {
            return
        }

        do {
            try session.reloadFromDisk()
            errorMessage = nil
            externalChangeDocumentName = nil
        } catch {
            errorMessage = "Failed to reload \(session.url.path): \(error.localizedDescription)"
        }
    }

    func keepCurrentVersionAfterExternalChange() {
        guard let session = activeSession else {
            return
        }

        session.acknowledgeExternalChangesKeepingCurrent()
        externalChangeDocumentName = nil
    }

    func checkForExternalChangesNow() {
        activeSession?.checkForExternalChanges()
    }

    private func bindActiveSession() {
        activeSessionCancellables.removeAll()
        externalChangeTimer?.invalidate()
        externalChangeTimer = nil
        monitoredSession = nil
        externalChangeDocumentName = nil

        guard let session = activeSession else {
            windowTitle = "Clearance"
            return
        }

        updateWindowTitle(for: session)

        session.$isDirty
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.activeSession === session else {
                    return
                }

                self.updateWindowTitle(for: session)
            }
            .store(in: &activeSessionCancellables)

        session.$hasExternalChanges
            .receive(on: RunLoop.main)
            .sink { [weak self] hasExternalChanges in
                guard let self, self.activeSession === session else {
                    return
                }

                if hasExternalChanges {
                    self.externalChangeDocumentName = session.url.lastPathComponent
                } else {
                    self.externalChangeDocumentName = nil
                }
            }
            .store(in: &activeSessionCancellables)

        monitoredSession = session
        let timer = Timer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(handleExternalChangeTimer),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = 0.3
        externalChangeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateWindowTitle(for session: DocumentSession) {
        windowTitle = session.displayTitle
    }

    @objc private func handleExternalChangeTimer() {
        guard let session = monitoredSession,
              activeSession === session else {
            externalChangeTimer?.invalidate()
            externalChangeTimer = nil
            monitoredSession = nil
            return
        }

        session.checkForExternalChanges()
    }
}
