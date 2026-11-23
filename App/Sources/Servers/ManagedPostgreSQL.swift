import Combine
import Darwin
import Foundation
import Security

final class ManagedPostgreSQL: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var busy = false
    @Published private(set) var operation = ""
    @Published private(set) var error = ""
    var port: String
    let user = "moko"
    let credentialAccount: String
    let dataDirectory: URL
    private let queue = DispatchQueue(label: "moko.postgresql.lifecycle")
    private var process: Process?
    private var ownsRecovered = false
    private var generation = UUID()
    private let secretProvider: (() throws -> String)?

    init(
        directory: URL? = nil, port: String = "15432", credentialAccount: String = "moko.bundled.postgresql",
        secretProvider: (() throws -> String)? = nil
    ) {
        self.dataDirectory = directory ?? RuntimePaths.storage.appendingPathComponent("databases/postgresql/18")
        self.port = port
        self.credentialAccount = credentialAccount
        self.secretProvider = secretProvider
    }
    func recover(secret: String) {
        guard !PreviewRuntime.isActive, !secret.isEmpty else { return }
        queue.async {
            guard let lease = try? DatabaseRuntimeLease(directory: self.dataDirectory.deletingLastPathComponent())
            else { return }
            defer { withExtendedLifetime(lease) {} }
            let active = self.authenticated(secret: secret)
            if active, let pid = self.pid, !DatabaseRuntimeLease.hasParent(pid) {
                self.ownsRecovered = (try? DatabaseRuntimeLease.claimOwnership(in: self.dataDirectory)) == true
            }
            DispatchQueue.main.async { if !self.busy { self.running = active } }
        }
    }
    func control(_ command: String, completed: @escaping (Result<String, Error>) -> Void) {
        guard !busy, !PreviewRuntime.isActive else { return }
        busy = true
        operation = command
        error = ""
        queue.async {
            let result = Result { () throws -> String in
                try RuntimePaths.privateDirectory(self.dataDirectory.deletingLastPathComponent())
                try RuntimePaths.privateDirectory(self.dataDirectory)
                let lease = try DatabaseRuntimeLease(directory: self.dataDirectory.deletingLastPathComponent())
                defer { withExtendedLifetime(lease) {} }
                if command != "start" { try self.stop() }
                return command == "stop" ? "" : try self.start()
            }
            DispatchQueue.main.async {
                self.busy = false
                self.operation = ""
                self.running = self.pid != nil
                if case let .failure(error) = result { self.error = error.localizedDescription }
                completed(result)
            }
        }
    }
    func shutdown(completed: @escaping () -> Void) {
        queue.async {
            if self.process != nil || self.ownsRecovered {
                if let lease = try? DatabaseRuntimeLease(directory: self.dataDirectory.deletingLastPathComponent()) {
                    try? self.stop()
                    withExtendedLifetime(lease) {}
                }
            }
            DispatchQueue.main.async { completed() }
        }
    }
    private var pid: Int32? {
        guard
            let first = try? String(contentsOf: dataDirectory.appendingPathComponent("postmaster.pid"), encoding: .utf8)
                .split(separator: "\n").first, let pid = Int32(first), pid > 1,
            kill(pid, 0) == 0 || errno == EPERM
        else { return nil }
        return pid
    }
    private func secret() throws -> String {
        if let secretProvider { return try secretProvider() }
        if let saved = Credentials.read(credentialAccount), !saved.isEmpty { return saved }
        guard !FileManager.default.fileExists(atPath: dataDirectory.appendingPathComponent("PG_VERSION").path) else {
            throw DatabaseError.message(
                "postgresql credentials are missing from keychain. restore them before starting")
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw DatabaseError.message("could not create postgresql credentials")
        }
        let value = bytes.map { String(format: "%02x", $0) }.joined()
        guard Credentials.save(value, account: credentialAccount) else {
            throw DatabaseError.message("allow keychain access and retry")
        }
        return value
    }
    private func connection(_ secret: String) -> DatabaseConnection {
        .init(
            host: "127.0.0.1", port: port, user: user, password: secret, engine: .postgresql,
            defaultDatabase: "postgres")
    }
    private func authenticated(secret: String) -> Bool {
        guard pid != nil else { return false }
        let response = connection(secret).execute("SELECT current_setting('data_directory'), current_setting('port')")
        return response.succeeded && response.results.first?.text(0, 0) == dataDirectory.path
            && response.results.first?.text(0, 1) == port
    }
    private func start() throws -> String {
        let value = try secret()
        if authenticated(secret: value) { return value }
        guard pid == nil else {
            throw DatabaseError.message("postgresql is already running, but its identity could not be verified")
        }
        let version = dataDirectory.appendingPathComponent("PG_VERSION")
        if !FileManager.default.fileExists(atPath: version.path) {
            let passwordFile = dataDirectory.deletingLastPathComponent().appendingPathComponent(
                ".initial-password-" + UUID().uuidString)
            try Data((value + "\n").utf8).write(to: passwordFile, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: passwordFile.path)
            defer { try? FileManager.default.removeItem(at: passwordFile) }
            let result = execute(
                RuntimePaths.executable("PostgreSQL/bin/initdb").path,
                [
                    "-D", dataDirectory.path, "-U", user, "--pwfile=" + passwordFile.path,
                    "--auth-host=scram-sha-256", "--auth-local=scram-sha-256", "--encoding=UTF8",
                    "--locale-provider=builtin", "--builtin-locale=PG_UNICODE_FAST",
                ])
            guard result.code == 0 else {
                throw DatabaseError.message("postgresql initialization failed: " + result.output)
            }
        }
        guard try String(contentsOf: version, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) == "18"
        else {
            throw DatabaseError.message(
                "this data directory requires a different postgresql major version; migration is required")
        }
        process = try RuntimePaths.launch(
            RuntimePaths.executable("PostgreSQL/bin/postgres"),
            arguments: [
                "-D", dataDirectory.path, "-h", "127.0.0.1", "-p", port,
                "-c", "unix_socket_directories=", "-c", "shared_buffers=64MB",
            ],
            log: dataDirectory.appendingPathComponent("server.log"))
        let deadline = Date().addingTimeInterval(15)
        while process?.isRunning == true && Date() < deadline {
            if authenticated(secret: value) {
                _ = try DatabaseRuntimeLease.claimOwnership(in: dataDirectory)
                let token = UUID()
                generation = token
                process?.terminationHandler = { [weak self] _ in
                    self?.queue.async {
                        guard let self, self.generation == token else { return }
                        self.process = nil
                        DatabaseRuntimeLease.clearOwnership(in: self.dataDirectory)
                        DispatchQueue.main.async {
                            self.running = false
                            self.error = "postgresql stopped unexpectedly. check the server log."
                        }
                    }
                }
                return value
            }
            Thread.sleep(forTimeInterval: 0.15)
        }
        RuntimePaths.stop(process)
        process = nil
        throw DatabaseError.message(RuntimePaths.errorLog(dataDirectory.appendingPathComponent("server.log")))
    }
    private func stop() throws {
        generation = UUID()
        guard pid != nil else {
            process = nil
            ownsRecovered = false
            return
        }
        let value = try secret()
        guard authenticated(secret: value) else {
            throw DatabaseError.message("could not verify this server; it was left running")
        }
        let result = execute(
            RuntimePaths.executable("PostgreSQL/bin/pg_ctl").path,
            ["-D", dataDirectory.path, "stop", "-m", "fast", "-w", "-t", "15"])
        guard result.code == 0 else { throw DatabaseError.message(result.output) }
        process?.waitUntilExit()
        process = nil
        ownsRecovered = false
        DatabaseRuntimeLease.clearOwnership(in: dataDirectory)
    }
}
