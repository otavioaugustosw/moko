import Foundation

enum PostgreSQLObjects {
    static let kinds: [DatabaseObjectKind] = [
        .schema, .view, .materializedView, .sequence, .function, .procedure, .trigger,
    ]
    static func catalog(schema: String) -> String {
        let scope = PostgreSQLSQL.literal(schema)
        return """
            SELECT nspname AS name,'schema' AS kind,'' AS detail,'1' AS enabled,oid::text AS identity,'' AS signature,'' AS result_type
              FROM pg_namespace WHERE nspname NOT LIKE 'pg_%' AND nspname<>'information_schema'
            UNION ALL SELECT c.relname,CASE c.relkind WHEN 'v' THEN 'view' WHEN 'm' THEN 'materialized view' ELSE 'sequence' END,
              '', '1',c.oid::text,'','' FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
              WHERE n.nspname=\(scope) AND c.relkind IN ('v','m','S')
            UNION ALL SELECT p.proname,CASE p.prokind WHEN 'p' THEN 'procedure' ELSE 'function' END,
              pg_get_function_identity_arguments(p.oid),'1',p.oid::text,pg_get_function_identity_arguments(p.oid),
              format_type(p.prorettype,NULL)
              FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname=\(scope) AND p.prokind IN ('p','f')
            UNION ALL SELECT t.tgname,'trigger',c.relname,CASE WHEN t.tgenabled='D' THEN '0' ELSE '1' END,t.oid::text,'',''
              FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
              WHERE n.nspname=\(scope) AND NOT t.tgisinternal ORDER BY kind,name;
            SELECT version() AS version,'' AS scheduler;
            """
    }
    static func definition(_ object: DatabaseObject, schema: String) -> String {
        let oid = PostgreSQLSQL.literal(object.nativeIdentity) + "::oid"
        let target = PostgreSQLSQL.qualified(schema, object.name)
        switch object.kind {
        case .function, .procedure:
            return """
                SELECT pg_get_functiondef(\(oid)) AS definition,prosrc AS body,'' AS sql_mode,'' AS collation_connection
                  FROM pg_proc WHERE oid=\(oid);
                SELECT ordinal::text,COALESCE(proargnames[ordinal], 'parameter'||ordinal),
                  CASE COALESCE(proargmodes[ordinal],'i') WHEN 'o' THEN 'OUT' WHEN 'b' THEN 'INOUT' ELSE 'IN' END,
                  format_type(type,NULL) FROM pg_proc CROSS JOIN LATERAL
                  unnest(COALESCE(proallargtypes,proargtypes::oid[])) WITH ORDINALITY AS args(type,ordinal) WHERE oid=\(oid);
                """
        case .view, .materializedView:
            let prefix = object.kind == .view ? "CREATE OR REPLACE VIEW " : "CREATE MATERIALIZED VIEW "
            return "SELECT " + PostgreSQLSQL.literal(prefix + target)
                + "||CASE WHEN reloptions IS NULL THEN '' ELSE ' WITH ('||array_to_string(reloptions,', ')||')' END"
                + "||' AS '||pg_get_viewdef(" + oid + ",true) AS definition, pg_get_viewdef(" + oid + ",true) AS body"
                + " FROM pg_class WHERE oid=" + oid
        case .trigger:
            return "SELECT pg_get_triggerdef(oid,true) AS definition, '' AS body FROM pg_trigger WHERE oid=" + oid
        case .sequence:
            return """
                SELECT \(PostgreSQLSQL.literal("CREATE SEQUENCE " + target))||' AS '||format_type(seqtypid,NULL)||
                  ' START WITH '||seqstart||' INCREMENT BY '||seqincrement||' MINVALUE '||seqmin||' MAXVALUE '||seqmax||
                  ' CACHE '||seqcache||CASE WHEN seqcycle THEN ' CYCLE' ELSE ' NO CYCLE' END AS definition,'' AS body
                FROM pg_sequence WHERE seqrelid=\(oid)
                """
        case .schema:
            return "SELECT " + PostgreSQLSQL.literal("CREATE SCHEMA " + PostgreSQLSQL.identifier(object.name))
                + " AS definition,'' AS body"
        case .event: return "SELECT '' AS definition,'' AS body WHERE false"
        }
    }
    static func decode(_ response: SQLResponse, object: DatabaseObject) -> DatabaseObjectDefinition? {
        guard let set = response.results.first, let sql = set.text(0, 0) else { return nil }
        let parameters =
            response.results.dropFirst().first.map { rows in
                rows.rows.indices.map { row in
                    RoutineParameter(
                        ordinal: Int(rows.text(row, 0) ?? "") ?? row + 1, name: rows.text(row, 1) ?? "",
                        mode: rows.text(row, 2) ?? "IN", type: rows.text(row, 3) ?? "text")
                }
            } ?? []
        return .init(
            object: object, sql: sql, body: set.text(0, 1) ?? "", sqlMode: "", collation: "",
            parameters: parameters, engine: .postgresql)
    }
    static func create(_ draft: NewDatabaseObjectDraft, schema: String) throws -> String {
        guard !draft.name.isEmpty, draft.name.utf8.count <= 63, !draft.name.contains("\0") else {
            throw DatabaseError.message("enter an object name up to 63 bytes")
        }
        let target = PostgreSQLSQL.qualified(schema, draft.name)
        if draft.kind == .schema { return "CREATE SCHEMA " + PostgreSQLSQL.identifier(draft.name) }
        if draft.kind == .sequence {
            guard let start = Int64(draft.sequenceStart), let increment = Int64(draft.sequenceIncrement), increment != 0
            else {
                throw DatabaseError.message("enter a valid sequence start and a nonzero increment")
            }
            return "CREATE SEQUENCE " + target + " START WITH \(start) INCREMENT BY \(increment) "
                + (draft.sequenceCycle ? "CYCLE" : "NO CYCLE")
        }
        if draft.kind == .trigger {
            guard !draft.table.isEmpty, !draft.triggerFunction.isEmpty, ["BEFORE", "AFTER"].contains(draft.timing),
                ["INSERT", "UPDATE", "DELETE"].contains(draft.triggerEvent)
            else {
                throw DatabaseError.message("choose a table and trigger function")
            }
            return "CREATE TRIGGER " + PostgreSQLSQL.identifier(draft.name) + " " + draft.timing + " "
                + draft.triggerEvent
                + " ON " + PostgreSQLSQL.qualified(schema, draft.table) + " FOR EACH ROW EXECUTE FUNCTION "
                + PostgreSQLSQL.qualified(schema, draft.triggerFunction) + "()"
        }
        guard !draft.body.isEmpty else { throw DatabaseError.message("enter the object body") }
        if draft.kind == .view || draft.kind == .materializedView {
            return "CREATE " + draft.kind.rawValue.uppercased() + " " + target + " AS " + draft.body
        }
        guard draft.kind.callable, ["sql", "plpgsql"].contains(draft.language),
            ["INVOKER", "DEFINER"].contains(draft.security),
            ["VOLATILE", "STABLE", "IMMUTABLE"].contains(draft.volatility)
        else {
            throw DatabaseError.message("choose valid postgresql routine attributes")
        }
        var names = Set<String>()
        let parameters = try draft.parameters.map { parameter in
            guard !parameter.name.isEmpty, names.insert(parameter.name).inserted,
                ["IN", "OUT", "INOUT"].contains(parameter.mode)
            else { throw DatabaseError.message("parameter names must be unique") }
            var type = PostgreSQLColumnDraft()
            type.type = parameter.type
            type.size = ""
            return parameter.mode + " " + PostgreSQLSQL.identifier(parameter.name) + " " + (try type.validatedType())
        }
        var returns = PostgreSQLColumnDraft()
        returns.type = draft.returns
        returns.size = ""
        // A random delimiter cannot be closed by pasted body text.
        let delimiter = "$moko_" + UUID().uuidString.replacingOccurrences(of: "-", with: "") + "$"
        return "CREATE " + draft.kind.rawValue.uppercased() + " " + target + "(" + parameters.joined(separator: ", ")
            + ")"
            + (draft.kind == .function && !draft.parameters.contains(where: { $0.mode != "IN" })
                ? " RETURNS " + (try returns.validatedType()) : "")
            + " LANGUAGE " + draft.language + " SECURITY " + draft.security
            + (draft.kind == .function ? " " + draft.volatility : "") + " AS " + delimiter + draft.body + delimiter
    }
    static func drop(_ object: DatabaseObject, schema: String) -> String {
        let target =
            object.kind == .schema
            ? PostgreSQLSQL.identifier(object.name) : PostgreSQLSQL.qualified(schema, object.name)
        if object.kind == .trigger {
            return "DROP TRIGGER " + PostgreSQLSQL.identifier(object.name) + " ON "
                + PostgreSQLSQL.qualified(schema, object.detail)
        }
        return "DROP " + object.kind.rawValue.uppercased() + " " + target
            + (object.kind.callable ? "(" + object.signature + ")" : "")
    }
    static func invocation(
        _ definition: DatabaseObjectDefinition, schema: String, values: [Int: String], nulls: Set<Int>
    ) -> SQLPlan {
        var parameters = [String?]()
        let arguments = definition.parameters.filter { $0.input || definition.object.kind == .procedure }.map { parameter in
            if !parameter.input { return "NULL::" + parameter.type }
            parameters.append(nulls.contains(parameter.ordinal) ? nil : values[parameter.ordinal] ?? "")
            return "$\(parameters.count)::" + parameter.type
        }
        let target = PostgreSQLSQL.qualified(schema, definition.object.name)
        let prefix = definition.object.kind == .procedure ? "CALL " : "SELECT * FROM "
        return .init(
            title: "run object", sql: prefix + target + "(" + arguments.joined(separator: ", ") + ")",
            database: "", parameters: parameters)
    }
}
