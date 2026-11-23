import CryptoKit
import Foundation

@main struct CheckComponents {
    static var checks = 0
    static func main() throws {
        try catalog()
        try migration()
        checks += try DatabaseUtilityChecks.run()
        checks += try AgentAccessChecks.run()
        print("Components: \(checks) catalog, migration, native transfer tools, service target and agent access checks passed.")
    }
    private static func require(_ condition: Bool, _ description: String) throws {
        guard condition else { throw DatabaseError.message(description) }
        checks += 1
    }
    private static func catalog() throws {
        let key = Curve25519.Signing.PrivateKey()
        let trust = RuntimeTrust(
            catalogURL: URL(string: "https://example.com/catalog.json")!,
            signatureURL: URL(string: "https://example.com/catalog.sig")!,
            publicKey: key.publicKey.rawRepresentation.base64EncodedString(), teamID: "ABCDE12345")
        let package: [String: Any] = [
            "id": "mariadb-11.8.9-arm64", "engine": "mariadb", "version": "11.8.9",
            "compatibilityLine": "11.8", "architecture": "arm64", "minimumOS": "26.0",
            "bytes": 100, "sha256": String(repeating: "a", count: 64),
            "url": "https://example.com/runtime.dmg", "sourcesURL": "https://example.com/source.zip",
            "licensesURL": "https://example.com/license", "teamID": "ABCDE12345",
        ]
        func encoded(_ packages: [[String: Any]]) throws -> Data {
            try JSONSerialization.data(
                withJSONObject: ["formatVersion": 1, "packages": packages], options: [.sortedKeys])
        }
        let data = try encoded([package]), signature = try key.signature(for: data)
        try require(try trust.verify(data, signature: signature).packages.count == 1, "valid catalog rejected")
        var changed = data
        changed[changed.startIndex] ^= 1
        try rejected { _ = try trust.verify(changed, signature: signature) }
        try rejected { _ = try trust.verify(data, signature: Data(repeating: 0, count: 64)) }
        for (name, value) in [
            ("id", "../escape"), ("id", ".hidden"), ("engine", "postgresql"),
            ("architecture", "x86_64"), ("minimumOS", "999.0"), ("minimumOS", "-26"),
            ("sha256", String(repeating: "z", count: 64)), ("url", "http://example.com/runtime"),
            ("sourcesURL", "file:///source"), ("teamID", "EVIL123456"), ("compatibilityLine", "12.0"),
        ] {
            var invalid = package
            invalid[name] = value
            let payload = try encoded([invalid])
            try rejected { _ = try trust.verify(payload, signature: key.signature(for: payload)) }
        }
        let duplicates = try encoded([package, package])
        try rejected { _ = try trust.verify(duplicates, signature: key.signature(for: duplicates)) }
        var invalid = package
        invalid["bytes"] = -1
        let negative = try encoded([invalid])
        try rejected { _ = try trust.verify(negative, signature: key.signature(for: negative)) }
    }
    private static func rejected(_ operation: () throws -> Void) throws {
        var failed = false
        do { try operation() } catch { failed = true }
        try require(failed, "unsafe component catalog was accepted")
    }
    private static func migration() throws {
        let suite = "moko.migration.check." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        var profiles = ConnectionProfiles(preferences: preferences)
        try require(
            profiles.selected.engine == .postgresql && profiles.selected.managed,
            "new install does not default to postgresql")
        preferences.removePersistentDomain(forName: suite)
        preferences.set("external", forKey: "moko.database.backend")
        preferences.set("fixture.invalid", forKey: "host")
        preferences.set("3307", forKey: "port")
        preferences.set("legacy", forKey: "username")
        profiles = ConnectionProfiles(preferences: preferences)
        try require(
            profiles.selected.engine == .mysql && !profiles.selected.managed,
            "legacy external connection changed engine")
        try require(
            profiles.selected.credentialAccount == "legacy@fixture.invalid:3307", "legacy keychain identifier changed")
        let selected = profiles.selected.id
        let reloaded = ConnectionProfiles(preferences: preferences)
        try require(
            reloaded.selectedID == selected && reloaded.selected.port == "3307", "profile selection did not persist")
        preferences.removePersistentDomain(forName: suite)
        preferences.set("bundled", forKey: "moko.database.backend")
        profiles = ConnectionProfiles(preferences: preferences)
        try require(
            profiles.selected.engine == .mariadb && profiles.selected.credentialAccount == "moko.bundled.mariadb",
            "legacy mariadb credentials or engine changed")
        let data = preferences.data(forKey: "moko.connectionProfiles.v1")!
        try require(!String(bytes: data, encoding: .utf8)!.contains("password"), "profile metadata stores a password")
        let external = ConnectionProfile(
            id: UUID(), name: "standalone", engine: .postgresql, managed: false,
            host: "fixture.invalid", port: "5432", user: "test", database: "postgres", tlsMode: "verify-full",
            rootCertificate: "", credentialAccount: "fixture-only")
        preferences.set(try JSONEncoder().encode([external]), forKey: "moko.connectionProfiles.v1")
        preferences.set(external.id.uuidString, forKey: "moko.selectedConnection")
        profiles = ConnectionProfiles(preferences: preferences)
        try require(
            profiles.selected.id == external.id && profiles.items.filter(\.managed).count == 2,
            "adding local components changed the selected external connection")
        let first = external.connection(password: "test-only")
        var duplicate = external
        duplicate.id = UUID()
        try require(
            first.identity != duplicate.connection(password: "test-only").identity,
            "different profiles share a catalog identity")
    }
}
