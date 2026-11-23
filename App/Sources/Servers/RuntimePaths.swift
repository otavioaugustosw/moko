import Foundation

/// Only the application's bundled executables are used. Existing installations stay independent.
enum RuntimePaths {
    static var root: URL {
        Bundle.main.resourceURL!.appendingPathComponent("Runtime", isDirectory: true)
    }
    static var storage: URL {
        #if DEBUG
            if ProcessInfo.processInfo.environment["MOKO_UI_TESTING"] == "1" {
                return FileManager.default.temporaryDirectory.appendingPathComponent(
                    "moko-interface-" + String(ProcessInfo.processInfo.processIdentifier))
            }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("moko", isDirectory: true)
    }
    private static let bundledVersions: [String: String] = {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("Manifest.json")),
            let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]]
        else { return [:] }
        return manifest.compactMapValues { $0["version"] as? String }
    }()
    static func version(of runtime: String) -> String {
        bundledVersions.first { $0.key == runtime || $0.key.hasPrefix(runtime + "@") }?.value ?? "unavailable"
    }
    static func executable(_ path: String) -> URL {
        if path == "MariaDB", let installed = installedMariaDB { return installed }
        if path.hasPrefix("MariaDB/"), let installed = installedMariaDB {
            return installed.appendingPathComponent(String(path.dropFirst("MariaDB/".count)))
        }
        return root.appendingPathComponent(path)
    }
    /// MariaDB shipped inside the application, signed together with it.
    static var includedMariaDB: URL? {
        let runtime = root.appendingPathComponent("MariaDB", isDirectory: true)
        return FileManager.default.isExecutableFile(atPath: runtime.appendingPathComponent("bin/mariadbd").path)
            ? runtime : nil
    }
    static var installedMariaDB: URL? {
        if validationCommand,
            let path = ProcessInfo.processInfo.environment["MOKO_VALIDATION_MARIADB_ROOT"] {
            return URL(fileURLWithPath: path)
        }
        if let included = includedMariaDB { return included }
        let folder = storage.appendingPathComponent("runtimes/mariadb", isDirectory: true)
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("active.json")),
            let record = try? JSONDecoder().decode(InstalledRuntime.self, from: data)
        else { return nil }
        let container = folder.appendingPathComponent(record.id).resolvingSymlinksInPath()
        guard container.path.hasPrefix(folder.resolvingSymlinksInPath().path + "/") else { return nil }
        let runtime = container.appendingPathComponent("MariaDB.runtime/Contents/Resources/Runtime/MariaDB")
        return FileManager.default.isExecutableFile(atPath: runtime.appendingPathComponent("bin/mariadbd").path)
            ? runtime : nil
    }
    private static var validationCommand: Bool {
        let commands = [
            "--test-database-export", "--test-sql-objects", "--test-managed-database",
            "--test-php-projects", "--test-table-creation", "--test-postgresql-runtime",
        ]
        return commands.contains { command in CommandLine.arguments.contains { $0.hasPrefix(command) } }
    }
    static func validateInstalledExecutable(_ executable: URL) throws {
        guard let installed = installedMariaDB, executable.path.hasPrefix(installed.path + "/") else { return }
        if installed == includedMariaDB { return }
        if validationCommand && ProcessInfo.processInfo.environment["MOKO_VALIDATION_MARIADB_ROOT"] != nil { return }
        guard let trust = RuntimeTrust.bundled, !trust.teamID.isEmpty else {
            throw DatabaseError.message("the component publisher is not configured in this build")
        }
        var bundle = installed
        for _ in 0..<4 { bundle.deleteLastPathComponent() }
        try RuntimeSignature.validate(bundle, teamID: trust.teamID)
    }
    static func privateDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
    static func logHandle(_ url: URL) throws -> FileHandle {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        return handle
    }
    static func launch(
        _ executable: URL, arguments: [String], log: URL,
        environment: [String: String]? = nil
    ) throws -> Process {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw DatabaseError.message("bundled runtime is missing. reinstall moko.")
        }
        try validateInstalledExecutable(executable)
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        let handle = try logHandle(log)
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        try handle.close()
        return process
    }
    static func stop(_ process: Process?) {
        guard let process, process.isRunning else { return }
        process.terminate()
        process.waitUntilExit()
    }
    static func errorLog(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "the server did not start" }
        return String(bytes: data.suffix(8_192), encoding: .utf8) ?? "log contains invalid text"
    }
}
