import Combine
import Foundation
import Security

final class ManagedDatabase: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var busy = false
    @Published private(set) var operation = ""
    @Published private(set) var error = ""
    var port: String
    let user = "moko"
    let credentialAccount: String
    private let queue = DispatchQueue(label: "moko.mariadb.lifecycle")
    private var process: Process?
    private var generation = UUID()
    private var adoptedPID: Int32?
    private var ownsAdoptedProcess = false
    private let directory: URL
    private let secretProvider: (() throws -> String)?
    var dataDirectory: URL { directory }
    var logURL: URL { dataDirectory.appendingPathComponent("server.log") }
    private var socket: URL { dataDirectory.appendingPathComponent("mysql.sock") }

    init(
        directory: URL? = nil, port: String = "13306", credentialAccount: String = "moko.bundled.mariadb",
        secretProvider: (() throws -> String)? = nil
    ) {
        self.directory = directory ?? RuntimePaths.storage.appendingPathComponent("database", isDirectory: true)
        self.port = port
        self.credentialAccount = credentialAccount
        self.secretProvider = secretProvider
    }
    func recover(secret: String) {
        guard !PreviewRuntime.isActive, !secret.isEmpty else { return }
        queue.async {
            let lease = try? DatabaseRuntimeLease(directory: self.dataDirectory)
            let recovered = lease != nil && self.adoptExisting(secret)
            withExtendedLifetime(lease) {}
            DispatchQueue.main.async { if !self.busy { self.running = recovered || self.process?.isRunning == true } }
        }
    }

    func control(_ command: String, completed: @escaping (Result<String, Error>) -> Void) {
        guard !PreviewRuntime.isActive, !busy else { return }
        busy = true
        operation = command
        error = ""
        queue.async {
            let result: Result<String, Error>
            do {
                try RuntimePaths.privateDirectory(self.dataDirectory)
                let lease = try DatabaseRuntimeLease(directory: self.dataDirectory)
                defer { withExtendedLifetime(lease) {} }
                if command != "start" {
                    self.generation = UUID()
                    try self.stopExisting()
                }
                let secret = command == "stop" ? "" : try self.start()
                result = .success(secret)
            } catch {
                RuntimePaths.stop(self.process)
                self.process = nil
                result = .failure(error)
            }
            DispatchQueue.main.async {
                self.busy = false
                self.operation = ""
                self.running = self.process?.isRunning == true || self.adoptedPID != nil
                if case let .failure(error) = result { self.error = error.localizedDescription }
                completed(result)
            }
        }
    }
    func shutdown(completed: @escaping () -> Void) {
        queue.async {
            self.generation = UUID()
            if self.process != nil || self.ownsAdoptedProcess {
                do {
                    let lease = try DatabaseRuntimeLease(directory: self.dataDirectory)
                    defer { withExtendedLifetime(lease) {} }
                    try self.stopExisting(expectedPID: self.process == nil ? self.adoptedPID : nil)
                } catch {
                    // Another instance may be changing this server. Leave it for authenticated recovery.
                }
            }
            self.adoptedPID = nil
            self.ownsAdoptedProcess = false
            DispatchQueue.main.async {
                self.running = false
                completed()
            }
        }
    }
    private func secret() throws -> String {
        if let secretProvider { return try secretProvider() }
        if let existing = Credentials.read(credentialAccount), !existing.isEmpty { return existing }
        guard !FileManager.default.fileExists(atPath: dataDirectory.appendingPathComponent("provisioned").path) else {
            throw DatabaseError.message(
                "database credentials are missing from keychain. restore the saved keychain before starting.")
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw DatabaseError.message("could not create database credentials")
        }
        let value = bytes.map { String(format: "%02x", $0) }.joined()
        guard Credentials.save(value, account: credentialAccount) else {
            throw DatabaseError.message("allow moko to save its database password in keychain and retry")
        }
        return value
    }
    private func arguments(networking: Bool) -> [String] {
        let base = RuntimePaths.executable("MariaDB")
        return [
            "--no-defaults", "--basedir=\(base.path)", "--datadir=\(dataDirectory.path)",
            "--plugin-dir=\(base.appendingPathComponent("lib/plugin").path)",
            "--socket=\(socket.path)", "--pid-file=\(dataDirectory.appendingPathComponent("server.pid").path)",
            "--character-set-server=utf8mb4", "--collation-server=utf8mb4_unicode_ci",
            "--performance-schema=ON", "--bind-address=127.0.0.1", "--port=\(port)",
        ]
            + (networking ? [] : ["--skip-networking"])
    }
    private func start() throws -> String {
        let secret = try secret()
        if process?.isRunning == true { return secret }
        if adoptExisting(secret) { return secret }
        guard DatabaseRuntimeLease.livePID(at: dataDirectory.appendingPathComponent("server.pid")) == nil else {
            throw DatabaseError.message(
                "this database is already running, but its saved credentials could not be verified. "
                    + "restore the keychain credentials and retry.")
        }
        try RuntimePaths.privateDirectory(dataDirectory)
        if !FileManager.default.fileExists(atPath: dataDirectory.appendingPathComponent("mysql").path) {
            let base = RuntimePaths.executable("MariaDB")
            let installer = try RuntimePaths.launch(
                base.appendingPathComponent("bin/mariadb-install-db"),
                arguments: [
                    "--no-defaults", "--basedir=\(base.path)", "--datadir=\(dataDirectory.path)",
                    "--auth-root-authentication-method=normal", "--skip-test-db",
                ], log: logURL)
            installer.waitUntilExit()
            guard installer.terminationStatus == 0 else {
                throw DatabaseError.message("database initialization failed: " + RuntimePaths.errorLog(logURL))
            }
        }
        if !FileManager.default.fileExists(atPath: dataDirectory.appendingPathComponent("provisioned").path) {
            try provision(secret)
        }
        process = try RuntimePaths.launch(
            RuntimePaths.executable("MariaDB/bin/mariadbd"),
            arguments: arguments(networking: true), log: logURL)
        try awaitReady(secret, networking: true)
        _ = try DatabaseRuntimeLease.claimOwnership(in: dataDirectory)
        let token = UUID()
        generation = token
        process?.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.running = false
                self.error = "database stopped unexpectedly. check the server log."
            }
        }
        return secret
    }
    private func adoptExisting(_ secret: String) -> Bool {
        guard let pid = DatabaseRuntimeLease.livePID(at: dataDirectory.appendingPathComponent("server.pid")) else {
            return false
        }
        let result = localQuery("SELECT @@port, HEX(@@datadir), HEX(@@socket)", password: secret)
        let values = result.output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\t")
        guard result.code == 0, values.count == 3, values[0] == port,
            let data = Data(hex: values[1]), let path = String(data: data, encoding: .utf8),
            let socketData = Data(hex: values[2]), let socketPath = String(data: socketData, encoding: .utf8),
            URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
                == dataDirectory.standardizedFileURL.resolvingSymlinksInPath(),
            URL(fileURLWithPath: socketPath).standardizedFileURL.resolvingSymlinksInPath()
                == socket.standardizedFileURL.resolvingSymlinksInPath()
        else { return false }
        adoptedPID = pid
        ownsAdoptedProcess =
            !DatabaseRuntimeLease.hasParent(pid)
            && (try? DatabaseRuntimeLease.claimOwnership(in: dataDirectory)) == true
        return true
    }
    private func stopExisting(expectedPID: Int32? = nil) throws {
        if let process {
            RuntimePaths.stop(process)
            self.process = nil
        } else if DatabaseRuntimeLease.livePID(at: dataDirectory.appendingPathComponent("server.pid")) != nil {
            let password = try secret()
            guard adoptExisting(password), let pid = adoptedPID else {
                throw DatabaseError.message("the running database could not be verified with its saved credentials")
            }
            if let expectedPID, expectedPID != pid { return }
            let result = localQuery("SHUTDOWN", password: password)
            guard result.code == 0 else { throw DatabaseError.message("could not stop the database (\(result.code))") }
            let deadline = Date().addingTimeInterval(15)
            while DatabaseRuntimeLease.livePID(at: dataDirectory.appendingPathComponent("server.pid")) == pid
                && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            guard DatabaseRuntimeLease.livePID(at: dataDirectory.appendingPathComponent("server.pid")) != pid else {
                throw DatabaseError.message("the database is still shutting down. wait before restarting.")
            }
        }
        adoptedPID = nil
        ownsAdoptedProcess = false
        DatabaseRuntimeLease.clearOwnership(in: dataDirectory)
    }
    private func provision(_ secret: String) throws {
        process = try RuntimePaths.launch(
            RuntimePaths.executable("MariaDB/bin/mariadbd"),
            arguments: arguments(networking: false), log: logURL)
        // This bootstrap listener has no TCP socket and lives inside a private user directory.
        try awaitReady(secret, networking: false, acceptEmptyPassword: true)
        let auth = localQuery("SELECT 1", password: secret).code == 0 ? secret : ""
        let sql = """
            CREATE USER IF NOT EXISTS 'moko'@'127.0.0.1' IDENTIFIED BY '\(secret)';
            ALTER USER 'moko'@'127.0.0.1' IDENTIFIED BY '\(secret)';
            GRANT ALL PRIVILEGES ON *.* TO 'moko'@'127.0.0.1' WITH GRANT OPTION;
            ALTER USER 'root'@'localhost' IDENTIFIED BY '\(secret)';
            """
        let result = localQuery(sql, password: auth)
        guard result.code == 0 else { throw DatabaseError.message("database account setup failed (\(result.code))") }
        RuntimePaths.stop(process)
        process = nil
        try Data().write(to: dataDirectory.appendingPathComponent("provisioned"), options: .atomic)
    }
    private func awaitReady(_ secret: String, networking: Bool, acceptEmptyPassword: Bool = false) throws {
        let deadline = Date().addingTimeInterval(20)
        while process?.isRunning == true && Date() < deadline {
            if networking {
                let result = DatabaseConnection(host: "127.0.0.1", port: port, user: user, password: secret).execute(
                    "SELECT 1")
                if result.succeeded { return }
            } else if localQuery("SELECT 1", password: secret).code == 0
                || (acceptEmptyPassword && localQuery("SELECT 1", password: "").code == 0) {
                return
            }
            Thread.sleep(forTimeInterval: 0.15)
        }
        throw DatabaseError.message("database startup failed: " + RuntimePaths.errorLog(logURL))
    }
    private func localQuery(_ sql: String, password: String) -> CommandResult {
        var code: Int32 = 1
        let output = "localhost".withCString { host in
            "root".withCString { user in
                password.withCString { secret in
                    socket.path.withCString { socket in
                        sql.withCString { query in nativeQuery(host, 0, user, secret, socket, query, &code) }
                    }
                }
            }
        }
        guard let output else { return .init(code: 1, output: "connection allocation failed") }
        defer { nativeFree(output) }
        return .init(code: code, output: String(cString: output))
    }
}
