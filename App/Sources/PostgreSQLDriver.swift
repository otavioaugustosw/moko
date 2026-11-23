import Darwin
import Foundation
import PostgresNative

struct PostgreSQLRequest {
    var database: String
    var multiple: Bool
    var maxRows: UInt32
    var oneRow: Bool
    var options: SQLQueryOptions
}

enum PostgreSQLDriver {
    static func execute(_ profile: DatabaseConnection, sql: String, request: PostgreSQLRequest) -> SQLResponse {
        let database =
            request.database.isEmpty
            ? (profile.defaultDatabase.isEmpty ? "postgres" : profile.defaultDatabase)
            : request.database
        let keys = [
            "host", "port", "user", "password", "dbname", "connect_timeout", "application_name",
            "sslmode", "sslrootcert",
        ]
        let values = [
            profile.host, profile.port, profile.user, profile.password, database, "4", "moko",
            profile.tlsMode.isEmpty ? "prefer" : profile.tlsMode, profile.rootCertificate,
        ]
        guard
            let connection = strings(
                keys,
                { keyPointers in
                    strings(values, { valuePointers in PQconnectdbParams(keyPointers, valuePointers, 0) })
                })
        else { return .failure("could not prepare the postgresql connection") }
        defer { PQfinish(connection) }
        guard PQstatus(connection) == CONNECTION_OK else {
            let detail = message(PQerrorMessage(connection))
            return .init(
                results: [], code: detail.contains("password authentication failed") ? 1045 : 2003, error: detail,
                rolledBack: false)
        }
        let job = request.options.job ?? SQLQueryJob()
        guard job.attach(connection) else { return .failure("query cancelled") }
        defer { job.detach() }
        guard configureSession(connection, schema: profile.schema) else {
            return .failure(message(PQerrorMessage(connection)))
        }
        let transaction = request.oneRow || request.options.statements != nil
        if transaction {
            guard command(connection, "BEGIN") else { return .failure(message(PQerrorMessage(connection))) }
        }
        var output = PostgreSQLResults(limit: request.maxRows)
        if let statements = request.options.statements {
            for statement in statements {
                guard PQsendQueryParams(connection, statement, 0, nil, nil, nil, nil, 0) == 1 else {
                    return .failure(message(PQerrorMessage(connection)))
                }
                output.read(connection)
                if !output.error.isEmpty { break }
            }
        } else {
            let parameters = request.options.parameters ?? []
            guard parameters.allSatisfy({ $0?.contains("\0") != true }) else {
                return .failure("text parameters cannot contain null bytes")
            }
            // Extended protocol rejects pasted extra statements in form-generated SQL.
            let sent =
                request.multiple && request.options.parameters == nil
                ? PQsendQuery(connection, sql)
                : optionalStrings(parameters) {
                    PQsendQueryParams(connection, sql, Int32(parameters.count), nil, $0, nil, nil, 0)
                }
            guard sent == 1 else { return .failure(message(PQerrorMessage(connection))) }
            output.read(connection)
        }
        var error = output.error
        if transaction {
            if request.oneRow && error.isEmpty && output.affected != 1 {
                error = "another connection changed or removed this row. refresh before editing"
            }
            if !command(connection, error.isEmpty ? "COMMIT" : "ROLLBACK"), error.isEmpty {
                error = message(PQerrorMessage(connection))
            }
        }
        let unfinished = rollbackUnfinished(connection)
        return .init(
            results: error.isEmpty ? output.results : [], code: error.isEmpty ? 0 : 1,
            error: error + (output.state.map { " (sqlstate " + $0 + ")" } ?? ""), rolledBack: unfinished,
            sqlState: output.state)
    }

    private static func configureSession(_ connection: OpaquePointer, schema: String) -> Bool {
        PQsetClientEncoding(connection, "UTF8") == 0
            && command(connection, "SET standard_conforming_strings = on")
            && command(connection, "SET search_path TO " + PostgreSQLSQL.identifier(schema))
    }
    private static func rollbackUnfinished(_ connection: OpaquePointer) -> Bool {
        let state = PQtransactionStatus(connection)
        guard state == PQTRANS_INTRANS || state == PQTRANS_INERROR else { return false }
        _ = command(connection, "ROLLBACK")
        return true
    }
    private static func command(_ connection: OpaquePointer, _ sql: String) -> Bool {
        guard let result = PQexecParams(connection, sql, 0, nil, nil, nil, nil, 0) else { return false }
        defer { PQclear(result) }
        return PQresultStatus(result) == PGRES_COMMAND_OK
    }
    private static func message(_ pointer: UnsafePointer<CChar>?) -> String {
        pointer.map { String(cString: $0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
    }
    private static func strings<T>(_ values: [String], _ body: ([UnsafePointer<CChar>?]) -> T) -> T {
        optionalStrings(values.map(Optional.some), body)
    }
    private static func optionalStrings<T>(_ values: [String?], _ body: ([UnsafePointer<CChar>?]) -> T) -> T {
        let pointers = values.map { $0.flatMap { strdup($0) } }
        defer { pointers.forEach { free($0) } }
        return body(pointers.map { $0.map { UnsafePointer($0) } } + [nil])
    }
}
