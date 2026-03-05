import Foundation
import Down

struct RenderedHTMLBuilder {
    private let codeBlockHTMLRegex = try! NSRegularExpression(pattern: "(?s)<pre><code(?: class=\"language-([^\"]+)\")?>(.*?)</code></pre>")
    private let codeStringRegex = try! NSRegularExpression(pattern: "\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|`(?:\\\\.|[^`\\\\])*`")
    private let codeNumberRegex = try! NSRegularExpression(pattern: "\\b\\d+(?:\\.\\d+)?\\b")
    private let codeLineCommentRegex = try! NSRegularExpression(pattern: "//.*$", options: [.anchorsMatchLines])
    private let codeBlockCommentRegex = try! NSRegularExpression(pattern: "(?s)/\\*.*?\\*/")
    private let hashCommentRegex = try! NSRegularExpression(pattern: "#.*$", options: [.anchorsMatchLines])
    private let yamlKeyRegex = try! NSRegularExpression(pattern: "(?m)^\\s*(?:-\\s+)?([A-Za-z0-9_.-]+)(?=\\s*:)")
    private let yamlLiteralRegex = try! NSRegularExpression(pattern: "\\b(?:true|false|null|yes|no|on|off)\\b", options: [.caseInsensitive])
    private let swiftKeywordRegex = try! NSRegularExpression(pattern: "\\b(?:actor|as|associatedtype|async|await|break|case|catch|class|continue|default|defer|do|else|enum|extension|fallthrough|false|for|func|guard|if|import|in|init|inout|internal|is|let|nil|operator|private|protocol|public|repeat|return|self|static|struct|subscript|super|switch|throw|throws|true|try|typealias|var|where|while)\\b")
    private let jsKeywordRegex = try! NSRegularExpression(pattern: "\\b(?:as|async|await|break|case|catch|class|const|continue|debugger|default|delete|do|else|enum|export|extends|false|finally|for|from|function|if|import|in|instanceof|interface|let|new|null|private|protected|public|readonly|return|static|switch|this|throw|true|try|type|typeof|var|void|while|with|yield)\\b")
    private let genericKeywordRegex = try! NSRegularExpression(pattern: "\\b(?:if|else|for|while|switch|case|break|continue|return|func|function|class|struct|enum|let|var|const|import|from|export|true|false|null|nil)\\b")

    func build(document: ParsedMarkdownDocument) -> String {
        let bodyHTML = (try? Down(markdownString: document.body).toHTML()) ?? "<pre>\(escapeHTML(document.body))</pre>"
        let highlightedBodyHTML = highlightCodeBlocks(in: bodyHTML)
        let frontmatterHTML = frontmatterTableHTML(from: document.flattenedFrontmatter)

        return """
        <!doctype html>
        <html lang=\"en\">
        <head>
          <meta charset=\"utf-8\" />
          <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
          <meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; img-src data: file:;\" />
          <style>
          \(stylesheet())
          </style>
        </head>
        <body>
          <main class=\"document\">
            \(frontmatterHTML)
            <article class=\"markdown\">\(highlightedBodyHTML)</article>
          </main>
        </body>
        </html>
        """
    }

    private func frontmatterTableHTML(from frontmatter: [String: String]) -> String {
        guard !frontmatter.isEmpty else {
            return ""
        }

        let rows = frontmatter.keys.sorted().map { key in
            let value = frontmatter[key] ?? ""
            return "<tr><th>\(escapeHTML(key))</th><td>\(escapeHTML(value))</td></tr>"
        }.joined()

        return """
        <section class=\"frontmatter\">
          <h2>Metadata</h2>
          <table>
            <tbody>
              \(rows)
            </tbody>
          </table>
        </section>
        """
    }

    private func highlightCodeBlocks(in html: String) -> String {
        let range = NSRange(location: 0, length: (html as NSString).length)
        let matches = codeBlockHTMLRegex.matches(in: html, range: range)
        guard !matches.isEmpty else {
            return html
        }

        var result = html
        for match in matches.reversed() {
            let nsHTML = html as NSString
            let languageRange = match.range(at: 1)
            let language: String
            if languageRange.location == NSNotFound {
                language = ""
            } else {
                language = nsHTML.substring(with: languageRange).lowercased()
            }

            let codeHTML = nsHTML.substring(with: match.range(at: 2))
            let decodedCode = decodeHTMLEntities(codeHTML)
            let highlightedCode = annotateCode(decodedCode, language: language)
            let languageClassAttribute = language.isEmpty ? "" : " class=\"language-\(escapeHTML(language))\""
            let replacement = "<pre><code\(languageClassAttribute)>\(highlightedCode)</code></pre>"
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
        }

        return result
    }

    private func annotateCode(_ code: String, language: String) -> String {
        let tokens = selectNonOverlappingTokens(codeTokens(in: code, language: language))
        return renderCode(code, tokens: tokens)
    }

    private func codeTokens(in code: String, language: String) -> [TokenSpan] {
        let fullRange = NSRange(location: 0, length: (code as NSString).length)
        var tokens: [TokenSpan] = []

        addMatches(codeNumberRegex, in: code, range: fullRange, className: "hl-number", priority: 10, to: &tokens)

        switch language {
        case "yaml", "yml":
            addMatches(yamlLiteralRegex, in: code, range: fullRange, className: "hl-keyword", priority: 20, to: &tokens)
            addMatches(yamlKeyRegex, in: code, range: fullRange, className: "hl-property", priority: 20, captureGroup: 1, to: &tokens)
            addMatches(hashCommentRegex, in: code, range: fullRange, className: "hl-comment", priority: 40, to: &tokens)
        case "swift":
            addMatches(swiftKeywordRegex, in: code, range: fullRange, className: "hl-keyword", priority: 20, to: &tokens)
            addMatches(codeBlockCommentRegex, in: code, range: fullRange, className: "hl-comment", priority: 40, to: &tokens)
            addMatches(codeLineCommentRegex, in: code, range: fullRange, className: "hl-comment", priority: 40, to: &tokens)
        case "bash", "sh", "zsh", "shell":
            addMatches(hashCommentRegex, in: code, range: fullRange, className: "hl-comment", priority: 40, to: &tokens)
            addMatches(genericKeywordRegex, in: code, range: fullRange, className: "hl-keyword", priority: 20, to: &tokens)
        case "js", "mjs", "cjs", "jsx", "ts", "tsx", "typescript", "javascript", "json", "jsonc":
            addMatches(jsKeywordRegex, in: code, range: fullRange, className: "hl-keyword", priority: 20, to: &tokens)
            addMatches(codeBlockCommentRegex, in: code, range: fullRange, className: "hl-comment", priority: 40, to: &tokens)
            addMatches(codeLineCommentRegex, in: code, range: fullRange, className: "hl-comment", priority: 40, to: &tokens)
        default:
            addMatches(genericKeywordRegex, in: code, range: fullRange, className: "hl-keyword", priority: 20, to: &tokens)
            addMatches(codeBlockCommentRegex, in: code, range: fullRange, className: "hl-comment", priority: 40, to: &tokens)
            addMatches(codeLineCommentRegex, in: code, range: fullRange, className: "hl-comment", priority: 40, to: &tokens)
            addMatches(hashCommentRegex, in: code, range: fullRange, className: "hl-comment", priority: 40, to: &tokens)
        }

        addMatches(codeStringRegex, in: code, range: fullRange, className: "hl-string", priority: 30, to: &tokens)
        return tokens
    }

    private func addMatches(
        _ regex: NSRegularExpression,
        in text: String,
        range: NSRange,
        className: String,
        priority: Int,
        captureGroup: Int = 0,
        to tokens: inout [TokenSpan]
    ) {
        for match in regex.matches(in: text, range: range) {
            let tokenRange = match.range(at: captureGroup)
            guard tokenRange.location != NSNotFound,
                  tokenRange.length > 0 else {
                continue
            }

            tokens.append(TokenSpan(range: tokenRange, cssClass: className, priority: priority))
        }
    }

    private func selectNonOverlappingTokens(_ tokens: [TokenSpan]) -> [TokenSpan] {
        let prioritized = tokens.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            if lhs.range.location != rhs.range.location {
                return lhs.range.location < rhs.range.location
            }
            return lhs.range.length > rhs.range.length
        }

        var selected: [TokenSpan] = []
        for token in prioritized {
            let intersects = selected.contains { existing in
                NSIntersectionRange(existing.range, token.range).length > 0
            }
            if !intersects {
                selected.append(token)
            }
        }

        return selected.sorted { $0.range.location < $1.range.location }
    }

    private func renderCode(_ code: String, tokens: [TokenSpan]) -> String {
        let nsCode = code as NSString
        var rendered = ""
        var cursor = 0

        for token in tokens {
            let tokenStart = token.range.location
            if tokenStart > cursor {
                let plainRange = NSRange(location: cursor, length: tokenStart - cursor)
                rendered += escapeHTML(nsCode.substring(with: plainRange))
            }

            let tokenText = nsCode.substring(with: token.range)
            rendered += "<span class=\"\(token.cssClass)\">\(escapeHTML(tokenText))</span>"
            cursor = token.range.location + token.range.length
        }

        if cursor < nsCode.length {
            let trailingRange = NSRange(location: cursor, length: nsCode.length - cursor)
            rendered += escapeHTML(nsCode.substring(with: trailingRange))
        }

        return rendered
    }

    private func decodeHTMLEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private func stylesheet() -> String {
        if let cssURL = Bundle.main.url(forResource: "render", withExtension: "css"),
           let css = try? String(contentsOf: cssURL) {
            return css
        }

        return """
        :root {
          color-scheme: light dark;
          --bg: #f3f5f9;
          --surface: #ffffff;
          --border: rgba(97, 112, 138, 0.26);
          --text: #1f2733;
          --muted: #5c697c;
          --heading: #2c62d6;
          --link: #2f6fe0;
          --code-bg: #0f172a;
          --code-text: #d5e2ff;
          --inline-bg: rgba(47, 111, 224, 0.14);
          --inline-text: #2757a8;
          --quote: #4f75ba;
          --rule: rgba(97, 112, 138, 0.24);
          --token-comment: #7c8aa0;
          --token-keyword: #7a3fe0;
          --token-string: #0b7a65;
          --token-number: #b05a00;
          --token-property: #2a6bb5;
        }
        @media (prefers-color-scheme: dark) {
          :root {
            --bg: #0e1118;
            --surface: #141a23;
            --border: rgba(144, 161, 190, 0.24);
            --text: #d5deeb;
            --muted: #97a5ba;
            --heading: #8ca8ff;
            --link: #90b2ff;
            --code-bg: #0a1020;
            --code-text: #dce6ff;
            --inline-bg: rgba(119, 157, 220, 0.22);
            --inline-text: #a6c7ff;
            --quote: #79a9ff;
            --rule: rgba(144, 161, 190, 0.26);
            --token-comment: #8fa2c2;
            --token-keyword: #b39bff;
            --token-string: #7dd7b8;
            --token-number: #ffb86b;
            --token-property: #8cb8ff;
          }
        }
        body { margin: 0; font-family: 'SF Pro Text', 'Inter', 'Helvetica Neue', sans-serif; background: var(--bg); color: var(--text); }
        .document { max-width: 860px; margin: 32px auto; padding: 0 24px 64px; }
        .frontmatter { background: var(--surface); border: 1px solid var(--border); border-radius: 0; padding: 12px 16px; margin-bottom: 22px; }
        .frontmatter h2 { margin: 0 0 8px; font-size: 14px; text-transform: uppercase; letter-spacing: 0.06em; color: var(--muted); }
        table { width: 100%; border-collapse: collapse; }
        th, td { text-align: left; padding: 8px 10px; vertical-align: top; border-top: 1px solid var(--rule); font-size: 13px; }
        th { width: 35%; color: var(--muted); font-weight: 600; }
        .markdown { background: transparent; border: none; border-radius: 0; padding: 0; }
        .markdown h1, .markdown h2, .markdown h3 { color: var(--heading); font-family: 'SF Pro Display', 'Inter', 'Helvetica Neue', sans-serif; font-weight: 700; }
        .markdown p, .markdown li { line-height: 1.65; }
        .markdown a { color: var(--link); }
        .markdown blockquote { border-left: 3px solid var(--quote); margin-left: 0; padding-left: 14px; color: var(--muted); }
        .markdown hr { border: none; border-top: 1px solid var(--rule); }
        .markdown code { font-family: 'SF Mono', Menlo, Monaco, monospace; background: var(--inline-bg); color: var(--inline-text); padding: 2px 6px; border-radius: 6px; font-size: 0.9em; }
        .markdown pre { background: var(--code-bg); color: var(--code-text); padding: 14px; border-radius: 8px; overflow-x: auto; }
        .markdown pre code { background: transparent; color: inherit; padding: 0; }
        .markdown pre code .hl-comment { color: var(--token-comment); }
        .markdown pre code .hl-keyword { color: var(--token-keyword); }
        .markdown pre code .hl-string { color: var(--token-string); }
        .markdown pre code .hl-number { color: var(--token-number); }
        .markdown pre code .hl-property { color: var(--token-property); }
        """
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

private struct TokenSpan {
    let range: NSRange
    let cssClass: String
    let priority: Int
}
