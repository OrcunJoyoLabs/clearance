import AppKit
import SwiftUI

@main
struct ClearanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appSettings = AppSettings()
    private let sparkleUpdateController = SparkleUpdateController()
    private let popoutWindowController = PopoutWindowController()

    var body: some Scene {
        WindowGroup {
            WorkspaceView(
                appSettings: appSettings,
                popoutWindowController: popoutWindowController
            )
        }
        .commands {
            ClearanceCommands(sparkleUpdateController: sparkleUpdateController)
        }

        Settings {
            SettingsView(settings: appSettings)
        }
    }
}

struct WorkspaceCommandActions {
    let openFile: () -> Void
    let toggleOutline: () -> Void
    let showViewMode: () -> Void
    let showEditMode: () -> Void
    let openInNewWindow: () -> Void
    let findInDocument: () -> Bool
    let findPreviousInDocument: () -> Bool
    let printDocument: () -> Bool
    let hasActiveSession: Bool
    let hasVisibleOutline: Bool
    let canShowOutline: Bool
}

private struct WorkspaceCommandActionsKey: FocusedValueKey {
    typealias Value = WorkspaceCommandActions
}

extension FocusedValues {
    var workspaceCommandActions: WorkspaceCommandActions? {
        get { self[WorkspaceCommandActionsKey.self] }
        set { self[WorkspaceCommandActionsKey.self] = newValue }
    }
}

private struct ClearanceCommands: Commands {
    @FocusedValue(\.workspaceCommandActions) private var actions
    private let sparkleUpdateController: SparkleUpdateController

    init(sparkleUpdateController: SparkleUpdateController) {
        self.sparkleUpdateController = sparkleUpdateController
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Clearance") {
                showAboutPanel()
            }
        }

        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                sparkleUpdateController.checkForUpdates()
            }
            .disabled(!sparkleUpdateController.canCheckForUpdates)
        }

        CommandGroup(replacing: .newItem) {
            Button("Open Markdown…") {
                actions?.openFile()
            }
            .keyboardShortcut("o")
            .disabled(actions == nil)

            Button("Open In New Window") {
                actions?.openInNewWindow()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(actions?.hasActiveSession != true)
        }

        CommandGroup(replacing: .printItem) {
            Button("Print…") {
                if let printDocument = actions?.printDocument {
                    _ = printDocument()
                } else {
                    _ = performPrint()
                }
            }
            .keyboardShortcut("p")
            .disabled(actions?.hasActiveSession != true)
        }

        CommandGroup(after: .textEditing) {
            Divider()

            Button("Find…") {
                if let findInDocument = actions?.findInDocument {
                    if !findInDocument() {
                        _ = performFind()
                    }
                } else {
                    _ = performFind()
                }
            }
            .keyboardShortcut("f")
            .disabled(actions?.hasActiveSession != true)

            Button("Find Previous") {
                if let findPreviousInDocument = actions?.findPreviousInDocument {
                    if !findPreviousInDocument() {
                        _ = performFindPrevious()
                    }
                } else {
                    _ = performFindPrevious()
                }
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(actions?.hasActiveSession != true)
        }

        CommandGroup(after: .sidebar) {
            Button("View Mode") {
                actions?.showViewMode()
            }
            .keyboardShortcut("1")
            .disabled(actions?.hasActiveSession != true)

            Button("Edit Mode") {
                actions?.showEditMode()
            }
            .keyboardShortcut("2")
            .disabled(actions?.hasActiveSession != true)

            Divider()

            Button(actions?.hasVisibleOutline == true ? "Hide Outline" : "Show Outline") {
                actions?.toggleOutline()
            }
            .keyboardShortcut("0")
            .disabled(actions?.canShowOutline != true)
        }
    }

    private func performFind() -> Bool {
        let findMenuItem = NSMenuItem()
        findMenuItem.tag = NSTextFinder.Action.showFindInterface.rawValue
        if NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: findMenuItem) {
            return true
        }

        let legacyFindMenuItem = NSMenuItem()
        legacyFindMenuItem.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        return NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: legacyFindMenuItem)
    }

    private func performFindPrevious() -> Bool {
        let findMenuItem = NSMenuItem()
        findMenuItem.tag = NSTextFinder.Action.previousMatch.rawValue
        return NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: findMenuItem)
    }

    private func performPrint() -> Bool {
        NSApp.sendAction(#selector(NSView.printView(_:)), to: nil, from: nil)
    }

    private func showAboutPanel() {
        let centeredParagraph = NSMutableParagraphStyle()
        centeredParagraph.alignment = .center

        let credits = NSMutableAttributedString()

        if let websiteURL = URL(string: "https://primeradiant.com") {
            credits.append(NSAttributedString(
                string: "https://primeradiant.com",
                attributes: [
                    .link: websiteURL,
                    .paragraphStyle: centeredParagraph
                ]
            ))
        }

        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits
        ])
    }
}
