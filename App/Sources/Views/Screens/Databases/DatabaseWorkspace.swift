import AppKit
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 26.0, *)
struct DatabaseWorkspace: View {
    @ObservedObject var server: WorkspaceModel
    @ObservedObject var browser: DatabaseModel
    @ObservedObject private var objects: DatabaseObjectLibrary
    @StateObject var exporter = DatabaseExporter()
    @StateObject var importer = DatabaseImporter()
    @State var importFile: URL?
    @State var selectedRow: Int?
    @State var rowDraft: RowDraft?
    @State var plan: SQLPlan?
    @State var columnEditor: ColumnEditorDraft?
    @State var postgresColumn: PostgreSQLColumnDraft?
    @State var newDatabase = false
    @State var newTable = false
    @State var newConstraint = false
    @State var renamingTable = false
    @State var tableName = ""
    @State var databaseName = ""
    @State var formError = ""
    @State var selectedColumn: String?
    @State private var objectDraft: NewDatabaseObjectDraft?
    init(server: WorkspaceModel, browser: DatabaseModel) {
        self.server = server
        self.browser = browser
        _objects = ObservedObject(wrappedValue: browser.objects)
    }
    var editing: Bool {
        rowDraft != nil || columnEditor != nil || postgresColumn != nil || newDatabase || newTable || plan != nil
            || objectDraft != nil || newConstraint || renamingTable
    }
    var endpoint: DatabaseConnection? {
        server.connected ? server.currentConnection : nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !server.connected {
                Label(
                    "connect to a server in settings → connection",
                    systemImage: "externaldrive.badge.exclamationmark"
                ).foregroundStyle(MokoTheme.secondaryInk)
            } else {
                HStack(spacing: 12) {
                    Button {
                        browser.reloadDatabases()
                    } label: {
                        Label("refresh", systemImage: "arrow.clockwise")
                    }.buttonStyle(MokoButtonStyle())
                    Button {
                        databaseName = ""
                        browser.error = ""
                        newDatabase = true
                    } label: {
                        Label("new database", systemImage: "plus")
                    }.buttonStyle(MokoButtonStyle())
                    if !browser.database.isEmpty {
                        Button("new table", systemImage: "plus") { newTable = true }.buttonStyle(MokoButtonStyle())
                        Menu {
                            ForEach(objects.kinds) { kind in
                                Button("new " + kind.rawValue) { objectDraft = .init(kind: kind) }
                            }
                        } label: {
                            Label("new object", systemImage: "plus")
                                .font(.system(size: 13, weight: .medium))
                        }.menuStyle(.borderlessButton).buttonStyle(.plain).fixedSize()
                            .padding(.horizontal, 12).frame(height: 34).foregroundStyle(MokoTheme.ink).tint(
                                MokoTheme.ink
                            )
                            .background(MokoTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(MokoTheme.separator, lineWidth: 1))
                            .disabled(!objects.writable)
                    }
                    Spacer()
                    if browser.busy {
                        ProgressView().controlSize(.small).accessibilityLabel("loading database")
                    }
                }.disabled(browser.busy)
                VStack(alignment: .leading, spacing: 16) {
                    if objects.selected != nil {
                        HStack {
                            Button("back to tables", systemImage: "chevron.left") { objects.clearSelection() }
                            Spacer()
                            databaseExportMenu
                            Button("open sql editor") {
                                objects.clearSelection()
                                browser.tab = "sql"
                            }
                        }.disabled(objects.busy)
                        DatabaseObjectWorkspace(
                            library: objects, viewData: { browser.loadTable($0) }, feedbackVisible: !editing)
                    } else {
                        tableContent
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !editing {
                    VStack(spacing: 0) {
                        TransientNotice($browser.error, isError: true)
                        TransientNotice($browser.message)
                        TransientNotice($formError, isError: true)
                        TransientNotice($exporter.error, isError: true)
                        TransientNotice($exporter.message)
                        TransientNotice($importer.error, isError: true)
                        TransientNotice($importer.message)
                        if objects.selected == nil {
                            TransientNotice(text: objects.error, isError: true, dismissMatching: objects.dismissError)
                            TransientNotice(text: objects.message, dismissMatching: objects.dismissMessage)
                        }
                    }
                }
            }
        }
        .tint(MokoTheme.selectionInk)
        .task(id: endpoint) {
            browser.configure(endpoint)
            browser.setWorkspaceVisible(true)
            selectedRow = nil
            rowDraft = nil
            plan = nil
            columnEditor = nil
        }
        .sheet(item: Binding(get: { importFile.map { ImportSelection(url: $0) } }, set: { importFile = $0?.url })) { selection in
            DestructiveReview(
                title: "import into " + browser.database,
                message: """
                    a backup is saved before import. the file must use this engine's sql.
                    postgresql uses a transaction; mariadb/mysql ddl may remain applied after an error.
                    no conversion between engines is performed.
                    only import trusted files. qualified objects and routines keep their original references
                    and run with this account's permissions. database switching and client commands are blocked.
                    """,
                actionTitle: "back up & import", cancel: { importFile = nil },
                confirm: {
                    if let connection = endpoint {
                        importer.start(selection.url, connection: connection, database: browser.database) {
                            browser.reloadDatabases()
                        }
                    }
                    importFile = nil
                })
        }
        .onDisappear {
            browser.setWorkspaceVisible(false)
            browser.setEditorVisible(false)
        }
        .onChange(of: editing) { browser.setEditorVisible(editing) }
        .onChange(of: browser.table) {
            selectedRow = nil
            selectedColumn = nil
        }
        .onChange(of: browser.data) { old, next in
            guard let selectedRow, let old, old.cells.indices.contains(selectedRow), let next else {
                self.selectedRow = nil
                return
            }
            let primary = browser.columns.indices.filter { browser.columns[$0].key == "PRI" }
            let identity = old.cells[selectedRow]
            self.selectedRow = next.cells.prefix(browser.pageSize).firstIndex { row in
                if primary.isEmpty { return row == identity }
                return primary.allSatisfy {
                    row.indices.contains($0) && identity.indices.contains($0)
                        && row[$0] == identity[$0]
                }
            }
        }
        .sheet(item: $rowDraft) { draft in
            RowEditor(browser: browser, columns: browser.columns, draft: draft) { updated in
                let generated = try browser.rowPlan(updated)
                formError = ""
                browser.apply(generated) { if $0 { rowDraft = nil } }
            }
        }
        .sheet(item: $postgresColumn) { draft in
            PostgreSQLColumnEditor(browser: browser, draft: draft)
        }
        .sheet(item: $columnEditor) { draft in
            ColumnEditor(browser: browser, draft: draft) { updated in
                let generated = try DatabaseSQL.columnPlan(
                    database: browser.database, table: browser.table, draft: updated)
                browser.apply(generated) { if $0 { columnEditor = nil } }
            }
        }
        .sheet(isPresented: $newTable) { NewTableView(browser: browser) }
        .sheet(isPresented: $newConstraint) { PostgreSQLConstraintEditor(browser: browser) }
        .sheet(isPresented: $newDatabase) {
            newDatabaseForm
        }
        .sheet(isPresented: $renamingTable) {
            renameTableForm
        }
        .sheet(item: $objectDraft) { draft in
            NewDatabaseObjectView(library: objects, tables: browser.tables, draft: draft) {
                objectDraft = nil
                browser.reloadTables()
            }
        }
        .sheet(item: $plan) { current in
            DatabaseConfirmation(plan: current, browser: browser) { plan = nil }
        }
    }
    @ViewBuilder
    private var tableContent: some View {
        if !browser.database.isEmpty { toolbar }
        if !browser.database.isEmpty || browser.tab == "sql" {
            Picker("view", selection: $browser.tab) {
                Text("data").tag("data")
                Text("structure").tag("structure")
                Text("sql").tag("sql")
            }.pickerStyle(.segmented).labelsHidden()
            switch browser.tab {
            case "sql": ScrollView { sqlEditor }
            case "structure":
                if !browser.table.isEmpty {
                    ScrollView { structure }
                } else {
                    Text("select a table").foregroundStyle(MokoTheme.secondaryInk)
                }
            default:
                if !browser.table.isEmpty {
                    records
                } else {
                    Text("select a table").foregroundStyle(MokoTheme.secondaryInk)
                }
            }
        } else if !browser.database.isEmpty {
            Text(
                browser.tables.isEmpty && !browser.busy
                    ? "no tables in this database" : "select a table"
            ).foregroundStyle(MokoTheme.secondaryInk).padding(.vertical, 28)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text("select a database").foregroundStyle(MokoTheme.secondaryInk)
                Button("open sql editor") { browser.tab = "sql" }.buttonStyle(MokoButtonStyle())
            }.padding(.vertical, 28)
        }
    }
    var newDatabaseForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("new database").font(.title2.weight(.semibold))
            TextField("name", text: $databaseName).textFieldStyle(.roundedBorder)
            TransientNotice($browser.error, isError: true)
            HStack {
                Button("cancel") { newDatabase = false }.disabled(browser.busy)
                Spacer()
                if browser.busy { ProgressView().controlSize(.small) }
                Button("create") {
                    browser.apply(
                        .init(
                            title: "create database",
                            sql:
                                "CREATE DATABASE \(browser.identifier(databaseName))"
                                + (browser.engine.isPostgreSQL ? "" : " CHARACTER SET utf8mb4") + ";",
                            database: "")
                    ) { if $0 { newDatabase = false } }
                }.disabled(
                    browser.busy || databaseName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }.padding(24).frame(width: 420).foregroundStyle(MokoTheme.ink).tint(
            MokoTheme.selectionInk)
    }
    var renameTableForm: some View {
        let name = tableName.trimmingCharacters(in: .whitespaces)
        return VStack(alignment: .leading, spacing: 16) {
            Text("rename table").font(.title2.weight(.semibold))
            TextField("name", text: $tableName).textFieldStyle(.roundedBorder)
                .accessibilityLabel("new table name")
            TransientNotice($browser.error, isError: true)
            HStack {
                Button("cancel") { renamingTable = false }.disabled(browser.busy)
                Spacer()
                if browser.busy { ProgressView().controlSize(.small) }
                Button("rename") {
                    browser.apply(browser.renameTablePlan(to: name)) { if $0 { renamingTable = false } }
                }.disabled(browser.busy || name.isEmpty || name == browser.table)
            }
        }.padding(24).frame(width: 420).foregroundStyle(MokoTheme.ink).tint(
            MokoTheme.selectionInk)
    }
    var toolbar: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(browser.table.isEmpty ? browser.database : browser.table).font(.headline)
                    .textSelection(.enabled).lineLimit(1)
                if !browser.table.isEmpty {
                    Text(
                        browser.database
                            + (browser.selectedTable?.isView == true
                                ? " · view" : " · " + (browser.selectedTable?.engine ?? ""))
                    ).font(.caption).foregroundStyle(MokoTheme.secondaryInk).lineLimit(1)
                }
            }
            Spacer()
            Menu {
                databaseExportMenuItem
                databaseImportMenuItem
                Divider()
                Button("new table") { newTable = true }
                if !browser.table.isEmpty {
                    Button("copy create table") { copy(browser.ddl) }
                    Button("rename table") {
                        tableName = browser.table
                        browser.error = ""
                        renamingTable = true
                    }.disabled(!browser.writable)
                    Divider()
                    Button("empty table", role: .destructive) { plan = browser.emptyTablePlan }
                        .disabled(!browser.writable)
                    Button("delete table", role: .destructive) {
                        plan = .init(
                            title: "delete table",
                            sql:
                                "DROP \(browser.selectedTable?.isView == true ? "VIEW" : "TABLE") \(browser.qualifiedTable);",
                            database: browser.database, destructive: true,
                            summary: browser.database + "." + browser.table)
                    }.disabled(!browser.writable)
                }
                Divider()
                Button("delete database", role: .destructive) {
                    plan = .init(
                        title: "delete database",
                        sql: "DROP DATABASE \(browser.identifier(browser.database));",
                        database: "", destructive: true, summary: browser.database)
                }.disabled(browser.engine.protectedDatabases.contains(browser.database))
            } label: {
                Image(systemName: "ellipsis").accessibilityLabel("database and table actions")
            }.menuStyle(.borderlessButton).buttonStyle(.plain).fixedSize().foregroundStyle(MokoTheme.ink).tint(
                MokoTheme.ink)
        }.disabled(browser.busy)
    }
}
