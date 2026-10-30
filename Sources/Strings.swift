import Foundation

/// Textos de la interfaz: inglés por defecto, castellano si el Mac está en español.
/// (Dos idiomas en un archivo, sin tablas .strings: la app es pequeña y así se lee de un vistazo.)
enum T {
    static let es: Bool = Locale.preferredLanguages.first?.lowercased().hasPrefix("es") ?? false
    static func s(_ en: String, _ es: String) -> String { T.es ? es : en }

    /// Idioma del dictado: el del sistema (es-ES, en-US, pt-BR…).
    static var speechLocale: Locale {
        let id = Locale.preferredLanguages.first ?? "en-US"
        return Locale(identifier: id)
    }
}
