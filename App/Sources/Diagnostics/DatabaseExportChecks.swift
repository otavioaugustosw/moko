import Foundation

enum DatabaseExportChecks {
    static func run() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard let port = environment["MOKO_VALIDATION_PORT"], let secret = environment["MYSQL_PWD"] else {
            return false
        }
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let database = "--moko_export_" + token, other = "moko_other_" + token
        let engine: DatabaseEngine = environment["MOKO_VALIDATION_ENGINE"] == "mysql" ? .mysql : .mariadb
        let connection = DatabaseConnection(host: "127.0.0.1", port: port, user: "root", password: secret, engine: engine)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("moko export " + UUID().uuidString)
        let destination = folder.appendingPathComponent("database.sql")
        var checks = 0
        func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw DatabaseError.message(message) }
            checks += 1
        }
        func query(_ sql: String, multiple: Bool = false) -> SQLResponse {
            connection.execute(sql, database: database, multiple: multiple)
        }
        defer {
            _ = connection.execute(
                "DROP DATABASE IF EXISTS \(DatabaseSQL.identifier(database)); "
                    + "DROP DATABASE IF EXISTS \(DatabaseSQL.identifier(other));", multiple: true)
            try? FileManager.default.removeItem(at: folder)
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try require(
                connection.execute(
                    "CREATE DATABASE \(DatabaseSQL.identifier(database)); "
                        + "CREATE DATABASE \(DatabaseSQL.identifier(other));", multiple: true
                ).succeeded, "fixture creation failed")
            let note = "olá 🦝\nquote' and slash\\"
            try require(
                query(
                    """
                    CREATE TABLE items (id int PRIMARY KEY, note text, payload varbinary(8));
                    INSERT INTO items VALUES (7,\(DatabaseSQL.literal(note)),0x0001FF00),(8,NULL,NULL);
                    """, multiple: true
                ).succeeded, "export fixture setup failed")
            // Match the forms' standalone DDL. MySQL retains a multi-statement script's
            // trailing trigger semicolon and produces an invalid dump (upstream bug 77856).
            for statement in [
                "CREATE VIEW item_view AS SELECT id, note FROM items",
                "CREATE PROCEDURE get_items() SELECT id FROM items",
                "CREATE FUNCTION add_one(amount int) RETURNS int DETERMINISTIC RETURN amount + 1",
                "CREATE TRIGGER preserve_note BEFORE INSERT ON items FOR EACH ROW SET NEW.note = NEW.note",
                "CREATE EVENT sample_event ON SCHEDULE EVERY 1 DAY DISABLE DO SELECT 1",
            ] {
                try require(query(statement).succeeded, "export object fixture setup failed: " + statement)
            }
            checks += try PHPDatabaseExampleChecks.run(
                connection: connection, database: database, folder: folder,
                tlsAvailable: environment["MOKO_VALIDATION_TLS"] == "1")
            try DatabaseDump.write(connection, database: database, to: destination)
            let content = try Data(contentsOf: destination)
            let text = String(bytes: content, encoding: .utf8) ?? ""
            try require(text.contains(database) && !text.contains(other), "export included another database")
            try require(!text.contains(secret), "export leaked connection credentials")
            try require((try destination.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0 > 0, "empty SQL export")
            try require(query("DROP DATABASE \(DatabaseSQL.identifier(database))").succeeded, "fixture drop failed")
            try require(
                connection.execute("CREATE DATABASE \(DatabaseSQL.identifier(database))").succeeded,
                "existing restore target could not be recreated")
            try DatabaseCommand.importFile(
                destination, connection: connection, database: database, job: DatabaseExportJob())
            let row = query("SELECT note, HEX(payload) FROM items WHERE id=7").results.first
            try require(
                row?.text(0, 0) == note && row?.text(0, 1) == "0001FF00",
                "Unicode, escaped text or binary round-trip failed")
            try require(
                query("SELECT note IS NULL, payload IS NULL FROM items WHERE id=8").results.first?.text(0, 0) == "1",
                "NULL round-trip failed")
            try require(
                query("SELECT COUNT(*) FROM item_view").results.first?.text(0, 0) == "2", "view was not restored")
            try require(query("CALL get_items()").results.first?.rows.count == 2, "procedure was not restored")
            try require(query("SELECT add_one(4)").results.first?.text(0, 0) == "5", "function was not restored")
            try require(
                query(
                    "SELECT COUNT(*) FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA="
                        + DatabaseSQL.literal(database)
                ).results.first?.text(0, 0) == "1", "trigger was not restored")
            try require(
                query(
                    "SELECT STATUS FROM information_schema.EVENTS WHERE EVENT_SCHEMA="
                        + DatabaseSQL.literal(database)
                ).results.first?.text(0, 0) == "DISABLED", "event state was not restored")
            var invalid = connection
            invalid.password += "invalid"
            var failed = false
            do {
                try DatabaseDump.write(invalid, database: database, to: destination)
            } catch { failed = true }
            try require(
                failed && (try Data(contentsOf: destination)) == content, "failed export replaced the previous file")
            let cancelled = DatabaseExportJob()
            cancelled.cancel()
            var wasCancelled = false
            do {
                try DatabaseDump.write(connection, database: database, to: destination, job: cancelled)
            } catch is CancellationError { wasCancelled = true }
            try require(wasCancelled, "export cancellation was ignored")
            try require((try Data(contentsOf: destination)) == content, "cancelled export replaced the previous file")
            try require(
                try FileManager.default.contentsOfDirectory(atPath: folder.path).allSatisfy {
                    !$0.hasPrefix(".moko-export-")
                },
                "partial export files were left behind")
            print("database export: \(checks) isolated dump/restore and failure-preservation checks passed.")
            return true
        } catch {
            print("database export: " + error.localizedDescription)
            return false
        }
    }
}
