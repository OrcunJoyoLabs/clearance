import AppKit
import Combine
import SwiftUI

@MainActor
final class PopoutWindowController {
    private var windows: [NSWindow] = []
    private var windowDelegates: [ObjectIdentifier: PopoutWindowDelegate] = [:]
    private var titleSubscriptions: [ObjectIdentifier: AnyCancellable] = [:]

    func openWindow(for session: DocumentSession, mode: WorkspaceMode) {
        let content = PopoutDocumentView(session: session, initialMode: mode)
        let hostingController = NSHostingController(rootView: content)

        let window = NSWindow(contentViewController: hostingController)
        window.title = session.displayTitle
        window.setContentSize(NSSize(width: 980, height: 760))
        window.styleMask.insert(.resizable)
        window.styleMask.insert(.closable)
        window.styleMask.insert(.miniaturizable)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        let windowID = ObjectIdentifier(window)

        let titleSubscription = session.$isDirty
            .receive(on: RunLoop.main)
            .sink { [weak window, weak session] _ in
                guard let window, let session else {
                    return
                }

                window.title = session.displayTitle
            }
        titleSubscriptions[windowID] = titleSubscription

        let windowDelegate = PopoutWindowDelegate { [weak self, weak window] in
            guard let self, let window else {
                return
            }
            self.removeWindow(window)
        }
        window.delegate = windowDelegate
        windowDelegates[windowID] = windowDelegate

        windows.append(window)
    }

    private func removeWindow(_ window: NSWindow) {
        let windowID = ObjectIdentifier(window)
        windows.removeAll { $0 === window }
        windowDelegates.removeValue(forKey: windowID)
        titleSubscriptions.removeValue(forKey: windowID)
    }
}

@MainActor
private final class PopoutWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

private struct PopoutDocumentView: View {
    @ObservedObject var session: DocumentSession
    @State private var mode: WorkspaceMode

    init(session: DocumentSession, initialMode: WorkspaceMode) {
        self.session = session
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        DocumentSurfaceView(session: session, mode: $mode)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Picker("Mode", selection: $mode) {
                        ForEach(WorkspaceMode.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
            }
            .frame(minWidth: 640, minHeight: 400)
    }
}
