import Combine
import DatabaseNative
import Foundation

struct SQLSession {
    let sqlMode: String
    let collation: String
    var statement: String {
        "SET SESSION sql_mode = \(DatabaseSQL.literal(sqlMode))"
            + (collation.isEmpty ? "" : ", collation_connection = \(DatabaseSQL.literal(collation))")
    }
}

struct DatabaseConnection: Equatable {
    var host: String
    var port: String
    var user: String
    var password: String
    var engine: DatabaseEngine = .mariadb
    var defaultDatabase = ""
    var schema = "public"
    var tlsMode = "prefer"
    var rootCertificate = ""
    var profileID: UUID?
    var identity: String { profileID?.uuidString ?? [engine.rawValue, host, port, user].joined(separator: "|") }
    func execute(
        _ sql: String, database: String = "", multiple: Bool = false, maxRows: UInt32 = 500, oneRow: Bool = false,
        formSession: Bool = false, session: SQLSession? = nil, options: SQLQueryOptions = .init()
    ) -> SQLResponse {
        guard !PreviewRuntime.isActive else { return .failure("queries are unavailable in previews") }
        if engine.isPostgreSQL {
            return PostgreSQLDriver.execute(
                self, sql: sql,
                request: .init(
                    database: database, multiple: multiple, maxRows: maxRows, oneRow: oneRow, options: options))
        }
        let context = MySQLQueryContext(connection: self, job: options.job)
        var code: Int32 = 1
        let pointer = withExtendedLifetime(context) {
            host.withCString { hostPointer in
                user.withCString { userPointer in
                    password.withCString { passwordPointer in
                        database.withCString { databasePointer in
                            sql.withCString { queryPointer in
                                (session?.statement ?? "").withCString { contextPointer in
                                    tlsMode.withCString { tlsPointer in
                                        rootCertificate.withCString { rootPointer in
                                            moko_database_execute_tls(
                                                hostPointer, UInt32(port) ?? 3306, userPointer, passwordPointer,
                                                databasePointer,
                                                queryPointer, multiple, maxRows, oneRow, formSession, contextPointer,
                                                tlsPointer, rootPointer,
                                                { identifier, context in
                                                    guard let context else { return true }
                                                    let state = Unmanaged<MySQLQueryContext>.fromOpaque(context)
                                                        .takeUnretainedValue()
                                                    return state.job?.mysqlLifecycle(
                                                        identifier, connection: state.connection) ?? true
                                                }, Unmanaged.passUnretained(context).toOpaque(), &code)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        guard let pointer else { return .failure("could not prepare the query") }
        defer { nativeFree(pointer) }
        do { return try JSONDecoder().decode(SQLResponse.self, from: Data(String(cString: pointer).utf8)) } catch {
            return .failure("could not read the result. check the server before repeating changes")
        }
    }
}
struct SQLField: Decodable, Equatable {
    let name: String
    let type: Int
    let binary: Bool
}
struct SQLCell: Equatable {
    let hex: String?
    var data: Data? { hex.flatMap(Data.init(hex:)) }
    var text: String? { data.flatMap { String(data: $0, encoding: .utf8) } }
    func display(binary: Bool = false) -> String {
        guard let hex else { return "null" }
        return binary ? "0x" + hex : (text ?? "0x" + hex)
    }
}
extension Data {
    init?(hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
struct SQLResult: Decodable, Equatable {
    let fields: [SQLField]
    let rows: [[String?]]
    let affected: UInt64
    let truncated: Bool
    let warnings: UInt32
    var cells: [[SQLCell]] { rows.map { $0.map { SQLCell(hex: $0) } } }
    func text(_ row: Int, _ column: Int) -> String? {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return nil }
        return SQLCell(hex: rows[row][column]).text
    }
}
struct SQLResponse: Decodable {
    let results: [SQLResult]
    let code: Int
    let error: String
    let rolledBack: Bool
    var sqlState: String?
    var succeeded: Bool { code == 0 }
    static func failure(_ message: String) -> SQLResponse {
        .init(results: [], code: 1, error: message, rolledBack: false)
    }
}
struct DatabaseTable: Identifiable, Equatable {
    var scope = ""
    var id: String { scope + ":" + name }
    let name: String
    let kind: String
    let engine: String
    let estimatedRows: String
    var isView: Bool { kind != "BASE TABLE" }
}
struct DatabaseColumn: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let type: String
    let nullable: Bool
    let key: String
    let defaultValue: String?
    let extra: String
    let collation: String
    let comment: String
    var engine: DatabaseEngine = .mariadb
    var generated: Bool { extra.contains("GENERATED") && !extra.contains("DEFAULT_GENERATED") }
    var binary: Bool {
        let columnType = type.lowercased()
        if engine.isPostgreSQL { return columnType == "bytea" }
        return ["binary", "blob", "bit(", "geometry", "point", "linestring", "polygon", "vector"].contains {
            columnType.contains($0)
        }
    }
    var temporal: SQLTemporalKind? { SQLTemporalKind(type: type) }
}
enum SQLTemporalKind {
    case date, time, datetime
    init?(type: String) {
        switch type.lowercased().split(separator: "(").first {
        case "date": self = .date
        case "time", "timetz", "time without time zone", "time with time zone": self = .time
        case "datetime", "timestamp", "timestamptz", "timestamp with time zone", "timestamp without time zone":
            self = .datetime
        default: return nil
        }
    }
    var format: String {
        switch self {
        case .date: "yyyy-MM-dd"
        case .time: "HH:mm:ss"
        case .datetime: "yyyy-MM-dd HH:mm:ss"
        }
    }
    static var zone: TimeZone { TimeZone(secondsFromGMT: 0)! }
    static func fraction(_ value: String) -> String {
        let suffix = timeZoneSuffix(value), local = suffix.isEmpty ? value : String(value.dropLast(suffix.count))
        guard let dot = local.firstIndex(of: ".") else { return "" }
        let fraction = String(local[local.index(after: dot)...])
        return fraction.count <= 6 && !fraction.isEmpty && fraction.allSatisfy({ $0.isASCII && $0.isNumber })
            ? "." + fraction : ""
    }
    static func timeZoneSuffix(_ value: String) -> String {
        guard
            let range = value.range(
                of: #"(?:Z|[+-](?:[01][0-9]|2[0-3])(?::?[0-5][0-9])?(?::?[0-5][0-9])?)$"#,
                options: .regularExpression), value[..<range.lowerBound].contains(":")
        else { return "" }
        return String(value[range])
    }
    func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = Self.zone
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }
    func parse(_ value: String) -> Date? {
        let suffix = Self.timeZoneSuffix(value)
        if self == .date && (value.contains(".") || !suffix.isEmpty) { return nil }
        let local = suffix.isEmpty ? value : String(value.dropLast(suffix.count))
        let base = local.components(separatedBy: ".").first ?? local, formatter = formatter()
        guard let date = formatter.date(from: base), formatter.string(from: date) == base else { return nil }
        if local.contains(".") && Self.fraction(value).isEmpty { return nil }
        return date
    }
    func string(_ date: Date, preserving value: String) -> String {
        formatter().string(from: date) + (self == .date ? "" : Self.fraction(value) + Self.timeZoneSuffix(value))
    }
}
struct ForeignKeyTarget: Equatable {
    let constraint: String
    let database: String
    let table: String
    let predicate: String
    let summary: String
    var engine: DatabaseEngine = .mariadb
    var schema = "public"
    var query: String {
        let target =
            engine.isPostgreSQL ? PostgreSQLSQL.qualified(schema, table) : DatabaseSQL.qualified(database, table)
        return "SELECT * FROM \(target) WHERE \(predicate) LIMIT 1;"
    }
    static func make(
        metadata: SQLResult?, columns: [DatabaseColumn], row: [SQLCell], column: Int, engine: DatabaseEngine = .mariadb
    ) -> ForeignKeyTarget? {
        guard columns.indices.contains(column), let metadata,
            let first = metadata.rows.indices.first(where: { metadata.text($0, 1) == columns[column].name }),
            let constraint = metadata.text(first, 0), let database = metadata.text(first, 2),
            let table = metadata.text(first, 3)
        else { return nil }
        var predicates = [String](), summaries = [String]()
        for index in metadata.rows.indices where metadata.text(index, 0) == constraint {
            guard let source = metadata.text(index, 1), let destination = metadata.text(index, 4),
                let local = columns.firstIndex(where: { $0.name == source }), row.indices.contains(local),
                let hex = row[local].hex
            else { return nil }
            let cell = row[local]
            let value: String
            if engine.isPostgreSQL {
                value = columns[local].binary ? "decode('" + hex + "','hex')" : PostgreSQLSQL.literal(cell.text ?? "")
            } else {
                value = !columns[local].binary && cell.text != nil ? DatabaseSQL.literal(cell.text!) : "X'\(hex)'"
            }
            predicates.append(
                (engine.isPostgreSQL ? PostgreSQLSQL.identifier(destination) : DatabaseSQL.identifier(destination))
                    + " = " + value)
            summaries.append(destination + " = " + String(cell.display(binary: columns[local].binary).prefix(80)))
        }
        guard !predicates.isEmpty else { return nil }
        return .init(
            constraint: constraint, database: database, table: table, predicate: predicates.joined(separator: " AND "),
            summary: summaries.joined(separator: " · "), engine: engine, schema: metadata.text(first, 6) ?? "public")
    }
}
enum CellMode: String, CaseIterable { case value = "value", null = "null", omitted = "default" }
struct CellDraft {
    var text: String
    var mode: CellMode
}
struct RowDraft: Identifiable {
    let id = UUID()
    let original: [SQLCell]?
    var values: [String: CellDraft]
    var rowVersion: String?
}
