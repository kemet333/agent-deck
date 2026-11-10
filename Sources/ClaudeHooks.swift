import AppKit

/// Avisos de Claude Code: tres ganchos (desde 0.15 también PermissionRequest) en ~/.claude/settings.json que abren agentdeck://alert cuando Claude Code
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
    /// Permisos desde la barra (0.15): el gancho PermissionRequest de esta copia.
    static var permissionsInstalled: Bool { installed && text.contains("PermissionRequest") }
    /// Los ganchos que pone Agent Bar: avisos (Stop, Notification) y permisos (PermissionRequest; espera tu respuesta 60 s).
    static let events: [(event: String, kind: String, matcher: Bool, timeout: Int?)] = [
        ("Stop", "done", false, Int(waitSeconds) + 60), ("Notification", "ask", false, nil), ("PermissionRequest", "permission", true, 90),
    ]
    /// Permisos apagados en Ajustes: el gancho sigue puesto, pero deja pasar el diálogo de Claude Code al momento.
    static var permissionsOffFile: URL { Autopilot.folder.appendingPathComponent("permissions-off") }
    static var permissionsPaused: Bool {
        get { FileManager.default.fileExists(atPath: permissionsOffFile.path) }
        set {
            if newValue { try? FileManager.default.createDirectory(at: Autopilot.folder, withIntermediateDirectories: true); try? Data().write(to: permissionsOffFile) }
            else { try? FileManager.default.removeItem(at: permissionsOffFile) }
        }
    }
    static var oldVersion: Bool { (text.contains(marker) || text.contains(helperName)) && !installed }
    private static var text: String { (try? String(contentsOf: settings, encoding: .utf8)) ?? "" }

    /// Apagados desde el menú: los ganchos siguen puestos, pero no avisan ni esperan (al momento, sin reiniciar Claude Code).
    static var offFile: URL { Autopilot.folder.appendingPathComponent("alerts-off") }
    static var paused: Bool {
        get { FileManager.default.fileExists(atPath: offFile.path) }
        set {
            if newValue { try? FileManager.default.createDirectory(at: Autopilot.folder, withIntermediateDirectories: true); try? Data().write(to: offFile) }
            else { try? FileManager.default.removeItem(at: offFile) }
        }
    }

    /// Quitar los ganchos de Agent Bar de ~/.claude/settings.json (con copia antes); el resto de tu configuración no se toca.
    static func uninstall() -> Outcome {
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: settings), var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .alreadyThere }
        guard text.contains(marker) || text.contains(helperName) else { return .alreadyThere }
        let backup = settings.deletingLastPathComponent().appendingPathComponent("settings.json.agentdeck-backup")
        try? fm.removeItem(at: backup)
        do { try fm.copyItem(at: settings, to: backup) } catch { return .failed(T.s("Couldn't make a backup, so nothing was changed.", "No se ha podido guardar una copia; no se ha cambiado nada.")) }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in events.map(\.event) {
            let list = (hooks[event] as? [[String: Any]] ?? []).filter { entry in
                !((entry["hooks"] as? [[String: Any]]) ?? []).contains { let c = $0["command"] as? String ?? ""; return c.contains(marker) || c.contains(helperName) }
            }
            if list.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = list }
        }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        do {
            try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: settings, options: .atomic)
            paused = false
            return .added
        } catch { return .failed(T.s("Couldn't write ~/.claude/settings.json.", "No se ha podido escribir ~/.claude/settings.json.")) }
    }

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
            if permissionsInstalled { return .alreadyThere }
            // copia antes de tocar nada
            let backup = settings.deletingLastPathComponent().appendingPathComponent("settings.json.agentdeck-backup")
            try? fm.removeItem(at: backup)
            do { try fm.copyItem(at: settings, to: backup) } catch { return .failed(T.s("Couldn't make a backup, so nothing was changed.", "No se ha podido guardar una copia; no se ha cambiado nada.")) }
        } else {
            try? fm.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for e in events {
            // los ganchos antiguos de Agent Deck se cambian por los nuevos; los demás no se tocan
            var list = (hooks[e.event] as? [[String: Any]] ?? []).filter { entry in
                !((entry["hooks"] as? [[String: Any]]) ?? []).contains { let c = $0["command"] as? String ?? ""; return c.contains(marker) || c.contains(helperName) }
            }
            // Stop espera tu respuesta en la tarjeta hasta 10 min: Claude Code no debe cortarlo antes
            var hook: [String: Any] = ["type": "command", "command": command(kind: e.kind)]
            if let t = e.timeout { hook["timeout"] = t }
            var entry: [String: Any] = ["hooks": [hook]]
            if e.matcher { entry["matcher"] = "*" }
            list.append(entry)
            hooks[e.event] = list
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
