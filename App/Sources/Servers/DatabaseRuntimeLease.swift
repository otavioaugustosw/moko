import Darwin
import Foundation

// Serialize lifecycle changes across app/debugger instances sharing one data folder.
final class DatabaseRuntimeLease {
    private let descriptor: Int32
    init(directory: URL) throws {
        descriptor = open(
            directory.appendingPathComponent("moko-lifecycle.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw DatabaseError.message("could not open the database lifecycle lock") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw DatabaseError.message("another moko instance is starting or stopping this database. wait and retry.")
        }
    }
    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
    static func livePID(at url: URL) -> Int32? {
        guard let value = try? String(contentsOf: url, encoding: .utf8),
            let pid = Int32(value.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1,
            kill(pid, 0) == 0 || errno == EPERM
        else { return nil }
        return pid
    }
    static func hasParent(_ pid: Int32) -> Bool {
        let result = execute("/bin/ps", ["-o", "ppid=", "-p", String(pid)])
        return Int(result.output.trimmingCharacters(in: .whitespacesAndNewlines)).map { $0 > 1 } ?? true
    }
    // A recovered orphan can have only one owning app, even though its PPID remains 1.
    static func claimOwnership(in directory: URL) throws -> Bool {
        let file = directory.appendingPathComponent("moko-owner.pid")
        let current = ProcessInfo.processInfo.processIdentifier
        if let owner = livePID(at: file), owner != current { return false }
        try Data(String(current).utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return true
    }
    static func clearOwnership(in directory: URL) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("moko-owner.pid"))
    }
}
