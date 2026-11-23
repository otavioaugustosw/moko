import Foundation
import LocalAuthentication
import Security

func fail(_ message: String, _ status: OSStatus = errSecParam) -> Never {
    fputs(message + " (status \(status)).\n", stderr)
    exit(1)
}

// Imports only a user-requested signing identity. Never queries password items.
let args = CommandLine.arguments
guard args.count >= 3 else { fail("Invalid setup arguments") }
let certificateData = try Data(contentsOf: URL(fileURLWithPath: args[2]))
if args[1] == "--check" {
    let context = LAContext()
    context.interactionNotAllowed = true
    let query: [String: Any] = [
        kSecClass as String: kSecClassIdentity,
        kSecReturnRef as String: true,
        kSecMatchLimit as String: kSecMatchLimitAll,
        kSecUseAuthenticationContext as String: context,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let identities = result as? [SecIdentity] else { exit(1) }
    for identity in identities {
        var certificate: SecCertificate?
        if SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess,
            let certificate, SecCertificateCopyData(certificate) as Data == certificateData { exit(0) }
    }
    exit(1)
}
guard args[1] == "--import", args.count == 4, let passphrase = readLine(), !passphrase.isEmpty else {
    fail("Invalid import arguments")
}
let data = try Data(contentsOf: URL(fileURLWithPath: args[3]))
let options = [kSecImportExportPassphrase as String: passphrase]
var items: CFArray?
let imported = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
guard imported == errSecSuccess else { fail("Could not import the signing identity", imported) }
print("Signing identity imported using the system keychain.")
