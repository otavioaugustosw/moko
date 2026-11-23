import Foundation

// Deterministic checks do not access Keychain, a database, or service control.
@main struct CheckConnectionTest {
    static func main() {
        var checks = 0
        func require(_ condition: Bool, _ message: String) {
            guard condition else {
                print("connection: failed: \(message)")
                exit(1)
            }
            checks += 1
        }
        func model(local: Bool = false) -> WorkspaceModel {
            let suite = "moko.connection.fixture." + UUID().uuidString
            let preferences = UserDefaults(suiteName: suite)!
            preferences.set(local ? "bundled" : "external", forKey: "moko.database.backend")
            let profiles = ConnectionProfiles(preferences: preferences)
            preferences.removePersistentDomain(forName: suite)
            let model = WorkspaceModel(profiles: profiles)
            model.backend = "external"
            model.host = "127.0.0.1"
            model.port = local ? "13306" : "3306"
            model.username = "fixture"
            model.password = ""
            return model
        }
        func wait(_ model: WorkspaceModel) {
            let deadline = Date().addingTimeInterval(3)
            while model.working && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            require(!model.working, "the test ends without leaving the panel blocked")
        }
        func succeeded(_ model: WorkspaceModel) -> Bool {
            if case .success? = model.connectionTest?.phase { return true }
            return false
        }
        func failed(_ model: WorkspaceModel, _ code: Int32) -> Bool {
            if case let .failure(actual, _)? = model.connectionTest?.phase { return actual == code }
            return false
        }

        let stopped = model(local: true)
        stopped.localServiceRunning = { false }
        stopped.connectionTestQuery = { _, _, _, _, _ in .init(code: 2003, output: "fixture: offline") }
        stopped.testConnection()
        require(stopped.connectionTest?.testing == true, "pop-up mostra progresso antes do resultado")
        wait(stopped)
        if case .serverStopped? = stopped.connectionTest?.phase {
            require(true, "servidor local desligado identificado")
        } else {
            require(false, "servidor local desligado identificado")
        }
        require(stopped.serviceOperation == nil, "the test does not start the server without a user action")

        let unmanaged = model()
        unmanaged.localServiceRunning = { false }
        unmanaged.connectionTestQuery = { sql, _, _, port, _ in
            .init(
                code: 0,
                output: sql == WorkspaceModel.sessionSQL
                    ? "" : "\(port)\t26.7.0\tfixture@localhost\tfixture\t/tmp/mysql.sock\n")
        }
        unmanaged.testConnection()
        wait(unmanaged)
        require(
            succeeded(unmanaged) && !unmanaged.saved,
            "a valid connection works without launchd and testing does not save credentials")

        let warming = model(local: true)
        warming.localServiceRunning = { true }
        var attempts = 0
        warming.connectionTestQuery = { sql, _, host, port, user in
            if sql == WorkspaceModel.sessionSQL { return .init(code: 0, output: "") }
            attempts += 1
            if attempts < 3 { return .init(code: 2003, output: "fixture: listener starting") }
            return .init(
                code: host == "127.0.0.1" && user == "fixture" ? 0 : 1,
                output: "\(port)\t26.7.0\tfixture@localhost\tfixture\t/tmp/mysql.sock\n")
        }
        warming.testConnection()
        wait(warming)
        require(succeeded(warming) && attempts == 3, "a transient startup retries with the same address and user")

        let denied = model()
        denied.localServiceRunning = { true }
        var deniedAttempts = 0
        denied.connectionTestQuery = { _, _, _, _, _ in
            deniedAttempts += 1
            return .init(code: 1045, output: "fixture: denied")
        }
        denied.testConnection()
        wait(denied)
        require(failed(denied, 1045) && deniedAttempts == 1, "an authentication error keeps the real code without retries")

        let remote = model()
        remote.host = "fixture.invalid"
        remote.localServiceRunning = { false }
        remote.connectionTestQuery = { _, _, _, _, _ in .init(code: 2003, output: "fixture: remote") }
        remote.testConnection()
        wait(remote)
        require(failed(remote, 2003), "a remote server does not offer local service control")

        let otherPort = model()
        otherPort.port = "1"
        otherPort.localServiceRunning = { false }
        otherPort.connectionTestQuery = { _, _, _, _, _ in .init(code: 2003, output: "fixture: other port") }
        otherPort.testConnection()
        wait(otherPort)
        require(failed(otherPort, 2003), "a different port is not mistaken for a stopped local service")
        print("connection: \(checks) deterministic checks passed")
    }
}
