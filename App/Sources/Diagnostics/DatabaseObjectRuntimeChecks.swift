import Foundation

enum DatabaseObjectRuntimeChecks {
    static func run() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard let port = environment["MOKO_VALIDATION_PORT"], let secret = environment["MYSQL_PWD"] else {
            return false
        }
        let database = "moko_objects_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let connection = DatabaseConnection(host: "127.0.0.1", port: port, user: "root", password: secret)
        let library = DatabaseObjectLibrary()
        var checks = 0
        func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw DatabaseError.message(message + " " + library.error) }
            checks += 1
        }
        func wait() {
            let until = Date().addingTimeInterval(15)
            while library.busy && Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        }
        func query(_ sql: String, multiple: Bool = false) -> SQLResponse {
            connection.execute(sql, database: database, multiple: multiple)
        }
        func create(_ draft: NewDatabaseObjectDraft) throws {
            try library.create(draft) { _ in }
            wait()
            try require(
                library.error.isEmpty && library.items.contains { $0.name == draft.name && $0.kind == draft.kind },
                "creation/catalog failed for " + draft.kind.rawValue)
        }
        func select(_ kind: DatabaseObjectKind) throws -> DatabaseObjectDefinition {
            guard let object = library.items.first(where: { $0.kind == kind }) else {
                throw DatabaseError.message("catalog is missing " + kind.rawValue)
            }
            library.select(object)
            wait()
            guard let definition = library.definition else {
                throw DatabaseError.message("definition is missing: " + library.error)
            }
            try require(
                definition.bodyRange != nil,
                "the original body could not be matched for \(kind.rawValue): \(definition.sql) / \(definition.body)")
            return definition
        }
        defer { _ = connection.execute("DROP DATABASE IF EXISTS \(DatabaseSQL.identifier(database))") }
        do {
            try require(
                connection.execute("CREATE DATABASE \(DatabaseSQL.identifier(database))").succeeded,
                "fixture creation failed")
            try require(
                query("CREATE TABLE items (id int PRIMARY KEY, qty int NOT NULL)").succeeded, "table creation failed")
            library.configure(connection: connection, database: database)
            wait()
            var procedure = NewDatabaseObjectDraft(kind: .procedure)
            procedure.name = "calculate"
            procedure.parameters = [
                .init(name: "amount", type: "int", mode: "IN"), .init(name: "total", type: "int", mode: "OUT"),
            ]
            procedure.body = "BEGIN SELECT amount + 1 AS value; SET total = amount + 2; END"
            try create(procedure)
            let procedureDefinition = try select(.procedure)
            try require(
                procedureDefinition.parameters.map(\.mode) == ["IN", "OUT"], "procedure parameter metadata failed")
            library.run(values: [1: "5"], nulls: [])
            wait()
            try require(
                library.results.first?.text(0, 0) == "6" && library.results.last?.text(0, 0) == "7",
                "procedure results/output parameters failed")
            try library.saveBody("BEGIN SELECT amount + 3 AS value; SET total = amount + 4; END") { _ in }
            wait()
            library.run(values: [1: "5"], nulls: [])
            wait()
            try require(
                library.results.first?.text(0, 0) == "8" && library.results.last?.text(0, 0) == "9",
                "procedure replacement/output parameters failed")

            var function = NewDatabaseObjectDraft(kind: .function)
            function.name = "multiply"
            function.parameters = [.init(name: "amount", type: "int")]
            function.body = "RETURN amount * 2"
            function.deterministic = true
            function.access = "NO SQL"
            try create(function)
            _ = try select(.function)
            library.run(values: [1: "4"], nulls: [])
            wait()
            try require(library.results.first?.text(0, 0) == "8", "function invocation failed")
            try library.saveBody("RETURN amount * 3") { _ in }
            wait()
            try require(
                library.error.isEmpty && query("SELECT multiply(4)").results.first?.text(0, 0) == "12",
                "function body replacement failed")
            try library.saveBody("RETURN (;)") { _ in }
            wait()
            try require(
                !library.error.isEmpty && query("SELECT multiply(4)").results.first?.text(0, 0) == "12",
                "invalid replacement did not preserve/recover the original function")

            var trigger = NewDatabaseObjectDraft(kind: .trigger)
            trigger.name = "increment_qty"
            trigger.table = "items"
            trigger.body = "SET NEW.qty = NEW.qty + 1"
            try create(trigger)
            try require(
                query("CREATE TRIGGER double_qty BEFORE INSERT ON items FOR EACH ROW SET NEW.qty = NEW.qty * 2")
                    .succeeded,
                "trigger order fixture failed")
            _ = try select(.trigger)
            try require(
                query("INSERT INTO items VALUES (1,3); SELECT qty FROM items WHERE id=1", multiple: true)
                    .results.last?.text(0, 0) == "8", "trigger was not executed in the expected order")
            try library.saveBody("SET NEW.qty = NEW.qty + 2") { _ in }
            wait()
            try require(
                library.error.isEmpty
                    && query(
                        "INSERT INTO items VALUES (2,3); SELECT qty FROM items WHERE id=2",
                        multiple: true
                    ).results.last?.text(0, 0) == "10",
                "trigger replacement changed execution order")
            try require(query("DROP TRIGGER double_qty").succeeded, "trigger order fixture cleanup failed")

            var event = NewDatabaseObjectDraft(kind: .event)
            event.name = "daily_increment"
            event.body = "UPDATE items SET qty = qty + 1"
            try create(event)
            _ = try select(.event)
            try require(library.selected?.enabled == false, "new event was not disabled by default")
            try library.saveBody("UPDATE items SET qty = qty + 2") { _ in }
            wait()
            try require(
                library.error.isEmpty && library.definition?.body.contains("qty + 2") == true
                    && library.selected?.enabled == false, "event replacement changed its enabled state")

            try checkViews(library: library, query: { query($0) }, create: create, select: select, wait: wait, require: require)
            library.reload()
            wait()
            try require(
                Set(library.items.map(\.kind)) == Set(library.kinds), "catalog omitted an object kind")
            for kind in library.kinds {
                _ = try select(kind)
                library.deleteSelected { _ in }
                wait()
                try require(
                    library.error.isEmpty && !library.items.contains { $0.kind == kind }, "object deletion failed")
            }
            print("SQL objects: \(checks) live catalog, definition, execution, replacement and deletion checks passed.")
            return true
        } catch {
            print("SQL objects: " + error.localizedDescription)
            return false
        }
    }
    private static func checkViews(
        library: DatabaseObjectLibrary, query: (String) -> SQLResponse,
        create: (NewDatabaseObjectDraft) throws -> Void, select: (DatabaseObjectKind) throws -> DatabaseObjectDefinition,
        wait: () -> Void, require: (Bool, String) throws -> Void
    ) throws {
        var view = NewDatabaseObjectDraft(kind: .view)
        view.name = "item_totals"
        view.body = "SELECT id, qty FROM items"
        try create(view)
        try require(
            query(
                "ALTER ALGORITHM=MERGE SQL SECURITY INVOKER VIEW item_totals AS "
                    + "SELECT id, qty FROM items WHERE qty > 0 WITH CASCADED CHECK OPTION"
            ).succeeded,
            "view attribute fixture failed")
        _ = try select(.view)
        try require(
            query("SELECT qty FROM item_totals WHERE id=2").results.first?.text(0, 0) == "10", "view data failed")
        try library.saveBody("SELECT id, qty FROM items WHERE qty > 1") { _ in }
        wait()
        try require(
            library.error.isEmpty
                && query("SELECT qty FROM item_totals WHERE id=2").results.first?.text(0, 0) == "10"
                && library.definition?.sql.contains("ALGORITHM=MERGE") == true
                && library.definition?.sql.contains("SQL SECURITY INVOKER") == true
                && library.definition?.sql.contains("WITH CASCADED CHECK OPTION") == true,
            "view replacement did not preserve algorithm, security and check option")
        view.name = "reject_extra_command"
        view.body = "SELECT id FROM items; DROP TABLE items"
        try library.create(view) { _ in }
        wait()
        try require(
            !library.error.isEmpty && query("SELECT COUNT(*) FROM items").succeeded,
            "pasted trailing SQL ran from the form")
    }

}
