import Foundation

enum DatabaseSQL {
    static func tableMetadata(database: String, table: String) -> String {
        let target = qualified(database, table)
        let condition = "TABLE_SCHEMA = \(literal(database)) AND TABLE_NAME = \(literal(table))"
        // STATISTICS has engine-specific columns. SELECT * preserves them when
        // available without requiring MySQL-only IS_VISIBLE or EXPRESSION on MariaDB.
        return """
            SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_KEY, COLUMN_DEFAULT, EXTRA, COALESCE(COLLATION_NAME,''), COLUMN_COMMENT
            FROM information_schema.COLUMNS WHERE \(condition) ORDER BY ORDINAL_POSITION;
            SHOW CREATE TABLE \(target);
            SELECT *
            FROM information_schema.STATISTICS WHERE \(condition) ORDER BY INDEX_NAME, SEQ_IN_INDEX;
            SELECT CONSTRAINT_NAME, COLUMN_NAME, REFERENCED_TABLE_SCHEMA, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME
            FROM information_schema.KEY_COLUMN_USAGE WHERE \(condition) AND REFERENCED_TABLE_NAME IS NOT NULL ORDER BY CONSTRAINT_NAME, ORDINAL_POSITION;
            """
    }
    static func identifier(_ text: String) -> String { "`" + text.replacingOccurrences(of: "`", with: "``") + "`" }
    static func literal(_ text: String) -> String { "CONVERT(X'" + Data(text.utf8).hexString + "' USING utf8mb4)" }
    // Form sessions use a known escaping mode; the console preserves the server mode.
    static func ddlString(_ text: String) -> String {
        "'"
            + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "''")
            .replacingOccurrences(of: "\0", with: "\\0") + "'"
    }
    static func qualified(_ database: String, _ table: String) -> String {
        identifier(database) + "." + identifier(table)
    }
    static func columnPlan(database: String, table: String, draft: ColumnEditorDraft) throws -> SQLPlan {
        let action = draft.original.map { "CHANGE COLUMN \(identifier($0))" } ?? "ADD COLUMN"
        return .init(
            title: draft.original == nil ? "add column" : "change column",
            sql:
                "ALTER TABLE \(qualified(database, table)) \(action) \(identifier(draft.name)) \(try draft.builtDefinition());",
            database: database)
    }
    static func value(_ draft: CellDraft, column: DatabaseColumn) throws -> String {
        if draft.mode == .null {
            guard column.nullable else { throw DatabaseError.message("\(column.name) does not allow null") }
            return "NULL"
        }
        if column.binary {
            let value = draft.text.hasPrefix("0x") ? String(draft.text.dropFirst(2)) : draft.text
            guard Data(hex: value) != nil else {
                throw DatabaseError.message("\(column.name): enter hexadecimal bytes")
            }
            return "X'\(value)'"
        }
        return literal(draft.text)
    }
    static func predicate(columns: [DatabaseColumn], original: [SQLCell]) throws -> String {
        guard columns.count == original.count, columns.contains(where: { $0.key == "PRI" }) else {
            throw DatabaseError.message("this table has no primary key; use the sql editor to make changes")
        }
        // Compare the entire original row as bytes, avoiding collation matches and lost updates.
        return zip(columns, original).map { column, cell in
            "CAST(\(identifier(column.name)) AS BINARY) <=> " + (cell.hex.map { "X'\($0)'" } ?? "NULL")
        }.joined(separator: " AND ")
    }
    static func rowPlan(database: String, table: String, columns: [DatabaseColumn], draft: RowDraft) throws -> SQLPlan {
        let target = qualified(database, table)
        if let original = draft.original {
            guard original.count == columns.count else {
                throw DatabaseError.message("the structure changed; refresh the table before editing")
            }
            var changes = [String]()
            var summaries = [String]()
            for (index, column) in columns.enumerated() where !column.generated {
                guard let value = draft.values[column.name] else { continue }
                if value.mode == .omitted {
                    changes.append(identifier(column.name) + " = DEFAULT")
                    summaries.append(column.name + ": default")
                    continue
                }
                let old = original[index]
                let unchanged =
                    value.mode == .null
                    ? old.hex == nil : (old.hex != nil && value.text == old.display(binary: column.binary))
                if !unchanged {
                    changes.append(identifier(column.name) + " = " + (try self.value(value, column: column)))
                    summaries.append(
                        column.name + ": " + String(old.display(binary: column.binary).prefix(120)) + " → "
                            + (value.mode == .null ? "null" : String(value.text.prefix(120))))
                }
            }
            guard !changes.isEmpty else { throw DatabaseError.message("no values changed") }
            return .init(
                title: "save row",
                sql:
                    "UPDATE \(target) SET \(changes.joined(separator: ", ")) WHERE \(try predicate(columns: columns, original: original)) LIMIT 1;",
                database: database, oneRow: true, summary: summaries.joined(separator: "\n"))
        }
        let included = columns.filter { !$0.generated && draft.values[$0.name].map { $0.mode != .omitted } == true }
        let values = try included.map { try value(draft.values[$0.name]!, column: $0) }
        return .init(
            title: "insert row",
            sql:
                "INSERT INTO \(target) (\(included.map { identifier($0.name) }.joined(separator: ", "))) VALUES (\(values.joined(separator: ", ")));",
            database: database, oneRow: true)
    }
    static func deletePlan(database: String, table: String, columns: [DatabaseColumn], row: [SQLCell]) throws -> SQLPlan {
        .init(
            title: "delete row",
            sql:
                "DELETE FROM \(qualified(database, table)) WHERE \(try predicate(columns: columns, original: row)) LIMIT 1;",
            database: database, oneRow: true, destructive: true,
            summary: "1 row from \(database).\(table)")
    }
    // SHOW CREATE preserves generated expressions, comments, invisible columns, enum values and defaults.
    static func columnDefinition(_ name: String, ddl: String) -> String? {
        guard let start = ddl.firstIndex(of: "(") else { return nil }
        var pieces = [String]()
        var part = ""
        var depth = 0
        var quote: Character?
        var escaped = false
        for char in ddl[ddl.index(after: start)...] {
            if let quotedCharacter = quote {
                part.append(char)
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == quotedCharacter {
                    quote = nil
                }
                continue
            }
            if char == "'" || char == "\"" || char == "`" {
                quote = char
                part.append(char)
                continue
            }
            if char == "(" { depth += 1 }
            if char == ")" {
                if depth == 0 {
                    pieces.append(part)
                    break
                }
                depth -= 1
            }
            if char == "," && depth == 0 {
                pieces.append(part)
                part = ""
            } else {
                part.append(char)
            }
        }
        let prefix = identifier(name) + " "
        return pieces.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { $0.hasPrefix(prefix) }.map {
            String($0.dropFirst(prefix.count))
        }
    }
}
