import Foundation

enum DatabaseEngine: String, Codable, CaseIterable, Identifiable {
    case postgresql, mariadb, mysql
    var id: String { rawValue }
    var isPostgreSQL: Bool { self == .postgresql }
    var defaultPort: String { isPostgreSQL ? "5432" : "3306" }
    var localPort: String { isPostgreSQL ? "15432" : "13306" }
    var protectedDatabases: Set<String> {
        isPostgreSQL
            ? ["postgres", "template0", "template1"]
            : ["mysql", "information_schema", "performance_schema", "sys"]
    }
}

struct DatabaseLocation: Equatable, Codable {
    var database: String
    var schema = "public"
}

struct ConnectionProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var engine: DatabaseEngine
    var managed: Bool
    var host: String
    var port: String
    var user: String
    var database: String
    var tlsMode: String
    var rootCertificate: String
    var credentialAccount: String

    static func local(_ engine: DatabaseEngine) -> Self {
        .init(
            id: engine.isPostgreSQL
                ? UUID(uuidString: "F0AB88AF-48EF-44C6-8DBD-7299BFE27401")!
                : UUID(uuidString: "F0AB88AF-48EF-44C6-8DBD-7299BFE27402")!,
            name: "local " + engine.rawValue, engine: engine, managed: true, host: "127.0.0.1",
            port: engine.localPort, user: "moko", database: engine.isPostgreSQL ? "postgres" : "",
            tlsMode: engine.isPostgreSQL ? "prefer" : "", rootCertificate: "",
            credentialAccount: engine.isPostgreSQL ? "moko.bundled.postgresql" : "moko.bundled.mariadb")
    }
    func connection(password: String) -> DatabaseConnection {
        .init(
            host: host, port: port, user: user, password: password, engine: engine,
            defaultDatabase: database, tlsMode: tlsMode, rootCertificate: rootCertificate, profileID: id)
    }
}
