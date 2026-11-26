import Foundation

final class PostgreSQLCheckFixture {
    let connection: DatabaseConnection
    let folder: URL
    let database = "moko_validation"
    var checks = 0
    init(connection: DatabaseConnection, folder: URL) {
        self.connection = connection
        self.folder = folder
    }
    func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw DatabaseError.message(message) }
        checks += 1
    }
    func query(_ sql: String, multiple: Bool = false) -> SQLResponse {
        connection.execute(sql, database: database, multiple: multiple)
    }
    func apply(_ plan: SQLPlan) -> SQLResponse {
        connection.execute(
            plan.sql, database: plan.database, oneRow: plan.oneRow,
            options: .init(parameters: plan.parameters, statements: plan.statements))
    }
    func columns() throws -> [DatabaseColumn] {
        let response = query(PostgreSQLSQL.metadata(schema: "work", table: "items"), multiple: true)
        try require(response.succeeded && response.results.count >= 4, "metadata failed: " + response.error)
        let rows = response.results[0]
        return rows.rows.indices.map {
            .init(
                name: rows.text($0, 0) ?? "", type: rows.text($0, 1) ?? "", nullable: rows.text($0, 2) == "YES",
                key: rows.text($0, 3) ?? "", defaultValue: rows.text($0, 4), extra: rows.text($0, 5) ?? "",
                collation: rows.text($0, 6) ?? "", comment: rows.text($0, 7) ?? "", engine: .postgresql)
        }
    }
}

enum PostgreSQLRuntimeChecks {
    static func run() -> Bool {
        guard let port = ProcessInfo.processInfo.environment["MOKO_VALIDATION_PORT"] else { return false }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("moko-pg-" + UUID().uuidString)
        let secret = UUID().uuidString + UUID().uuidString
        let service = ManagedPostgreSQL(
            directory: folder.appendingPathComponent("data"), port: port, secretProvider: { secret })
        let connection = DatabaseConnection(
            host: "127.0.0.1", port: port, user: "moko", password: secret,
            engine: .postgresql, defaultDatabase: "postgres", schema: "work")
        let fixture = PostgreSQLCheckFixture(connection: connection, folder: folder)
        defer {
            _ = control(service, "stop")
            try? FileManager.default.removeItem(at: folder)
        }
        do {
            let started = control(service, "start")
            try fixture.require(started?.isSuccess == true, "postgresql start failed: " + service.error)
            try fixture.require(
                connection.execute("CREATE DATABASE moko_validation").succeeded, "database creation failed")
            try fixture.require(
                fixture.query("CREATE SCHEMA work; CREATE SCHEMA shadow", multiple: true).succeeded,
                "schema creation failed")
            try testTables(fixture)
            try testRows(fixture)
            try testColumns(fixture)
            try testExtensions(fixture)
            try PostgreSQLStructureChecks.run(fixture)
            try PostgreSQLTypeChecks.run(fixture)
            try PostgreSQLObjectChecks.run(fixture)
            try testFiles(fixture)
            try testCancellation(fixture)
            try testResultLimits(fixture)
            try testPHP(fixture)
            let restored = ManagedPostgreSQL(
                directory: folder.appendingPathComponent("data"), port: port, secretProvider: { secret })
            restored.recover(secret: secret)
            wait { restored.running }
            try fixture.require(restored.running, "authenticated recovery failed")
            try fixture.require(control(service, "stop")?.isSuccess == true, "stop failed")
            try fixture.require(!connection.execute("SELECT 1").succeeded, "owned server remained running")
            try fixture.require(control(service, "start")?.isSuccess == true, "restart failed")
            try fixture.require(
                fixture.query("SELECT count(*) FROM work.items").results.first?.text(0, 0) == "1", "restart lost data")
            print(
                "PostgreSQL: \(fixture.checks) live runtime, catalog, CRUD, concurrency, object, file and PHP checks passed."
            )
            return true
        } catch {
            print("PostgreSQL: " + error.localizedDescription)
            return false
        }
    }
    static func wait(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(20)
        while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    }
    private static func control(_ service: ManagedPostgreSQL, _ command: String) -> Result<String, Error>? {
        var result: Result<String, Error>?
        service.control(command) { result = $0 }
        wait { result != nil }
        return result
    }
    private static func testTables(_ fixture: PostgreSQLCheckFixture) throws {
        var draft = NewTableDraft()
        draft.name = "items"
        draft.columns += [
            .init(name: "name", size: "180"), .init(name: "active", type: "boolean", size: ""),
            .init(name: "created_at", type: "datetime", size: "", nullable: true),
        ]
        let plan = try draft.plan(database: fixture.database, engine: .postgresql, schema: "work")
        let created = fixture.apply(plan)
        try fixture.require(created.succeeded, "table form failed: " + created.error)
        try fixture.require(
            fixture.query("CREATE TABLE shadow.items (id integer PRIMARY KEY, note text)").succeeded,
            "homonymous schema table failed")
        try fixture.require(
            fixture.query(PostgreSQLSQL.tables(schema: "work")).results.first?.text(0, 0) == "items",
            "table catalog failed")
        let columns = try fixture.columns()
        try fixture.require(
            columns.count == 4 && columns[0].key == "PRI" && columns[0].extra.contains("IDENTITY"),
            "column metadata failed")
        let model = DatabaseModel()
        model.configure(fixture.connection)
        wait { !model.busy }
        model.selectDatabase(fixture.database)
        wait { !model.busy && model.tables.contains { $0.name == "items" } }
        model.loadTable("items")
        wait { !model.busy && model.data != nil }
        try fixture.require(model.error.isEmpty && model.columns.count == 4, "editor loading failed: " + model.error)
        model.selectSchema("shadow")
        wait { !model.busy }
        model.loadTable("items")
        wait { !model.busy && model.data != nil }
        try fixture.require(model.columns.last?.name == "note", "schema switching mixed table metadata")
    }
    private static func testRows(_ fixture: PostgreSQLCheckFixture) throws {
        let columns = try fixture.columns(), location = DatabaseLocation(database: fixture.database, schema: "work")
        let values: [String: CellDraft] = [
            "id": .init(text: "", mode: .omitted),
            "name": .init(text: "O'Reilly; DROP TABLE work.items; — 🦝", mode: .value),
            "active": .init(text: "true", mode: .value), "created_at": .init(text: "", mode: .null),
        ]
        let plan = try PostgreSQLSQL.rowPlan(
            location: location, table: "items", columns: columns, draft: .init(original: nil, values: values))
        try fixture.require(fixture.apply(plan).succeeded, "parameterized insertion failed")
        let snapshot = fixture.query("SELECT *, xmin::text FROM work.items").results[0]
        var update = RowDraft(
            original: Array(snapshot.cells[0].dropLast()), values: values, rowVersion: snapshot.text(0, 4))
        update.values["id"] = .init(text: "1", mode: .value)
        update.values["name"] = .init(text: "updated", mode: .value)
        let changed = try PostgreSQLSQL.rowPlan(location: location, table: "items", columns: columns, draft: update)
        try fixture.require(fixture.apply(changed).succeeded, "parameterized update failed")
        try fixture.require(!fixture.apply(changed).succeeded, "stale row update was not rejected")
        try fixture.require(
            fixture.query("SELECT name FROM work.items").results[0].text(0, 0) == "updated", "conflict altered data")
        let fresh = fixture.query("SELECT *, xmin::text FROM work.items").results[0]
        let deletion = RowDraft(original: Array(fresh.cells[0].dropLast()), values: [:], rowVersion: fresh.text(0, 4))
        try fixture.require(
            fixture.apply(
                try PostgreSQLSQL.rowPlan(
                    location: location, table: "items", columns: columns, draft: deletion, deleting: true)
            ).succeeded,
            "parameterized deletion failed")
        try fixture.require(fixture.apply(plan).succeeded, "insertion after deletion failed")
        try fixture.require(
            !fixture.connection.execute("SELECT 1; DROP TABLE work.items", database: fixture.database).succeeded,
            "form allowed extra statements")
    }
    private static func testColumns(_ fixture: PostgreSQLCheckFixture) throws {
        var draft = PostgreSQLColumnDraft()
        draft.name = "payload"
        draft.type = "jsonb"
        draft.size = ""
        draft.comment = "test 'comment'"
        let location = DatabaseLocation(database: fixture.database, schema: "work")
        try fixture.require(
            fixture.apply(try draft.plan(location: location, table: "items")).succeeded, "column creation failed")
        let column = try fixture.columns().first { $0.name == "payload" }!
        var edit = PostgreSQLColumnDraft(column: column)
        edit.name = "details"
        edit.defaultSQL = "'{}'::jsonb"
        try fixture.require(
            fixture.apply(try edit.plan(location: location, table: "items")).succeeded, "column rename/default failed")
        try fixture.require(try fixture.columns().last?.name == "details", "column catalog after edit failed")
        let failed = fixture.connection.execute(
            "ALTER TABLE work.items ADD COLUMN broken integer", database: fixture.database,
            options: .init(statements: ["ALTER TABLE work.items ADD COLUMN broken integer", "SELECT no_such_column"]))
        try fixture.require(
            !failed.succeeded && !(try fixture.columns()).contains { $0.name == "broken" },
            "failed structure batch was not rolled back")
    }
    /// The runtime ships PostgreSQL's contrib modules (built with `make world-bin`), which projects
    /// routinely depend on: pgcrypto needs the bundled OpenSSL, uuid-ossp the system UUID library.
    private static func testExtensions(_ fixture: PostgreSQLCheckFixture) throws {
        let required = ["pgcrypto", "uuid-ossp", "pg_trgm", "citext", "unaccent", "hstore"]
        let listed = required.map { "'" + $0 + "'" }.joined(separator: ", ")
        let available = fixture.query("SELECT name FROM pg_available_extensions WHERE name IN (\(listed))")
        let rows = available.results.first
        let names = Set((0..<(rows?.rows.count ?? 0)).compactMap { rows?.text($0, 0) })
        let missing = required.filter { !names.contains($0) }
        try fixture.require(
            available.succeeded && missing.isEmpty,
            "contrib extensions are not available: " + missing.joined(separator: ", "))
        let created = fixture.query(
            required.map { "CREATE EXTENSION \"\($0)\" SCHEMA shadow" }.joined(separator: "; "), multiple: true)
        try fixture.require(created.succeeded, "contrib extension creation failed: " + created.error)
        let probe = fixture.query(
            "SELECT encode(shadow.digest('moko', 'sha256'), 'hex'), shadow.uuid_generate_v4() IS NOT NULL, "
                + "shadow.similarity('moko', 'moko') = 1, shadow.unaccent('ação'), "
                + "'MOKO'::shadow.citext OPERATOR(shadow.=) 'moko'::shadow.citext,shadow.crypt('moko', shadow.gen_salt('bf')) <> ''")
        let row = probe.results.first
        try fixture.require(
            probe.succeeded
                && row?.text(0, 0) == "e7a03d87e87b1a33a06c9d62d24d37f41e218b13f856e66a65abd70de854b1f5"
                && row?.text(0, 3) == "acao"
                && [1, 2, 4, 5].allSatisfy { row?.text(0, $0) == "t" },
            "contrib extension functions failed: " + probe.error)
    }
    private static func testFiles(_ fixture: PostgreSQLCheckFixture) throws {
        let dump = fixture.folder.appendingPathComponent("database.sql")
        try DatabaseDump.write(fixture.connection, database: fixture.database, to: dump)
        try fixture.require(
            (try dump.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 100, "pg_dump output is empty")
        try fixture.require(
            fixture.connection.execute("CREATE DATABASE moko_restored").succeeded, "restore target failed")
        try DatabaseCommand.importFile(
            dump, connection: fixture.connection, database: "moko_restored", job: DatabaseExportJob())
        try fixture.require(
            fixture.connection.execute("SELECT count(*) FROM work.items", database: "moko_restored").results[0].text(
                0, 0) == "1", "psql import lost data")
        let invalid = fixture.folder.appendingPathComponent("invalid.sql")
        try Data("CREATE TABLE work.should_rollback(id integer); SELECT no_such_column;".utf8).write(to: invalid)
        do {
            try DatabaseCommand.importFile(
                invalid, connection: fixture.connection, database: fixture.database, job: DatabaseExportJob())
            throw DatabaseError.message("invalid import succeeded")
        } catch {
            try fixture.require(
                fixture.query("SELECT to_regclass('work.should_rollback')").results[0].text(0, 0) == nil,
                "failed import was not rolled back")
        }
    }
    private static func testCancellation(_ fixture: PostgreSQLCheckFixture) throws {
        let job = SQLQueryJob(), start = Date()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) { job.cancel() }
        let response = fixture.connection.execute(
            "SELECT pg_sleep(8)", database: fixture.database, options: .init(job: job))
        try fixture.require(
            !response.succeeded && response.sqlState == "57014" && Date().timeIntervalSince(start) < 4,
            "query cancellation failed: " + response.error)
    }
    private static func testResultLimits(_ fixture: PostgreSQLCheckFixture) throws {
        let response = fixture.connection.execute(
            "SELECT generate_series(1,10000)", database: fixture.database, maxRows: 5)
        try fixture.require(
            response.succeeded && response.results.count == 1
                && response.results[0].rows.count == 5 && response.results[0].truncated,
            "chunked query did not enforce the display limit")
        let multiple = fixture.query(
            "SELECT generate_series(1,100); SELECT decode('00ff','hex') AS bytes", multiple: true)
        try fixture.require(
            multiple.succeeded && multiple.results.count == 2
                && multiple.results[0].rows.count == 100 && multiple.results[1].rows[0][0] == "00ff",
            "chunked results were mixed or binary bytes were lost")
        let failed = fixture.query("SELECT 1/(value-90) FROM generate_series(1,100) value")
        try fixture.require(
            !failed.succeeded && failed.sqlState == "22012" && failed.results.isEmpty,
            "rows from a failed streamed query were retained")
    }
    private static func testPHP(_ fixture: PostgreSQLCheckFixture) throws {
        fixture.checks += try PHPDatabaseExampleChecks.run(
            connection: fixture.connection, database: fixture.database, folder: fixture.folder)
        let process = Process(), output = Pipe()
        process.executableURL = RuntimePaths.executable("PHP/bin/php")
        process.arguments = [
            "-c", RuntimePaths.executable("PHP/php.ini").path, "-r",
            """
            foreach(['pdo_pgsql','pgsql','pdo_mysql','mysqli'] as $e) { if(!extension_loaded($e)) exit(4); }
            $db = new PDO('pgsql:host=127.0.0.1;port='.getenv('PGPORT').';dbname=moko_validation', 'moko', getenv('PGPASSWORD'));
            echo $db->query('SELECT count(*) FROM work.items')->fetchColumn();
            """,
        ]
        process.environment = DatabaseCommand.environment(fixture.connection).merging([
            "PGPORT": fixture.connection.port, "PHP_INI_SCAN_DIR": "",
        ]) { _, new in new }
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(bytes: data, encoding: .utf8) ?? ""
        try fixture.require(process.terminationStatus == 0 && text == "1", "PHP PostgreSQL driver failed: " + text)
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
