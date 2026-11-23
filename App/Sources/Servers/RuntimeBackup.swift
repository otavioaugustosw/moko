import Foundation

enum RuntimeBackup {
    static func copy(_ source: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        let lease = try DatabaseRuntimeLease(directory: source)
        defer { withExtendedLifetime(lease) {} }
        guard DatabaseRuntimeLease.livePID(at: source.appendingPathComponent("server.pid")) == nil else {
            throw DatabaseError.message("stop mariadb before backing up its data folder")
        }
        let backups = RuntimePaths.storage.appendingPathComponent("backups")
        try RuntimePaths.privateDirectory(backups)
        let target = backups.appendingPathComponent("mariadb-" + UUID().uuidString)
        do { try FileManager.default.copyItem(at: source, to: target) } catch {
            try? FileManager.default.removeItem(at: target)
            throw DatabaseError.message(
                "backup failed. the installed runtime was left unchanged: " + error.localizedDescription)
        }
    }
}
