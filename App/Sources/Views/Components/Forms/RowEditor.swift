import AppKit
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 26.0, *)
struct RowEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var browser: DatabaseModel
    let columns: [DatabaseColumn]
    @State var draft: RowDraft
    let submit: (RowDraft) throws -> Void
    @State private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.original == nil ? "new row" : "edit row").font(.title2.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(columns) { column in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(column.name).font(.headline)
                                Text(column.type).font(.caption).foregroundStyle(MokoTheme.secondaryInk)
                                if !column.nullable && column.defaultValue == nil && !column.generated
                                    && !column.extra.lowercased().contains("auto_increment") {
                                    Text("required").font(.caption).foregroundStyle(MokoTheme.secondaryInk)
                                }
                                Spacer()
                                if column.generated {
                                    Text("generated").font(.caption).foregroundStyle(MokoTheme.secondaryInk)
                                }
                            }
                            if !column.generated {
                                HStack {
                                    Toggle(
                                        column.extra.lowercased().contains("auto_increment")
                                            ? "auto-generated" : "use database default",
                                        isOn: modeBinding(column.name, .omitted)
                                    )
                                    .toggleStyle(.switch).controlSize(.small).fixedSize()
                                    .accessibilityLabel("use database default for " + column.name)
                                    if column.nullable {
                                        Toggle("null", isOn: modeBinding(column.name, .null))
                                            .toggleStyle(.switch).controlSize(.small).fixedSize()
                                            .accessibilityLabel("store null in " + column.name)
                                    }
                                    Spacer()
                                }
                            }
                            SQLValueField(column: column, text: binding(column.name).text).disabled(
                                column.generated || draft.values[column.name]?.mode != .value)
                            if !column.generated {
                                Text(
                                    draft.values[column.name]?.mode == .omitted
                                        ? "the database generates or supplies the value"
                                        : ""
                                )
                                .font(.caption).foregroundStyle(MokoTheme.secondaryInk)
                            }
                            if column.binary && !column.generated {
                                Text("hexadecimal bytes, e.g. 0x00ff").font(.caption)
                                    .foregroundStyle(MokoTheme.secondaryInk)
                            }
                        }
                    }
                }.padding(4)
            }.frame(maxHeight: 420).disabled(browser.busy)
            TransientNotice($error, isError: true)
            TransientNotice($browser.error, isError: true)
            HStack {
                Button("cancel") { dismiss() }.disabled(browser.busy)
                Spacer()
                if browser.busy { ProgressView().controlSize(.small) }
                Button("save") {
                    do {
                        try submit(draft)
                        error = ""
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(MokoButtonStyle(prominent: true)).foregroundStyle(MokoTheme.onAccent).tint(
                    MokoTheme.accent
                )
                .disabled(browser.busy)
            }
        }.padding(24).frame(width: 580).foregroundStyle(MokoTheme.ink).tint(MokoTheme.selectionInk)
            .onAppear { browser.error = "" }.interactiveDismissDisabled(browser.busy)
    }
    func binding(_ name: String) -> Binding<CellDraft> {
        Binding(
            get: { draft.values[name] ?? .init(text: "", mode: .value) },
            set: { draft.values[name] = $0 })
    }
    func modeBinding(_ name: String, _ mode: CellMode) -> Binding<Bool> {
        Binding(
            get: { draft.values[name]?.mode == mode },
            set: { enabled in
                var value = draft.values[name] ?? .init(text: "", mode: .value)
                value.mode = enabled ? mode : .value
                draft.values[name] = value
            })
    }
}
