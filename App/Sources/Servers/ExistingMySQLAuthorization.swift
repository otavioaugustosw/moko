import Foundation

/// Optional standing permission for the installed MySQL service. One administrator approval installs a
/// root-owned script that can only start, stop or restart that service on its port, plus a sudo rule
/// that lets the current user run that script without a password. Off unless the user turns it on.
extension ExistingMySQLService {
    enum Standing: Equatable { case absent, ready, outdated }
    static let tool = "/Library/PrivilegedHelperTools/com.otavioaugustosw.moko.mysql-service"
    static let rule = "/etc/sudoers.d/moko-mysql"

    /// The complete script installed for `port`; its three branches are the same guarded commands
    /// used for one-time authorization.
    static func serviceScript(port: String) throws -> String {
        var script = "#!/bin/sh\ncase \"${1:-}\" in\n"
        for operation in [Operation.start, .stop, .restart] {
            script += operation.rawValue + ")\n" + (try shellCommand(operation, port: port)) + "\n;;\n"
        }
        return script + "*) echo 'usage: start|stop|restart' >&2; exit 2 ;;\nesac\n"
    }
    static func sudoRule(user: uid_t) -> String {
        let commands = [Operation.start, .stop, .restart].map { tool + " " + $0.rawValue }.joined(separator: ", ")
        return "#\(user) ALL=(root) NOPASSWD: " + commands + "\n"
    }
    static func installCommand(port: String, user: uid_t) throws -> String {
        """
        set -eu
        umask 022
        work=$(/usr/bin/mktemp -d)
        trap '/bin/rm -rf "$work"' EXIT
        /bin/cat > "$work/tool" <<'MOKO_SERVICE_SCRIPT'
        \(try serviceScript(port: port))MOKO_SERVICE_SCRIPT
        /bin/cat > "$work/rule" <<'MOKO_SUDO_RULE'
        \(sudoRule(user: user))MOKO_SUDO_RULE
        /usr/sbin/visudo -cf "$work/rule" >/dev/null
        /bin/mkdir -p /Library/PrivilegedHelperTools
        /usr/bin/install -o root -g wheel -m 755 "$work/tool" '\(tool)'
        /usr/bin/install -o root -g wheel -m 440 "$work/rule" '\(rule)'
        echo 'authorization saved'
        """
    }
    static let removeCommand = "/bin/rm -f '\(rule)' '\(tool)'\necho 'authorization removed'"

    /// Only a root-owned script that nobody else can change, with exactly the expected content, counts.
    static func standing(port: String, files: FileManager = .default) -> Standing {
        guard !PreviewRuntime.isActive, files.fileExists(atPath: tool) || files.fileExists(atPath: rule) else {
            return .absent
        }
        guard files.fileExists(atPath: rule), let expected = try? serviceScript(port: port),
            let attributes = try? files.attributesOfItem(atPath: tool),
            (attributes[.ownerAccountID] as? NSNumber)?.intValue == 0,
            let mode = attributes[.posixPermissions] as? NSNumber, mode.intValue & 0o022 == 0,
            let installed = try? String(contentsOfFile: tool, encoding: .utf8), installed == expected
        else { return .outdated }
        return .ready
    }
    /// Runs the installed script through sudo; nil when sudo would need a password.
    static func runStanding(_ operation: Operation) -> CommandResult? {
        let result = execute("/usr/bin/sudo", ["-n", tool, operation.rawValue])
        if result.code != 0 && result.output.contains("password is required") { return nil }
        return .init(code: result.code, output: result.output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    static func authorize(port: String, completed: @escaping (CommandResult) -> Void) {
        do {
            let command = try installCommand(port: port, user: getuid())
            administrator(
                command, prompt: "moko needs permission to save the authorization for the installed mysql service.",
                completed: completed)
        } catch { completed(.init(code: 1, output: error.localizedDescription)) }
    }
    static func revoke(completed: @escaping (CommandResult) -> Void) {
        administrator(
            removeCommand, prompt: "moko needs permission to remove the saved mysql service authorization.",
            completed: completed)
    }
    static func appleScript(_ shell: String, prompt: String) -> String {
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"" + escaped + "\" with prompt \"" + prompt + "\" with administrator privileges"
    }
    private static func administrator(_ shell: String, prompt: String, completed: @escaping (CommandResult) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            let descriptor = NSAppleScript(source: appleScript(shell, prompt: prompt))?.executeAndReturnError(&error)
            let code = (error?[NSAppleScript.errorNumber] as? NSNumber)?.int32Value ?? (descriptor == nil ? 1 : 0)
            let output =
                code == -128
                ? "cancelled" : (error?[NSAppleScript.errorMessage] as? String ?? descriptor?.stringValue ?? "")
            DispatchQueue.main.async { completed(.init(code: code, output: output)) }
        }
    }
}
