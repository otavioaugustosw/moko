import Foundation

enum ManagedDatabaseRuntimeChecks {
    static func run() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard let port = environment["MOKO_LIFECYCLE_PORT"], let number = Int(port), (1024...65535).contains(number),
            let secret = environment["MYSQL_PWD"], !secret.isEmpty
        else { return false }
        // Unix sockets on macOS have a 103-byte path limit.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "moko-db-" + UUID().uuidString.prefix(8))
        let first = ManagedDatabase(directory: folder, port: port, secretProvider: { secret })
        let recovered = ManagedDatabase(directory: folder, port: port, secretProvider: { secret })
        let connection = DatabaseConnection(host: "127.0.0.1", port: port, user: "moko", password: secret)
        var checks = 0
        func spin(until finished: () -> Bool, timeout: Double = 45) {
            let deadline = Date().addingTimeInterval(timeout)
            while !finished() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        }
        func control(_ server: ManagedDatabase, _ command: String) throws {
            var result: Result<String, Error>?
            server.control(command) { result = $0 }
            spin(until: { result != nil })
            guard let result else {
                throw DatabaseError.message(
                    "lifecycle operation timed out: " + command + " · " + server.error + "\n"
                        + RuntimePaths.errorLog(server.logURL))
            }
            _ = try result.get()
        }
        @discardableResult func shutdown(_ server: ManagedDatabase) -> Bool {
            var done = false
            server.shutdown { done = true }
            spin(until: { done })
            return done
        }
        func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw DatabaseError.message(message) }
            checks += 1
        }
        defer {
            let borrowerFinished = shutdown(recovered), ownerFinished = shutdown(first)
            if borrowerFinished && ownerFinished
                && DatabaseRuntimeLease.livePID(at: folder.appendingPathComponent("server.pid")) == nil {
                try? FileManager.default.removeItem(at: folder)
            } else {
                print("test files preserved until the owned server stops: " + folder.path)
            }
        }
        do {
            try control(first, "start")
            try require(first.running && connection.execute("SELECT 1").succeeded, "initial server did not start")
            let pidFile = folder.appendingPathComponent("server.pid")
            let pid = DatabaseRuntimeLease.livePID(at: pidFile)
            try require(pid != nil, "server PID was not recorded")
            try require(
                connection.execute(
                    "CREATE DATABASE fixture; CREATE TABLE fixture.rows_check (id int PRIMARY KEY); "
                        + "INSERT INTO fixture.rows_check VALUES (7);", multiple: true
                ).succeeded, "fixture write failed")
            try control(recovered, "start")
            try require(
                recovered.running && DatabaseRuntimeLease.livePID(at: pidFile) == pid,
                "recovery launched a competing database process")
            shutdown(recovered)
            try require(
                connection.execute("SELECT id FROM fixture.rows_check").results.first?.text(0, 0) == "7",
                "closing a borrowing instance stopped the live owner's server")
            try control(recovered, "start")
            let until = Date().addingTimeInterval(33)
            var stable = true
            while Date() < until {
                stable =
                    stable && connection.execute("SELECT 1").succeeded
                    && DatabaseRuntimeLease.livePID(at: pidFile) == pid
                RunLoop.current.run(until: Date().addingTimeInterval(1))
            }
            try require(stable, "recovered server disconnected after the former 30-second lock timeout")
            do {
                let lease = try DatabaseRuntimeLease(directory: folder)
                var rejected = false
                do { _ = try DatabaseRuntimeLease(directory: folder) } catch { rejected = true }
                try require(rejected, "parallel lifecycle lease was accepted")
                withExtendedLifetime(lease) {}
            }
            try checkStopAndPersistence(
                recovered, first: first, connection: connection, control: control, require: require)
            print("managed database: \(checks) lifecycle, recovery and 33-second stability checks passed.")
            return true
        } catch {
            print("managed database: " + error.localizedDescription)
            return false
        }
    }
    private static func checkStopAndPersistence(
        _ recovered: ManagedDatabase, first: ManagedDatabase, connection: DatabaseConnection,
        control: (ManagedDatabase, String) throws -> Void, require: (Bool, String) throws -> Void
    ) throws {
        try control(recovered, "stop")
        try require(!recovered.running && !connection.execute("SELECT 1").succeeded, "explicit recovery stop failed")
        try control(first, "start")
        try require(
            connection.execute("SELECT id FROM fixture.rows_check").results.first?.text(0, 0) == "7",
            "data did not persist through recovery and restart")
    }
}
