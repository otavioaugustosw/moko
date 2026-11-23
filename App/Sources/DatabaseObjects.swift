import Foundation

enum DatabaseObjectKind: String, CaseIterable, Identifiable {
    case procedure, function, trigger, event, view, schema, sequence
    case materializedView = "materialized view"
    var id: String { rawValue }
    var title: String { rawValue + "s" }
    var symbol: String {
        switch self {
        case .procedure: "list.bullet.rectangle"
        case .function: "function"
        case .trigger: "bolt"
        case .event: "calendar.badge.clock"
        case .view, .materializedView: "eye"
        case .schema: "folder"
        case .sequence: "number"
        }
    }
    var callable: Bool { self == .procedure || self == .function }
}

struct DatabaseObject: Identifiable, Equatable {
    let name: String
    let kind: DatabaseObjectKind
    let detail: String
    let enabled: Bool
    var schema = "public"
    var nativeIdentity = ""
    var resultType = ""
    var signature = ""
    var scope = ""
    var id: String { scope + ":" + kind.rawValue + ":" + schema + ":" + name + ":" + nativeIdentity + ":" + signature }
}

struct RoutineParameter: Identifiable, Equatable {
    let ordinal: Int
    let name: String
    let mode: String
    let type: String
    var id: Int { ordinal }
    var input: Bool { mode != "OUT" }
}

struct DatabaseObjectDefinition {
    let object: DatabaseObject
    let sql: String
    let body: String
    let sqlMode: String
    let collation: String
    let parameters: [RoutineParameter]
    var triggerOrderClause = ""
    var engine: DatabaseEngine = .mariadb
    var bodyRange: Range<String.Index>? { body.isEmpty ? nil : sql.range(of: body, options: .backwards) }
    func replacingBody(_ next: String) throws -> String {
        guard let range = bodyRange else { throw DatabaseError.message("the server did not expose an editable body") }
        if engine.isPostgreSQL && object.kind.callable {
            let prefix = String(sql[..<range.lowerBound]), suffix = String(sql[range.upperBound...])
            guard let delimiterRange = prefix.range(of: #"\$[a-zA-Z_0-9]*\$\s*$"#, options: .regularExpression) else {
                throw DatabaseError.message("this routine uses a body format that must be edited in the sql console")
            }
            let original = String(prefix[delimiterRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard suffix.hasPrefix(original) else {
                throw DatabaseError.message("could not identify the routine body delimiter")
            }
            let delimiter = "$moko_" + UUID().uuidString.replacingOccurrences(of: "-", with: "") + "$"
            return String(prefix[..<delimiterRange.lowerBound]) + delimiter + next + delimiter
                + suffix.dropFirst(original.count)
        }
        var result = sql
        result.replaceSubrange(range, with: triggerOrderClause + next)
        return result
    }
    var session: SQLSession { .init(sqlMode: sqlMode, collation: collation) }
}

struct NewDatabaseObjectDraft: Identifiable {
    struct Parameter: Identifiable {
        let id = UUID()
        var name = "value"
        var type = "int"
        var mode = "IN"
    }
    let id = UUID()
    var kind: DatabaseObjectKind
    var name = ""
    var body = ""
    var parameters: [Parameter] = []
    var returns = "int"
    var table = ""
    var timing = "BEFORE"
    var triggerEvent = "INSERT"
    var schedule = "EVERY 1 DAY"
    var enabled = false
    var deterministic = false
    var security = "INVOKER"
    var access = "CONTAINS SQL"
    var comment = ""
    var language = "plpgsql"
    var volatility = "VOLATILE"
    var triggerFunction = ""
    var sequenceStart = "1"
    var sequenceIncrement = "1"
    var sequenceCycle = false

    func statement(database: String) throws -> String {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw DatabaseError.message("enter a name and SQL body")
        }
        let target = DatabaseSQL.qualified(database, name)
        if kind == .view { return "CREATE VIEW \(target) AS \(body)" }
        if kind == .trigger {
            guard !table.isEmpty, ["BEFORE", "AFTER"].contains(timing),
                ["INSERT", "UPDATE", "DELETE"].contains(triggerEvent)
            else {
                throw DatabaseError.message("choose a table, timing and trigger event")
            }
            return "CREATE TRIGGER \(target) \(timing) \(triggerEvent) ON "
                + DatabaseSQL.qualified(database, table) + " FOR EACH ROW \(body)"
        }
        if kind == .event {
            guard
                schedule.range(
                    of: #"^(EVERY\s+[0-9]+\s+(SECOND|MINUTE|HOUR|DAY|WEEK|MONTH|QUARTER|YEAR)|AT\s+'[0-9 :.-]+')$"#,
                    options: [.regularExpression, .caseInsensitive]) != nil
            else {
                throw DatabaseError.message("use EVERY 1 DAY or AT 'YYYY-MM-DD HH:MM:SS'")
            }
            return "CREATE EVENT \(target) ON SCHEDULE \(schedule) ON COMPLETION PRESERVE "
                + (enabled ? "ENABLE" : "DISABLE") + " COMMENT \(DatabaseSQL.ddlString(comment)) DO \(body)"
        }
        guard ["INVOKER", "DEFINER"].contains(security),
            ["CONTAINS SQL", "NO SQL", "READS SQL DATA", "MODIFIES SQL DATA"].contains(access)
        else {
            throw DatabaseError.message("choose valid routine attributes")
        }
        var names = Set<String>()
        let declarations = try parameters.map { parameter in
            guard !parameter.name.isEmpty, names.insert(parameter.name.lowercased()).inserted,
                ["IN", "OUT", "INOUT"].contains(parameter.mode)
            else {
                throw DatabaseError.message("parameter names must be unique; select a valid direction")
            }
            return (kind == .procedure ? parameter.mode + " " : "")
                + DatabaseSQL.identifier(parameter.name) + " " + (try Self.validatedType(parameter.type))
        }.joined(separator: ", ")
        var result = "CREATE \(kind.rawValue.uppercased()) \(target)(\(declarations)) "
        if kind == .function {
            result +=
                "RETURNS \(try Self.validatedType(returns)) "
                + (deterministic ? "DETERMINISTIC " : "NOT DETERMINISTIC ")
        }
        return result + access + " SQL SECURITY \(security) COMMENT \(DatabaseSQL.ddlString(comment)) \(body)"
    }
    private static func validatedType(_ type: String) throws -> String {
        let normalized = type.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            normalized.range(
                of: #"^[A-Za-z]+(?:\([0-9]+(?:,\s*[0-9]+)?\))?(?:\s+UNSIGNED)?$"#,
                options: .regularExpression) != nil
        else {
            throw DatabaseError.message("use a SQL type such as int, varchar(255) or decimal(12,2)")
        }
        return normalized
    }
}

enum DatabaseObjectSQL {
    static func catalog(_ database: String) -> String {
        let schema = DatabaseSQL.literal(database)
        return """
            SELECT ROUTINE_NAME AS name, LOWER(ROUTINE_TYPE) AS kind, COALESCE(DTD_IDENTIFIER,'') AS detail, '1' AS enabled
            FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = \(schema)
            UNION ALL SELECT TRIGGER_NAME, 'trigger', CONCAT(ACTION_TIMING,' ',EVENT_MANIPULATION,' · ',EVENT_OBJECT_TABLE),'1'
            FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = \(schema)
            UNION ALL SELECT EVENT_NAME, 'event', STATUS, IF(STATUS='ENABLED','1','0')
            FROM information_schema.EVENTS WHERE EVENT_SCHEMA = \(schema)
            UNION ALL SELECT TABLE_NAME, 'view', 'view', '1'
            FROM information_schema.VIEWS WHERE TABLE_SCHEMA = \(schema)
            ORDER BY kind, name;
            SELECT VERSION() AS version, @@event_scheduler AS scheduler;
            """
    }
    static func definition(_ object: DatabaseObject, database: String) -> String {
        let schema = DatabaseSQL.literal(database), name = DatabaseSQL.literal(object.name)
        let target = DatabaseSQL.qualified(database, object.name)
        var query = "SET SESSION sql_quote_show_create = 1; SHOW CREATE \(object.kind.rawValue.uppercased()) \(target);"
        switch object.kind {
        case .procedure, .function:
            query += """
                SELECT ROUTINE_DEFINITION AS body, SQL_MODE AS sql_mode, COLLATION_CONNECTION AS collation_connection
                FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA=\(schema) AND ROUTINE_NAME=\(name)
                  AND ROUTINE_TYPE=\(DatabaseSQL.literal(object.kind.rawValue.uppercased()));
                SELECT ORDINAL_POSITION, COALESCE(PARAMETER_NAME,''), COALESCE(PARAMETER_MODE,'IN'), DTD_IDENTIFIER
                FROM information_schema.PARAMETERS WHERE SPECIFIC_SCHEMA=\(schema) AND SPECIFIC_NAME=\(name)
                  AND ROUTINE_TYPE=\(DatabaseSQL.literal(object.kind.rawValue.uppercased())) AND ORDINAL_POSITION>0
                ORDER BY ORDINAL_POSITION;
                """
        case .trigger:
            query += """
                SELECT t.ACTION_STATEMENT AS body, t.SQL_MODE AS sql_mode, t.COLLATION_CONNECTION AS collation_connection,
                  (SELECT s.TRIGGER_NAME FROM information_schema.TRIGGERS s
                   WHERE s.TRIGGER_SCHEMA=t.TRIGGER_SCHEMA AND s.EVENT_OBJECT_TABLE=t.EVENT_OBJECT_TABLE
                     AND s.ACTION_TIMING=t.ACTION_TIMING AND s.EVENT_MANIPULATION=t.EVENT_MANIPULATION
                     AND s.ACTION_ORDER>t.ACTION_ORDER ORDER BY s.ACTION_ORDER LIMIT 1) AS next_trigger
                FROM information_schema.TRIGGERS t WHERE t.TRIGGER_SCHEMA=\(schema) AND t.TRIGGER_NAME=\(name);
                """
        case .event:
            query += """
                SELECT EVENT_DEFINITION AS body, SQL_MODE AS sql_mode, COLLATION_CONNECTION AS collation_connection
                FROM information_schema.EVENTS WHERE EVENT_SCHEMA=\(schema) AND EVENT_NAME=\(name);
                """
        case .schema, .sequence, .materializedView: return "SELECT 1 WHERE false"
        case .view:
            query += """
                SELECT VIEW_DEFINITION AS body, @@SESSION.sql_mode AS sql_mode, COLLATION_CONNECTION AS collation_connection
                FROM information_schema.VIEWS WHERE TABLE_SCHEMA=\(schema) AND TABLE_NAME=\(name);
                """
        }
        return query
    }
    static func decode(_ response: SQLResponse, object: DatabaseObject) -> DatabaseObjectDefinition? {
        let definition = response.results.first { result in
            result.fields.contains { $0.name.lowercased().hasPrefix("create ") || $0.name == "SQL Original Statement" }
        }
        guard let definition,
            let column = definition.fields.firstIndex(where: {
                $0.name.lowercased().hasPrefix("create ") || $0.name == "SQL Original Statement"
            }), let sql = definition.text(0, column), !sql.isEmpty
        else { return nil }
        let metadata = response.results.first { $0.fields.first?.name == "body" }
        let arguments = response.results.first { $0.fields.first?.name == "ORDINAL_POSITION" }
        let parameters =
            arguments.map { result in
                result.rows.indices.map {
                    RoutineParameter(
                        ordinal: Int(result.text($0, 0) ?? "") ?? 0, name: result.text($0, 1) ?? "",
                        mode: result.text($0, 2) ?? "IN", type: result.text($0, 3) ?? "")
                }
            } ?? []
        // SHOW CREATE can omit the current schema while VIEW_DEFINITION qualifies it.
        // Edit the exact SHOW CREATE body so the algorithm, definer and check option survive.
        let body = object.kind == .view ? viewBody(in: sql) : metadata?.text(0, 0)
        return .init(
            object: object, sql: sql, body: body ?? "", sqlMode: metadata?.text(0, 1) ?? "",
            collation: metadata?.text(0, 2) ?? "", parameters: parameters,
            triggerOrderClause: object.kind == .trigger
                ? metadata?.text(0, 3).map { "PRECEDES " + DatabaseSQL.identifier($0) + " " } ?? "" : "")
    }
    private static func viewBody(in sql: String) -> String? {
        var index = sql.startIndex, sawView = false
        while index < sql.endIndex {
            let character = sql[index]
            if ["`", "'", "\""].contains(character) {
                index = sql.index(after: index)
                while index < sql.endIndex {
                    let current = sql[index]
                    index = sql.index(after: index)
                    if current == character {
                        if index < sql.endIndex && sql[index] == character {
                            index = sql.index(after: index)
                        } else {
                            break
                        }
                    } else if current == "\\" && index < sql.endIndex {
                        index = sql.index(after: index)
                    }
                }
            } else if character.isLetter {
                let start = index
                while index < sql.endIndex && (sql[index].isLetter || sql[index] == "_") {
                    index = sql.index(after: index)
                }
                let word = sql[start..<index].uppercased()
                if word == "VIEW" { sawView = true }
                if sawView && word == "AS" {
                    var body = String(sql[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if let option = body.range(
                        of: #"\s+WITH\s+(?:LOCAL|CASCADED)\s+CHECK\s+OPTION\s*$"#,
                        options: [.regularExpression, .caseInsensitive]) {
                        body.removeSubrange(option)
                    }
                    return body
                }
            } else {
                index = sql.index(after: index)
            }
        }
        return nil
    }
    static func replacement(_ definition: DatabaseObjectDefinition, body: String) throws -> String {
        let updated = try definition.replacingBody(body)
        return updated.replacingOccurrences(
            of: #"^CREATE\s+(?:OR\s+REPLACE\s+)?"#, with: "CREATE OR REPLACE ",
            options: [.regularExpression, .caseInsensitive])
    }
    static func invocation(
        _ definition: DatabaseObjectDefinition, database: String, values: [Int: String],
        nulls: Set<Int>
    ) -> String {
        let parameters = definition.parameters
        let literal: (RoutineParameter) -> String = {
            nulls.contains($0.ordinal) ? "NULL" : DatabaseSQL.literal(values[$0.ordinal] ?? "")
        }
        let target = DatabaseSQL.qualified(database, definition.object.name)
        if definition.object.kind == .function {
            return "SELECT \(target)(\(parameters.map(literal).joined(separator: ", "))) AS result;"
        }
        var setup = "", arguments = [String](), output = [String]()
        for parameter in parameters {
            if parameter.mode == "IN" {
                arguments.append(literal(parameter))
            } else {
                let variable = "@moko_argument_\(parameter.ordinal)"
                setup += "SET \(variable) = \(parameter.input ? literal(parameter) : "NULL"); "
                arguments.append(variable)
                output.append(variable + " AS " + DatabaseSQL.identifier(parameter.name))
            }
        }
        return setup + "CALL \(target)(\(arguments.joined(separator: ", ")));"
            + (output.isEmpty ? "" : " SELECT " + output.joined(separator: ", ") + ";")
    }
}
