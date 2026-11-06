import Foundation
import Security
import LocalAuthentication

enum VoiceKeychain {
    private static let service = "com.kemetcapital.agentdesk.openai"
    private static let account = "api-key"
    /// Mientras la app no tenga una firma estable de Apple, cada versión es «otra app» para el Llavero, que pregunta
    /// (y bloquea) en cada actualización. La clave va a un archivo privado de la app (0600, solo tu usuario);
    /// la que hubiera en el Llavero se pasa al archivo la primera vez.
    static var file: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Agent Deck", isDirectory: true).appendingPathComponent("openai-key")
    }
    static func read() -> String? {
        if let s = try? String(contentsOf: file, encoding: .utf8) {
            let k = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return k.isEmpty ? nil : k
        }
        guard let old = readKeychain() else { return nil }
        try? writeFile(old)
        return old
    }
    private static func writeFile(_ key: String) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data(key.utf8).write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    static func readKeychain() -> String? {
        let context=LAContext();context.interactionNotAllowed=true
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne,kSecUseAuthenticationContext as String:context]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary,&value) == errSecSuccess,let data = value as? Data else { return nil }
        return String(data:data,encoding:.utf8)
    }
    static func save(_ key: String) throws {
        let clean = key.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 1024, !clean.contains("\n"), !clean.contains("\r") else { throw VoiceServiceError(message:T.s("Enter a valid OpenAI API key.","Introduce una clave válida de la API de OpenAI.")) }
        do { try writeFile(clean) } catch { throw VoiceServiceError(message:T.s("Could not save the key on this Mac.","No se ha podido guardar la clave en este Mac.")) }
    }
    static func remove() throws {
        try? FileManager.default.removeItem(at: file)
        _ = SecItemDelete([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account] as CFDictionary) // la copia antigua, si la hubiera
    }
}
