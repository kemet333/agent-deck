import Foundation
import Security
import LocalAuthentication

enum VoiceKeychain {
    private static let service = "com.kemetcapital.agentdesk.openai"
    private static let account = "api-key"
    static func read() -> String? {
        let context=LAContext();context.interactionNotAllowed=true
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne,kSecUseAuthenticationContext as String:context]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary,&value) == errSecSuccess,let data = value as? Data else { return nil }
        return String(data:data,encoding:.utf8)
    }
    static func save(_ key: String) throws {
        let clean = key.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 1024, !clean.contains("\n"), !clean.contains("\r") else { throw VoiceServiceError(message:T.s("Enter a valid OpenAI API key.","Introduce una clave válida de la API de OpenAI.")) }
        let base: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account]
        let attrs: [String:Any] = [kSecValueData as String:Data(clean.utf8)]
        let existing = SecItemUpdate(base as CFDictionary,attrs as CFDictionary)
        let status: OSStatus
        if existing == errSecItemNotFound { status = SecItemAdd(base.merging(attrs){_,new in new}.merging([kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]){_,new in new} as CFDictionary,nil) } else { status = existing }
        guard status == errSecSuccess else { throw VoiceServiceError(message:T.s("Could not save the key in Keychain.","No se ha podido guardar la clave en el Llavero.")) }
    }
    static func remove() throws {
        let status = SecItemDelete([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VoiceServiceError(message:T.s("Could not remove the key from Keychain.","No se ha podido eliminar la clave del Llavero.")) }
    }
}
