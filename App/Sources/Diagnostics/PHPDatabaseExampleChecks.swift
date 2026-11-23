import Foundation

enum PHPDatabaseExampleChecks {
    static func run(
        connection: DatabaseConnection, database: String, folder: URL, tlsAvailable: Bool = false
    ) throws -> Int {
        let file = folder.appendingPathComponent("pdo-example.php")
        let script =
            PHPDatabaseExample.pdo(connection.engine) + """

                echo $pdo->query('SELECT 1')->fetchColumn();
                """
        try Data(script.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        var checks = 0
        for mode in ["prefer", "require", "verify-full"] {
            var candidate = connection
            candidate.tlsMode = mode
            let result = try execute(file, connection: candidate, database: database)
            // Native MySQL generates a self-signed certificate. Other fixtures disable TLS.
            // No fixture supplies a trusted CA, so verify-full must always reject it.
            let expected = mode == "prefer" || (mode == "require" && tlsAvailable)
            guard (result.status == 0 && result.output == "1") == expected,
                expected || result.status != 0
            else { throw DatabaseError.message("copied PDO example failed TLS policy " + mode + ": " + result.output) }
            checks += 1
        }
        var invalid = connection
        invalid.password += "invalid"
        let rejected = try execute(file, connection: invalid, database: database)
        guard rejected.status != 0 else {
            throw DatabaseError.message("copied PDO example ignored authentication failure")
        }
        checks += 1
        let example = PHPDatabaseExample.environment(connection, database: database, password: nil)
        guard !example.contains(connection.password), example.contains("MOKO_DB_PASSWORD=''"),
            example.contains("MOKO_DB_DATABASE=")
        else { throw DatabaseError.message("copied environment leaked credentials or omitted the database") }
        return checks + 1
    }
    private static func execute(
        _ file: URL, connection: DatabaseConnection, database: String
    ) throws -> (status: Int32, output: String) {
        let process = Process(), output = Pipe()
        process.executableURL = RuntimePaths.executable("PHP/bin/php")
        process.arguments = ["-c", RuntimePaths.executable("PHP/php.ini").path, file.path]
        process.environment = ProcessInfo.processInfo.environment.merging(
            PHPDatabaseExample.variables(connection, database: database, password: connection.password)
        ) { _, next in next }
        process.environment?["PHP_INI_SCAN_DIR"] = ""
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        var detail = String(bytes: data, encoding: .utf8) ?? "invalid PHP output"
        if !connection.password.isEmpty {
            detail = detail.replacingOccurrences(of: connection.password, with: "[redacted]")
        }
        return (process.terminationStatus, detail)
    }
}
