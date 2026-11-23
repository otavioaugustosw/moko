import SwiftUI

@available(macOS 26.0, *)
struct NewTableView: View {
    @ObservedObject var browser: DatabaseModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = NewTableDraft()
    @State private var error = ""
    private let mysqlTypes = [
        "bigint", "int", "smallint", "tinyint", "varchar", "char", "text", "longtext",
        "decimal", "double", "boolean", "date", "datetime", "timestamp", "time", "json", "blob", "varbinary",
    ]
    private var types: [String] { browser.engine.isPostgreSQL ? PostgreSQLSQL.types : mysqlTypes }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("new table").font(.title2.weight(.semibold))
            Text(browser.database).font(.callout).foregroundStyle(MokoTheme.secondaryInk)
            TextField("table name", text: $draft.name).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach($draft.columns) { $column in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("column name", text: $column.name).frame(minWidth: 120)
                                Picker("type", selection: $column.type) {
                                    ForEach(types, id: \.self) { Text($0).tag($0) }
                                }.labelsHidden().frame(width: 140)
                                TextField("size", text: $column.size).frame(width: 70).disabled(!column.hasSize)
                                Button(role: .destructive) {
                                    draft.columns.removeAll { $0.id == column.id }
                                } label: {
                                    Image(systemName: "trash")
                                }.help("remove column")
                            }
                            HStack(spacing: 20) {
                                Toggle("nullable", isOn: $column.nullable).disabled(column.primary)
                                Toggle("primary key", isOn: $column.primary)
                                Toggle(
                                    browser.engine.isPostgreSQL ? "identity" : "auto increment",
                                    isOn: $column.autoIncrement)
                                if !browser.engine.isPostgreSQL { Toggle("unsigned", isOn: $column.unsigned) }
                            }.font(.caption).toggleStyle(.checkbox)
                        }.padding(12).background(MokoTheme.sidebar, in: RoundedRectangle(cornerRadius: 10))
                            .onChange(of: column.type) {
                                switch column.type {
                                case "varchar", "varbinary": column.size = "255"
                                case "char": column.size = "1"
                                case "decimal", "numeric": column.size = "12,2"
                                default: column.size = ""
                                }
                                if browser.engine.isPostgreSQL
                                    && !["smallint", "integer", "bigint"].contains(column.type) {
                                    column.autoIncrement = false
                                }
                            }
                            .onChange(of: column.primary) { if column.primary { column.nullable = false } }
                            .onChange(of: column.autoIncrement) {
                                if column.autoIncrement {
                                    column.primary = true
                                    column.nullable = false
                                }
                            }
                    }
                }
            }.frame(height: 300).disabled(browser.busy)
            Button("add column", systemImage: "plus") { draft.columns.append(.init()) }.disabled(browser.busy)
            TransientNotice($error, isError: true)
            TransientNotice($browser.error, isError: true)
            HStack {
                Button("cancel") { dismiss() }.disabled(browser.busy)
                Spacer()
                if browser.busy { ProgressView().controlSize(.small) }
                Button("create table") { save() }.buttonStyle(MokoButtonStyle(prominent: true)).foregroundStyle(
                    MokoTheme.onAccent
                )
                .disabled(browser.busy || draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }.padding(24).frame(width: 700).foregroundStyle(MokoTheme.ink).background(MokoTheme.canvas)
            .tint(MokoTheme.selectionInk).buttonStyle(MokoButtonStyle())
            .textFieldStyle(.roundedBorder).interactiveDismissDisabled(browser.busy)
    }
    private func save() {
        do {
            let plan = try draft.plan(database: browser.database, engine: browser.engine, schema: browser.schema)
            error = ""
            browser.apply(plan) { success in
                if success {
                    browser.table = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    browser.tab = "data"
                    dismiss()
                }
            }
        } catch { self.error = error.localizedDescription }
    }
}
