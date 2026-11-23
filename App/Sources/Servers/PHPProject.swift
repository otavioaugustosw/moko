import Combine
import Foundation

struct PHPProject: Codable, Identifiable, Equatable {
    var id = UUID()
    var path: String
    var port = "8080"
    var router = ""
    var connectionProfileID: UUID?
    var database: String?
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
    var available: Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
    }
}

final class PHPProjectLibrary: ObservableObject {
    @Published private(set) var items: [PHPProject]
    @Published private(set) var activeID: UUID?
    private let preferences: UserDefaults
    private let storageKey = "moko.php.projects"
    var active: PHPProject? { items.first { $0.id == activeID } }
    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        items =
            preferences.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([PHPProject].self, from: $0) } ?? []
        activeID = preferences.string(forKey: "moko.php.activeProject").flatMap(UUID.init(uuidString:))
        if items.isEmpty, let path = preferences.string(forKey: "moko.php.root"), !path.isEmpty {
            let project = PHPProject(path: path, port: preferences.string(forKey: "moko.php.port") ?? "8080")
            items = [project]
            activeID = project.id
            persist()
        }
        if !items.contains(where: { $0.id == activeID }) { activeID = nil }
    }
    @discardableResult
    func add(_ url: URL, port: String = "8080") -> PHPProject {
        let path = url.standardizedFileURL.path
        if let existing = items.first(where: { $0.path == path }) { return existing }
        let project = PHPProject(path: path, port: port)
        items.append(project)
        persist()
        return project
    }
    func activate(_ project: PHPProject) {
        guard items.contains(where: { $0.id == project.id }) else { return }
        activeID = project.id
        persist()
    }
    @discardableResult
    func update(_ project: PHPProject) -> PHPProject {
        guard let index = items.firstIndex(where: { $0.id == project.id }) else { return project }
        items[index] = project
        persist()
        return project
    }
    func remove(_ project: PHPProject) {
        items.removeAll { $0.id == project.id }
        if activeID == project.id { activeID = nil }
        persist()
    }
    func associate(_ project: PHPProject, profileID: UUID?, database: String) {
        var updated = project
        updated.connectionProfileID = profileID
        updated.database = database.isEmpty ? nil : database
        update(updated)
    }
    private func persist() {
        guard !PreviewRuntime.isActive else { return }
        if let data = try? JSONEncoder().encode(items) { preferences.set(data, forKey: storageKey) }
        preferences.set(activeID?.uuidString, forKey: "moko.php.activeProject")
    }
}

struct PHPProjectPrompt: Identifiable {
    enum Kind { case switchProject, missingFolder, updateFolder, removeProject }
    let id = UUID()
    var project: PHPProject
    var kind: Kind
}
