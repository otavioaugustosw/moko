import Foundation

enum AgentAccessChecks {
    private final class Recorder {
        var statements = [String]()
        var multiple = [Bool]()
        var log = [String]()
    }
    static func run() throws -> Int {
        var checks = 0
        func require(_ condition: Bool, _ detail: String) throws {
            guard condition else { throw DatabaseError.message("agent access: " + detail) }
            checks += 1
        }
        try guardChecks(require)
        try toolChecks(require)
        try protocolChecks(require)
        try setupChecks(require)
        return checks
    }
    private static func guardChecks(_ require: (Bool, String) throws -> Void) throws {
        let accepted = [
            "SELECT 1", "select * from t where a = 'x; drop table t'", "WITH a AS (SELECT 1) SELECT * FROM a;",
            "SHOW TABLES", "EXPLAIN SELECT 1", "SELECT CASE WHEN a = 1 THEN 2 END FROM t",
            "SELECT replace(a, 'x', 'y') FROM t -- drop table t", "SELECT 1 /* delete from t */",
        ]
        for sql in accepted {
            try require(AgentSQLGuard.refusal(sql, postgres: true) == nil, "postgresql should accept " + sql)
            try require(AgentSQLGuard.refusal(sql, postgres: false) == nil, "mysql should accept " + sql)
        }
        let refused = [
            "", "DROP TABLE t", "SELECT 1; DROP TABLE t", "WITH d AS (DELETE FROM t RETURNING *) SELECT * FROM d",
            "SELECT * INTO copy FROM t", "SELECT 'a\\'; DROP TABLE t; --'", "/*! DROP TABLE t */ SELECT 1",
            "EXPLAIN ANALYZE DELETE FROM t", "SELECT pg_terminate_backend(1)", "SELECT * FROM t FOR UPDATE",
            "SELECT a FROM t INTO OUTFILE '/tmp/x'", "UPDATE t SET a = 1", "CALL p()",
        ]
        for sql in refused {
            try require(AgentSQLGuard.refusal(sql, postgres: true) != nil, "postgresql should refuse " + sql)
            try require(AgentSQLGuard.refusal(sql, postgres: false) != nil, "mysql should refuse " + sql)
        }
        try require(AgentSQLGuard.refusal("SELECT 1--1; DROP TABLE t", postgres: false) != nil, "mysql -- needs a space")
        try require(AgentSQLGuard.refusal("SELECT 1 # 2; DROP TABLE t", postgres: true) != nil, "# is not a postgresql comment")
        try require(AgentSQLGuard.refusal("SELECT 1 # ; drop table t", postgres: false) == nil, "# is a mysql comment")
        try require(AgentSQLGuard.refusal("SELECT $a$; DROP TABLE t; $a$", postgres: false) != nil, "mysql has no dollar quotes")
        try require(AgentSQLGuard.refusal("SELECT $a$; drop table t; $a$", postgres: true) == nil, "postgresql dollar quotes")
        try require(AgentSQLGuard.refusal("SELECT `a;b` FROM t", postgres: false) == nil, "mysql backtick identifiers")
        try require(AgentSQLGuard.refusal("SELECT 1 ` ; DROP TABLE t; `", postgres: true) != nil, "postgresql backticks")
    }
    private static func tools(
        _ recorder: Recorder, enabled: Bool = true, mode: AgentAccess.Mode = .read, password: String? = "secret"
    ) -> AgentTools {
        let postgres = ConnectionProfile.local(.postgresql)
        var mysql = ConnectionProfile.local(.mariadb)
        mysql.name = "Existing Server"
        let result = SQLResult(
            fields: [SQLField(name: "n", type: 3, binary: false)], rows: [["31"], [nil]], affected: 0, truncated: false,
            warnings: 0)
        let empty = SQLResult(fields: [], rows: [], affected: 0, truncated: false, warnings: 0)
        return AgentTools(
            enabled: { enabled }, mode: { mode }, profiles: { [postgres, mysql] }, selected: { postgres.id },
            password: { _ in password },
            execute: { _, sql, _, multiple, _ in
                recorder.statements.append(sql)
                recorder.multiple.append(multiple)
                return SQLResponse(results: multiple ? [empty, result, empty] : [result], code: 0, error: "", rolledBack: false)
            }, record: { recorder.log.append($0) })
    }
    private static func toolChecks(_ require: (Bool, String) throws -> Void) throws {
        var recorder = Recorder()
        let off = tools(recorder, enabled: false).call("run_sql", arguments: ["sql": "SELECT 1"])
        try require(off.failed && off.text.contains("turned off") && recorder.statements.isEmpty, "disabled access runs nothing")
        let listed = tools(recorder).call("list_connections", arguments: [:])
        try require(
            !listed.failed && listed.text.contains("local postgresql") && listed.text.contains("read only")
                && !listed.text.contains("secret"), "connections are listed without passwords")
        try require(tools(recorder).call("run_sql", arguments: ["sql": "SELECT 1", "connection": "nope"]).failed, "unknown connection")
        let locked = tools(recorder, password: nil).call("run_sql", arguments: ["sql": "SELECT 1"])
        try require(locked.failed && locked.text.contains("no saved password") && recorder.statements.isEmpty, "missing password")
        let read = tools(recorder).call("run_sql", arguments: ["sql": "SELECT 1;"])
        try require(
            recorder.statements == ["BEGIN READ ONLY; SELECT 1; ROLLBACK"] && recorder.multiple == [true],
            "postgresql reads run inside a read-only transaction")
        try require(!read.failed && read.text.contains("\"rows\":[[\"1\"],[null]]") && !read.text.contains("results"), "rows render")
        recorder = Recorder()
        _ = tools(recorder).call("run_sql", arguments: ["sql": "SELECT 1", "connection": "existing server"])
        try require(recorder.statements == ["START TRANSACTION READ ONLY; SELECT 1; ROLLBACK"], "mysql read-only transaction")
        let refused = tools(recorder).call("run_sql", arguments: ["sql": "DELETE FROM t"])
        try require(refused.failed && recorder.statements.count == 1, "refused statements never reach the server")
        try require(recorder.log.count == 2 && recorder.log[1].contains("refused"), "every call is recorded")
        recorder = Recorder()
        _ = tools(recorder, mode: .write).call("run_sql", arguments: ["sql": "DELETE FROM t; SELECT 1"])
        try require(recorder.statements == ["DELETE FROM t; SELECT 1"], "write access sends the statement unchanged")
        _ = tools(recorder).call("describe_table", arguments: ["database": "d", "table": "it's"])
        try require(recorder.statements.last?.contains("'it''s'") == true, "table names are quoted as literals")
        try require(tools(recorder).call("list_tables", arguments: [:]).failed, "list_tables requires a database")
    }
    private static func protocolChecks(_ require: (Bool, String) throws -> Void) throws {
        let recorder = Recorder()
        func handle(_ message: [String: Any]) -> [String: Any]? { AgentServer.handle(message, tools: tools(recorder)) }
        func result(_ message: [String: Any]) -> [String: Any] { handle(message)?["result"] as? [String: Any] ?? [:] }
        let known = result(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2024-11-05"]])
        try require(known["protocolVersion"] as? String == "2024-11-05", "supported protocol version is echoed")
        let unknown = result(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "1999-01-01"]])
        try require(unknown["protocolVersion"] as? String == AgentServer.protocols[0], "unknown version falls back")
        try require(handle(["jsonrpc": "2.0", "method": "notifications/initialized"]) == nil, "notifications get no reply")
        let listed = result(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])["tools"] as? [[String: Any]] ?? []
        try require(listed.count == 5 && listed.allSatisfy { $0["inputSchema"] != nil }, "five tools with schemas")
        let missing = handle(["jsonrpc": "2.0", "id": 3, "method": "resources/list"])?["error"] as? [String: Any]
        try require(missing?["code"] as? Int == -32601, "unknown methods are rejected")
        let called = result([
            "jsonrpc": "2.0", "id": "a", "method": "tools/call",
            "params": ["name": "run_sql", "arguments": ["sql": "DROP TABLE t"]],
        ])
        try require(called["isError"] as? Bool == true, "tool refusals are reported as tool errors")
        try require(((called["content"] as? [[String: Any]])?.first?["text"] as? String)?.contains("read-only") == true, "reason")
    }
    private static func setupChecks(_ require: (Bool, String) throws -> Void) throws {
        let path = "/Volumes/My Disk/moko.app/Contents/MacOS/moko"
        try require(
            AgentAccess.claudeCommand(executable: path)
                == "claude mcp add --scope user moko -- '/Volumes/My Disk/moko.app/Contents/MacOS/moko' --mcp",
            "claude command quotes the path")
        let data = Data(AgentAccess.configuration(executable: path).utf8)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: [String: Any]]]
        try require(json?["mcpServers"]?["moko"]?["command"] as? String == path, "json configuration keeps the path")
        try require(json?["mcpServers"]?["moko"]?["args"] as? [String] == ["--mcp"], "json configuration passes --mcp")
        try require(
            AgentAccess.claudeExecutable(home: "/h", exists: { $0 == "/opt/homebrew/bin/claude" }) == "/opt/homebrew/bin/claude",
            "claude is located")
        try require(AgentAccess.claudeExecutable(home: "/h", exists: { _ in false }) == nil, "missing claude is reported")
        let preferences = UserDefaults(suiteName: "moko-agent-checks-" + UUID().uuidString)!
        try require(!AgentAccess.enabled(preferences) && AgentAccess.mode(preferences) == .read, "off and read only by default")
    }
}
