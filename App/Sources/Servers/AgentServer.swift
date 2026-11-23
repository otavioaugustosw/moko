import Foundation

/// Model Context Protocol server over stdio, started with `moko --mcp` by the agent itself.
/// Standard output carries only protocol messages, one JSON object per line.
enum AgentServer {
    static let protocols = ["2025-06-18", "2025-03-26", "2024-11-05"]
    static let instructions = """
        moko gives access to the user's local development databases (postgresql, mariadb, mysql). \
        call list_connections first. read-only access refuses anything except one select, show, describe, \
        explain, with, table or values statement. ask the user before changing or deleting data.
        """

    static func run() -> Never {
        while let line = readLine(strippingNewline: true) {
            guard let data = line.data(using: .utf8), !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "parse error"]])
                continue
            }
            if let reply = handle(message) { send(reply) }
        }
        exit(0)
    }
    private static func send(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else {
            return
        }
        FileHandle.standardOutput.write(data + Data("\n".utf8))
    }
    /// Returns the response for a request, or nil for a notification.
    static func handle(_ message: [String: Any], tools: AgentTools = AgentTools()) -> [String: Any]? {
        guard let method = message["method"] as? String else { return nil }
        guard let identifier = message["id"], !(identifier is NSNull) else { return nil }
        let parameters = message["params"] as? [String: Any] ?? [:]
        func result(_ value: [String: Any]) -> [String: Any] { ["jsonrpc": "2.0", "id": identifier, "result": value] }
        switch method {
        case "initialize":
            let requested = parameters["protocolVersion"] as? String ?? ""
            return result([
                "protocolVersion": protocols.contains(requested) ? requested : protocols[0],
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": [
                    "name": AgentAccess.serverName,
                    "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
                ],
                "instructions": instructions,
            ])
        case "ping": return result([:])
        case "tools/list": return result(["tools": AgentTools.definitions])
        case "tools/call":
            let name = parameters["name"] as? String ?? ""
            let outcome = tools.call(name, arguments: parameters["arguments"] as? [String: Any] ?? [:])
            return result(["content": [["type": "text", "text": outcome.text]], "isError": outcome.failed])
        default:
            return ["jsonrpc": "2.0", "id": identifier, "error": ["code": -32601, "message": "method not found: " + method]]
        }
    }
}

struct AgentOutcome: Error {
    var text: String
    var failed = false
    static func failure(_ text: String) -> AgentOutcome { .init(text: text, failed: true) }
}

/// The tools an agent can call. Dependencies are injected so the checks run without a database.
struct AgentTools {
    var enabled: () -> Bool = { AgentAccess.enabled() }
    var mode: () -> AgentAccess.Mode = { AgentAccess.mode() }
    var profiles: () -> [ConnectionProfile] = { ConnectionProfiles.stored().items }
    var selected: () -> UUID? = { ConnectionProfiles.stored().selected }
    var password: (ConnectionProfile) -> String? = { Credentials.read($0.credentialAccount, allowInteraction: false) }
    var execute: (DatabaseConnection, String, String, Bool, UInt32) -> SQLResponse = {
        $0.execute($1, database: $2, multiple: $3, maxRows: $4)
    }
    var record: (String) -> Void = AgentAccess.record

    static let definitions: [[String: Any]] = [
        tool("list_connections", "List the database connections configured in moko and the current access mode.", [:]),
        tool("list_databases", "List the databases of a connection.", ["connection": connectionProperty]),
        tool(
            "list_tables", "List the tables and views of a database.",
            ["connection": connectionProperty, "database": text("Database name.")], required: ["database"]),
        tool(
            "describe_table", "List the columns of a table: type, nullability, default and key.",
            [
                "connection": connectionProperty, "database": text("Database name."), "table": text("Table name."),
                "schema": text("PostgreSQL schema. Defaults to public."),
            ], required: ["database", "table"]),
        tool(
            "run_sql",
            "Run SQL. Read-only access accepts a single reading statement; read and write access runs any statement.",
            [
                "connection": connectionProperty,
                "database": text("Database to run in. Required for PostgreSQL unless the connection has a default."),
                "sql": text("The SQL text."),
                "max_rows": ["type": "integer", "description": "Rows to return, 1 to 1000. Defaults to 200."],
            ], required: ["sql"]),
    ]
    private static let connectionProperty = text("Connection name from list_connections. Defaults to the one selected in moko.")
    private static func text(_ description: String) -> [String: Any] { ["type": "string", "description": description] }
    private static func tool(
        _ name: String, _ description: String, _ properties: [String: Any], required: [String] = []
    ) -> [String: Any] {
        [
            "name": name, "description": description,
            "inputSchema": ["type": "object", "properties": properties, "required": required],
        ]
    }

    func call(_ name: String, arguments: [String: Any]) -> AgentOutcome {
        guard enabled() else {
            return .failure("agent access is turned off. the user can turn it on in moko → settings → agents.")
        }
        let outcome: AgentOutcome
        switch name {
        case "list_connections": outcome = connections()
        case "list_databases": outcome = query(arguments) { $0.engine.isPostgreSQL ? Self.postgresDatabases : "SHOW DATABASES" }
        case "list_tables": outcome = query(arguments, needsDatabase: true) { Self.tablesSQL($0, arguments) }
        case "describe_table": outcome = query(arguments, needsDatabase: true) { Self.columnsSQL($0, arguments) }
        case "run_sql": outcome = runSQL(arguments)
        default: return .failure("unknown tool: " + name)
        }
        let target = [arguments["connection"], arguments["database"]].compactMap { $0 as? String }.joined(separator: "/")
        let statement = (arguments["sql"] as? String).map { " · " + String($0.prefix(300)) } ?? ""
        record(name + (target.isEmpty ? "" : " " + target) + (outcome.failed ? " · refused or failed" : " · ok") + statement)
        return outcome
    }

    private func connections() -> AgentOutcome {
        let current = selected()
        let items: [[String: Any]] = profiles().map {
            [
                "name": $0.name, "engine": $0.engine.rawValue, "host": $0.host, "port": $0.port, "user": $0.user,
                "managed_by_moko": $0.managed, "selected": $0.id == current, "password_saved": password($0) != nil,
            ]
        }
        return .init(text: Self.json(["access": mode().title, "connections": items]))
    }
    private func connection(_ arguments: [String: Any]) -> Result<DatabaseConnection, AgentOutcome> {
        let all = profiles()
        let wanted = (arguments["connection"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let profile =
            wanted.isEmpty
            ? all.first { $0.id == selected() } ?? all.first
            : all.first { $0.name.caseInsensitiveCompare(wanted) == .orderedSame || $0.id.uuidString == wanted }
        guard let profile else {
            return .failure(.failure("no connection named \(wanted). call list_connections for the names."))
        }
        guard let secret = password(profile) else {
            return .failure(
                .failure(
                    "moko has no saved password for \(profile.name). "
                        + "the user can save it in moko → settings → connection."))
        }
        return .success(profile.connection(password: secret))
    }
    private func query(
        _ arguments: [String: Any], needsDatabase: Bool = false, sql: (DatabaseConnection) -> String?
    ) -> AgentOutcome {
        let database = arguments["database"] as? String ?? ""
        if needsDatabase && database.isEmpty { return .failure("the database argument is required.") }
        switch connection(arguments) {
        case let .failure(outcome): return outcome
        case let .success(connection):
            guard let statement = sql(connection) else { return .failure("the table argument is required.") }
            return Self.render(execute(connection, statement, connection.engine.isPostgreSQL ? database : "", false, 1000))
        }
    }
    private func runSQL(_ arguments: [String: Any]) -> AgentOutcome {
        let sql = (arguments["sql"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sql.isEmpty else { return .failure("the sql argument is required.") }
        let rows = UInt32(min(1000, max(1, arguments["max_rows"] as? Int ?? 200)))
        let database = arguments["database"] as? String ?? ""
        switch connection(arguments) {
        case let .failure(outcome): return outcome
        case let .success(connection):
            guard mode() == .read else { return Self.render(execute(connection, sql, database, true, rows)) }
            if let reason = AgentSQLGuard.refusal(sql, postgres: connection.engine.isPostgreSQL) {
                return .failure(reason + ". the user can allow changes in moko → settings → agents.")
            }
            let body = sql.hasSuffix(";") ? String(sql.dropLast()) : sql
            let opening = connection.engine.isPostgreSQL ? "BEGIN READ ONLY" : "START TRANSACTION READ ONLY"
            return Self.render(execute(connection, opening + "; " + body + "; ROLLBACK", database, true, rows), wrapped: true)
        }
    }

    private static let postgresDatabases = "SELECT datname AS database FROM pg_database WHERE NOT datistemplate ORDER BY 1"
    private static func tablesSQL(_ connection: DatabaseConnection, _ arguments: [String: Any]) -> String {
        if connection.engine.isPostgreSQL {
            return """
                SELECT table_schema AS schema, table_name AS name, table_type AS kind FROM information_schema.tables
                WHERE table_schema NOT IN ('pg_catalog', 'information_schema') ORDER BY 1, 2
                """
        }
        return "SELECT TABLE_NAME AS name, TABLE_TYPE AS kind, ENGINE AS engine, TABLE_ROWS AS estimated_rows "
            + "FROM information_schema.TABLES WHERE TABLE_SCHEMA = "
            + DatabaseSQL.literal(arguments["database"] as? String ?? "") + " ORDER BY 1"
    }
    private static func columnsSQL(_ connection: DatabaseConnection, _ arguments: [String: Any]) -> String? {
        guard let table = arguments["table"] as? String, !table.isEmpty else { return nil }
        if connection.engine.isPostgreSQL {
            let schema = (arguments["schema"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "public"
            return "SELECT column_name AS name, data_type AS type, is_nullable AS nullable, column_default AS default_value "
                + "FROM information_schema.columns WHERE table_schema = " + PostgreSQLSQL.literal(schema)
                + " AND table_name = " + PostgreSQLSQL.literal(table) + " ORDER BY ordinal_position"
        }
        return "SELECT COLUMN_NAME AS name, COLUMN_TYPE AS type, IS_NULLABLE AS nullable, COLUMN_DEFAULT AS default_value, "
            + "COLUMN_KEY AS column_key, EXTRA AS extra FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = "
            + DatabaseSQL.literal(arguments["database"] as? String ?? "") + " AND TABLE_NAME = "
            + DatabaseSQL.literal(table) + " ORDER BY ORDINAL_POSITION"
    }

    /// `wrapped` drops the results of the read-only transaction's own opening and closing statements.
    static func render(_ response: SQLResponse, wrapped: Bool = false) -> AgentOutcome {
        guard response.succeeded else {
            return .failure(response.error.isEmpty ? "the server refused the statement (code \(response.code))." : response.error)
        }
        var results = response.results
        if wrapped, results.count >= 2 { results = Array(results.dropFirst().dropLast()) }
        let rendered: [[String: Any]] = results.map { result in
            guard !result.fields.isEmpty else { return ["rows_affected": result.affected] }
            let rows: [[Any]] = result.rows.map { row in
                zip(row, result.fields).map { cell, field in
                    guard cell != nil else { return NSNull() }
                    let value = SQLCell(hex: cell).display(binary: field.binary)
                    return value.count > 2000 ? String(value.prefix(2000)) + "… [truncated]" : value
                }
            }
            return [
                "columns": result.fields.map(\.name), "rows": rows, "row_count": rows.count,
                "truncated": result.truncated,
            ]
        }
        let value: [String: Any] = rendered.count == 1 ? rendered[0] : ["results": rendered]
        return AgentOutcome(text: json(value))
    }
    static func json(_ value: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}
