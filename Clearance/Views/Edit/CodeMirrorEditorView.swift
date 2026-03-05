import AppKit
import SwiftUI

struct CodeMirrorEditorView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = EditorTextView(frame: .zero)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 20, height: 18)
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindPanel = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.delegate = context.coordinator
        textView.string = text

        context.coordinator.textView = textView
        context.coordinator.applyTheme(to: textView)
        context.coordinator.highlighter.apply(to: textView)
        textView.onAppearanceDidChange = { [weak textView, weak coordinator = context.coordinator] in
            guard let textView,
                  let coordinator else {
                return
            }

            coordinator.applyTheme(to: textView)
            coordinator.highlighter.apply(to: textView)
        }

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self

        guard let textView = context.coordinator.textView,
              textView.string != text else {
            return
        }

        context.coordinator.isSyncingFromBinding = true

        let oldSelection = textView.selectedRange()
        textView.string = text
        context.coordinator.highlighter.apply(to: textView)

        let maxLength = (textView.string as NSString).length
        let clampedLocation = min(oldSelection.location, maxLength)
        let clampedLength = min(oldSelection.length, max(0, maxLength - clampedLocation))
        textView.setSelectedRange(NSRange(location: clampedLocation, length: clampedLength))

        context.coordinator.isSyncingFromBinding = false
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeMirrorEditorView
        weak var textView: EditorTextView?
        let highlighter = MarkdownSyntaxHighlighter()
        var isSyncingFromBinding = false

        init(parent: CodeMirrorEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isSyncingFromBinding,
                  let textView else {
                return
            }

            highlighter.apply(to: textView)
            let latest = textView.string
            if parent.text != latest {
                parent.text = latest
            }
        }

        func applyTheme(to textView: NSTextView) {
            textView.backgroundColor = ClearancePalette.editorBackground
            textView.textColor = ClearancePalette.text
            textView.insertionPointColor = ClearancePalette.insertionPoint
            textView.selectedTextAttributes = [
                .backgroundColor: ClearancePalette.selectionBackground,
                .foregroundColor: ClearancePalette.selectionText
            ]
        }
    }
}

final class EditorTextView: NSTextView {
    var onAppearanceDidChange: (@MainActor () -> Void)?

    private lazy var editorUndoManager: UndoManager = {
        let manager = UndoManager()
        manager.levelsOfUndo = 100_000
        return manager
    }()

    override var undoManager: UndoManager? {
        editorUndoManager
    }

    override func keyDown(with event: NSEvent) {
        if handleControlUndoShortcut(event) {
            return
        }

        super.keyDown(with: event)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceDidChange?()
    }

    private func handleControlUndoShortcut(_ event: NSEvent) -> Bool {
        guard let key = event.charactersIgnoringModifiers?.lowercased(),
              key == "z" else {
            return false
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == [.control] {
            undoManager?.undo()
            return true
        }

        if flags == [.control, .shift] {
            undoManager?.redo()
            return true
        }

        return false
    }
}

@MainActor
final class MarkdownSyntaxHighlighter {
    private let headingRegex = try! NSRegularExpression(pattern: "(?m)^(#{1,6})\\s+(.+)$")
    private let frontmatterRegex = try! NSRegularExpression(pattern: "(?s)\\A---\\n.*?\\n---\\n?")
    private let fencedCodeRegex = try! NSRegularExpression(pattern: "(?s)(?:```|~~~)([A-Za-z0-9_+-]*)[^\\n]*\\n(.*?)\\n?(?:```|~~~)")
    private let inlineCodeRegex = try! NSRegularExpression(pattern: "`[^`\\n]+`")
    private let linkRegex = try! NSRegularExpression(pattern: "\\[[^\\]]+\\]\\([^\\)]+\\)")
    private let strongRegex = try! NSRegularExpression(pattern: "(\\*\\*|__)(?=\\S)(.+?\\S)\\1")
    private let emphasisRegex = try! NSRegularExpression(pattern: "(\\*|_)(?=\\S)(.+?\\S)\\1")
    private let blockquoteRegex = try! NSRegularExpression(pattern: "(?m)^>.*$")
    private let listMarkerRegex = try! NSRegularExpression(pattern: "(?m)^\\s*(?:[-*+] |\\d+\\. )")
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

    func apply(to textView: NSTextView) {
        guard let storage = textView.textStorage else {
            return
        }

        let fullRange = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: fullRange)

        let fullText = storage.string
        let fullTextRange = NSRange(location: 0, length: (fullText as NSString).length)
        let fencedCodeMatches = fencedCodeRegex.matches(in: fullText, range: fullTextRange)

        for match in frontmatterRegex.matches(in: fullText, range: fullTextRange) {
            storage.addAttributes(frontmatterAttributes, range: match.range)
        }

        for match in headingRegex.matches(in: fullText, range: fullTextRange) {
            let level = max(1, min(match.range(at: 1).length, 6))
            storage.addAttributes(headingAttributes(for: level), range: match.range)
        }

        for match in blockquoteRegex.matches(in: fullText, range: fullTextRange) {
            storage.addAttributes(blockquoteAttributes, range: match.range)
        }

        for match in listMarkerRegex.matches(in: fullText, range: fullTextRange) {
            storage.addAttributes(listMarkerAttributes, range: match.range)
        }

        for match in linkRegex.matches(in: fullText, range: fullTextRange) {
            storage.addAttributes(linkAttributes, range: match.range)
        }

        for match in strongRegex.matches(in: fullText, range: fullTextRange) {
            storage.addAttributes(strongAttributes, range: match.range)
        }

        for match in emphasisRegex.matches(in: fullText, range: fullTextRange) {
            storage.addAttributes(emphasisAttributes, range: match.range)
        }

        for match in inlineCodeRegex.matches(in: fullText, range: fullTextRange) {
            storage.addAttributes(inlineCodeAttributes, range: match.range)
        }

        for match in fencedCodeMatches {
            applyFencedCodeHighlighting(for: match, in: storage, fullText: fullText)
        }

        storage.endEditing()
        textView.typingAttributes = baseAttributes
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .regular),
            .foregroundColor: ClearancePalette.text
        ]
    }

    private var frontmatterAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: 14.5, weight: .regular),
            .foregroundColor: ClearancePalette.frontmatter
        ]
    }

    private var blockquoteAttributes: [NSAttributedString.Key: Any] {
        [
            .foregroundColor: ClearancePalette.secondaryText
        ]
    }

    private var listMarkerAttributes: [NSAttributedString.Key: Any] {
        [
            .foregroundColor: ClearancePalette.listMarker
        ]
    }

    private var linkAttributes: [NSAttributedString.Key: Any] {
        [
            .foregroundColor: ClearancePalette.link,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
    }

    private var strongAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .semibold)
        ]
    }

    private var emphasisAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFontManager.shared.convert(NSFont.monospacedSystemFont(ofSize: 15, weight: .regular), toHaveTrait: .italicFontMask)
        ]
    }

    private var inlineCodeAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: ClearancePalette.inlineCodeText,
            .backgroundColor: ClearancePalette.inlineCodeBackground
        ]
    }

    private var fencedCodeAttributes: [NSAttributedString.Key: Any] {
        [
            .font: codeFont,
            .foregroundColor: ClearancePalette.codeBlockText,
            .backgroundColor: ClearancePalette.codeBlockBackground
        ]
    }

    private var codeFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    }

    private var codeCommentAttributes: [NSAttributedString.Key: Any] {
        [
            .font: codeFont,
            .foregroundColor: ClearancePalette.syntaxComment
        ]
    }

    private var codeKeywordAttributes: [NSAttributedString.Key: Any] {
        [
            .font: codeFont,
            .foregroundColor: ClearancePalette.syntaxKeyword
        ]
    }

    private var codeStringAttributes: [NSAttributedString.Key: Any] {
        [
            .font: codeFont,
            .foregroundColor: ClearancePalette.syntaxString
        ]
    }

    private var codeNumberAttributes: [NSAttributedString.Key: Any] {
        [
            .font: codeFont,
            .foregroundColor: ClearancePalette.syntaxNumber
        ]
    }

    private var codePropertyAttributes: [NSAttributedString.Key: Any] {
        [
            .font: codeFont,
            .foregroundColor: ClearancePalette.syntaxProperty
        ]
    }

    private func applyFencedCodeHighlighting(for match: NSTextCheckingResult, in storage: NSTextStorage, fullText: String) {
        storage.addAttributes(fencedCodeAttributes, range: match.range)

        let codeRange = match.range(at: 2)
        guard codeRange.location != NSNotFound else {
            return
        }

        let languageRange = match.range(at: 1)
        let language: String
        if languageRange.location == NSNotFound {
            language = ""
        } else {
            language = (fullText as NSString).substring(with: languageRange).lowercased()
        }

        applyCodeTokenColors(in: storage, fullText: fullText, codeRange: codeRange, language: language)
    }

    private func applyCodeTokenColors(in storage: NSTextStorage, fullText: String, codeRange: NSRange, language: String) {
        applyRegex(codeNumberRegex, attributes: codeNumberAttributes, in: storage, fullText: fullText, range: codeRange)

        switch language {
        case "yaml", "yml":
            applyRegex(yamlLiteralRegex, attributes: codeKeywordAttributes, in: storage, fullText: fullText, range: codeRange)
            applyRegex(yamlKeyRegex, attributes: codePropertyAttributes, in: storage, fullText: fullText, range: codeRange, captureGroup: 1)
            applyRegex(hashCommentRegex, attributes: codeCommentAttributes, in: storage, fullText: fullText, range: codeRange)
        case "swift":
            applyRegex(swiftKeywordRegex, attributes: codeKeywordAttributes, in: storage, fullText: fullText, range: codeRange)
            applyRegex(codeBlockCommentRegex, attributes: codeCommentAttributes, in: storage, fullText: fullText, range: codeRange)
            applyRegex(codeLineCommentRegex, attributes: codeCommentAttributes, in: storage, fullText: fullText, range: codeRange)
        case "bash", "sh", "zsh", "shell":
            applyRegex(hashCommentRegex, attributes: codeCommentAttributes, in: storage, fullText: fullText, range: codeRange)
            applyRegex(genericKeywordRegex, attributes: codeKeywordAttributes, in: storage, fullText: fullText, range: codeRange)
        case "js", "mjs", "cjs", "jsx", "ts", "tsx", "typescript", "javascript", "json", "jsonc":
            applyRegex(jsKeywordRegex, attributes: codeKeywordAttributes, in: storage, fullText: fullText, range: codeRange)
            applyRegex(codeBlockCommentRegex, attributes: codeCommentAttributes, in: storage, fullText: fullText, range: codeRange)
            applyRegex(codeLineCommentRegex, attributes: codeCommentAttributes, in: storage, fullText: fullText, range: codeRange)
        default:
            applyRegex(genericKeywordRegex, attributes: codeKeywordAttributes, in: storage, fullText: fullText, range: codeRange)
            applyRegex(codeBlockCommentRegex, attributes: codeCommentAttributes, in: storage, fullText: fullText, range: codeRange)
            applyRegex(codeLineCommentRegex, attributes: codeCommentAttributes, in: storage, fullText: fullText, range: codeRange)
            applyRegex(hashCommentRegex, attributes: codeCommentAttributes, in: storage, fullText: fullText, range: codeRange)
        }

        applyRegex(codeStringRegex, attributes: codeStringAttributes, in: storage, fullText: fullText, range: codeRange)
    }

    private func applyRegex(_ regex: NSRegularExpression, attributes: [NSAttributedString.Key: Any], in storage: NSTextStorage, fullText: String, range: NSRange, captureGroup: Int = 0) {
        for match in regex.matches(in: fullText, range: range) {
            let matchRange = match.range(at: captureGroup)
            guard matchRange.location != NSNotFound else {
                continue
            }

            storage.addAttributes(attributes, range: matchRange)
        }
    }

    private func headingAttributes(for level: Int) -> [NSAttributedString.Key: Any] {
        let size: CGFloat
        switch level {
        case 1:
            size = 20
        case 2:
            size = 18
        case 3:
            size = 16.5
        case 4:
            size = 15.5
        default:
            size = 15
        }

        return [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: .semibold),
            .foregroundColor: ClearancePalette.heading
        ]
    }
}

private enum ClearancePalette {
    static let editorBackground = dynamic(light: hex(0xF3F5F9), dark: hex(0x0E1118))
    static let text = dynamic(light: hex(0x1F2733), dark: hex(0xD5DEEB))
    static let secondaryText = dynamic(light: hex(0x5C697C), dark: hex(0x97A5BA))
    static let heading = dynamic(light: hex(0x2C62D6), dark: hex(0x8CA8FF))
    static let frontmatter = dynamic(light: hex(0x0E7490), dark: hex(0x7AD0C8))
    static let listMarker = dynamic(light: hex(0xCB7A1A), dark: hex(0xF2B46B))
    static let link = dynamic(light: hex(0x2F6FE0), dark: hex(0x90B2FF))
    static let inlineCodeText = dynamic(light: hex(0x2757A8), dark: hex(0xA6C7FF))
    static let inlineCodeBackground = dynamic(light: hex(0x2F6FE0, alpha: 0.14), dark: hex(0x779DDC, alpha: 0.22))
    static let codeBlockText = dynamic(light: hex(0xD5E2FF), dark: hex(0xDCE6FF))
    static let codeBlockBackground = dynamic(light: hex(0x0F172A), dark: hex(0x0A1020))
    static let insertionPoint = dynamic(light: hex(0x2F6FE0), dark: hex(0x90B2FF))
    static let selectionBackground = dynamic(light: hex(0x2F6FE0, alpha: 0.28), dark: hex(0x4B6290, alpha: 0.35))
    static let selectionText = dynamic(light: hex(0x0B1220), dark: hex(0xF3F5F9))
    static let syntaxComment = dynamic(light: hex(0x7C8AA0), dark: hex(0x8FA2C2))
    static let syntaxKeyword = dynamic(light: hex(0x7A3FE0), dark: hex(0xB39BFF))
    static let syntaxString = dynamic(light: hex(0x0B7A65), dark: hex(0x7DD7B8))
    static let syntaxNumber = dynamic(light: hex(0xB05A00), dark: hex(0xFFB86B))
    static let syntaxProperty = dynamic(light: hex(0x2A6BB5), dark: hex(0x8CB8FF))

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            if match == .darkAqua {
                return dark
            }
            return light
        }
    }

    private static func hex(_ value: UInt32, alpha: CGFloat = 1.0) -> NSColor {
        let red = CGFloat((value >> 16) & 0xFF) / 255.0
        let green = CGFloat((value >> 8) & 0xFF) / 255.0
        let blue = CGFloat(value & 0xFF) / 255.0
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}
