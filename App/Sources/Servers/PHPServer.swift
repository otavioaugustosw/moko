import Combine
import Foundation

final class PHPServer: ObservableObject {
    @Published var documentRoot: String
    @Published var port: String
    @Published var router: String
    @Published var projectPrompt: PHPProjectPrompt?
    let projects: PHPProjectLibrary
    let preferences: UserDefaults
    let storageURL: URL
    @Published private(set) var databaseEndpoint: String?
    @Published private(set) var running = false
    @Published private(set) var busy = false
    @Published private(set) var error = ""
    private let queue = DispatchQueue(label: "moko.php.lifecycle")
    private var process: Process?
    private var generation = UUID()
    var address: URL? { URL(string: "http://127.0.0.1:\(port)/") }
    var logURL: URL { storageURL.appendingPathComponent("php.log") }

    init(preferences: UserDefaults = .standard, storageURL: URL = RuntimePaths.storage) {
        self.preferences = preferences
        self.storageURL = storageURL
        projects = PHPProjectLibrary(preferences: preferences)
        documentRoot = projects.active?.path ?? preferences.string(forKey: "moko.php.root") ?? ""
        port = projects.active?.port ?? preferences.string(forKey: "moko.php.port") ?? "8080"
        router = projects.active?.router ?? ""
    }

    func start(connection: DatabaseConnection?) {
        guard !PreviewRuntime.isActive, !busy, !running else { return }
        guard let value = Int(port), (1024...65535).contains(value), !documentRoot.isEmpty else {
            error = "choose a document folder and a port between 1024 and 65535"
            return
        }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: documentRoot, isDirectory: &directory), directory.boolValue else {
            error = "the document folder is unavailable"
            return
        }
        if !router.isEmpty && !FileManager.default.fileExists(atPath: router) {
            error = "the router script is unavailable"
            return
        }
        busy = true
        error = ""
        let root = documentRoot, currentPort = port, script = router
        let token = UUID()
        generation = token
        queue.async { [self] in
            do {
                try RuntimePaths.privateDirectory(storageURL)
                var environment = ProcessInfo.processInfo.environment
                environment["PHP_INI_SCAN_DIR"] = ""
                environment["MIBS"] = ""
                environment["MOKO_DB_ENGINE"] = connection?.engine.rawValue ?? ""
                environment["MOKO_DB_HOST"] = connection?.host ?? ""
                environment["MOKO_DB_PORT"] = connection?.port ?? ""
                environment["MOKO_DB_USER"] = connection?.user ?? ""
                environment["MOKO_DB_PASSWORD"] = connection?.password ?? ""
                environment["MOKO_DB_DATABASE"] = connection?.defaultDatabase ?? ""
                environment["MOKO_DB_TLS_MODE"] = connection?.tlsMode ?? "prefer"
                environment["MOKO_DB_ROOT_CERTIFICATE"] = connection?.rootCertificate ?? ""
                let configuration = RuntimePaths.root.appendingPathComponent("PHP/php.ini")
                self.process = try RuntimePaths.launch(
                    RuntimePaths.executable("PHP/bin/php"),
                    arguments: [
                        "-c", configuration.path,
                        "-d", "openssl.cafile=\(RuntimePaths.root.appendingPathComponent("PHP/cert.pem").path)",
                        "-d", "curl.cainfo=\(RuntimePaths.root.appendingPathComponent("PHP/cert.pem").path)", "-S",
                        "127.0.0.1:\(currentPort)", "-t", root,
                    ]
                        + (script.isEmpty ? [] : [script]), log: self.logURL, environment: environment)
                Thread.sleep(forTimeInterval: 0.4)
                guard self.process?.isRunning == true else {
                    let detail = RuntimePaths.errorLog(self.logURL)
                    if detail.localizedCaseInsensitiveContains("address already in use") {
                        throw DatabaseError.message(
                            "port \(currentPort) is already in use. choose another port and try again.")
                    }
                    throw DatabaseError.message("php startup failed: " + detail)
                }
                self.process?.terminationHandler = { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self, self.generation == token else { return }
                        self.running = false
                        self.databaseEndpoint = nil
                        self.error = "php stopped unexpectedly. check the server log."
                    }
                }
                DispatchQueue.main.async {
                    self.busy = false
                    self.running = true
                    self.databaseEndpoint = connection.map { "\($0.host):\($0.port)" }
                    self.saveConfiguration()
                }
            } catch {
                RuntimePaths.stop(self.process)
                self.process = nil
                DispatchQueue.main.async {
                    self.busy = false
                    self.error = error.localizedDescription
                }
            }
        }
    }
    func stop(completed: @escaping () -> Void = {}) {
        guard !PreviewRuntime.isActive else {
            completed()
            return
        }
        busy = true
        generation = UUID()
        queue.async {
            RuntimePaths.stop(self.process)
            self.process = nil
            DispatchQueue.main.async {
                self.busy = false
                self.running = false
                self.databaseEndpoint = nil
                completed()
            }
        }
    }
    func logTail() -> String {
        guard !PreviewRuntime.isActive, let handle = try? FileHandle(forReadingFrom: logURL) else { return "" }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return "" }
        try? handle.seek(toOffset: end > 8_192 ? end - 8_192 : 0)
        let data = (try? handle.readToEnd()) ?? Data()
        return String(bytes: data, encoding: .utf8) ?? "log contains invalid text"
    }
}
