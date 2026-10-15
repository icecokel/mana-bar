import Foundation
import Security

func require(_ status: OSStatus, _ operation: String) throws {
    guard status == errSecSuccess else {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        throw NSError(domain: operation, code: Int(status), userInfo: [
            NSLocalizedDescriptionKey: "\(operation): \(message) (\(status))",
        ])
    }
}

do {
    try require(SecKeychainSetUserInteractionAllowed(false), "Disable signing helper prompts")
    let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let password = try String(contentsOf: directory.appendingPathComponent("password"), encoding: .utf8)
        .trimmingCharacters(in: .newlines)
    let path = directory.appendingPathComponent("manabar-signing.keychain-db").path
    var keychain: SecKeychain?
    if FileManager.default.fileExists(atPath: path) {
        try require(SecKeychainOpen(path, &keychain), "Open local signing keychain")
    } else {
        // Private keychains outside System/login paths do not enter the user's search list.
        try password.withCString {
            try require(SecKeychainCreate(path, UInt32(password.utf8.count), $0, false, nil, &keychain),
                        "Create local signing keychain")
        }
    }
    try password.withCString {
        try require(SecKeychainUnlock(keychain, UInt32(password.utf8.count), $0, true), "Unlock local signing keychain")
    }
    var identity: CFTypeRef?
    let query: [String: Any] = [
        kSecClass as String: kSecClassIdentity,
        kSecMatchSearchList as String: [keychain!],
        kSecReturnRef as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    let status = SecItemCopyMatching(query as CFDictionary, &identity)
    if status == errSecItemNotFound {
        var signer: SecTrustedApplication?
        try require(SecTrustedApplicationCreateFromPath("/usr/bin/codesign", &signer), "Find codesign")
        var access: SecAccess?
        try require(SecAccessCreate("ManaBar local development signing" as CFString,
                                    [signer!] as CFArray, &access), "Create signing key access")
        let data = try Data(contentsOf: directory.appendingPathComponent("identity.p12"))
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: password,
            kSecImportExportKeychain as String: keychain!,
            kSecImportExportAccess as String: access!,
        ]
        var items: CFArray?
        try require(SecPKCS12Import(data as CFData, options as CFDictionary, &items), "Import local signing identity")
    } else {
        try require(status, "Read local signing identity")
    }
} catch {
    fputs("Local signing preparation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
