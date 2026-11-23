import Combine
import Foundation

final class ConnectionProfiles: ObservableObject {
    @Published private(set) var items: [ConnectionProfile]
    @Published private(set) var selectedID: UUID
    private let preferences: UserDefaults
    private let key = "moko.connectionProfiles.v1"
    var selected: ConnectionProfile { items.first { $0.id == selectedID } ?? items[0] }

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        if let data = preferences.data(forKey: key),
            let saved = try? JSONDecoder().decode([ConnectionProfile].self, from: data),
            !saved.isEmpty {
            items = saved
            selectedID =
                preferences.string(forKey: "moko.selectedConnection")
                .flatMap(UUID.init(uuidString:)) ?? saved[0].id
        } else {
            var profiles = [ConnectionProfile.local(.postgresql), .local(.mariadb)]
            let previousBackend = preferences.string(forKey: "moko.database.backend")
            if previousBackend == "external" || preferences.string(forKey: "host") != nil {
                let host =
                    preferences.string(forKey: "moko.external.host") ?? preferences.string(forKey: "host")
                    ?? "127.0.0.1"
                let port =
                    preferences.string(forKey: "moko.external.port") ?? preferences.string(forKey: "port") ?? "3306"
                let user =
                    preferences.string(forKey: "moko.external.user") ?? preferences.string(forKey: "username") ?? "root"
                let profile = ConnectionProfile(
                    id: UUID(), name: "existing server", engine: .mysql, managed: false,
                    host: host, port: port, user: user, database: "", tlsMode: "",
                    rootCertificate: "", credentialAccount: "\(user)@\(host):\(port)")
                profiles.append(profile)
                selectedID = previousBackend == "bundled" ? profiles[1].id : profile.id
            } else {
                selectedID = previousBackend == "bundled" ? profiles[1].id : profiles[0].id
            }
            items = profiles
        }
        for engine in [DatabaseEngine.postgresql, .mariadb]
        where !items.contains(where: { $0.managed && $0.engine == engine }) {
            items.append(.local(engine))
        }
        if !items.contains(where: { $0.id == selectedID }) { selectedID = items[0].id }
        persist()
    }
    func select(_ id: UUID) {
        guard items.contains(where: { $0.id == id }) else { return }
        selectedID = id
        persist()
    }
    func save(_ profile: ConnectionProfile) {
        if let index = items.firstIndex(where: { $0.id == profile.id }) {
            items[index] = profile
        } else {
            items.append(profile)
        }
        persist()
    }
    func remove(_ id: UUID) {
        guard let profile = items.first(where: { $0.id == id }), !profile.managed else { return }
        items.removeAll { $0.id == id }
        if selectedID == id { selectedID = items[0].id }
        persist()
    }
    /// Read-only snapshot for other processes of the app (the agent server); never writes preferences.
    static func stored(_ preferences: UserDefaults = .standard) -> (items: [ConnectionProfile], selected: UUID?) {
        preferences.synchronize()
        let items =
            preferences.data(forKey: "moko.connectionProfiles.v1")
            .flatMap { try? JSONDecoder().decode([ConnectionProfile].self, from: $0) } ?? []
        return (items, preferences.string(forKey: "moko.selectedConnection").flatMap(UUID.init(uuidString:)))
    }
    private func persist() {
        guard !PreviewRuntime.isActive else { return }
        if let data = try? JSONEncoder().encode(items) { preferences.set(data, forKey: key) }
        preferences.set(selectedID.uuidString, forKey: "moko.selectedConnection")
    }
}
