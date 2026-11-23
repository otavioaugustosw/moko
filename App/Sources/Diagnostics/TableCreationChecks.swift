import Foundation
import Security

extension DatabaseChecks {
    static func runTableCreationCheck() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        let connection: DatabaseConnection
        if let port = environment["MOKO_VALIDATION_PORT"], let secret = environment["MYSQL_PWD"] {
            // The validator supplies credentials only to this isolated child process.
            connection = .init(host: "127.0.0.1", port: port, user: "root", password: secret)
        } else {
            let model = WorkspaceModel()
            let external = CommandLine.arguments.contains("--test-table-creation-external")
            let preferences = UserDefaults.standard
            let bundled = !external && model.usesBundledDatabase
            let host = bundled ? "127.0.0.1" : (preferences.string(forKey: "moko.external.host") ?? model.host)
            let port =
                bundled ? model.managedDatabase.port : (preferences.string(forKey: "moko.external.port") ?? model.port)
            let user =
                bundled
                ? model.managedDatabase.user : (preferences.string(forKey: "moko.external.user") ?? model.username)
            let account = bundled ? model.managedDatabase.credentialAccount : "\(user)@\(host):\(port)"
            guard let secret = Credentials.read(account, allowInteraction: false) else { return false }
            connection = .init(host: host, port: port, user: user, password: secret)
        }
        return validateTableCreation(connection)
    }

    static func validateTableCreation(_ connection: DatabaseConnection) -> Bool {
        let database = "moko_table_check_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        var created = false, checks = 0
        func run(_ sql: String, multiple: Bool = false) throws -> SQLResponse {
            let response = connection.execute(
                sql, database: created ? database : "", multiple: multiple, formSession: true)
            guard response.succeeded else { throw DatabaseError.message("\(response.error) (\(response.code))") }
            return response
        }
        func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw DatabaseError.message(message) }
            checks += 1
        }
        defer {
            if created { _ = connection.execute("DROP DATABASE \(DatabaseSQL.identifier(database));") }
        }
        do {
            _ = try run("CREATE DATABASE \(DatabaseSQL.identifier(database));")
            created = true
            let draft = NewTableDraft(
                name: "typed_records",
                columns: [
                    .init(name: "id", type: "int", size: "", primary: true, autoIncrement: true),
                    .init(name: "enabled", type: "boolean", size: ""),
                    .init(name: "name", type: "varchar", size: "180"),
                    .init(name: "created_at", type: "datetime", size: ""),
                ])
            _ = try run(draft.plan(database: database).sql)
            let metadata = try run(DatabaseSQL.tableMetadata(database: database, table: draft.name), multiple: true)
            try require(metadata.results.count == 4, "table metadata is incomplete")
            let columns = metadata.results[0], indexes = metadata.results[2]
            try require(columns.rows.count == 4 && columns.text(0, 3) == "PRI", "primary key metadata missing")
            try require(columns.text(1, 1)?.hasPrefix("tinyint") == true, "boolean normalization missing")
            let indexName = indexes.fields.firstIndex { $0.name == "INDEX_NAME" }
            try require(indexName.map { indexes.text(0, $0) == "PRIMARY" } == true, "index metadata missing")
            let target = DatabaseSQL.qualified(database, draft.name)
            _ = try run(
                "INSERT INTO \(target) (`enabled`,`name`,`created_at`) VALUES (1,'initial','2026-10-11 12:30:00');")
            let row = try run("SELECT id,enabled,name,created_at FROM \(target);").results[0]
            try require(
                row.text(0, 0) == "1" && row.text(0, 1) == "1" && row.text(0, 2) == "initial",
                "typed row cannot be read")
            _ = try run("UPDATE \(target) SET enabled=0, name='updated' WHERE id=1;")
            let updated = try run("SELECT enabled,name,created_at FROM \(target);").results[0]
            try require(
                updated.text(0, 0) == "0" && updated.text(0, 1) == "updated"
                    && updated.text(0, 2) == "2026-10-11 12:30:00", "typed row update failed")
            let view = "typed_view"
            _ = try run("CREATE VIEW \(DatabaseSQL.qualified(database, view)) AS SELECT * FROM \(target);")
            let viewMetadata = try run(DatabaseSQL.tableMetadata(database: database, table: view), multiple: true)
            try require(viewMetadata.results.count == 4 && viewMetadata.results[2].rows.isEmpty, "view metadata failed")
            let cleanup = connection.execute("DROP DATABASE \(DatabaseSQL.identifier(database));")
            created = !cleanup.succeeded
            try require(cleanup.succeeded, "fixture cleanup failed")
            print("table creation: \(checks) checks passed (int, boolean, varchar, datetime, indexes and views).")
            return true
        } catch {
            print("table creation: \(error.localizedDescription)")
            return false
        }
    }
}

extension WorkspaceModel {
    // Command-line checks use the same server and saved credential as the panel.
    var diagnosticCredentialAccount: String {
        usesBundledDatabase ? managedDatabase.credentialAccount : credentialKey
    }
}
