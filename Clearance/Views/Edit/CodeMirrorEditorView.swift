import SwiftUI
import WebKit

struct CodeMirrorEditorView: NSViewRepresentable {
    @Binding var text: String

    private let templateProvider = EditorTemplateProvider()

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "textDidChange")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.loadHTMLString(templateProvider.html(), baseURL: Bundle.main.bundleURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.pushTextIfNeeded(text)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: CodeMirrorEditorView
        weak var webView: WKWebView?

        private var isReady = false
        private var lastPushedText = ""

        init(parent: CodeMirrorEditorView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            pushTextIfNeeded(parent.text)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "textDidChange",
                  let latest = message.body as? String else {
                return
            }

            lastPushedText = latest
            if parent.text != latest {
                parent.text = latest
            }
        }

        func pushTextIfNeeded(_ text: String) {
            guard isReady,
                  text != lastPushedText,
                  let webView else {
                return
            }

            lastPushedText = text
            let payload = jsStringLiteral(text)
            webView.evaluateJavaScript("setContent(\(payload));", completionHandler: nil)
        }

        private func jsStringLiteral(_ text: String) -> String {
            guard let data = try? JSONEncoder().encode(text),
                  let encoded = String(data: data, encoding: .utf8) else {
                return "\"\""
            }
            return encoded
        }
    }
}
