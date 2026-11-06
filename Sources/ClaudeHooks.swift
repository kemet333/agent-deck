import AppKit

/// Avisos de Claude Code: dos ganchos en ~/.claude/settings.json que abren agentdeck://alert cuando Claude Code
/// termina (Stop) o espera tu permiso o tu respuesta (Notification). Solo se añaden si el usuario lo confirma en
/// la app; antes se guarda una copia del archivo y nunca se toca nada más de su configuración.
enum ClaudeHooks {
    static let settings = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    static let marker = "agentdeck://alert"

    /// El programa de Agent Bar que decide en cada parada (piloto automático y aviso), dentro de esta app.
    static var helper: String { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/AgentBarClaudeHook").path }
    static let helperName = "AgentBarClaudeHook"
    static func command(kind: String) -> String { "\"\(helper)\" \(kind)" }
    /// Lo que el gancho de una conversación terminada espera tu respuesta en la tarjeta (luego para como siempre).
    static let waitSeconds: Double = 600

    /// Ganchos de esta versión, apuntando a esta copia de la app.
    static var installed: Bool { text.contains(helper) && text.contains("\"timeout\"") }
    static var oldVersion: Bool { (text.contains(marker) || text.contains(helperName)) && !installed }
    private static var text: String { (try? String(contentsOf: settings, encoding: .utf8)) ?? "" }

    enum Outcome { case added, alreadyThere, failed(String) }

    static func install() -> Outcome {
        let fm = FileManager.default
        var root: [String: Any] = [:]
        if fm.fileExists(atPath: settings.path) {
            guard let data = try? Data(contentsOf: settings),
                  let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return .failed(T.s("~/.claude/settings.json isn't valid JSON, so nothing was changed.", "~/.claude/settings.json no es un JSON válido; no se ha cambiado nada."))
            }
            root = parsed
            if installed { return .alreadyThere }
            // copia antes de tocar nada
            let backup = settings.deletingLastPathComponent().appendingPathComponent("settings.json.agentdeck-backup")
            try? fm.removeItem(at: backup)
            do { try fm.copyItem(at: settings, to: backup) } catch { return .failed(T.s("Couldn't make a backup, so nothing was changed.", "No se ha podido guardar una copia; no se ha cambiado nada.")) }
        } else {
            try? fm.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for (event, kind) in [("Stop", "done"), ("Notification", "ask")] {
            // los ganchos antiguos de Agent Deck se cambian por los nuevos; los demás no se tocan
            var list = (hooks[event] as? [[String: Any]] ?? []).filter { entry in
                !((entry["hooks"] as? [[String: Any]]) ?? []).contains { let c = $0["command"] as? String ?? ""; return c.contains(marker) || c.contains(helperName) }
            }
            // Stop espera tu respuesta en la tarjeta hasta 10 min: Claude Code no debe cortarlo antes
            var hook: [String: Any] = ["type": "command", "command": command(kind: kind)]
            if event == "Stop" { hook["timeout"] = Int(waitSeconds) + 60 }
            list.append(["hooks": [hook]])
            hooks[event] = list
        }
        root["hooks"] = hooks
        do {
            let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: settings, options: .atomic)
            return .added
        } catch {
            return .failed(T.s("Couldn't write ~/.claude/settings.json.", "No se ha podido escribir ~/.claude/settings.json."))
        }
    }
}
