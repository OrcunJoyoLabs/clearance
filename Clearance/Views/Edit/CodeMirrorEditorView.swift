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
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.delegate = context.coordinator
        textView.string = text

        context.coordinator.textView = textView
        context.coordinator.highlighter.apply(to: textView)

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
    }
}

final class EditorTextView: NSTextView {
    private lazy var editorUndoManager: UndoManager = {
        let manager = UndoManager()
        manager.levelsOfUndo = 100_000
        return manager
    }()

    override var undoManager: UndoManager? {
        editorUndoManager
    }
}

@MainActor
final class MarkdownSyntaxHighlighter {
    private let headingRegex = try! NSRegularExpression(pattern: "(?m)^(#{1,6})\\s+(.+)$")
    private let frontmatterRegex = try! NSRegularExpression(pattern: "(?s)\\A---\\n.*?\\n---\\n?")
    private let fencedCodeRegex = try! NSRegularExpression(pattern: "(?s)```[^\\n]*\\n.*?\\n```")
    private let inlineCodeRegex = try! NSRegularExpression(pattern: "`[^`\\n]+`")
    private let linkRegex = try! NSRegularExpression(pattern: "\\[[^\\]]+\\]\\([^\\)]+\\)")
    private let strongRegex = try! NSRegularExpression(pattern: "(\\*\\*|__)(?=\\S)(.+?\\S)\\1")
    private let emphasisRegex = try! NSRegularExpression(pattern: "(\\*|_)(?=\\S)(.+?\\S)\\1")
    private let blockquoteRegex = try! NSRegularExpression(pattern: "(?m)^>.*$")
    private let listMarkerRegex = try! NSRegularExpression(pattern: "(?m)^\\s*(?:[-*+] |\\d+\\. )")

    func apply(to textView: NSTextView) {
        guard let storage = textView.textStorage else {
            return
        }

        let fullRange = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: fullRange)

        let fullText = storage.string
        let fullTextRange = NSRange(location: 0, length: (fullText as NSString).length)

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

        for match in fencedCodeRegex.matches(in: fullText, range: fullTextRange) {
            storage.addAttributes(fencedCodeAttributes, range: match.range)
        }

        storage.endEditing()
        textView.typingAttributes = baseAttributes
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]
    }

    private var frontmatterAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular),
            .foregroundColor: NSColor.systemTeal
        ]
    }

    private var blockquoteAttributes: [NSAttributedString.Key: Any] {
        [
            .foregroundColor: NSColor.secondaryLabelColor
        ]
    }

    private var listMarkerAttributes: [NSAttributedString.Key: Any] {
        [
            .foregroundColor: NSColor.systemOrange
        ]
    }

    private var linkAttributes: [NSAttributedString.Key: Any] {
        [
            .foregroundColor: NSColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
    }

    private var strongAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
        ]
    }

    private var emphasisAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFontManager.shared.convert(NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), toHaveTrait: .italicFontMask)
        ]
    }

    private var inlineCodeAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.systemBrown,
            .backgroundColor: NSColor.tertiaryLabelColor.withAlphaComponent(0.16)
        ]
    }

    private var fencedCodeAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.systemBrown,
            .backgroundColor: NSColor.tertiaryLabelColor.withAlphaComponent(0.12)
        ]
    }

    private func headingAttributes(for level: Int) -> [NSAttributedString.Key: Any] {
        let size: CGFloat
        switch level {
        case 1:
            size = 22
        case 2:
            size = 20
        case 3:
            size = 18
        case 4:
            size = 16
        default:
            size = 14
        }

        return [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: .semibold),
            .foregroundColor: NSColor.systemIndigo
        ]
    }
}
