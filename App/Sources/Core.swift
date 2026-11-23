import AppKit
import Darwin
import LocalAuthentication
import Security
import SwiftUI

@_silgen_name("moko_mysql_query")
func nativeQuery(
    _ host: UnsafePointer<CChar>, _ port: UInt32, _ user: UnsafePointer<CChar>, _ password: UnsafePointer<CChar>,
    _ socket: UnsafePointer<CChar>?, _ sql: UnsafePointer<CChar>, _ code: UnsafeMutablePointer<Int32>
) -> UnsafeMutablePointer<CChar>?
@_silgen_name("moko_mysql_free")
func nativeFree(_ output: UnsafeMutablePointer<CChar>)
@_silgen_name("moko_mysql_change_password")
func nativeChangePassword(
    _ host: UnsafePointer<CChar>, _ port: UInt32, _ user: UnsafePointer<CChar>, _ old: UnsafePointer<CChar>,
    _ new: UnsafePointer<CChar>, _ code: UnsafeMutablePointer<Int32>
) -> UnsafeMutablePointer<CChar>?

// Xcode previews must never contact the service or read saved credentials.
enum PreviewRuntime {
    static var isActive: Bool {
        let environment = ProcessInfo.processInfo.environment
        #if DEBUG
            if environment["MOKO_UI_TESTING"] == "1" { return true }
        #endif
        return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
    }
}

struct CommandResult {
    var code: Int32
    var output: String
}
func execute(_ path: String, _ arguments: [String], input: String? = nil) -> CommandResult {
    guard !PreviewRuntime.isActive else { return .init(code: 1, output: "preview") }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = arguments
    let pipe = Pipe()
    let stdin = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    task.standardInput = stdin
    do {
        try task.run()
        if let input { stdin.fileHandleForWriting.write(Data(input.utf8)) }
        try? stdin.fileHandleForWriting.close()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return CommandResult(code: task.terminationStatus, output: String(decoding: data, as: Unicode.UTF8.self))
    } catch { return CommandResult(code: 1, output: error.localizedDescription) }
}
func quoteShell(_ string: String) -> String { "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'" }
func sqlLiteral(_ string: String) -> String {
    "'"
        + string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(
            of: "\u{0}", with: "\\0"
        ).replacingOccurrences(of: "\u{1a}", with: "\\Z") + "'"
}
/// Saved passwords live in a single Keychain item created by the application itself, so macOS has
/// one access decision to make for moko instead of one per connection.
enum Credentials {
    static let service = "com.otavioaugustosw.moko.credentials"
    private static let vault = "saved passwords"
    private static let lock = NSLock()
    private static func item(allowInteraction: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: vault,
        ]
        if !allowInteraction {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }
        return query
    }
    /// The Keychain status and every saved password, keyed by connection account.
    static func load(allowInteraction: Bool = true) -> (status: OSStatus, passwords: [String: String]) {
        guard !PreviewRuntime.isActive else { return (errSecItemNotFound, [:]) }
        var query = item(allowInteraction: allowInteraction)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        guard status == errSecSuccess, let data = value as? Data,
            let passwords = try? JSONDecoder().decode([String: String].self, from: data)
        else { return (status == errSecSuccess ? errSecDecode : status, [:]) }
        return (status, passwords)
    }
    static func read(_ account: String, allowInteraction: Bool = true) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let password = load(allowInteraction: allowInteraction).passwords[account] { return password }
        guard let separate = separateItem(account) else { return nil }
        _ = store([account: separate])
        return separate
    }
    /// A password saved as its own item is adopted only when macOS already lets moko read it;
    /// this lookup never shows a dialog.
    private static func separateItem(_ account: String) -> String? {
        guard !PreviewRuntime.isActive, account != vault else { return nil }
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne, kSecUseAuthenticationContext as String: context,
        ]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess, let data = value as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ password: String, account: String) -> Bool { save([account: password]) }
    static func save(_ entries: [String: String]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return store(entries)
    }
    private static func store(_ entries: [String: String]) -> Bool {
        guard !PreviewRuntime.isActive else { return false }
        let current = load()
        // Never replace an item that exists but could not be read.
        guard current.status == errSecSuccess || current.status == errSecItemNotFound else { return false }
        guard let data = try? JSONEncoder().encode(current.passwords.merging(entries) { _, new in new }) else {
            return false
        }
        let base = item(allowInteraction: true)
        if current.status == errSecSuccess {
            return SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecSuccess
        }
        var query = base
        query[kSecValueData as String] = data
        query[kSecAttrLabel as String] = "moko — saved passwords"
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }
}
enum LightState {
    case green, yellow, red
    var color: NSColor {
        switch self {
        case .green: return .systemGreen
        case .yellow: return .systemYellow
        case .red: return .systemRed
        }
    }
    var title: String {
        switch self {
        case .green: return "server running"
        case .yellow: return "starting up"
        case .red: return "server stopped"
        }
    }
}
struct Event: Identifiable {
    let id = UUID()
    let time = Date()
    let text: String
}
struct ConnectionTest: Identifiable {
    enum Phase { case testing, starting, serverStopped, success, failure(Int32?, String) }
    let id = UUID()
    let host: String
    let port: String
    let user: String
    var phase: Phase = .testing
    var saveCredentials = false
    var testing: Bool {
        switch phase {
        case .testing, .starting: true
        default: false
        }
    }
}
struct ServerSession: Decodable, Identifiable, Equatable {
    let id: UInt64
    let user: String
    let host: String
    let database: String
    let command: String
    let seconds: UInt64
    let state: String

    static func decode(_ output: String) throws -> [ServerSession] {
        try output.split(separator: "\n").map { line in
            try JSONDecoder().decode(ServerSession.self, from: Data(line.utf8))
        }
    }
}

final class WorkspaceModel: ObservableObject {
    let databaseBrowser = DatabaseModel()
    let services: ServiceCoordinator
    var managedDatabase: ManagedDatabase { services.mariadb }
    var postgresql: ManagedPostgreSQL { services.postgresql }
    let profiles: ConnectionProfiles
    var engine: DatabaseEngine { profiles.selected.engine }
    var currentConnection: DatabaseConnection {
        var profile = profiles.selected
        profile.host = host
        profile.port = port
        profile.user = username
        return profile.connection(password: password)
    }
    var phpServer: PHPServer { services.php }
    @Published var backend =
        UserDefaults.standard.string(forKey: "moko.database.backend")
        ?? (UserDefaults.standard.string(forKey: "host") == nil ? "bundled" : "external")
    @Published var page = "overview"
    @Published var settingsSection = "connection"
    @Published var light: LightState = .yellow
    @Published var status = "checking"
    @Published var subtitle = "checking the database server"
    @Published var running = false
    @Published var connected = false
    @Published var managesServer = false
    @Published var working = false
    @Published var serviceOperation: String?
    var checking = false
    @Published var host = UserDefaults.standard.string(forKey: "host") ?? "127.0.0.1"
    @Published var port = UserDefaults.standard.string(forKey: "port") ?? "3306"
    @Published var username = UserDefaults.standard.string(forKey: "username") ?? "root"
    @Published var password = ""
    @Published var remember = true
    @Published var saved = false
    @Published var account = "waiting for connection"
    @Published var version = "—"
    @Published var actualPort = "—"
    var uptime = "—"
    @Published var connections = "—"
    @Published var sessions: [ServerSession] = []
    @Published var sessionError = ""
    var sessionUpdatedAt: Date?
    @Published var serverName = "—"
    @Published var socket = "/tmp/mysql.sock"
    @Published var notice = ""
    @Published var passwordChanged = false
    @Published var connectionTest: ConnectionTest?
    @Published var events: [Event] = []
    var notify: (() -> Void)?
    private var timer: Timer?
    private var pendingControl: (command: String, saveCredentials: Bool, completed: ((Bool) -> Void)?)?
    var localServiceRunning: () -> Bool = { false }
    var connectionTestQuery: ((String, String, String, String, String) -> CommandResult)?
    var targetsLocalService: Bool {
        profiles.selected.managed && host == "127.0.0.1" && port == profiles.selected.port
    }
    var credentialKey: String { profiles.selected.credentialAccount }
    var displayStatus: String {
        if serviceOperation == "stop" { return "going to sleep" }
        return (working ? LightState.yellow : light).title
    }
    static let sessionSQL = """
        SELECT JSON_OBJECT('id', ID, 'user', USER, 'host', COALESCE(HOST,''),
          'database', COALESCE(DB,''), 'command', COMMAND, 'seconds', TIME,
          'state', COALESCE(STATE,''))
        FROM information_schema.PROCESSLIST
        WHERE ID <> CONNECTION_ID()
          AND USER NOT IN ('system user', 'event_scheduler')
          AND COMMAND <> 'Daemon'
        ORDER BY ID;
        """
    init(phpServer: PHPServer = PHPServer(), profiles: ConnectionProfiles = ConnectionProfiles()) {
        self.services = ServiceCoordinator(php: phpServer)
        self.profiles = profiles
        let profile = profiles.selected
        backend = profile.managed ? (profile.engine.isPostgreSQL ? "postgresql" : "bundled") : "external"
        host = profile.host
        port = profile.port
        username = profile.user
    }
    func begin() {
        guard !PreviewRuntime.isActive else { return }
        configureBackend()
        recoverLocalServices()
        if !usesBundledDatabase, let secret = Credentials.read(credentialKey) {
            password = secret
            saved = true
        }
        add("moko opened.")
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in self?.refresh() }
    }
    func add(_ message: String) {
        events.insert(Event(text: message), at: 0)
        if events.count > 60 { events.removeLast() }
    }
    func resetConnection() {
        connected = false
        actualPort = "—"
        account = "waiting for connection"
        saved = false
        notice = ""
        sessions = []
        connections = "—"
        sessionUpdatedAt = nil
        sessionError = ""
    }
    func refresh(manual: Bool = false, discover: Bool = false, saveDiscoveredCredentials: Bool = true) {
        guard !PreviewRuntime.isActive, !checking, !working else { return }
        checking = true
        let profileID = profiles.selectedID
        let connection = currentConnection
        let sql = healthSQL, sessions = sessionsSQL
        let managed = usesBundledDatabase
        let serviceRunning = managed ? (engine.isPostgreSQL ? postgresql.running : managedDatabase.running) : false
        let existing = controlsExistingMySQL
        DispatchQueue.global(qos: .utility).async {
            let running = serviceRunning || (existing && ExistingMySQLService.running())
            let data = Self.query(sql, connection: connection)
            let sessionResult =
                data.code == 0
                ? Self.query(sessions, connection: connection) : nil
            DispatchQueue.main.async {
                defer {
                    self.checking = false
                    if let pending = self.pendingControl {
                        self.pendingControl = nil
                        self.control(pending.command, completed: pending.completed)
                    }
                }
                guard self.profiles.selectedID == profileID, self.host == connection.host, self.port == connection.port,
                    self.username == connection.user
                else { return }
                self.managesServer = self.usesBundledDatabase
                self.running = running || data.code == 0
                if data.code == 0 {
                    self.consume(data.output)
                    if let sessionResult { self.consumeSessions(sessionResult) }
                    self.light = .green
                    self.status = "database available"
                    self.subtitle = "authenticated connection; server responding"
                } else {
                    self.consumeDisconnectedStatus(data: data, responds: data.code == 1045, running: running)
                }
                if manual { self.notice = "status refreshed" }
                self.serviceOperation = nil
                self.notify?()
            }
        }
    }
    private func consumeDisconnectedStatus(data: CommandResult?, responds: Bool, running: Bool) {
        if self.connected { self.connected = false }
        if self.uptime != "—" { self.uptime = "—" }
        if self.connections != "—" { self.connections = "—" }
        if !self.sessions.isEmpty { self.sessions = [] }
        self.sessionUpdatedAt = nil
        if !self.sessionError.isEmpty { self.sessionError = "" }
        let nextLight: LightState = responds || running ? .yellow : .red
        let nextStatus = responds || running ? "check the connection" : "database stopped"
        let nextSubtitle =
            responds || running
            ? self.friendly(data?.output ?? "", code: data?.code ?? 0)
            : "start the server to connect your applications"
        if self.light != nextLight { self.light = nextLight }
        if self.status != nextStatus { self.status = nextStatus }
        if self.subtitle != nextSubtitle { self.subtitle = nextSubtitle }
    }
    func consumeSessions(_ result: CommandResult) {
        guard result.code == 0 else {
            sessions = []
            connections = "—"
            sessionUpdatedAt = nil
            sessionError =
                result.code == 1142 || result.code == 1227
                ? "the account cannot view sessions."
                : "could not query sessions. code \(result.code)."
            return
        }
        do {
            let rows = try ServerSession.decode(result.output)
            if sessions != rows { sessions = rows }
            let count = String(rows.count)
            if connections != count { connections = count }
            if !sessionError.isEmpty { sessionError = "" }
            sessionUpdatedAt = Date()
        } catch {
            sessions = []
            connections = "—"
            sessionUpdatedAt = nil
            sessionError = "could not read the session list."
        }
    }
    func showSessions() {
        page = "connections"
        notice = ""
        refresh()
    }
    func consume(_ output: String) {
        let lines = output.split(separator: "\n").map(String.init)
        guard let first = lines.first else { return }
        let fields = first.components(separatedBy: "\t")
        guard fields.count >= 5 else { return }
        if actualPort != fields[0] { actualPort = fields[0] }
        if version != fields[1] { version = fields[1] }
        if account != fields[2] { account = fields[2] }
        if serverName != fields[3] { serverName = fields[3] }
        if socket != fields[4] { socket = fields[4] }
        if !connected { connected = true }
        for line in lines.dropFirst() {
            let values = line.components(separatedBy: "\t")
            if values.count != 2 { continue }
            if values[0] == "Uptime", let seconds = Int(values[1]) {
                uptime =
                    seconds >= 86400
                    ? "\(seconds / 86400)d \((seconds % 86400) / 3600)h"
                    : (seconds >= 3600
                        ? "\(seconds / 3600)h \((seconds % 3600) / 60)min" : "\(seconds / 60)min \(seconds % 60)s")
            }
        }
    }
    func friendly(_ error: String, code: Int32 = 0) -> String {
        if code == 1820 || error.contains("1820") { return "change the initial password in settings → account" }
        if code == 1045 || error.contains("Access denied") { return "server responds; check the user and password" }
        if code == 2003 || code == 2002 { return "server started; waiting for a connection" }
        return "check the connection details and try again"
    }
    func testConnection(saveCredentials: Bool = false) {
        guard !working else { return }
        connectionTest = .init(host: host, port: port, user: username, saveCredentials: saveCredentials)
        guard let value = Int(port), (1...65535).contains(value), !host.isEmpty, !username.isEmpty else {
            connectionTest?.phase = .failure(nil, "enter a host, user and valid port")
            return
        }
        executeConnectionTest()
    }
    private func executeConnectionTest() {
        guard let test = connectionTest else { return }
        guard test.host == host, test.port == port, test.user == username else {
            connectionTest?.phase = .failure(
                nil, "connection details changed; check the host and port before testing again")
            return
        }
        connectionTest?.phase = .testing
        working = true
        notice = ""
        let testID = connectionTest!.id, started = Date()
        let secret = password, currentHost = host, currentPort = port, currentUser = username
        let capturedConnection = currentConnection
        let local = targetsLocalService
        let healthSQL = healthSQL, sessionsSQL = sessionsSQL
        DispatchQueue.global().async {
            func query(_ sql: String) -> CommandResult {
                self.connectionTestQuery?(sql, secret, currentHost, currentPort, currentUser)
                    ?? Self.query(sql, connection: capturedConnection)
            }
            let sql = healthSQL
            var result = query(sql)
            // A freshly started local service can publish its process before its
            // TCP listener is ready. Keep testing the requested endpoint.
            if local && self.localServiceRunning() {
                for _ in 0..<3 where result.code == 2002 || result.code == 2003 {
                    Thread.sleep(forTimeInterval: 0.25)
                    result = query(sql)
                }
            }
            let stopped = local && (result.code == 2002 || result.code == 2003) && !self.localServiceRunning()
            let sessionResult = result.code == 0 ? query(sessionsSQL) : nil
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, 0.6 - Date().timeIntervalSince(started))) {
                guard self.connectionTest?.id == testID else { return }
                guard self.host == currentHost, self.port == currentPort, self.username == currentUser else {
                    self.working = false
                    self.connectionTest?.phase = .failure(nil, "connection details changed; test again")
                    return
                }
                self.working = false
                if result.code == 0 {
                    self.consume(result.output)
                    if let sessionResult { self.consumeSessions(sessionResult) }
                    if test.saveCredentials { self.rememberCredentials() }
                    self.light = .green
                    self.status = "database available"
                    self.subtitle = "authenticated connection; server responding"
                    self.connectionTest?.phase = .success
                    self.add("connection verified at \(currentHost):\(self.actualPort).")
                } else if stopped {
                    self.connected = false
                    self.connectionTest?.phase = .serverStopped
                    self.add("connection test: server stopped.")
                } else {
                    self.connected = false
                    let detail =
                        result.code == 2002 || result.code == 2003
                        ? "could not reach the server; check the host and port"
                        : self.friendly(result.output, code: result.code).lowercased()
                    self.connectionTest?.phase = .failure(result.code, detail)
                    self.add("connection test: error \(result.code). " + detail)
                }
                self.notify?()
            }
        }
    }
    func startAndTestConnection() {
        guard let test = connectionTest, !test.testing, !working, targetsLocalService,
            test.host == host, test.port == port, test.user == username
        else { return }
        connectionTest?.phase = .starting
        control("start", saveDiscoveredCredentials: test.saveCredentials) { success in
            guard self.connectionTest?.id == test.id else { return }
            if success {
                self.waitForConnectionTestStartup(id: test.id, deadline: Date().addingTimeInterval(15))
            } else {
                self.connectionTest?.phase = .failure(nil, self.notice.lowercased())
            }
        }
    }
    private func waitForConnectionTestStartup(id: UUID, deadline: Date) {
        guard connectionTest?.id == id else { return }
        if !checking && running {
            executeConnectionTest()
            return
        }
        if Date() >= deadline {
            connectionTest?.phase = .failure(nil, "the server took too long to start; try again")
            return
        }
        if !checking { refresh(discover: true, saveDiscoveredCredentials: connectionTest?.saveCredentials == true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.waitForConnectionTestStartup(id: id, deadline: deadline)
        }
    }
    func control(_ command: String, saveDiscoveredCredentials: Bool = true, completed: ((Bool) -> Void)? = nil) {
        guard !PreviewRuntime.isActive else {
            completed?(false)
            return
        }
        guard !working else {
            completed?(false)
            return
        }
        if checking {
            pendingControl = (command, saveDiscoveredCredentials, completed)
            return
        }
        if usesBundledDatabase {
            controlBundled(command, completed: completed)
            return
        }
        if controlsExistingMySQL, let operation = ExistingMySQLService.Operation(rawValue: command) {
            controlExisting(operation, completed: completed)
            return
        }
        notice = "external servers are connection-only; manage their service outside moko"
        completed?(false)
    }
    func rememberCredentials() {
        guard !PreviewRuntime.isActive else { return }
        var profile = profiles.selected
        profile.host = host
        profile.port = port
        profile.user = username
        profiles.save(profile)
        UserDefaults.standard.set(host, forKey: "host")
        UserDefaults.standard.set(port, forKey: "port")
        UserDefaults.standard.set(username, forKey: "username")
        if remember {
            saved = Credentials.save(password, account: credentialKey)
            if !saved { notice = "connected, but could not save the password in keychain." }
        }
    }
}
