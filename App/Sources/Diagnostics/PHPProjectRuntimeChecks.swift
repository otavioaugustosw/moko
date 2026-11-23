import Foundation

enum PHPProjectRuntimeChecks {
    static func run() -> Bool {
        guard let port = ProcessInfo.processInfo.environment["MOKO_VALIDATION_PHP_PORT"],
            let number = Int(port), (1024...65535).contains(number)
        else { return false }
        let suite = "moko.php.runtime." + UUID().uuidString
        guard let preferences = UserDefaults(suiteName: suite) else { return false }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let php = PHPServer(preferences: preferences, storageURL: folder)
        let competing = PHPServer(preferences: preferences, storageURL: folder.appendingPathComponent("competing"))
        var checks = 0
        func waitForServer(_ server: PHPServer? = nil) {
            let server = server ?? php
            let deadline = Date().addingTimeInterval(8)
            while server.busy && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        }
        func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw DatabaseError.message(message + " " + php.error) }
            checks += 1
        }
        func response() -> String {
            execute("/usr/bin/curl", ["--silent", "--fail", "--max-time", "2", "http://127.0.0.1:\(port)/"]).output
        }
        defer {
            competing.stop()
            waitForServer(competing)
            php.stop()
            waitForServer()
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        do {
            let firstFolder = folder.appendingPathComponent("first"),
                secondFolder = folder.appendingPathComponent("second")
            for (url, marker) in [(firstFolder, "first"), (secondFolder, "second")] {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try Data("<?php echo '\(marker)';".utf8).write(to: url.appendingPathComponent("index.php"))
            }
            let first = php.projects.add(firstFolder, port: port), second = php.projects.add(secondFolder, port: port)
            php.requestSwitch(to: first)
            try require(
                php.documentRoot.isEmpty && php.projectPrompt?.kind == .switchProject, "confirmation was skipped")
            php.confirmSwitch(to: first, connection: nil)
            php.start(connection: .init(host: "127.0.0.1", port: "13306", user: "fixture", password: "test-only"))
            waitForServer()
            let firstResponse = response()
            try require(
                php.running && firstResponse == "first" && php.databaseEndpoint == "127.0.0.1:13306",
                "first project failed: running=\(php.running), response=\(firstResponse), endpoint="
                    + (php.databaseEndpoint ?? "none") + "\n" + php.logTail())
            competing.documentRoot = firstFolder.path
            competing.port = port
            competing.start(connection: nil)
            waitForServer(competing)
            try require(
                !competing.running && competing.error.contains("port \(port) is already in use"),
                "a port conflict was not explained")
            try require(php.running && response() == "first", "the port conflict interrupted the existing server")
            php.requestSwitch(to: second)
            try require(
                php.projects.activeID == first.id && response() == "first", "project changed before confirmation")
            php.confirmSwitch(to: second, connection: nil)
            waitForServer()
            try require(
                php.running && php.projects.activeID == second.id && response() == "second"
                    && php.databaseEndpoint == nil,
                "project restart failed or kept stale database configuration")
            php.requestRemoval(second)
            try require(php.running && response() == "second", "removal happened before confirmation")
            php.removeProject(second)
            waitForServer()
            try require(
                !php.running && php.documentRoot.isEmpty && php.databaseEndpoint == nil,
                "removal did not stop the active server")
            try require(
                FileManager.default.fileExists(atPath: secondFolder.appendingPathComponent("index.php").path),
                "project files were removed")
            print("php projects: \(checks) live server and HTTP switching checks passed.")
            return true
        } catch {
            print("php projects: " + error.localizedDescription)
            return false
        }
    }
}
