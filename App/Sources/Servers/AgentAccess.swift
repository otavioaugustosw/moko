import Foundation

/// Opt-in access for AI agents through `moko --mcp` (Model Context Protocol over stdio).
/// The server is a child process of the agent: nothing listens on the network.
enum AgentAccess {
    enum Mode: String, CaseIterable, Identifiable {
        case read, write
        var id: String { rawValue }
        var title: String { self == .read ? "read only" : "read and write" }
    }
    static let enabledKey = "moko.agents.enabled"
    static let modeKey = "moko.agents.mode"
    static let serverName = "moko"

    static func enabled(_ preferences: UserDefaults = .standard) -> Bool {
        preferences.synchronize()
        return preferences.bool(forKey: enabledKey)
    }
    static func mode(_ preferences: UserDefaults = .standard) -> Mode {
        preferences.synchronize()
        return Mode(rawValue: preferences.string(forKey: modeKey) ?? "") ?? .read
    }
    static var executable: String { Bundle.main.executablePath ?? CommandLine.arguments[0] }
    static var logURL: URL { RuntimePaths.storage.appendingPathComponent("Agent Activity.log") }

    /// Arguments for `claude mcp add`; the user scope makes the server available in every project.
    static func claudeArguments(executable: String) -> [String] {
        ["mcp", "add", "--scope", "user", serverName, "--", executable, "--mcp"]
    }
    static func claudeCommand(executable: String) -> String {
        (["claude"] + claudeArguments(executable: executable)).map(shellWord).joined(separator: " ")
    }
    static func configuration(executable: String) -> String {
        let server: [String: Any] = ["command": executable, "args": ["--mcp"]]
        let data =
            (try? JSONSerialization.data(
                withJSONObject: ["mcpServers": [serverName: server]],
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(bytes: data, encoding: .utf8) ?? ""
    }
    static func claudeExecutable(home: String = NSHomeDirectory(), exists: (String) -> Bool = defaultExists) -> String? {
        [home + "/.local/bin/claude", home + "/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first(where: exists)
    }
    private static func defaultExists(_ path: String) -> Bool { FileManager.default.isExecutableFile(atPath: path) }
    private static func shellWord(_ word: String) -> String {
        word.range(of: #"^[A-Za-z0-9_./:=@-]+$"#, options: .regularExpression) != nil ? word : quoteShell(word)
    }
    static func record(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let entry = Data((stamp + " " + line.replacingOccurrences(of: "\n", with: " ") + "\n").utf8)
        try? FileManager.default.createDirectory(at: RuntimePaths.storage, withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: entry)
        } else {
            try? entry.write(to: logURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logURL.path)
        }
    }
}

/// Decides whether a statement may run in read-only mode. It is a guard against accidents, not a
/// security boundary: the database account's own privileges remain the real limit.
enum AgentSQLGuard {
    private static let readers: Set<String> = ["SELECT", "SHOW", "DESCRIBE", "DESC", "EXPLAIN", "WITH", "TABLE", "VALUES"]
    private static let refused: Set<String> = [
        "INSERT", "UPDATE", "DELETE", "MERGE", "INTO", "OUTFILE", "DUMPFILE", "CREATE", "DROP", "ALTER", "TRUNCATE",
        "EXECUTE", "PREPARE", "CALL", "GRANT", "REVOKE", "COPY", "LOCK", "COMMIT", "ROLLBACK", "NEXTVAL", "SETVAL",
        "SET_CONFIG", "PG_TERMINATE_BACKEND", "PG_CANCEL_BACKEND", "PG_RELOAD_CONF", "PG_READ_FILE",
        "PG_READ_BINARY_FILE", "PG_LS_DIR", "PG_SLEEP", "PG_ADVISORY_LOCK", "LO_IMPORT", "LO_EXPORT", "DBLINK",
        "DBLINK_EXEC", "LOAD_FILE", "SLEEP", "BENCHMARK", "GET_LOCK",
    ]
    /// Returns nil when the SQL is one read-only statement, otherwise the reason it was refused.
    static func refusal(_ sql: String, postgres: Bool) -> String? {
        if sql.contains("/*!") || sql.contains("/*M!") || sql.contains("/*+") {
            return "read-only access does not run executable comments or optimizer hints"
        }
        guard let statements = split(sql, postgres: postgres) else {
            return "read-only access does not accept backslashes inside quoted text"
        }
        guard !statements.isEmpty else { return "the statement is empty" }
        guard statements.count == 1 else { return "read-only access runs one statement at a time" }
        let words = statements[0].uppercased().split { !($0.isLetter || $0.isNumber || $0 == "_") }.map(String.init)
        guard let first = words.first, readers.contains(first) else {
            return "read-only access accepts only select, show, describe, explain, with, table and values"
        }
        if let word = words.first(where: refused.contains) {
            return "read-only access does not run statements containing " + word.lowercased()
        }
        return nil
    }
    /// Statements with comments, quoted text and quoted identifiers removed, split on semicolons.
    /// Returns nil when quoted text contains a backslash, whose meaning depends on server settings.
    static func split(_ sql: String, postgres: Bool) -> [String]? {
        var statements = [String](), current = "", index = sql.startIndex
        func starts(_ text: String) -> Bool { sql[index...].hasPrefix(text) }
        func skip(past terminator: String, from start: String.Index) {
            index = sql.range(of: terminator, range: start..<sql.endIndex)?.upperBound ?? sql.endIndex
        }
        while index < sql.endIndex {
            let character = sql[index]
            if lineComment(sql, at: index, postgres: postgres) {
                skip(past: "\n", from: index)
                current.append(" ")
            } else if starts("/*") {
                skip(past: "*/", from: sql.index(index, offsetBy: 2))
                current.append(" ")
            } else if character == "'" || character == "\"" || (character == "`" && !postgres) {
                guard let end = endOfQuoted(sql, from: index, quote: character) else { return nil }
                index = end
                current.append(" x ")
            } else if postgres, character == "$", let tag = dollarTag(sql, at: index) {
                skip(past: tag, from: sql.index(index, offsetBy: tag.count))
                current.append(" x ")
            } else if character == ";" {
                statements.append(current)
                current = ""
                index = sql.index(after: index)
            } else {
                current.append(character)
                index = sql.index(after: index)
            }
        }
        statements.append(current)
        return statements.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    /// MySQL needs whitespace after `--` and also accepts `#`; PostgreSQL treats `#` as an operator.
    private static func lineComment(_ sql: String, at index: String.Index, postgres: Bool) -> Bool {
        if sql[index] == "#" { return !postgres }
        guard sql[index...].hasPrefix("--") else { return false }
        if postgres { return true }
        let after = sql.index(index, offsetBy: 2)
        return after == sql.endIndex || sql[after].isWhitespace
    }
    private static func endOfQuoted(_ sql: String, from start: String.Index, quote: Character) -> String.Index? {
        var index = sql.index(after: start)
        while index < sql.endIndex {
            let character = sql[index], next = sql.index(after: index)
            if character == "\\" { return nil }
            if character == quote {
                guard next < sql.endIndex, sql[next] == quote else { return next }
                index = sql.index(after: next)
            } else {
                index = next
            }
        }
        return sql.endIndex
    }
    private static func dollarTag(_ sql: String, at start: String.Index) -> String? {
        var index = sql.index(after: start)
        while index < sql.endIndex, sql[index].isLetter || sql[index].isNumber || sql[index] == "_" {
            index = sql.index(after: index)
        }
        guard index < sql.endIndex, sql[index] == "$" else { return nil }
        let tag = String(sql[start...index])
        return tag.dropFirst().first?.isNumber == true ? nil : tag
    }
}
