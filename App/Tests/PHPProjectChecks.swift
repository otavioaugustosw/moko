import Foundation

@main struct CheckPHPProjects {
    static func main() throws {
        let suite = "moko.projects.test." + UUID().uuidString
        guard let preferences = UserDefaults(suiteName: suite) else { exit(1) }
        defer { preferences.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let firstFolder = folder.appendingPathComponent("first")
        let secondFolder = folder.appendingPathComponent("second")
        let movedFolder = folder.appendingPathComponent("moved")
        for url in [firstFolder, secondFolder] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        var checks = 0
        func require(_ condition: Bool, _ message: String) {
            guard condition else { print("php projects: " + message); exit(1) }
            checks += 1
        }
        let php = PHPServer(preferences: preferences)
        require(php.projects.items.isEmpty && php.documentRoot.isEmpty, "new library is empty")
        let first = php.projects.add(firstFolder, port: "8081")
        let second = php.projects.add(secondFolder, port: "8082")
        require(first.available && second.available, "existing directories are available")
        require(php.projects.add(firstFolder).id == first.id && php.projects.items.count == 2, "adding a folder is idempotent")
        php.requestSwitch(to: first)
        require(php.projectPrompt?.kind == .switchProject && php.documentRoot.isEmpty, "request requires confirmation")
        php.projectPrompt = nil
        require(php.projects.activeID == nil, "cancelling does not select a project")
        php.confirmSwitch(to: first, connection: nil)
        require(php.documentRoot == first.path && php.port == "8081", "confirmation applies project settings")
        require(!php.running, "selecting a project does not start a stopped server")
        php.requestSwitch(to: second)
        require(php.documentRoot == first.path && php.projects.activeID == first.id, "request preserves current project")
        php.confirmSwitch(to: second, connection: nil)
        php.port = "8083"
        php.router = secondFolder.appendingPathComponent("router.php").path
        php.saveConfiguration()
        let restored = PHPServer(preferences: preferences)
        require(restored.projects.items.count == 2 && restored.projects.activeID == second.id, "library persists selection")
        require(restored.port == "8083" && restored.router == php.router, "project configuration persists")
        try FileManager.default.moveItem(at: secondFolder, to: movedFolder)
        let unavailable = php.projects.active!
        require(!unavailable.available, "missing directories are detected")
        php.requestSwitch(to: unavailable)
        require(php.projectPrompt?.kind == .missingFolder, "missing directory offers repair")
        php.updateFolder(for: unavailable, to: movedFolder)
        require(php.projectPrompt?.kind == .switchProject, "repair requires confirmation before switching")
        require(php.documentRoot == unavailable.path, "repair does not silently replace active server folder")
        let repaired = php.projects.active!
        php.confirmSwitch(to: repaired, connection: nil)
        require(php.documentRoot == movedFolder.path && repaired.id == second.id, "repair preserves project identity")
        php.removeProject(first)
        require(php.projects.activeID == second.id && FileManager.default.fileExists(atPath: first.path),
                "removing another project preserves active project and files")
        php.requestRemoval(repaired)
        require(php.projects.items.count == 1 && php.projectPrompt?.kind == .removeProject, "removal is reviewable")
        php.removeProject(repaired)
        require(php.projects.items.isEmpty && php.documentRoot.isEmpty, "removing active project clears selection")
        require(FileManager.default.fileExists(atPath: movedFolder.path), "project removal leaves files intact")
        preferences.set(first.path, forKey: "moko.php.root")
        preferences.set("8091", forKey: "moko.php.port")
        let migrated = PHPServer(preferences: preferences)
        require(migrated.projects.active?.path == first.path && migrated.port == "8091", "existing folder is migrated")
        print("php projects: \(checks) persistence, confirmation, removal and path-repair checks passed.")
    }
}
