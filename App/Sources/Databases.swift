import Combine
import DatabaseNative
import Foundation

let nativeDatabaseExecute = moko_database_execute

enum ColumnDefaultMode: String, CaseIterable {
    case none = "no default", null = "null", value = "value", currentTimestamp = "current timestamp", expression =
        "existing expression"
}
struct ColumnEditorValues: Equatable {
    var typeName = "varchar", parameters = "255", choicesText = ""
    var nullable = true, unsigned = false, zerofill = false, autoIncrement = false, invisible = false
    var defaultMode = ColumnDefaultMode.null, defaultText = "", collation = "", comment = ""
}
// Keep SHOW CREATE fragments for attributes the form does not own, including generated
// expressions, ON UPDATE, CHARACTER SET, SRID and engine-specific attributes.
struct ColumnEditorDraft: Identifiable {
    let id = UUID()
    let original: String?
    var name: String
    private var values: ColumnEditorValues
    private let baseline: ColumnEditorValues
    private let parts: ColumnDefinitionParts
    var typeName: String {
        get { values.typeName }
        set { values.typeName = newValue }
    }
    var parameters: String {
        get { values.parameters }
        set { values.parameters = newValue }
    }
    var choicesText: String {
        get { values.choicesText }
        set { values.choicesText = newValue }
    }
    var nullable: Bool {
        get { values.nullable }
        set { values.nullable = newValue }
    }
    var unsigned: Bool {
        get { values.unsigned }
        set { values.unsigned = newValue }
    }
    var zerofill: Bool {
        get { values.zerofill }
        set { values.zerofill = newValue }
    }
    var autoIncrement: Bool {
        get { values.autoIncrement }
        set { values.autoIncrement = newValue }
    }
    var invisible: Bool {
        get { values.invisible }
        set { values.invisible = newValue }
    }
    var defaultMode: ColumnDefaultMode {
        get { values.defaultMode }
        set { values.defaultMode = newValue }
    }
    var defaultText: String {
        get { values.defaultText }
        set { values.defaultText = newValue }
    }
    var collation: String {
        get { values.collation }
        set { values.collation = newValue }
    }
    var comment: String {
        get { values.comment }
        set { values.comment = newValue }
    }
    var generated: Bool { parts.generated }
    var preservedExpressionAvailable: Bool { baseline.defaultMode == .expression }
    var preservedDefaultExpression: String { baseline.defaultText }
    var changeRisks: [String] {
        guard original != nil else { return [] }
        var risks: [String] = []
        if typeName != baseline.typeName {
            risks.append("changing the data type may convert or truncate existing values \n")
        }
        if parameters != baseline.parameters {
            let safeGrowth =
                ["varchar", "char", "varbinary", "binary"].contains(typeName)
                && typeName == baseline.typeName
                && Int(parameters).map { next in Int(baseline.parameters).map { next >= $0 } ?? false } == true
            if !safeGrowth { risks.append("changing size or precision may truncate existing values \n") }
        }
        if choicesText != baseline.choicesText && enumerated {
            let choices = Set(choicesText.components(separatedBy: "\n"))
            if !Set(baseline.choicesText.components(separatedBy: "\n")).isSubset(of: choices) {
                risks.append("removing allowed values may invalidate existing rows")
            }
        }
        if baseline.nullable && !nullable { risks.append("existing null values will no longer be allowed \n") }
        if unsigned != baseline.unsigned { risks.append("changing signedness changes the allowed numeric range \n") }
        if collation != baseline.collation { risks.append("changing collation may affect uniqueness and sorting \n") }
        return risks
    }
    var numeric: Bool {
        [
            "tinyint", "smallint", "mediumint", "int", "integer", "bigint", "decimal", "numeric", "float", "double",
            "real",
        ].contains(typeName.lowercased())
    }
    var integer: Bool {
        ["tinyint", "smallint", "mediumint", "int", "integer", "bigint"].contains(typeName.lowercased())
    }
    var enumerated: Bool { ["enum", "set"].contains(typeName.lowercased()) }
    var textual: Bool {
        ["char", "varchar", "tinytext", "text", "mediumtext", "longtext", "enum", "set"].contains(typeName.lowercased())
    }
    var definition: String { (try? builtDefinition()) ?? parts.source }
    init(original: String?, name: String, definition: String) {
        self.original = original
        self.name = name
        let parsed = ColumnDefinitionParts(definition)
        parts = parsed
        values = parsed.values
        baseline = parsed.values
    }
    func builtDefinition() throws -> String {
        let type = try validatedTypeName()
        var replacements = [(Range<Int>, String)](), appended = [String]()
        func replace(_ attribute: String, _ text: String) {
            if let range = parts.ranges[attribute] {
                replacements.append((range, text))
            } else if !text.isEmpty {
                appended.append(text)
            }
        }
        if typeName != baseline.typeName || parameters != baseline.parameters || choicesText != baseline.choicesText {
            var declaration = type
            if enumerated {
                let choices = choicesText.components(separatedBy: "\n")
                guard !choices.isEmpty else { throw DatabaseError.message("add the allowed values") }
                declaration += "(" + choices.map(DatabaseSQL.ddlString).joined(separator: ",") + ")"
            } else if !parameters.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let size = parameters.trimmingCharacters(in: .whitespacesAndNewlines)
                guard size.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "," || $0.isWhitespace) }) else {
                    throw DatabaseError.message("size and precision may only contain numbers and commas")
                }
                declaration += "(\(size))"
            }
            replace("type", declaration)
        }
        var addedTypeModifiers = [String]()
        if unsigned != baseline.unsigned {
            if parts.ranges["unsigned"] != nil {
                replace("unsigned", unsigned ? "UNSIGNED" : "")
            } else if unsigned {
                addedTypeModifiers.append("UNSIGNED")
            }
        }
        if zerofill != baseline.zerofill {
            if parts.ranges["zerofill"] != nil {
                replace("zerofill", zerofill ? "ZEROFILL" : "")
            } else if zerofill {
                addedTypeModifiers.append("ZEROFILL")
            }
        }
        if !addedTypeModifiers.isEmpty, let typeRange = parts.ranges["type"] {
            // Numeric modifiers belong immediately after the datatype, before
            // NULL/DEFAULT/COMMENT. Insert after any modifier already present.
            let position = max(
                typeRange.upperBound, parts.ranges["unsigned"]?.upperBound ?? 0,
                parts.ranges["zerofill"]?.upperBound ?? 0)
            replacements.append((position..<position, " " + addedTypeModifiers.joined(separator: " ")))
        }
        if nullable != baseline.nullable { replace("nullable", nullable ? "NULL" : "NOT NULL") }
        if autoIncrement != baseline.autoIncrement { replace("autoIncrement", autoIncrement ? "AUTO_INCREMENT" : "") }
        if invisible != baseline.invisible { replace("invisible", invisible ? "INVISIBLE" : "VISIBLE") }
        if collation != baseline.collation {
            let collation = collation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard collation.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else {
                throw DatabaseError.message("enter a valid collation")
            }
            replace("collation", collation.isEmpty ? "" : "COLLATE \(collation)")
        }
        if comment != baseline.comment {
            replace("comment", comment.isEmpty ? "" : "COMMENT " + DatabaseSQL.ddlString(comment))
        }
        if defaultMode != baseline.defaultMode || defaultText != baseline.defaultText {
            let text = try defaultClause(type: type)
            replace("default", text)
        }
        var characters = Array(parts.source)
        for (range, replacement) in replacements.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
            characters.replaceSubrange(range, with: Array(replacement))
        }
        return (String(characters) + (appended.isEmpty ? "" : " " + appended.joined(separator: " ")))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func validatedTypeName() throws -> String {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DatabaseError.message("enter a column name")
        }
        let type = typeName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !type.isEmpty, type.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "_") }) else {
            throw DatabaseError.message("select a valid type")
        }
        guard numeric || (!unsigned && !zerofill) else {
            throw DatabaseError.message("unsigned and zerofill require a numeric type")
        }
        guard !zerofill || unsigned else { throw DatabaseError.message("zerofill requires unsigned") }
        guard nullable || defaultMode != .null else {
            throw DatabaseError.message("disable default null before making the column not null")
        }
        guard !autoIncrement || (integer && !nullable && !generated) else {
            throw DatabaseError.message("auto_increment requires an indexed, non-null integer")
        }
        guard
            !generated || (!autoIncrement && defaultMode == baseline.defaultMode && defaultText == baseline.defaultText)
        else {
            throw DatabaseError.message(
                "generated columns preserve their expression and cannot have a default or auto_increment")
        }
        return type
    }

    private func defaultClause(type: String) throws -> String {
        let text: String
        switch defaultMode {
        case .none: text = ""
        case .null:
            guard nullable else { throw DatabaseError.message("default null requires a nullable column") }
            text = "DEFAULT NULL"
        case .value:
            let literal = DatabaseSQL.ddlString(defaultText)
            let expressionRequired = [
                "tinytext", "text", "mediumtext", "longtext", "tinyblob", "blob", "mediumblob", "longblob", "json",
            ].contains(type)
            text = "DEFAULT " + (expressionRequired ? "(\(literal))" : literal)
        case .currentTimestamp:
            guard ["datetime", "timestamp"].contains(type) else {
                throw DatabaseError.message("current timestamp requires datetime or timestamp")
            }
            text = "DEFAULT CURRENT_TIMESTAMP" + (parameters.isEmpty ? "" : "(\(parameters))")
        case .expression:
            guard baseline.defaultMode == .expression, defaultText == baseline.defaultText,
                let raw = parts.text("default")
            else {
                throw DatabaseError.message("the existing expression is preserved; use the sql tab for new expressions")
            }
            text = raw
        }
        return text
    }

}

struct SQLPlan: Identifiable {
    let id = UUID()
    let title: String
    let sql: String
    let database: String
    var oneRow = false
    var destructive = false
    var summary = ""
    var rowDraft: RowDraft?
    var columnDraft: ColumnEditorDraft?
    var parameters: [String?]?
    var statements: [String]?
}

enum DatabaseError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case let .message(message) = self { return message }
        return nil
    }
}

final class DatabaseModel: ObservableObject {
    let objects = DatabaseObjectLibrary()
    @Published var databases: [String] = []
    @Published var tables: [DatabaseTable] = []
    @Published var schemas: [String] = []
    @Published var schema = "public"
    private var rowVersions: [String?] = []
    var engine: DatabaseEngine { connection?.engine ?? .mariadb }
    var location: DatabaseLocation { .init(database: database, schema: schema) }
    var qualifiedTable: String { qualified(table) }
    func identifier(_ name: String) -> String {
        engine.isPostgreSQL ? PostgreSQLSQL.identifier(name) : DatabaseSQL.identifier(name)
    }
    func qualified(_ name: String) -> String {
        engine.isPostgreSQL ? PostgreSQLSQL.qualified(schema, name) : DatabaseSQL.qualified(database, name)
    }
    func renameTablePlan(to name: String) -> SQLPlan {
        .init(
            title: "rename table",
            sql: engine.isPostgreSQL
                ? "ALTER TABLE \(qualifiedTable) RENAME TO \(identifier(name));"
                : "RENAME TABLE \(qualifiedTable) TO \(qualified(name));",
            database: database, summary: database + "." + table + " → " + name)
    }
    var emptyTablePlan: SQLPlan {
        .init(
            title: "empty table", sql: "TRUNCATE TABLE \(qualifiedTable);", database: database,
            destructive: true, summary: database + "." + table + " · all rows")
    }
    func rowPlan(_ draft: RowDraft, deleting: Bool = false) throws -> SQLPlan {
        if engine.isPostgreSQL {
            return try PostgreSQLSQL.rowPlan(
                location: location, table: table, columns: columns, draft: draft, deleting: deleting)
        }
        if deleting, let original = draft.original {
            return try DatabaseSQL.deletePlan(database: database, table: table, columns: columns, row: original)
        }
        return try DatabaseSQL.rowPlan(database: database, table: table, columns: columns, draft: draft)
    }
    @Published var database = ""
    @Published var table = ""
    @Published var columns: [DatabaseColumn] = []
    @Published var indexes: SQLResult?
    @Published var constraints: SQLResult?
    @Published var foreignKeys: SQLResult?
    @Published var ddl = ""
    @Published var data: SQLResult?
    @Published var tab = "data" { didSet { updateRefreshTimer() } }
    @Published var busy = false
    @Published var error = ""
    @Published var message = ""
    @Published var offset = 0
    @Published var sortColumn = ""
    @Published var descending = false
    @Published var filter = ""
    @Published var sql = ""
    @Published var sqlResults: [SQLResult] = []
    @Published private(set) var queryRunning = false
    private var queryJob: SQLQueryJob?
    @Published var elapsed: Double = 0
    @Published var history: [String] = []
    @Published var refreshInterval = UserDefaults.standard.integer(forKey: "moko.databaseRefreshInterval") {
        didSet {
            if ![0, 5, 10].contains(refreshInterval) {
                refreshInterval = 0
                return
            }
            if !PreviewRuntime.isActive {
                UserDefaults.standard.set(refreshInterval, forKey: "moko.databaseRefreshInterval")
            }
            updateRefreshTimer()
        }
    }
    var connection: DatabaseConnection?
    private var generation = UUID()
    private var operation = UUID()
    private var refreshTimer: Timer?
    @Published private(set) var nextRefreshAt: Date?
    private var automaticQueryInFlight = false
    private var workspaceVisible = false
    private var windowVisible = true
    private var editorVisible = false
    private var refreshUpdateScheduled = false
    let pageSize = 100
    var selectedTable: DatabaseTable? { tables.first { $0.name == table } }
    var writable: Bool {
        !database.isEmpty
            && (engine.isPostgreSQL
                ? !["pg_catalog", "information_schema"].contains(schema)
                : !["mysql", "information_schema", "performance_schema", "sys"].contains(database))
            && selectedTable?.isView == false
    }
    var rowEditable: Bool { writable && columns.contains { $0.key == "PRI" } && data?.truncated != true }
    var automaticRefreshAllowed: Bool {
        refreshInterval > 0 && workspaceVisible && windowVisible && !editorVisible && tab == "data"
            && connection != nil && !table.isEmpty && !columns.isEmpty
    }
    func setWorkspaceVisible(_ visible: Bool) {
        guard workspaceVisible != visible else { return }
        workspaceVisible = visible
        updateRefreshTimer()
    }
    func setWindowVisible(_ visible: Bool) {
        guard windowVisible != visible else { return }
        windowVisible = visible
        updateRefreshTimer()
    }
    func setEditorVisible(_ visible: Bool) {
        guard editorVisible != visible else { return }
        editorVisible = visible
        updateRefreshTimer()
    }
    private func updateRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        // AppKit can end editing while updateNSView is reconciling the table.
        // Keep policy changes immediate, but publish the clock after that update.
        guard !refreshUpdateScheduled else { return }
        refreshUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshUpdateScheduled = false
            self.installRefreshTimer()
        }
    }
    private func installRefreshTimer() {
        if nextRefreshAt != nil { nextRefreshAt = nil }
        guard automaticRefreshAllowed else { return }
        nextRefreshAt = Date().addingTimeInterval(Double(refreshInterval))
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Double(refreshInterval), repeats: true) { [weak self] _ in
            self?.refreshDataAutomatically()
        }
    }
    func refreshDataAutomatically() {
        if automaticRefreshAllowed { nextRefreshAt = Date().addingTimeInterval(Double(refreshInterval)) }
        guard !PreviewRuntime.isActive else { return }
        guard automaticRefreshAllowed, !busy, !automaticQueryInFlight, let connection else { return }
        automaticQueryInFlight = true
        let query = dataQuery(), database = database, table = table, token = generation, operation = operation
        let maxRows = UInt32(pageSize + 1)
        DispatchQueue.global(qos: .utility).async {
            let response = connection.execute(query, database: database, maxRows: maxRows)
            DispatchQueue.main.async {
                self.automaticQueryInFlight = false
                guard token == self.generation, operation == self.operation,
                    self.automaticRefreshAllowed, !self.busy, database == self.database,
                    table == self.table, query == self.dataQuery()
                else { return }
                if response.succeeded {
                    self.consumeData(response.results.first)
                    if !self.error.isEmpty { self.error = "" }
                } else {
                    // Keep the displayed page and selection while a transient refresh fails.
                    let message = "automatic refresh: \(response.error) (\(response.code))"
                    if self.error != message { self.error = message }
                }
            }
        }
    }
    func consumeData(_ next: SQLResult?) {
        var visible = next
        if engine.isPostgreSQL, let next, next.fields.last?.name == "__moko_xmin" {
            rowVersions = next.rows.indices.map { next.text($0, next.fields.count - 1) }
            visible = .init(
                fields: Array(next.fields.dropLast()), rows: next.rows.map { Array($0.dropLast()) },
                affected: next.affected, truncated: next.truncated, warnings: next.warnings)
        }
        if data != visible { data = visible }
    }
    deinit { refreshTimer?.invalidate() }
    func configure(_ next: DatabaseConnection?) {
        guard !PreviewRuntime.isActive else { return }
        guard next != connection else { return }
        queryJob?.cancel()
        queryJob = nil
        queryRunning = false
        connection = next
        schemas = []
        schema = next?.schema ?? "public"
        objects.configure(connection: next, database: "")
        generation = UUID()
        busy = false
        databases = []
        database = ""
        tables = []
        clearTable()
        error = ""
        message = ""
        updateRefreshTimer()
        if next != nil { reloadDatabases() }
    }
    private func perform(_ work: @escaping (DatabaseConnection) -> SQLResponse, then: @escaping (SQLResponse) -> Void) {
        guard !busy, let connection else { return }
        operation = UUID()
        busy = true
        error = ""
        let token = generation
        DispatchQueue.global(qos: .userInitiated).async {
            let response = work(connection)
            DispatchQueue.main.async {
                guard token == self.generation else { return }
                self.busy = false
                if !response.succeeded { self.error = "\(response.error) (\(response.code))" }
                then(response)
            }
        }
    }
    func reloadDatabases() {
        perform(
            { $0.execute(self.engine.isPostgreSQL ? PostgreSQLSQL.databases : "SHOW DATABASES", maxRows: 10000) },
            then: { result in
                guard result.succeeded, let set = result.results.first else { return }
                self.databases = set.rows.indices.compactMap { set.text($0, 0) }
                if !self.database.isEmpty && !self.databases.contains(self.database) {
                    self.database = ""
                    self.objects.configure(connection: self.connection, database: "")
                    self.tables = []
                    self.clearTable()
                }
                if !self.database.isEmpty {
                    if self.engine.isPostgreSQL { self.reloadSchemas() } else { self.reloadTables() }
                }
            })
    }
    func selectDatabase(_ name: String) {
        guard !busy else { return }
        database = name
        objects.configure(connection: connection, database: name)
        tables = []
        clearTable()
        if engine.isPostgreSQL { reloadSchemas() } else { reloadTables() }
    }
    func reloadSchemas() {
        let target = database
        perform(
            { $0.execute(PostgreSQLSQL.schemas, database: target, maxRows: 10000) },
            then: { response in
                guard response.succeeded, let rows = response.results.first, self.database == target else { return }
                self.schemas = rows.rows.indices.compactMap { rows.text($0, 0) }
                if !self.schemas.contains(self.schema) { self.schema = self.schemas.first ?? "public" }
                self.connection?.schema = self.schema
                self.reloadTables()
            })
    }
    func selectSchema(_ name: String) {
        guard !busy, schemas.contains(name) else { return }
        schema = name
        connection?.schema = name
        tables = []
        clearTable()
        reloadTables()
    }
    func clearTable() {
        table = ""
        columns = []
        indexes = nil
        constraints = nil
        foreignKeys = nil
        ddl = ""
        data = nil
        rowVersions = []
        offset = 0
        sortColumn = ""
        descending = false
        filter = ""
        updateRefreshTimer()
    }
    func reloadTables(select target: String? = nil, filter initialFilter: String? = nil) {
        let database = database
        guard !database.isEmpty else { return }
        objects.configure(connection: connection, database: database)
        objects.reload()
        let query =
            engine.isPostgreSQL
            ? PostgreSQLSQL.tables(schema: schema)
            : "SELECT TABLE_NAME, TABLE_TYPE, COALESCE(ENGINE,''), COALESCE(CAST(TABLE_ROWS AS CHAR),'—') FROM information_schema.TABLES WHERE TABLE_SCHEMA = \(DatabaseSQL.literal(database)) ORDER BY TABLE_NAME;"
        perform(
            { $0.execute(query, database: database, maxRows: 10000) },
            then: { result in
                guard result.succeeded, let set = result.results.first else { return }
                self.tables = set.rows.indices.map {
                    .init(
                        scope: (self.connection?.identity ?? "") + ":" + database + ":" + self.schema,
                        name: set.text($0, 0) ?? "", kind: set.text($0, 1) ?? "", engine: set.text($0, 2) ?? "",
                        estimatedRows: set.text($0, 3) ?? "")
                }
                if let target {
                    if self.tables.contains(where: { $0.name == target }) {
                        self.loadTable(target, filter: initialFilter)
                    } else {
                        self.error = "related table not found"
                    }
                    return
                }
                if !self.table.isEmpty {
                    if self.tables.contains(where: { $0.name == self.table }) {
                        self.loadTable(self.table)
                    } else {
                        self.clearTable()
                    }
                }
            })
    }
    func openReference(_ target: ForeignKeyTarget) {
        guard !busy else { return }
        clearTable()
        setEditorVisible(false)
        database = target.database
        schema = target.schema
        connection?.schema = schema
        tables = []
        tab = "data"
        reloadTables(select: target.table, filter: target.predicate)
    }
    func loadTable(_ name: String, filter initialFilter: String? = nil) {
        guard !busy else { return }
        objects.clearSelection()
        let changed = name != table
        if changed {
            clearTable()
            table = name
        }
        if let initialFilter {
            filter = initialFilter
            offset = 0
        }
        let database = database
        let query =
            engine.isPostgreSQL
            ? PostgreSQLSQL.metadata(schema: schema, table: name)
            : DatabaseSQL.tableMetadata(database: database, table: name)
        perform(
            { $0.execute(query, database: database, multiple: true, maxRows: 10000, formSession: true) },
            then: { result in
                guard result.succeeded, result.results.count >= 4 else { return }
                let set = result.results[0]
                self.columns = set.rows.indices.map {
                    .init(
                        name: set.text($0, 0) ?? "", type: set.text($0, 1) ?? "", nullable: set.text($0, 2) == "YES",
                        key: set.text($0, 3) ?? "", defaultValue: set.text($0, 4), extra: set.text($0, 5) ?? "",
                        collation: set.text($0, 6) ?? "", comment: set.text($0, 7) ?? "", engine: self.engine)
                }
                self.ddl = result.results[1].text(0, 1) ?? ""
                self.indexes = result.results[2]
                self.foreignKeys = result.results[3]
                self.constraints = result.results.count > 4 ? result.results[4] : nil
                if self.sortColumn.isEmpty {
                    self.sortColumn =
                        self.columns.first(where: { $0.key == "PRI" })?.name ?? self.columns.first?.name ?? ""
                }
                self.updateRefreshTimer()
                self.loadData()
            })
    }
    func dataQuery() -> String {
        var names = columns.map { identifier($0.name) }.joined(separator: ", ")
        if engine.isPostgreSQL && selectedTable?.isView == false { names += ", xmin::text AS \"__moko_xmin\"" }
        let sorting = columns.contains(where: { $0.name == sortColumn }) ? sortColumn : ""
        let order =
            sorting.isEmpty
            ? ""
            : " ORDER BY \(identifier(sorting)) \(descending ? "DESC" : "ASC")"
                + columns.filter { $0.key == "PRI" && $0.name != sorting }.map {
                    ", \(identifier($0.name)) ASC"
                }.joined()
        let whereSQL = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        return "SELECT \(names) FROM \(qualifiedTable)"
            + (whereSQL.isEmpty ? "" : " WHERE (\(whereSQL))") + order + " LIMIT \(pageSize + 1) OFFSET \(offset);"
    }
    func loadData() {
        guard !table.isEmpty, !columns.isEmpty else { return }
        let query = dataQuery(), database = database
        perform(
            { $0.execute(query, database: database, maxRows: UInt32(self.pageSize + 1)) },
            then: { result in
                if result.succeeded { self.consumeData(result.results.first) }
            })
    }
    func draft(row: Int?) -> RowDraft {
        let original = row.flatMap { index in data?.cells.indices.contains(index) == true ? data?.cells[index] : nil }
        var values = [String: CellDraft]()
        for (index, column) in columns.enumerated() {
            if let original {
                let cell = original[index]
                values[column.name] = .init(
                    text: cell.hex == nil ? "" : cell.display(binary: column.binary),
                    mode: cell.hex == nil ? .null : .value)
            } else if engine.isPostgreSQL {
                values[column.name] = .init(
                    text: "",
                    mode: column.generated || column.extra.contains("auto_increment")
                        || column.defaultValue != nil ? .omitted : .value)
            } else {
                let automatic =
                    column.generated || column.extra.lowercased().contains("auto_increment")
                    || column.extra.contains("DEFAULT_GENERATED")
                if automatic {
                    values[column.name] = .init(text: "", mode: .omitted)
                } else if let definition = DatabaseSQL.columnDefinition(column.name, ddl: ddl) {
                    // MariaDB reports quoted literals in COLUMN_DEFAULT; SHOW CREATE
                    // lets the form distinguish literal values, NULL and expressions.
                    let editor = ColumnEditorDraft(original: column.name, name: column.name, definition: definition)
                    switch editor.defaultMode {
                    case .value: values[column.name] = .init(text: editor.defaultText, mode: .value)
                    case .null: values[column.name] = .init(text: "", mode: .null)
                    case .currentTimestamp, .expression: values[column.name] = .init(text: "", mode: .omitted)
                    case .none: values[column.name] = .init(text: "", mode: .value)
                    }
                } else {
                    values[column.name] = .init(text: column.defaultValue ?? "", mode: .value)
                }
            }
        }
        return .init(
            original: original, values: values,
            rowVersion: row.flatMap { rowVersions.indices.contains($0) ? rowVersions[$0] : nil })
    }
    func apply(_ plan: SQLPlan, completed: @escaping (Bool) -> Void) {
        guard !busy, connection != nil else {
            completed(false)
            return
        }
        perform(
            {
                $0.execute(
                    plan.sql, database: plan.database, oneRow: plan.oneRow,
                    options: .init(parameters: plan.parameters, statements: plan.statements))
            },
            then: { result in
                completed(result.succeeded)
                if result.succeeded {
                    self.message = "changes applied"
                    self.reloadDatabases()
                }
            })
    }
    func runSQL() {
        let script = sql.trimmingCharacters(in: .whitespacesAndNewlines), database = database
        guard !script.isEmpty else { return }
        guard !busy, connection != nil else { return }
        let started = Date(), job = SQLQueryJob()
        queryJob = job
        queryRunning = true
        message = ""
        perform(
            { $0.execute(script, database: database, multiple: true, options: .init(job: job)) },
            then: { result in
                self.queryJob = nil
                self.queryRunning = false
                self.elapsed = Date().timeIntervalSince(started)
                self.sqlResults = result.results
                if self.history.first != script {
                    self.history.insert(script, at: 0)
                    self.history = Array(self.history.prefix(20))
                }
                if result.rolledBack {
                    self.message = "unfinished transaction: rolled back at the end of execution"
                } else if result.succeeded {
                    self.message = "completed in \(String(format: "%.2f", self.elapsed)) s"
                }
            })
    }
    func cancelSQL() { queryJob?.cancel() }

}
