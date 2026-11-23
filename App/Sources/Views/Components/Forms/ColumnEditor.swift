import AppKit
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 26.0, *)
struct ColumnEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var browser: DatabaseModel
    @State var draft: ColumnEditorDraft
    let submit: (ColumnEditorDraft) throws -> Void
    @State private var error = ""
    @State private var reviewingRisk = false
    var types: [String] {
        Array(
            Set([
                draft.typeName, "tinyint", "smallint", "mediumint", "int", "bigint", "decimal",
                "float", "double", "boolean", "bit", "char", "varchar", "text", "mediumtext",
                "longtext", "binary", "varbinary", "blob", "mediumblob", "longblob", "date", "time",
                "datetime", "timestamp", "year", "json", "enum", "set", "geometry", "point",
            ])
        ).sorted()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.original == nil ? "new column" : "edit column").font(.title2.weight(.semibold))
            Form {
                TextField("name", text: $draft.name)
                Picker("type", selection: $draft.typeName) {
                    ForEach(types, id: \.self) { Text($0).tag($0) }
                }
                if draft.enumerated {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("allowed values").font(.caption).foregroundStyle(MokoTheme.secondaryInk)
                        TextEditor(text: $draft.choicesText).font(
                            .system(.callout, design: .default)
                        ).frame(height: 74).padding(4).background(
                            .background, in: RoundedRectangle(cornerRadius: 8))
                        Text("one value per line").font(.caption).foregroundStyle(MokoTheme.secondaryInk)
                    }
                } else {
                    TextField(
                        ["decimal", "numeric"].contains(draft.typeName)
                            ? "precision, scale" : "size or precision", text: $draft.parameters
                    ).help("leave empty for the type default")
                }
                Section("modifiers") {
                    Toggle("allow null", isOn: $draft.nullable).help(
                        "allows a missing value, distinct from an empty string")
                    Toggle("unsigned", isOn: $draft.unsigned).disabled(!draft.numeric)
                        .help("allows only nonnegative numbers and changes the numeric range")
                    Toggle("zerofill", isOn: $draft.zerofill).disabled(!draft.numeric)
                        .help("pads displayed numbers with zeros; also enables unsigned")
                    Toggle("auto_increment", isOn: $draft.autoIncrement).disabled(
                        !draft.integer || draft.generated
                    ).help("requires an index on this column")
                    Toggle("invisible", isOn: $draft.invisible)
                        .disabled(browser.columns.first { $0.name == draft.original }?.key == "PRI")
                        .help("excludes this column from select *; primary key columns must remain visible")
                }
                Section("default value") {
                    Picker("default", selection: $draft.defaultMode) {
                        Text("no default").tag(ColumnDefaultMode.none)
                        if draft.nullable { Text("null").tag(ColumnDefaultMode.null) }
                        Text("value").tag(ColumnDefaultMode.value)
                        if ["datetime", "timestamp"].contains(draft.typeName) {
                            Text("current timestamp").tag(ColumnDefaultMode.currentTimestamp)
                        }
                        if draft.preservedExpressionAvailable {
                            Text("existing expression").tag(ColumnDefaultMode.expression)
                        }
                    }.disabled(draft.generated)
                    if draft.defaultMode == .value {
                        TextField("value", text: $draft.defaultText).disabled(draft.generated)
                    }
                    if draft.defaultMode == .expression {
                        Text("the current expression will be preserved").font(.caption).foregroundStyle(
                            MokoTheme.secondaryInk)
                    }
                }
                if draft.textual {
                    TextField("collation", text: $draft.collation).help(
                        "leave empty for the table default")
                }
                TextField("comment", text: $draft.comment)
                if draft.generated {
                    Text("the generated column expression will be preserved").font(.caption)
                        .foregroundStyle(MokoTheme.secondaryInk)
                }
            }.formStyle(.grouped).scrollContentBackground(.hidden).frame(height: 460).disabled(
                browser.busy)
            TransientNotice($error, isError: true)
            TransientNotice($browser.error, isError: true)
            HStack {
                Button("cancel") { dismiss() }.disabled(browser.busy)
                Spacer()
                if browser.busy { ProgressView().controlSize(.small) }
                Button("save") {
                    if draft.changeRisks.isEmpty { save() } else { reviewingRisk = true }
                }.buttonStyle(MokoButtonStyle(prominent: true)).foregroundStyle(MokoTheme.onAccent).tint(
                    MokoTheme.accent
                )
                .disabled(
                    browser.busy
                        || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 570).foregroundStyle(MokoTheme.ink).tint(MokoTheme.selectionInk)
            .onAppear { browser.error = "" }
            .onChange(of: draft.nullable) {
                if !draft.nullable && draft.defaultMode == .null { draft.defaultMode = .none }
            }
            .onChange(of: draft.autoIncrement) {
                if draft.autoIncrement {
                    draft.nullable = false
                    draft.defaultMode = .none
                }
            }
            .onChange(of: draft.zerofill) { if draft.zerofill { draft.unsigned = true } }
            .onChange(of: draft.unsigned) { if !draft.unsigned { draft.zerofill = false } }
            .onChange(of: draft.defaultMode) {
                if draft.defaultMode == .expression {
                    draft.defaultText = draft.preservedDefaultExpression
                }
            }
            .onChange(of: draft.typeName) {
                if !draft.numeric {
                    draft.unsigned = false
                    draft.zerofill = false
                }
                if !draft.integer { draft.autoIncrement = false }
                if !draft.textual { draft.collation = "" }
                switch draft.typeName {
                case "varchar", "varbinary": draft.parameters = "255"
                case "char", "binary": draft.parameters = "1"
                case "decimal", "numeric": draft.parameters = "12,2"
                default: draft.parameters = ""
                }
                if draft.defaultMode == .currentTimestamp
                    && !["timestamp", "datetime"].contains(draft.typeName) {
                    draft.defaultMode = .none
                }
            }
            .interactiveDismissDisabled(browser.busy)
            .sheet(isPresented: $reviewingRisk) {
                DestructiveReview(
                    title: "review column changes",
                    message: draft.changeRisks.joined(separator: "\n")
                        + "\nback up important data before continuing.",
                    cancel: { reviewingRisk = false },
                    confirm: {
                        reviewingRisk = false
                        save()
                    })
            }
    }
    private func save() {
        do {
            try submit(draft)
            error = ""
        } catch { self.error = error.localizedDescription }
    }
}
