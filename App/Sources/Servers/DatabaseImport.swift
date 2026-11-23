import Combine
import Foundation

enum DatabaseCommand {
    static func tls(_ connection: DatabaseConnection, tool: DatabaseTool) -> [String] {
        guard tool.kind == .mysql else { return mariaTLS(connection) }
        let mode = connection.tlsMode == "verify-full" ? "VERIFY_IDENTITY"
            : (connection.tlsMode == "require" ? "REQUIRED" : "PREFERRED")
        return ["--ssl-mode=" + mode]
            + (connection.rootCertificate.isEmpty ? [] : ["--ssl-ca=" + connection.rootCertificate])
    }
    static func mariaTLS(_ connection: DatabaseConnection) -> [String] {
        let verified = connection.tlsMode == "verify-full"
        var arguments = verified ? ["--ssl", "--ssl-verify-server-cert"] : ["--skip-ssl-verify-server-cert"]
        if connection.tlsMode == "require" { arguments += ["--ssl"] }
        if !connection.rootCertificate.isEmpty { arguments += ["--ssl-ca=" + connection.rootCertificate] }
        return arguments
    }
    static func environment(_ connection: DatabaseConnection) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["MIBS"] = ""
        if connection.engine.isPostgreSQL {
            environment["PGPASSWORD"] = connection.password
            environment["PGSSLMODE"] = connection.tlsMode.isEmpty ? "prefer" : connection.tlsMode
            environment["PGCONNECT_TIMEOUT"] = "10"
            environment["PGAPPNAME"] = "moko"
            if !connection.rootCertificate.isEmpty { environment["PGSSLROOTCERT"] = connection.rootCertificate }
        } else {
            environment["MYSQL_PWD"] = connection.password
        }
        return environment
    }
    static func importFile(_ file: URL, connection: DatabaseConnection, database: String, job: DatabaseExportJob) throws {
        guard !database.isEmpty, file.isFileURL else {
            throw DatabaseError.message("select a database and a local import file")
        }
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        let signature = try input.read(upToCount: 5)
        try input.seek(toOffset: 0)
        let archive = signature == Data("PGDMP".utf8)
        if !archive { try DatabaseImportPolicy.validate(file, engine: connection.engine, database: database) }
        let tool = try DatabaseTools.resolve(.importSQL, engine: connection.engine, archive: archive)
        let process = try job.prepare(), errors = Pipe()
        process.executableURL = tool.executable
        if connection.engine.isPostgreSQL {
            process.arguments =
                [
                    "--no-password", "--host=" + connection.host, "--port=" + connection.port,
                    "--username=" + connection.user, "--dbname=" + database, "--single-transaction",
                ]
                + (archive
                    ? ["--exit-on-error", file.path] : ["--no-psqlrc", "--set=ON_ERROR_STOP=1", "--file=" + file.path])
            process.standardInput = FileHandle.nullDevice
        } else {
            guard !archive else {
                throw DatabaseError.message("a postgresql archive cannot be imported into mariadb or mysql")
            }
            process.arguments =
                [
                    "--no-defaults", "--protocol=TCP", "--host=" + connection.host, "--port=" + connection.port,
                    "--user=" + connection.user, "--database=" + database, "--default-character-set=utf8mb4", "--batch",
                ] + tool.pluginArguments + tls(connection, tool: tool)
                + (tool.kind == .mariadb ? ["--sandbox"] : []) + ["--binary-mode"]
            process.standardInput = input
        }
        process.environment = environment(connection)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try job.run()
        var diagnostic = Data()
        while let block = try errors.fileHandleForReading.read(upToCount: 4096), !block.isEmpty {
            diagnostic.append(block.prefix(max(0, 16384 - diagnostic.count)))
        }
        process.waitUntilExit()
        try job.checkCancellation()
        guard process.terminationStatus == 0 else {
            var detail = (String(bytes: diagnostic, encoding: .utf8) ?? "import diagnostics are unavailable")
            if !connection.password.isEmpty {
                detail = detail.replacingOccurrences(of: connection.password, with: "[redacted]")
            }
            throw DatabaseError.message(detail.isEmpty ? "import failed" : detail)
        }
    }
}

final class DatabaseImporter: ObservableObject {
    @Published private(set) var busy = false
    @Published var error = ""
    @Published var message = ""
    private var job: DatabaseExportJob?
    func start(_ file: URL, connection: DatabaseConnection, database: String, completed: @escaping () -> Void) {
        guard !busy, !PreviewRuntime.isActive else { return }
        busy = true
        error = ""
        message = ""
        let job = DatabaseExportJob()
        self.job = job
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { () throws -> URL in
                let folder = RuntimePaths.storage.appendingPathComponent("backups")
                try RuntimePaths.privateDirectory(folder)
                let backup = folder.appendingPathComponent("before-import-" + UUID().uuidString + ".sql")
                try DatabaseDump.write(connection, database: database, to: backup, job: job)
                try DatabaseCommand.importFile(file, connection: connection, database: database, job: job)
                return backup
            }
            DispatchQueue.main.async {
                self.busy = false
                self.job = nil
                switch result {
                case let .success(backup):
                    self.message = "import completed. backup: " + backup.path
                    completed()
                case .failure(is CancellationError): self.error = "import cancelled. check the target before retrying"
                case let .failure(error): self.error = error.localizedDescription
                }
            }
        }
    }
    func cancel() { job?.cancel() }
}
