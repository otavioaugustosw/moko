import AppKit
import SwiftUI

@available(macOS 26.0, *)
struct LegalDocumentsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var document = "License"
    private let documents = ["License", "GPL-3.0", "Privacy", "Third Party"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("legal & credits").font(.title2.weight(.semibold))
            Picker("document", selection: $document) {
                ForEach(documents, id: \.self) { name in
                    Text(name.lowercased()).tag(name)
                }
            }.pickerStyle(.segmented)
            LegalDocumentText(contents: contents)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            HStack {
                Button("open component licenses", systemImage: "folder") {
                    NSWorkspace.shared.open(RuntimePaths.root.appendingPathComponent("Licenses"))
                }.buttonStyle(MokoButtonStyle())
                Spacer()
                Button("done") { dismiss() }.buttonStyle(MokoButtonStyle(prominent: true))
                    .keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 720, height: 560)
            .foregroundStyle(MokoTheme.ink).tint(MokoTheme.selectionInk)
    }

    private var contents: String {
        guard
            let url = Bundle.main.resourceURL?.appendingPathComponent("Legal")
                .appendingPathComponent(document + ".txt"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "the documents are included with the packaged application. contact contato@otavioaugustosw.com."
        }
        return text
    }
}

struct LegalDocumentText: NSViewRepresentable {
    let contents: String
    @Environment(\.colorScheme) private var colorScheme
    func makeNSView(context: Context) -> NSScrollView {
        let text = NSTextView(usingTextLayoutManager: true)
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainerInset = NSSize(width: 14, height: 14)
        text.setAccessibilityLabel("document content")
        let scroll = NSScrollView()
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView else { return }
        scroll.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        text.backgroundColor = MokoTheme.native("Surface")
        text.textColor = MokoTheme.native("Ink")
        text.font = .systemFont(ofSize: 13)
        if text.string != contents {
            text.string = contents
            text.setSelectedRange(NSRange(location: 0, length: 0))
            text.scrollRangeToVisible(NSRange(location: 0, length: 0))
        }
    }
}

#Preview("legal documents") {
    LegalDocumentsView()
}
