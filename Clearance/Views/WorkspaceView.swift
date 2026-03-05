import SwiftUI

struct WorkspaceView: View {
    @StateObject private var viewModel = WorkspaceViewModel()

    var body: some View {
        NavigationSplitView {
            RecentFilesSidebar(entries: viewModel.recentFilesStore.entries) { entry in
                viewModel.open(recentEntry: entry)
            }
            .navigationTitle("Open Files")
        } detail: {
            Group {
                if let session = viewModel.activeSession {
                    switch viewModel.mode {
                    case .view:
                        let parsed = FrontmatterParser().parse(markdown: session.content)
                        RenderedMarkdownView(document: parsed)
                    case .edit:
                        CodeMirrorEditorView(
                            text: Binding(
                                get: { session.content },
                                set: { session.content = $0 }
                            )
                        )
                    }
                } else {
                    ContentUnavailableView("Open a Markdown File", systemImage: "doc.text")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("Mode", selection: $viewModel.mode) {
                    ForEach(WorkspaceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .disabled(viewModel.activeSession == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Open") {
                    viewModel.promptAndOpenFile()
                }
            }
        }
        .alert("Could Not Open File", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        ), actions: {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        }, message: {
            Text(viewModel.errorMessage ?? "")
        })
    }
}
