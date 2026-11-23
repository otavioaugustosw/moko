import CryptoKit
import Foundation
import Security

enum RuntimeSignature {
    static func validate(_ runtime: URL, teamID: String) throws {
        guard teamID.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil else {
            throw DatabaseError.message("the runtime publisher identity is invalid")
        }
        var requirement: SecRequirement?
        let expression =
            "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\" "
            + "and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        guard SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess,
            let requirement
        else { throw DatabaseError.message("could not validate the runtime publisher") }
        var bundleCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(runtime as CFURL, [], &bundleCode) == errSecSuccess, let bundleCode,
            SecStaticCodeCheckValidity(bundleCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement)
                == errSecSuccess
        else {
            throw DatabaseError.message("the runtime bundle has an invalid publisher signature")
        }
        guard
            let enumerator = FileManager.default.enumerator(
                at: runtime, includingPropertiesForKeys: [.isSymbolicLinkKey])
        else {
            throw DatabaseError.message("the runtime package is empty")
        }
        var executables = 0
        for case let file as URL in enumerator {
            let resolved = file.resolvingSymlinksInPath()
            guard resolved.path.hasPrefix(runtime.resolvingSymlinksInPath().path + "/") else {
                throw DatabaseError.message("the runtime contains a link outside its package")
            }
            guard let input = try? FileHandle(forReadingFrom: file) else { continue }
            let header = try? input.read(upToCount: 8)
            try? input.close()
            guard let header else { continue }
            let magic = header.prefix(4)
            let unsupported = [
                Data([0xFE, 0xED, 0xFA, 0xCF]), Data([0xCE, 0xFA, 0xED, 0xFE]),
                Data([0xFE, 0xED, 0xFA, 0xCE]), Data([0xCA, 0xFE, 0xBA, 0xBE]),
                Data([0xBE, 0xBA, 0xFE, 0xCA]), Data([0xCA, 0xFE, 0xBA, 0xBF]),
                Data([0xBF, 0xBA, 0xFE, 0xCA]),
            ]
            guard !unsupported.contains(Data(magic)) else {
                throw DatabaseError.message("the runtime contains an unsupported executable format")
            }
            guard magic == Data([0xCF, 0xFA, 0xED, 0xFE]) else { continue }
            guard header.suffix(4) == Data([0x0C, 0x00, 0x00, 0x01]) else {
                throw DatabaseError.message("the runtime contains an unsupported processor architecture")
            }
            var code: SecStaticCode?
            guard SecStaticCodeCreateWithPath(file as CFURL, [], &code) == errSecSuccess, let code,
                SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement)
                    == errSecSuccess
            else {
                throw DatabaseError.message("a runtime executable has an invalid publisher signature")
            }
            executables += 1
        }
        guard executables > 0 else { throw DatabaseError.message("the runtime has no supported executables") }
    }
    static func sha256(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let block = try handle.read(upToCount: 1024 * 1024), !block.isEmpty { hash.update(data: block) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

final class RuntimeDownload {
    private let session: URLSession
    private var download: URLSessionDownloadTask?
    private var observation: NSKeyValueObservation?
    init(session: URLSession = .shared) { self.session = session }
    func cancel() { download?.cancel() }
    func fetch(_ url: URL, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let task = session.downloadTask(with: url) { temporary, response, error in
                do {
                    if let error { throw error }
                    guard let temporary, let response = response as? HTTPURLResponse, response.statusCode == 200,
                        response.url?.scheme == "https"
                    else { throw DatabaseError.message("the component download is unavailable") }
                    try FileManager.default.moveItem(at: temporary, to: destination)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
            self.download = task
            observation = task.progress.observe(\.fractionCompleted, options: [.new]) { value, _ in
                progress(value.fractionCompleted)
            }
            task.resume()
        }
    }
}
