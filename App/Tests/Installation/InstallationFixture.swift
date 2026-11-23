import CryptoKit
import Foundation
import Security

final class InstallationTLS: NSObject, URLSessionDelegate {
    private let certificate: SecCertificate
    init(certificate: URL) throws {
        guard let value = SecCertificateCreateWithData(nil, try Data(contentsOf: certificate) as CFData) else {
            throw DatabaseError.message("invalid fixture certificate")
        }
        self.certificate = value
    }
    func urlSession(
        _ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let trust = challenge.protectionSpace.serverTrust,
            SecTrustSetAnchorCertificates(trust, [certificate] as CFArray) == errSecSuccess,
            SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
            SecTrustEvaluateWithError(trust, nil)
        else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

@MainActor
final class InstallationFixture {
    let root: URL
    let base: URL
    let session: URLSession
    let key = Curve25519.Signing.PrivateKey()
    let metadata: [String: Any]
    private(set) var checks = 0

    init() throws {
        let environment = ProcessInfo.processInfo.environment
        func input(_ name: String) throws -> String {
            guard let value = environment["MOKO_INSTALLATION_" + name], !value.isEmpty else {
                throw DatabaseError.message("missing isolated installation fixture: " + name)
            }
            return value
        }
        root = URL(fileURLWithPath: try input("WORK"))
        guard let base = URL(string: try input("URL")), base.scheme == "https", base.host == "127.0.0.1" else {
            throw DatabaseError.message("the installation fixture must use loopback HTTPS")
        }
        self.base = base
        metadata = try JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: try input("METADATA")))) as? [String: Any] ?? [:]
        let delegate = try InstallationTLS(certificate: URL(fileURLWithPath: try input("CERT")))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 120
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
    var trust: RuntimeTrust {
        .init(
            catalogURL: base.appendingPathComponent("catalog.json"),
            signatureURL: base.appendingPathComponent("catalog.sig"),
            publicKey: key.publicKey.rawRepresentation.base64EncodedString(), teamID: "TEST123456")
    }
    func require(_ value: Bool, _ description: String) throws {
        guard value else { throw DatabaseError.message(description) }
        checks += 1
    }
    func publish(path: String = "runtime.dmg", version: String = "11.8.9", identifier: String? = nil) throws {
        var package = metadata
        package.removeValue(forKey: "public")
        package["id"] = identifier ?? "mariadb-" + version + "-arm64"
        package["version"] = version
        package["compatibilityLine"] = version.hasPrefix("12.") ? "12.0" : "11.8"
        package["url"] = base.appendingPathComponent(path).absoluteString
        package["sourcesURL"] = "https://example.invalid/fixture-source.zip"
        package["licensesURL"] = "https://example.invalid/fixture-license"
        package["teamID"] = trust.teamID
        let data = try JSONSerialization.data(withJSONObject: ["formatVersion": 1, "packages": [package]])
        try data.write(to: root.appendingPathComponent("catalog.json"), options: .atomic)
        try key.signature(for: data).write(to: root.appendingPathComponent("catalog.sig"), options: .atomic)
    }
    func model(_ name: String, production: Bool = false) -> RuntimeComponents {
        let folder = root.appendingPathComponent(name)
        let database = root.appendingPathComponent(name + "-data")
        if production {
            return RuntimeComponents(validationFolder: folder, databaseFolder: database, trust: trust, session: session)
        }
        return RuntimeComponents(
            validationFolder: folder, databaseFolder: database, trust: trust, session: session,
            extractor: { image, destination, package in
                try Self.extractDevelopment(image, destination, package)
            })
    }
    nonisolated private static func extractDevelopment(_ image: URL, _ target: URL, _ package: RuntimePackage) throws {
        try RuntimeArchive.copyVerified(image, destination: target, package: package) { runtime in
            let checked = execute("/usr/bin/codesign", ["--verify", "--deep", "--strict", runtime.path])
            guard checked.code == 0 else { throw DatabaseError.message("invalid development signature") }
        }
    }
    func wait(_ model: RuntimeComponents, timeout: Double = 80) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while model.busy && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try require(!model.busy, "installation operation timed out: " + model.phase)
    }
    func install(_ model: RuntimeComponents, inactive: @escaping () -> Bool = { true }) async throws {
        await model.refresh()
        guard let package = model.packages.first else {
            throw DatabaseError.message("fixture catalog was not loaded: " + model.error)
        }
        model.install(package, inactive: inactive)
        try await wait(model)
    }
    func requireClean(_ name: String) throws {
        let folder = root.appendingPathComponent(name)
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        try require(!entries.contains { $0.hasPrefix(".install-") }, "partial installation was left active")
        try require(!entries.contains("active.json"), "failed installation activated a component")
    }
}
