import Foundation

/// Un pack de teclas: un nombre y sus teclas. Se comparte como enlace (getagentbar.com/p#… o agentdeck://pack?d=…)
/// con el JSON en base64url, sin servidor: el enlace lleva el pack entero.
struct KeyPack: Codable, Equatable {
    struct Key: Codable, Equatable { var label: String; var text: String; var icon: String; var enter: Bool }
    var name: String
    var keys: [Key]

    /// Límites para que un enlace no traiga nada raro: como mucho 12 teclas y textos cortos.
    var valid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && name.count <= 40 && (1...12).contains(keys.count)
            && keys.allSatisfy { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty && $0.text.count <= 2000 && $0.label.count <= 24 && $0.icon.count <= 60 }
    }

    var encoded: String {
        let d = (try? JSONEncoder().encode(self)) ?? Data()
        return d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ s: String) -> KeyPack? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        guard s.count < 40_000, let d = Data(base64Encoded: b), let p = try? JSONDecoder().decode(KeyPack.self, from: d), p.valid else { return nil }
        return p
    }

    var shareURL: String { "https://getagentbar.com/p/#" + encoded }

    /// Packs listos, por herramienta.
    static let builtIn: [KeyPack] = [
        KeyPack(name: "Claude Code", keys: [
            Key(label: T.s("Plan first", "Plan antes"), text: T.s("make a plan first and wait for my ok", "haz un plan primero y espera a mi ok"), icon: "list.bullet.clipboard", enter: true),
            Key(label: T.s("Continue", "Continúa"), text: T.s("continue", "continúa"), icon: "arrow.right.circle", enter: true),
            Key(label: T.s("Test it", "Pruébalo"), text: T.s("run the tests and tell me what fails", "pasa los tests y dime qué falla"), icon: "testtube.2", enter: true),
            Key(label: T.s("Fix it", "Arréglalo"), text: T.s("fix those errors, then continue", "arregla esos errores y sigue"), icon: "wrench.and.screwdriver", enter: true),
            Key(label: T.s("Commit", "Commit"), text: T.s("commit this with a clear message", "haz commit de esto con un mensaje claro"), icon: "checkmark.seal", enter: true),
            Key(label: T.s("Recap", "Resumen"), text: T.s("short recap: where are we and what's left", "resumen corto: dónde estamos y qué falta"), icon: "list.bullet.rectangle", enter: true),
        ]),
        KeyPack(name: "Cursor", keys: [
            Key(label: T.s("Continue", "Continúa"), text: T.s("continue", "continúa"), icon: "arrow.right.circle", enter: true),
            Key(label: T.s("Smaller", "Más pequeño"), text: T.s("make a smaller change, only what's needed", "haz un cambio más pequeño, solo lo necesario"), icon: "scissors", enter: true),
            Key(label: T.s("Explain", "Explica"), text: T.s("explain what you changed and why, in 3 lines", "explica qué has cambiado y por qué, en 3 líneas"), icon: "text.quote", enter: true),
            Key(label: T.s("Fix lint", "Arregla lint"), text: T.s("fix the lint and type errors", "arregla los errores de lint y de tipos"), icon: "hammer", enter: true),
            Key(label: T.s("Undo", "Deshaz"), text: T.s("undo that last change", "deshaz el último cambio"), icon: "arrow.uturn.backward.circle", enter: true),
        ]),
        KeyPack(name: "ChatGPT", keys: [
            Key(label: T.s("Go on", "Sigue"), text: T.s("go on", "sigue"), icon: "arrow.right.circle", enter: true),
            Key(label: T.s("Shorter", "Más corto"), text: T.s("shorter, half the length", "más corto, la mitad"), icon: "text.badge.minus", enter: true),
            Key(label: T.s("Simpler", "Más simple"), text: T.s("explain it like I'm new to this", "explícamelo como si fuera nuevo en esto"), icon: "lightbulb", enter: true),
            Key(label: T.s("Table", "Tabla"), text: T.s("put that in a table", "ponlo en una tabla"), icon: "tablecells", enter: true),
            Key(label: T.s("Sources", "Fuentes"), text: T.s("give me the sources with links", "dame las fuentes con enlaces"), icon: "link", enter: true),
        ]),
        KeyPack(name: T.s("Writing", "Escribir"), keys: [
            Key(label: T.s("Shorter", "Más corto"), text: T.s("make it shorter and clearer", "hazlo más corto y más claro"), icon: "text.badge.minus", enter: true),
            Key(label: T.s("Friendlier", "Más cercano"), text: T.s("make the tone warmer and more natural", "dale un tono más cercano y natural"), icon: "face.smiling", enter: true),
            Key(label: T.s("Formal", "Formal"), text: T.s("make it formal and professional", "hazlo formal y profesional"), icon: "briefcase", enter: true),
            Key(label: T.s("3 options", "3 opciones"), text: T.s("give me 3 different versions", "dame 3 versiones distintas"), icon: "square.stack.3d.up", enter: true),
            Key(label: T.s("Translate", "Traduce"), text: T.s("translate it to English", "tradúcelo al inglés"), icon: "globe", enter: true),
        ]),
    ]
}
