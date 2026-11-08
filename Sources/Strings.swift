import Foundation

/// Textos de la interfaz: inglés por defecto (Diego, 08/11); castellano si se elige en Ajustes → General → Idioma.
/// (Dos idiomas en un archivo, sin tablas .strings: la app es pequeña y así se lee de un vistazo.)
/// El dictado no depende de esto: escucha en el idioma del sistema.
enum T {
    static let languageKey = "appLanguage"
    static let es: Bool = UserDefaults.standard.string(forKey: languageKey) == "es"
    static func s(_ en: String, _ es: String) -> String { T.es ? es : en }

    /// Idioma del dictado: el del sistema (es-ES, en-US, pt-BR…).
    static var speechLocale: Locale {
        let id = Locale.preferredLanguages.first ?? "en-US"
        return Locale(identifier: id)
    }
}
