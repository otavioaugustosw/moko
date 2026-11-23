import AppKit
import SwiftUI

struct SQLBodyEditor: NSViewRepresentable {
    @Binding var text: String
    var parameters: [String] = []
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var enabled
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let editor = ParameterTextView(usingTextLayoutManager: true)
        editor.delegate = context.coordinator
        editor.completionFinished = { [weak coordinator = context.coordinator] in coordinator?.commitCompletion($0) }
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isGrammarCheckingEnabled = false
        editor.allowsUndo = true
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width: 10, height: 10)
        editor.setAccessibilityLabel("sql body")
        let scroll = NSScrollView()
        scroll.documentView = editor
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? ParameterTextView else { return }
        let coordinator = context.coordinator
        let restyle =
            coordinator.parent.parameters != parameters || coordinator.lastScheme != colorScheme
            || editor.string != text
        coordinator.updating = true
        defer { coordinator.updating = false }
        coordinator.parent = self
        editor.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        editor.backgroundColor = MokoTheme.native("Surface")
        editor.isEditable = enabled
        editor.insertionPointColor = MokoTheme.native("SelectionInk")
        if editor.string != text {
            let selection = editor.selectedRange()
            editor.string = text
            let location = min(selection.location, text.utf16.count)
            editor.setSelectedRange(
                NSRange(location: location, length: min(selection.length, text.utf16.count - location)))
        }
        if restyle || coordinator.lastScheme == nil { coordinator.highlight(editor) }
        coordinator.lastScheme = colorScheme
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SQLBodyEditor
        var updating = false
        var lastScheme: ColorScheme?
        private var completionWork: DispatchWorkItem?
        init(_ parent: SQLBodyEditor) { self.parent = parent }
        func highlight(_ editor: NSTextView) {
            guard let storage = editor.textStorage else { return }
            let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: MokoTheme.native("Ink")]
            storage.beginEditing()
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
            for range in SQLParameterSyntax.highlights(editor.string, parameters: parent.parameters) {
                storage.addAttributes(
                    [
                        .foregroundColor: MokoTheme.native("SelectionInk"),
                        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
                    ], range: range)
            }
            storage.endEditing()
            editor.typingAttributes = attributes
        }
        func textDidChange(_ notification: Notification) {
            guard !updating, let editor = notification.object as? ParameterTextView, !editor.applyingCompletion else {
                return
            }
            parent.text = editor.string
            highlight(editor)
            completionWork?.cancel()
            guard !editor.applyingCompletion, editor.selectedRange().length == 0,
                SQLParameterSyntax.completion(
                    editor.string, caret: editor.selectedRange().location,
                    parameters: parent.parameters) != nil
            else { return }
            let work = DispatchWorkItem { [weak editor] in
                guard let editor, editor.window?.firstResponder === editor else { return }
                editor.complete(nil)
            }
            completionWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }
        func commitCompletion(_ editor: ParameterTextView) {
            guard !updating else { return }
            parent.text = editor.string
            highlight(editor)
        }
        func textView(
            _ textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange,
            indexOfSelectedItem index: UnsafeMutablePointer<Int>?
        ) -> [String] {
            index?.pointee = -1
            guard
                let completion = SQLParameterSyntax.completion(
                    textView.string, caret: NSMaxRange(charRange),
                    parameters: parent.parameters),
                completion.range == charRange
            else { return [] }
            return completion.suggestions
        }
        deinit { completionWork?.cancel() }
    }
}

final class ParameterTextView: NSTextView {
    var applyingCompletion = false
    var completionFinished: ((ParameterTextView) -> Void)?
    override func insertCompletion(
        _ word: String, forPartialWordRange charRange: NSRange, movement: Int, isFinal flag: Bool
    ) {
        applyingCompletion = true
        super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: flag)
        applyingCompletion = false
        if flag { completionFinished?(self) }
    }
}
