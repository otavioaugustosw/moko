import Foundation
import LocalAuthentication
import Security

// An exclusive account in the test service isolates this fixture from user credentials.
let args = CommandLine.arguments
guard args.count == 3 else { exit(2) }
let service = "com.otavioaugustosw.moko.signing-continuity-fixture"
let account = args[2]
guard account.hasPrefix("moko-signing-"), account.count < 100 else { exit(2) }
let expected = Data("fixture-without-user-credentials".utf8)
let context = LAContext()
context.interactionNotAllowed = true
let key: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: account,
    kSecUseAuthenticationContext as String: context,
]

#if REBUILD
    print("Verification binary B.")
#else
    print("Verification binary A.")
#endif

if args[1] == "--create" {
    var entry = key
    entry[kSecValueData as String] = expected
    let saved = SecItemAdd(entry as CFDictionary, nil)
    print("Isolated fixture created: \(saved == errSecSuccess).")
    exit(saved == errSecSuccess ? 0 : 1)
}

var query = key
query[kSecMatchLimit as String] = kSecMatchLimitOne
query[kSecReturnData as String] = true
var value: CFTypeRef?
let status = SecItemCopyMatching(query as CFDictionary, &value)
let success = status == errSecSuccess && (value as? Data) == expected
if args[1] == "--delete" {
    guard success else { print("Unrecognized fixture; not removed."); exit(1) }
    let deleted = SecItemDelete(key as CFDictionary)
    print("Fixture removed: \(deleted == errSecSuccess).")
    exit(deleted == errSecSuccess ? 0 : 1)
}
print("Read after rebuilding without a dialog: \(success). Status: \(status).")
exit(success ? 0 : 1)
