import Foundation

struct EditorTemplateProvider {
    func html() -> String {
        if let url = Bundle.main.url(forResource: "editor", withExtension: "html"),
           let html = try? String(contentsOf: url) {
            return html
        }

        return fallbackHTML
    }

    private var fallbackHTML: String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset=\"utf-8\" />
          <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
          <link rel=\"stylesheet\" href=\"https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.css\" />
          <script src=\"https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.js\"></script>
          <script src=\"https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/mode/markdown/markdown.min.js\"></script>
          <style>
            html, body { height: 100%; margin: 0; }
            .CodeMirror { height: 100vh; font-size: 14px; font-family: Menlo, monospace; }
          </style>
        </head>
        <body>
          <textarea id=\"editor\"></textarea>
          <script>
            const editor = CodeMirror.fromTextArea(document.getElementById('editor'), {
              mode: 'markdown',
              lineNumbers: true,
              lineWrapping: true,
              undoDepth: 10000
            });

            window.setContent = function(value) {
              if (editor.getValue() !== value) {
                editor.setValue(value);
              }
            };

            editor.on('change', function() {
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.textDidChange) {
                window.webkit.messageHandlers.textDidChange.postMessage(editor.getValue());
              }
            });
          </script>
        </body>
        </html>
        """
    }
}
