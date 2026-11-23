import Combine
import Foundation

final class DatabaseObjectLibrary: ObservableObject {
    @Published private(set) var items: [DatabaseObject] = []
    @Published private(set) var selected: DatabaseObject?
    @Published private(set) var definition: DatabaseObjectDefinition?
    @Published private(set) var busy = false
    @Published private(set) var error = ""
    @Published private(set) var message = ""
    @Published private(set) var results: [SQLResult] = []
    @Published private(set) var version = ""
    @Published private(set) var scheduler = ""
    private var connection: DatabaseConnection?
    private var generation = UUID()
    private(set) var database = ""
    var engine: DatabaseEngine { connection?.engine ?? .mariadb }
    var schema: String { connection?.schema ?? "public" }
    var kinds: [DatabaseObjectKind] {
        engine.isPostgreSQL ? PostgreSQLObjects.kinds : [.procedure, .function, .trigger, .event, .view]
    }
    var writable: Bool {
        !database.isEmpty
            && (engine.isPostgreSQL
                ? schema != "information_schema" && !schema.hasPrefix("pg_")
                : !["mysql", "sys", "information_schema", "performance_schema"].contains(database))
    }
    var editable: Bool {
        writable && definition?.bodyRange != nil
            && (engine.isPostgreSQL && selected?.kind != .materializedView || version.lowercased().contains("mariadb")
                || selected?.kind == .view)
    }
    func configure(connection: DatabaseConnection?, database: String) {
        guard connection != self.connection || database != self.database else { return }
        generation = UUID()
        self.connection = connection
        self.database = database
        items = []
        clearSelection()
        busy = false
        error = ""
        message = ""
        version = ""
        scheduler = ""
        reload()
    }
    func dismissError(_ value: String) { if !value.isEmpty && error == value { error = "" } }
    func dismissMessage(_ value: String) { if !value.isEmpty && message == value { message = "" } }
    func clearSelection() {
        selected = nil
        definition = nil
        results = []
    }
    private func perform(_ query: String, multiple: Bool = false, then: @escaping (SQLResponse) -> Void) {
        guard !busy, let connection, !database.isEmpty, !PreviewRuntime.isActive else { return }
        busy = true
        error = ""
        message = ""
        let database = database, token = generation
        DispatchQueue.global(qos: .userInitiated).async {
            let response = connection.execute(
                query, database: database, multiple: multiple, maxRows: 10000, formSession: true)
            DispatchQueue.main.async {
                guard token == self.generation else { return }
                self.busy = false
                if !response.succeeded { self.error = "\(response.error) (\(response.code))" }
                then(response)
            }
        }
    }
    func reload() {
        perform(
            engine.isPostgreSQL ? PostgreSQLObjects.catalog(schema: schema) : DatabaseObjectSQL.catalog(database),
            multiple: true
        ) { response in
            guard response.succeeded, let rows = response.results.first else { return }
            let items = rows.rows.indices.compactMap { index -> DatabaseObject? in
                guard let name = rows.text(index, 0),
                    let kind = rows.text(index, 1).flatMap(DatabaseObjectKind.init(rawValue:))
                else { return nil }
                return .init(
                    name: name, kind: kind, detail: rows.text(index, 2) ?? "", enabled: rows.text(index, 3) == "1",
                    schema: self.schema,
                    nativeIdentity: self.engine.isPostgreSQL ? (rows.text(index, 4) ?? "") : "",
                    resultType: self.engine.isPostgreSQL ? (rows.text(index, 6) ?? "") : "",
                    signature: self.engine.isPostgreSQL ? (rows.text(index, 5) ?? "") : "",
                    scope: (self.connection?.identity ?? "") + ":" + self.database)
            }
            if self.items != items { self.items = items }
            if let meta = response.results.first(where: { $0.fields.first?.name == "version" }) {
                self.version = meta.text(0, 0) ?? ""
                self.scheduler = meta.text(0, 1) ?? ""
            }
            if let selected = self.selected, !items.contains(where: { $0.id == selected.id }) { self.clearSelection() }
        }
    }
    func select(_ object: DatabaseObject) {
        guard !busy else { return }
        selected = object
        definition = nil
        results = []
        perform(
            engine.isPostgreSQL
                ? PostgreSQLObjects.definition(object, schema: schema)
                : DatabaseObjectSQL.definition(object, database: database), multiple: true
        ) { response in
            guard response.succeeded, self.selected?.id == object.id else { return }
            self.definition =
                self.engine.isPostgreSQL
                ? PostgreSQLObjects.decode(response, object: object)
                : DatabaseObjectSQL.decode(response, object: object)
            if self.definition == nil { self.error = "the definition is not available with this account's permissions" }
        }
    }
    func create(_ draft: NewDatabaseObjectDraft, completed: @escaping (Bool) -> Void) throws {
        guard writable else { throw DatabaseError.message("this database is read-only") }
        let sql =
            try engine.isPostgreSQL
            ? PostgreSQLObjects.create(draft, schema: schema) : draft.statement(database: database)
        perform(sql) { response in
            completed(response.succeeded)
            if response.succeeded { self.reload() }
        }
    }
    func saveBody(_ body: String, completed: @escaping (Bool) -> Void) throws {
        guard editable, let definition, let connection, !busy else {
            throw DatabaseError.message(
                "body replacement is supported for MariaDB objects and views. use the SQL console for other servers.")
        }
        let query =
            try engine.isPostgreSQL
            ? definition.replacingBody(body) : DatabaseObjectSQL.replacement(definition, body: body)
        let database = database, token = generation
        busy = true
        error = ""
        message = ""
        DispatchQueue.global(qos: .userInitiated).async {
            let response = connection.execute(query, database: database, session: definition.session)
            var recovery = ""
            if !response.succeeded && !connection.engine.isPostgreSQL {
                let check = connection.execute(
                    DatabaseObjectSQL.definition(definition.object, database: database),
                    database: database, multiple: true)
                if [1305, 1360, 1539, 1146].contains(check.code) {
                    let restored = connection.execute(definition.sql, database: database, session: definition.session)
                    recovery =
                        restored.succeeded
                        ? "\nthe original definition was restored."
                        : "\nrecovery failed. copy the original definition below before retrying."
                }
            }
            DispatchQueue.main.async {
                guard token == self.generation else { return }
                self.busy = false
                if response.succeeded {
                    self.select(definition.object)
                    self.message = "changes applied"
                } else {
                    self.error = "\(response.error) (\(response.code))" + recovery
                }
                completed(response.succeeded)
            }
        }
    }
    func deleteSelected(completed: @escaping (Bool) -> Void) {
        guard writable, let selected else { return }
        let query =
            engine.isPostgreSQL
            ? PostgreSQLObjects.drop(selected, schema: schema)
            : "DROP \(selected.kind.rawValue.uppercased()) \(DatabaseSQL.qualified(database, selected.name));"
        perform(query) { response in
            completed(response.succeeded)
            if response.succeeded {
                self.clearSelection()
                self.reload()
            }
        }
    }
    func refreshMaterializedView() {
        guard engine.isPostgreSQL, writable, let selected, selected.kind == .materializedView else { return }
        perform("REFRESH MATERIALIZED VIEW " + PostgreSQLSQL.qualified(schema, selected.name)) { response in
            if response.succeeded { self.message = "materialized view refreshed" }
        }
    }
    func setTriggerEnabled(_ enabled: Bool) {
        guard engine.isPostgreSQL, writable, let selected, selected.kind == .trigger else { return }
        perform(
            "ALTER TABLE " + PostgreSQLSQL.qualified(schema, selected.detail)
                + (enabled ? " ENABLE" : " DISABLE") + " TRIGGER " + PostgreSQLSQL.identifier(selected.name)
        ) { response in
            if response.succeeded {
                self.reload()
                self.message = "trigger state updated"
            }
        }
    }
    func run(values: [Int: String], nulls: Set<Int>) {
        guard let definition, definition.object.kind.callable else { return }
        if engine.isPostgreSQL, let connection {
            let plan = PostgreSQLObjects.invocation(definition, schema: schema, values: values, nulls: nulls)
            let database = database, token = generation
            busy = true
            DispatchQueue.global(qos: .userInitiated).async {
                let response = connection.execute(
                    plan.sql, database: database, options: .init(parameters: plan.parameters))
                DispatchQueue.main.async {
                    guard self.generation == token else { return }
                    self.busy = false
                    self.results = response.results
                    self.error = response.error
                }
            }
            return
        }
        perform(
            DatabaseObjectSQL.invocation(definition, database: database, values: values, nulls: nulls),
            multiple: true
        ) { response in
            self.results = response.results.filter { !$0.fields.isEmpty }
            if response.succeeded {
                self.message =
                    response.rolledBack
                    ? "execution completed; uncommitted changes were rolled back" : "execution completed"
            }
        }
    }
    func setEventEnabled(_ enabled: Bool) {
        guard writable, let selected, selected.kind == .event else { return }
        let query = "ALTER EVENT \(DatabaseSQL.qualified(database, selected.name)) \(enabled ? "ENABLE" : "DISABLE");"
        perform(query) { response in
            if response.succeeded {
                let updated = DatabaseObject(
                    name: selected.name, kind: selected.kind, detail: enabled ? "ENABLED" : "DISABLED",
                    enabled: enabled)
                self.selected = updated
                self.reload()
            }
        }
    }
    func setSchedulerEnabled(_ enabled: Bool) {
        perform("SET GLOBAL event_scheduler = \(enabled ? "ON" : "OFF");") { response in
            if response.succeeded { self.reload() }
        }
    }
}

#if DEBUG
    extension DatabaseObjectLibrary {
        static func preview(definition: DatabaseObjectDefinition, results: [SQLResult] = []) -> DatabaseObjectLibrary {
            let library = DatabaseObjectLibrary()
            library.database = "example"
            library.connection = .init(
                host: "fixture.invalid", port: "5432", user: "fixture", password: "",
                engine: definition.engine)
            library.items = [definition.object]
            library.selected = definition.object
            library.definition = definition
            library.version = "11.8-MariaDB"
            library.scheduler = "OFF"
            library.results = results
            return library
        }
    }
#endif
