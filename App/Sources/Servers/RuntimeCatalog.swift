import CryptoKit
import Foundation

struct RuntimePackage: Codable, Identifiable, Equatable {
    let id: String
    let engine: String
    let version: String
    let compatibilityLine: String
    let architecture: String
    let minimumOS: String
    let bytes: Int64
    let sha256: String
    let url: URL
    let sourcesURL: URL
    let licensesURL: URL
    let teamID: String
}
struct RuntimeCatalog: Codable {
    let formatVersion: Int
    let packages: [RuntimePackage]
}
struct RuntimeTrust: Codable {
    let catalogURL: URL
    let signatureURL: URL
    let publicKey: String
    let teamID: String
    static var bundled: Self? {
        guard let url = Bundle.main.url(forResource: "RuntimeTrust", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    private static func compatibleOS(_ version: String) -> Bool {
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard !parts.isEmpty, parts[0] >= 26, parts.allSatisfy({ $0 >= 0 }), parts.count <= 3,
            parts.count == version.split(separator: ".").count
        else { return false }
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(
            .init(
                majorVersion: parts[0], minorVersion: parts.count > 1 ? parts[1] : 0,
                patchVersion: parts.count > 2 ? parts[2] : 0))
    }
    func verify(_ catalog: Data, signature: Data) throws -> RuntimeCatalog {
        guard catalog.count <= 1_000_000, let bytes = Data(base64Encoded: publicKey),
            let key = try? Curve25519.Signing.PublicKey(rawRepresentation: bytes),
            key.isValidSignature(signature, for: catalog)
        else { throw DatabaseError.message("the component catalog signature is invalid") }
        let result = try JSONDecoder().decode(RuntimeCatalog.self, from: catalog)
        guard result.formatVersion == 1 else {
            throw DatabaseError.message("update moko to use this component catalog")
        }
        var identifiers = Set<String>()
        for package in result.packages {
            guard package.engine == "mariadb", package.architecture == "arm64", package.teamID == teamID,
                package.id.range(of: #"^[a-z0-9][a-z0-9.-]{0,95}$"#, options: .regularExpression) != nil,
                identifiers.insert(package.id).inserted,
                package.url.scheme == "https", package.sourcesURL.scheme == "https",
                package.licensesURL.scheme == "https",
                package.version.hasPrefix(package.compatibilityLine + "."),
                package.bytes > 0, package.bytes <= 4_000_000_000, package.sha256.count == 64,
                package.sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
                !package.id.hasPrefix("."), !package.id.contains(".."),
                Self.compatibleOS(package.minimumOS),
                teamID.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil
            else {
                throw DatabaseError.message("the component catalog contains an unsupported package")
            }
        }
        return result
    }
}
struct InstalledRuntime: Codable {
    let id: String
    let version: String
    let compatibilityLine: String
    var sourcesURL: URL?
    var licensesURL: URL?
}
