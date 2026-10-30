import AppKit
import ApplicationServices

/// Escribe una frase en la app que tiene el foco (Claude, ChatGPT en el navegador, Cursor, Terminal…):
/// la deja en el portapapeles, pulsa ⌘V y, si procede, Intro; luego devuelve el portapapeles anterior.
/// Necesita el permiso de Accesibilidad (Ajustes del Sistema → Privacidad y seguridad → Accesibilidad).
enum Sender {
    static let keyV: CGKeyCode = 9
    static let keyReturn: CGKeyCode = 36

    static func accessibilityGranted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func send(_ text: String, enter: Bool) {
        guard accessibilityGranted(prompt: true) else { return }
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // El pegado va a la app activa; el panel del Desk no activa Agent Desk, así que el chat sigue delante.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            tap(keyV, flags: .maskCommand)
            if enter {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { tap(keyReturn, flags: []) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if let previous = previous {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                }
            }
        }
    }

    static func tap(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Nombre de la app que recibirá la frase (la que está delante).
    static func targetName() -> String {
        let app = NSWorkspace.shared.frontmostApplication
        if app?.bundleIdentifier == Bundle.main.bundleIdentifier { return "…" }
        return app?.localizedName ?? "…"
    }
}
