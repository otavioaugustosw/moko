import Foundation

/// Explicit control of Oracle's local installation. Each action asks for administrator approval
/// unless the user saved the optional authorization (see ExistingMySQLAuthorization). No resident
/// helper process, saved administrator password, remote control or automatic shutdown at app exit.
enum ExistingMySQLService {
    enum Operation: String { case start, stop, restart }
    static let label = "com.oracle.oss.mysql.mysqld"
    static let plist = URL(fileURLWithPath: "/Library/LaunchDaemons/" + label + ".plist")
    static let executable = "/usr/local/mysql/bin/mysqld"

    static func matches(_ connection: DatabaseConnection, servicePort: String) -> Bool {
        connection.engine == .mysql && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(connection.host.lowercased())
            && connection.port == servicePort
    }
    static func available(for connection: DatabaseConnection) -> Bool {
        guard !PreviewRuntime.isActive, let port = installationPort() else { return false }
        return matches(connection, servicePort: port)
    }
    private static func installationPort() -> String? {
        let paths = [
            "/Library", "/Library/LaunchDaemons", plist.path,
            "/usr", "/usr/local", "/usr/local/mysql", "/usr/local/mysql/bin", executable,
        ]
        for path in paths {
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path),
                (attributes[.ownerAccountID] as? NSNumber)?.intValue == 0,
                let mode = attributes[.posixPermissions] as? NSNumber, mode.intValue & 0o022 == 0
            else { return nil }
        }
        guard let data = try? Data(contentsOf: plist),
            let record = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            record["Label"] as? String == label, record["Program"] as? String == executable,
            record["UserName"] as? String == "_mysql",
            let arguments = record["ProgramArguments"] as? [String], arguments.first == executable
        else { return nil }
        var port = "3306"
        for (index, argument) in arguments.enumerated() {
            if argument.hasPrefix("--port=") { port = String(argument.dropFirst(7)) }
            if argument == "--port", arguments.indices.contains(index + 1) { port = arguments[index + 1] }
        }
        return UInt16(port).map { $0 > 0 ? String($0) : nil } ?? nil
    }
    static func running() -> Bool {
        guard !PreviewRuntime.isActive else { return false }
        let result = execute("/bin/launchctl", ["print", "system/" + label])
        return result.code == 0 && result.output.contains("state = running")
    }
    static func perform(
        _ operation: Operation, connection: DatabaseConnection, completed: @escaping (CommandResult) -> Void
    ) {
        guard available(for: connection) else {
            completed(.init(code: 1, output: "this connection does not match the installed local mysql service"))
            return
        }
        let port = connection.port
        DispatchQueue.global(qos: .userInitiated).async {
            if standing(port: port) == .ready, let saved = runStanding(operation) {
                DispatchQueue.main.async { completed(saved) }
                return
            }
            let result: CommandResult
            do {
                let source = try authorizationScript(operation, port: port)
                var error: NSDictionary?
                let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&error)
                let code = (error?[NSAppleScript.errorNumber] as? NSNumber)?.int32Value ?? (descriptor == nil ? 1 : 0)
                result = .init(
                    code: code,
                    output: code == -128 ? "mysql service control cancelled"
                        : (error?[NSAppleScript.errorMessage] as? String ?? descriptor?.stringValue ?? "mysql service updated"))
            } catch { result = .init(code: 1, output: error.localizedDescription) }
            DispatchQueue.main.async { completed(result) }
        }
    }
    static func authorizationScript(_ operation: Operation, port: String) throws -> String {
        appleScript(
            try shellCommand(operation, port: port),
            prompt: "moko needs permission to " + operation.rawValue + " the installed mysql service on this mac.")
    }
    static func shellCommand(_ operation: Operation, port: String) throws -> String {
        guard let value = UInt16(port), value > 0, String(value) == port else {
            throw DatabaseError.message("invalid local mysql port")
        }
        let stop = """
            /bin/launchctl bootout "$service"
            elapsed=0
            while [ -n "$pid" ] && /bin/kill -0 "$pid" 2>/dev/null; do
              [ "$elapsed" -lt 120 ] || { echo 'mysql is still stopping; wait before starting it again'; exit 1; }
              /bin/sleep 0.25
              elapsed=$((elapsed + 1))
            done
            """
        let start = """
            if /bin/launchctl print "$service" >/dev/null 2>&1; then
              /bin/launchctl kickstart "$service"
            else
              /bin/launchctl bootstrap system '\(plist.path)'
            fi
            elapsed=0
            while :; do
              pid=$(/bin/launchctl print "$service" 2>/dev/null | /usr/bin/awk '$1 == "pid" && $2 == "=" {print $3; exit}')
              if [ -n "$pid" ] && /usr/sbin/lsof -nP -a -p "$pid" -iTCP:\(port) -sTCP:LISTEN >/dev/null; then
                break
              fi
              [ "$elapsed" -lt 120 ] || { echo 'mysql did not open its connection port; check its server log'; exit 1; }
              /bin/sleep 0.25
              elapsed=$((elapsed + 1))
            done
            """
        let action: String
        switch operation {
        case .start: action = "if [ -z \"$pid\" ]; then\n" + start + "\nfi"
        case .stop: action = "if /bin/launchctl print \"$service\" >/dev/null 2>&1; then\n" + stop + "\nfi"
        case .restart:
            action = "if /bin/launchctl print \"$service\" >/dev/null 2>&1; then\n" + stop + "\nfi\n" + start
        }
        return """
            set -eu
            service='system/\(label)'
            pid=$(/bin/launchctl print "$service" 2>/dev/null | /usr/bin/awk '$1 == "pid" && $2 == "=" {print $3; exit}')
            if [ -n "$pid" ]; then
              /usr/sbin/lsof -nP -a -p "$pid" -iTCP:\(port) -sTCP:LISTEN >/dev/null || {
                echo 'the installed mysql service does not own this connection port'; exit 1;
              }
            elif /usr/sbin/lsof -nP -iTCP:\(port) -sTCP:LISTEN >/dev/null; then
              echo 'another process is using this port; no service was changed'; exit 1
            fi
            \(action)
            echo 'mysql service \(operation.rawValue) completed'
            """
    }
}
