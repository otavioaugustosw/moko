import Foundation

enum DatabaseUtilityChecks {
    static func run() throws -> Int {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("moko-tools-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let native = root.appendingPathComponent("native"), maria = root.appendingPathComponent("mariadb")
        let postgres = root.appendingPathComponent("postgres")
        var checks = 0
        func require(_ condition: Bool, _ detail: String) throws {
            guard condition else { throw DatabaseError.message(detail) }
            checks += 1
        }
        func fixture(_ file: URL) throws {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        }
        func locate(_ operation: DatabaseTools.Operation, _ engine: DatabaseEngine) throws -> DatabaseTool {
            try DatabaseTools.locate(operation, engine: engine, postgres: postgres, mariadb: maria, directories: [native])
        }
        for file in ["mysqldump", "mysql"] { try fixture(native.appendingPathComponent(file)) }
        for file in ["mariadb-dump", "mariadb"] { try fixture(maria.appendingPathComponent("bin/" + file)) }
        for operation in [DatabaseTools.Operation.exportSQL, .importSQL] {
            let mysql = try locate(operation, .mysql), bundled = try locate(operation, .mariadb)
            let name = operation == .exportSQL ? "mysqldump" : "mysql"
            try require(mysql.kind == .mysql && mysql.executable.path == native.appendingPathComponent(name).path,
                        "existing mysql used the optional mariadb tools")
            try require(bundled.kind == .mariadb, "mariadb did not retain its matching tools")
        }
        try FileManager.default.removeItem(at: maria)
        try require(try locate(.exportSQL, .mysql).kind == .mysql, "mysql export requires the optional server")
        var connection = DatabaseConnection(host: "127.0.0.1", port: "3306", user: "fixture", password: "", engine: .mysql)
        let tool = try locate(.exportSQL, .mysql)
        for (mode, expected) in [("prefer", "PREFERRED"), ("require", "REQUIRED"), ("verify-full", "VERIFY_IDENTITY")] {
            connection.tlsMode = mode
            try require(DatabaseCommand.tls(connection, tool: tool).contains("--ssl-mode=" + expected), "mysql TLS mode changed")
        }
        try require(tool.pluginArguments.isEmpty, "mysql inherited the mariadb plugin directory")
        try require(ExistingMySQLService.matches(connection, servicePort: "3306"), "local mysql target rejected")
        connection.host = "remote.invalid"
        try require(!ExistingMySQLService.matches(connection, servicePort: "3306"), "remote connection controls a local service")
        connection.host = "127.0.0.1"
        connection.port = "3307"
        try require(!ExistingMySQLService.matches(connection, servicePort: "3306"), "wrong port controls the local service")
        connection.port = "3306"
        connection.engine = .postgresql
        try require(!ExistingMySQLService.matches(connection, servicePort: "3306"), "wrong engine controls mysql")
        for operation in [ExistingMySQLService.Operation.start, .stop, .restart] {
            let source = try ExistingMySQLService.authorizationScript(operation, port: "3306")
            var error: NSDictionary?
            let script = NSAppleScript(source: source)
            try require(script?.compileAndReturnError(&error) == true, "invalid system authorization script: \(error ?? [:])")
            try require(source.contains("with administrator privileges") && source.contains("-p \\\"$pid\\\""),
                        "service authorization or listener ownership guard is missing")
            let shell = try ExistingMySQLService.shellCommand(operation, port: "3306")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-n", "-c", shell]
            try process.run()
            process.waitUntilExit()
            try require(process.terminationStatus == 0, "invalid service shell syntax")
        }
        var rejected = false
        do { _ = try ExistingMySQLService.shellCommand(.start, port: "3306; exit") } catch { rejected = true }
        try require(rejected, "untrusted port text entered an authorized shell")
        try standingAuthorization(require)
        if ProcessInfo.processInfo.environment["MOKO_CHECK_SYSTEM_MYSQL"] == "1" {
            var local = connection
            local.engine = .mysql
            try require(ExistingMySQLService.available(for: local), "the installed local mysql service was not detected")
            print("Existing MySQL: control target verified; running=\(ExistingMySQLService.running()). No service was changed.")
        }
        return checks
    }
    private static func shell(_ arguments: [String]) throws -> (code: Int32, output: String) {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "")
    }
    private static func standingAuthorization(_ require: (Bool, String) throws -> Void) throws {
        let tool = ExistingMySQLService.tool
        let script = try ExistingMySQLService.serviceScript(port: "3306")
        try require(try shell(["-n", "-c", script]).code == 0, "invalid saved service script syntax")
        try require(
            ["start)", "stop)", "restart)", "exit 2"].allSatisfy(script.contains), "saved script accepts only the three actions")
        try require(try shell(["-c", script, "sh", "status"]).code == 2, "saved script ran an unknown action")
        try require(
            ExistingMySQLService.sudoRule(user: 501)
                == "#501 ALL=(root) NOPASSWD: \(tool) start, \(tool) stop, \(tool) restart\n",
            "sudo rule is not limited to the three actions")
        let install = try ExistingMySQLService.installCommand(port: "3306", user: 501)
        try require(try shell(["-n", "-c", install]).code == 0, "invalid authorization install syntax")
        try require(
            install.contains("visudo -cf") && install.contains("-o root -g wheel -m 755")
                && install.contains("-o root -g wheel -m 440"), "install does not validate the rule or fix ownership")
        // Without privileges: run the part that writes and validates the files, then print the script.
        let preparation = install.components(separatedBy: "/bin/mkdir -p")[0] + "/bin/cat \"$work/tool\"\n"
        let prepared = try shell(["-c", preparation])
        try require(prepared.code == 0 && prepared.output == script, "the installed script would differ from the checked one")
        var error: NSDictionary?
        let source = ExistingMySQLService.appleScript(install, prompt: "moko")
        try require(NSAppleScript(source: source)?.compileAndReturnError(&error) == true, "invalid install authorization script")
        var rejected = false
        do { _ = try ExistingMySQLService.installCommand(port: "3306; exit", user: 501) } catch { rejected = true }
        try require(rejected, "untrusted port text entered the saved script")
        try require(ExistingMySQLService.removeCommand.contains(ExistingMySQLService.rule), "removal keeps the sudo rule")
    }
}
