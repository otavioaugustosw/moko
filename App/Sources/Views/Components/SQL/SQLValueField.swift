import AppKit
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 26.0, *)
struct SQLValueField: View {
    let column: DatabaseColumn
    @Binding var text: String
    @State private var choosingDate = false
    private var placeholder: String {
        if column.generated { return "calculated" }
        if column.extra.lowercased().contains("auto_increment") { return "auto-generated" }
        switch column.temporal {
        case .date: return "YYYY-MM-DD"
        case .time: return "HH:MM:SS"
        case .datetime: return "YYYY-MM-DD HH:MM:SS"
        default: return "value"
        }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if column.type.lowercased().contains("text") || column.type.lowercased() == "json" {
                TextEditor(text: $text).font(.system(.callout, design: .monospaced)).frame(
                    height: 56
                ).padding(4).border(.quaternary)
                    .accessibilityLabel("value of \(column.name)")
            } else {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder).font(.system(.callout, design: .monospaced))
                    .accessibilityLabel("value of \(column.name)")
            }
            if let kind = column.temporal {
                Button {
                    choosingDate = true
                } label: {
                    Image(systemName: kind == .time ? "clock" : "calendar")
                }
                .buttonStyle(.plain).frame(width: 30, height: 30).contentShape(Rectangle()).help(
                    kind == .time ? "choose time" : "choose date"
                )
                .accessibilityLabel(kind == .time ? "choose time" : "choose date")
                .popover(isPresented: $choosingDate) {
                    SQLTemporalEditor(
                        name: column.name, kind: kind, value: text, saveTitle: "use",
                        save: { value, completed in
                            text = value
                            completed(nil)
                        }, close: { choosingDate = false })
                }
            }
        }
    }
}
