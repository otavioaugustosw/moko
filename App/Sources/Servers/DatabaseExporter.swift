import Combine
import Darwin
import Foundation

final class DatabaseExportJob {
    private(set) var process = Process()
    private let lock = NSLock()
    private var cancelled = false
    func prepare() throws -> Process {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled, !process.isRunning else { throw CancellationError() }
        process = Process()
        return process
    }
    func run() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { throw CancellationError() }
        try process.run()
    }
    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if process.isRunning { process.terminate() }
    }
    func checkCancellation() throws {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { throw CancellationError() }
    }
}

enum DatabaseDump {
    static func write(
        _ connection: DatabaseConnection, database: String, to destination: URL,
        job: DatabaseExportJob = DatabaseExportJob()
    ) throws {
        guard !PreviewRuntime.isActive, !database.isEmpty, !database.contains("\0"), destination.isFileURL else {
            throw DatabaseError.message("select a database and a local SQL file")
        }
        try job.checkCancellation()
        let tool = try DatabaseTools.resolve(.exportSQL, engine: connection.engine)
        let staging = destination.deletingLastPathComponent().appendingPathComponent(
            ".moko-export-\(UUID().uuidString).sql")
        let descriptor = open(staging.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw DatabaseError.message("could not create the SQL file in this folder") }
        let output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer {
            try? output.close()
            try? FileManager.default.removeItem(at: staging)
        }
        let process = try job.prepare(), errors = Pipe()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }
        process.executableURL = tool.executable
        process.arguments =
            connection.engine.isPostgreSQL
            ? [
                "--no-password", "--host=" + connection.host, "--port=" + connection.port,
                "--username=" + connection.user, "--dbname=" + database, "--format=plain", "--encoding=UTF8",
            ]
            : [
                "--no-defaults", "--protocol=TCP", "--host=\(connection.host)", "--port=\(connection.port)",
                "--user=\(connection.user)",
                "--default-character-set=utf8mb4", "--single-transaction", "--quick",
                "--skip-lock-tables", "--routines", "--events", "--triggers", "--hex-blob",
            ] + tool.pluginArguments + DatabaseCommand.tls(connection, tool: tool)
                + (tool.kind == .mysql ? ["--column-statistics=0", "--no-tablespaces", "--set-gtid-purged=OFF"] : [])
                + ["--", database]
        process.environment = DatabaseCommand.environment(connection)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors
        try job.run()
        var diagnostic = Data()
        while let chunk = try errors.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
            diagnostic.append(chunk.prefix(max(0, 16384 - diagnostic.count)))
        }
        process.waitUntilExit()
        try job.checkCancellation()
        guard process.terminationStatus == 0 else {
            var detail = (String(bytes: diagnostic, encoding: .utf8) ?? "could not read export diagnostics")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !connection.password.isEmpty {
                detail = detail.replacingOccurrences(of: connection.password, with: "[redacted]")
            }
            throw DatabaseError.message(
                detail.isEmpty ? "database export failed (\(process.terminationStatus))" : detail)
        }
        try output.synchronize()
        try output.close()
        try job.checkCancellation()
        // Same-directory rename publishes a complete file atomically, including when replacing an existing export.
        guard rename(staging.path, destination.path) == 0 else {
            throw DatabaseError.message("could not save the completed SQL file. the previous file was preserved.")
        }
    }
}

final class DatabaseExporter: ObservableObject {
    @Published private(set) var busy = false
    @Published var error = ""
    @Published var message = ""
    private var job: DatabaseExportJob?
    func start(_ connection: DatabaseConnection, database: String, to destination: URL) {
        guard !busy else { return }
        let job = DatabaseExportJob()
        self.job = job
        busy = true
        error = ""
        message = ""
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try DatabaseDump.write(connection, database: database, to: destination, job: job) }
            DispatchQueue.main.async {
                self.job = nil
                self.busy = false
                switch result {
                case .success: self.message = "exported \(database) to \(destination.lastPathComponent)"
                case .failure(is CancellationError): self.message = "export cancelled"
                case let .failure(error): self.error = error.localizedDescription
                }
            }
        }
    }
    func cancel() { job?.cancel() }
}
