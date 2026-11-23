import AppKit
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 26.0, *)
struct SQLTemporalEditor: View {
    let name: String
    let kind: SQLTemporalKind
    @State private var text: String
    @State private var date: Date
    @State private var busy = false
    @State private var error = ""
    let saveTitle: String
    let save: (String, @escaping (String?) -> Void) -> Void
    let close: () -> Void
    init(
        name: String, kind: SQLTemporalKind, value: String, saveTitle: String = "save",
        save: @escaping (String, @escaping (String?) -> Void) -> Void, close: @escaping () -> Void
    ) {
        self.name = name
        self.kind = kind
        self.saveTitle = saveTitle
        self.save = save
        self.close = close
        _text = State(initialValue: value)
        _date = State(initialValue: kind.parse(value) ?? Date())
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(name).font(.headline)
            NativeSQLDatePicker(
                kind: kind,
                value: Binding(
                    get: { date },
                    set: {
                        date = $0
                        text = kind.string($0, preserving: text)
                    })
            )
            .frame(width: kind == .datetime ? 320 : 160, height: 165).frame(maxWidth: .infinity)
            TextField(kind.format.lowercased(), text: $text).textFieldStyle(.roundedBorder).font(
                .system(.callout, design: .monospaced)
            )
            .onChange(of: text) { if let parsed = kind.parse(text) { date = parsed } }
            if !SQLTemporalKind.timeZoneSuffix(text).isEmpty {
                Text("time zone offset · " + SQLTemporalKind.timeZoneSuffix(text)).font(.caption)
                    .foregroundStyle(MokoTheme.secondaryInk)
            }
            if kind.parse(text) == nil && !text.isEmpty {
                Text("edit this value in the text field").font(.caption)
                    .foregroundStyle(MokoTheme.secondaryInk)
            }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(MokoTheme.errorInk) }
            HStack {
                Button("cancel", action: close)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button(saveTitle) {
                    if text.isEmpty { text = kind.string(date, preserving: "") }
                    busy = true
                    error = ""
                    save(text) { failure in
                        busy = false
                        if let failure { error = failure } else { close() }
                    }
                }.buttonStyle(MokoButtonStyle(prominent: true)).tint(MokoTheme.accent).foregroundStyle(
                    MokoTheme.onAccent)
            }
        }.padding(16).frame(width: kind == .datetime ? 380 : 260).disabled(busy).foregroundStyle(
            MokoTheme.ink)
    }
}
