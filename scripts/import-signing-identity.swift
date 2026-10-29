import Foundation
import Security

// The temporary wrapping password is read from a private file, never argv/logs.
// Only /usr/bin/codesign receives pre-authorized access to this new private key.
func check(_ status: OSStatus) throws {
    guard status == errSecSuccess else {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
            NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
        ])
    }
}

do {
    guard CommandLine.arguments.count == 4 else { throw NSError(domain: "SigningSetup", code: 1) }
    let keychainPath = CommandLine.arguments[1]
    let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
    let password = try String(contentsOfFile: CommandLine.arguments[3], encoding: .utf8)
        .trimmingCharacters(in: .newlines)
    var keychain: SecKeychain?
    try check(SecKeychainOpen(keychainPath, &keychain))
    var signer: SecTrustedApplication?
    try check(SecTrustedApplicationCreateFromPath("/usr/bin/codesign", &signer))
    var access: SecAccess?
    try check(SecAccessCreate("Whisper Paste Local Signing" as CFString, [signer!] as CFArray, &access))
    let options = [kSecImportExportPassphrase: password,
                   kSecImportExportKeychain: keychain!, kSecImportExportAccess: access!] as CFDictionary
    var items: CFArray?
    try check(SecPKCS12Import(archive as CFData, options, &items))
    print("Imported the local signing identity into the user keychain.")
} catch {
    FileHandle.standardError.write(Data(("Signing import failed: \(error.localizedDescription)\n").utf8))
    exit(1)
}
