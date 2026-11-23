import SwiftUI

struct PostgreSQLConstraintEditor: View {
    @ObservedObject var browser: DatabaseModel
    @State var draft = PostgreSQLConstraintDraft()
    @State private var referenceTables: [String] = []
    @State private var referenceColumns: [String] = []
    @State private var error = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("new index or constraint").font(.title2.weight(.semibold))
            Text(
                browser.database + (postgres ? " · " + browser.schema + "." : ".") + browser.table
            ).foregroundStyle(MokoTheme.secondaryInk)
            Picker("kind", selection: $draft.kind) {
                ForEach(PostgreSQLConstraintDraft.Kind.allCases) { Text($0.rawValue).tag($0) }
            }
            if postgres || draft.kind != .primaryKey {
                ObjectField("name") {
                    TextField("e.g. items_name_index", text: $draft.name).textFieldStyle(.roundedBorder)
                }
            }
            if draft.kind == .check {
                ObjectField("check expression") {
                    TextField("e.g. amount >= 0", text: $draft.expression).textFieldStyle(.roundedBorder)
                }
            } else {
                columnSelection("columns in selected order", choices: browser.columns.map(\.name), reference: false)
            }
            if draft.kind == .index {
                if postgres {
                    Picker("method", selection: $draft.method) {
                        ForEach(["btree", "hash", "gin", "gist", "spgist", "brin"], id: \.self) { Text($0).tag($0) }
                    }
                }
                Toggle("unique", isOn: $draft.uniqueIndex).toggleStyle(.switch)
            } else if draft.kind != .check && postgres {
                Toggle("deferrable", isOn: $draft.deferrable).toggleStyle(.switch)
            }
            if draft.kind == .foreignKey { referenceFields }
            TransientNotice($error, isError: true)
            TransientNotice($browser.error, isError: true)
            HStack {
                Button("cancel") { dismiss() }
                Spacer()
                if browser.busy { ProgressView().controlSize(.small) }
                Button("create") { save() }.buttonStyle(MokoButtonStyle(prominent: true))
                    .disabled(browser.busy || (draft.name.isEmpty && (postgres || draft.kind != .primaryKey)))
            }
        }.padding(24).frame(width: 560).foregroundStyle(MokoTheme.ink).background(MokoTheme.canvas)
            .buttonStyle(MokoButtonStyle()).tint(MokoTheme.selectionInk).disabled(browser.busy)
            .interactiveDismissDisabled(browser.busy)
            .onAppear { draft.referenceSchema = browser.schema }
            .task(id: draft.kind) {
                if draft.kind == .foreignKey {
                    await loadReferences()
                    await loadColumns()
                }
            }
            .task(id: draft.referenceSchema) { if draft.kind == .foreignKey { await loadReferences() } }
            .task(id: draft.referenceTable) { if draft.kind == .foreignKey { await loadColumns() } }
    }
    private var postgres: Bool { browser.engine.isPostgreSQL }
    private var actions: [String] {
        ["NO ACTION", "RESTRICT", "CASCADE", "SET NULL"] + (postgres ? ["SET DEFAULT"] : [])
    }
    private var referenceFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            if postgres {
                Picker("referenced schema", selection: $draft.referenceSchema) {
                    ForEach(browser.schemas, id: \.self) { Text($0).tag($0) }
                }
            }
            Picker("referenced table", selection: $draft.referenceTable) {
                Text("select a table").tag("")
                ForEach(referenceTables, id: \.self) { Text($0).tag($0) }
            }
            columnSelection("referenced columns in matching order", choices: referenceColumns, reference: true)
            HStack {
                actionPicker("on delete", selection: $draft.onDelete)
                actionPicker("on update", selection: $draft.onUpdate)
            }
        }
    }
    private func actionPicker(_ label: String, selection: Binding<String>) -> some View {
        Picker(label, selection: selection) {
            ForEach(actions, id: \.self) {
                Text($0.lowercased()).tag($0)
            }
        }
    }
    private func columnSelection(_ label: String, choices: [String], reference: Bool) -> some View {
        let selected = reference ? draft.referenceColumns : draft.columns
        return ObjectField(label) {
            HStack {
                Text(selected.isEmpty ? "none selected" : selected.joined(separator: ", "))
                    .foregroundStyle(selected.isEmpty ? MokoTheme.secondaryInk : MokoTheme.ink).lineLimit(2)
                Spacer()
                Menu("choose columns") {
                    ForEach(choices, id: \.self) { column in
                        Toggle(
                            column,
                            isOn: Binding(
                                get: { selected.contains(column) },
                                set: { value in
                                    draft.select(column, selected: value, reference: reference)
                                }))
                    }
                }.disabled(choices.isEmpty)
            }
        }
    }
    private func loadReferences() async {
        #if DEBUG
            if PreviewRuntime.isActive {
                referenceTables = ["customers", "orders"]
                return
            }
        #endif
        guard let connection = browser.connection else { return }
        guard postgres else {
            referenceTables = browser.tables.filter { !$0.isView }.map(\.name)
            return
        }
        let schema = draft.referenceSchema, database = browser.database
        let response = await Task.detached {
            connection.execute(PostgreSQLSQL.tables(schema: schema), database: database)
        }.value
        guard !Task.isCancelled, schema == draft.referenceSchema else { return }
        referenceTables =
            response.results.first.map { rows in
                rows.rows.indices.compactMap { rows.text($0, 1) == "BASE TABLE" ? rows.text($0, 0) : nil }
            } ?? []
        if !referenceTables.contains(draft.referenceTable) {
            draft.referenceTable = ""
            draft.referenceColumns = []
        }
        if !response.succeeded { error = response.error }
    }
    private func loadColumns() async {
        #if DEBUG
            if PreviewRuntime.isActive {
                referenceColumns = ["id", "email"]
                return
            }
        #endif
        guard let connection = browser.connection, !draft.referenceTable.isEmpty else {
            referenceColumns = []
            return
        }
        let table = draft.referenceTable, schema = draft.referenceSchema, database = browser.database
        let postgres = postgres
        let response = await Task.detached {
            postgres
                ? connection.execute(
                    PostgreSQLSQL.metadata(schema: schema, table: table), database: database, multiple: true)
                : connection.execute(
                    "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = "
                        + DatabaseSQL.literal(database) + " AND TABLE_NAME = " + DatabaseSQL.literal(table)
                        + " ORDER BY ORDINAL_POSITION;", database: database)
        }.value
        guard !Task.isCancelled, table == draft.referenceTable, schema == draft.referenceSchema else { return }
        referenceColumns =
            response.results.first.map { rows in rows.rows.indices.compactMap { rows.text($0, 0) } } ?? []
        draft.referenceColumns.removeAll { !referenceColumns.contains($0) }
        if !response.succeeded { error = response.error }
    }
    private func save() {
        do {
            let plan =
                try postgres
                ? draft.plan(location: browser.location, table: browser.table)
                : draft.mysqlPlan(database: browser.database, table: browser.table)
            browser.apply(plan) { if $0 { dismiss() } }
        } catch { self.error = error.localizedDescription }
    }
}
