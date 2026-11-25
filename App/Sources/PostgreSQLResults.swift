import Foundation
import PostgresNative

/// Keeps only the displayed rows; libpq releases each incoming chunk immediately.
struct PostgreSQLResults {
    private(set) var results: [SQLResult] = []
    private(set) var error = ""
    private(set) var state: String?
    private(set) var affected: UInt64 = 0
    private var fields: [SQLField] = []
    private var rows: [[String?]] = []
    private var bytes = 0
    private var truncated = false
    let limit: UInt32

    init(limit: UInt32) { self.limit = limit }

    mutating func read(_ connection: OpaquePointer) {
        guard PQsetChunkedRowsMode(connection, 32) == 1 else {
            error = "could not enable bounded result retrieval"
            return
        }
        while let result = PQgetResult(connection) {
            consume(result, connection: connection)
            PQclear(result)
        }
        if PQstatus(connection) != CONNECTION_OK && error.isEmpty {
            error = Self.message(PQerrorMessage(connection))
        }
        if !error.isEmpty { results = [] }
    }
    private mutating func consume(_ result: OpaquePointer, connection: OpaquePointer) {
        let status = PQresultStatus(result)
        if status == PGRES_TUPLES_CHUNK {
            if error.isEmpty {
                if fields.isEmpty { fields = Self.fields(result) }
                appendRows(result)
            }
        } else if status == PGRES_TUPLES_OK || status == PGRES_COMMAND_OK || status == PGRES_EMPTY_QUERY {
            guard error.isEmpty else { return }
            if fields.isEmpty { fields = Self.fields(result) }
            affected = UInt64(Self.message(PQcmdTuples(result))) ?? 0
            if results.count < 64 {
                results.append(.init(fields: fields, rows: rows, affected: affected, truncated: truncated, warnings: 0))
            } else {
                error = "this query returned more than 64 result sets. run fewer statements at a time"
            }
            fields = []
            rows = []
            truncated = false
        } else if status == PGRES_COPY_IN {
            error = "use import sql for COPY data transfers"
            _ = PQputCopyEnd(connection, "moko editor does not accept COPY input")
        } else if status == PGRES_COPY_OUT {
            error = "use export sql for COPY data transfers"
            var buffer: UnsafeMutablePointer<CChar>?
            while PQgetCopyData(connection, &buffer, 0) > 0 {
                if let buffer { PQfreemem(buffer) }
            }
        } else if error.isEmpty {
            error = Self.message(PQresultErrorMessage(result))
            if error.isEmpty { error = "unsupported postgresql result" }
            state = PQresultErrorField(result, 67).map { String(cString: $0) }
            fields = []
            rows = []
        }
    }
    private mutating func appendRows(_ result: OpaquePointer) {
        for row in 0..<Int(PQntuples(result)) {
            guard rows.count < Int(limit), !truncated else {
                truncated = true
                continue
            }
            var values = [String?]()
            let length = fields.indices.reduce(0) { $0 + Int(PQgetlength(result, Int32(row), Int32($1))) }
            guard length <= 8 * 1024 * 1024 - bytes else {
                truncated = true
                continue
            }
            for column in fields.indices {
                if PQgetisnull(result, Int32(row), Int32(column)) == 1 {
                    values.append(nil)
                    continue
                }
                let raw = PQgetvalue(result, Int32(row), Int32(column))!
                let value: Data
                if fields[column].binary {
                    var count = 0
                    if let decoded = PQunescapeBytea(UnsafePointer<UInt8>(OpaquePointer(raw)), &count) {
                        value = Data(bytes: decoded, count: count)
                        PQfreemem(decoded)
                    } else {
                        value = Data()
                    }
                } else {
                    value = Data(bytes: raw, count: Int(PQgetlength(result, Int32(row), Int32(column))))
                }
                values.append(value.hexString)
            }
            bytes += length
            rows.append(values)
        }
    }
    private static func fields(_ result: OpaquePointer) -> [SQLField] {
        (0..<PQnfields(result)).map {
            .init(name: message(PQfname(result, $0)), type: Int(PQftype(result, $0)), binary: PQftype(result, $0) == 17)
        }
    }
    static func message(_ pointer: UnsafePointer<CChar>?) -> String {
        pointer.map { String(cString: $0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
    }
}
