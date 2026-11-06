import AppKit

/// Avisos de Claude Code: dos ganchos en ~/.claude/settings.json que abren agentdeck://alert cuando Claude Code
/// termina (Stop) o espera tu permiso o tu respuesta (Notification). Solo se añaden si el usuario lo confirma en
/// la app; antes se guarda una copia del archivo y nunca se toca nada más de su configuración.
enum ClaudeHooks {
    static let settings = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    static let marker = "agentdeck://alert"

    /// El comando de cada gancho: el nombre de la carpeta del proyecto va en el aviso.
    static func command(kind: String) -> String {
        "d=$(basename \"$PWD\" | sed 's/ /%20/g'); open -g \"\(marker)?app=Claude%20Code&kind=\(kind)&place=$d\""
    }

    static var installed: Bool {
        guard let data = try? Data(contentsOf: settings), let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains(marker)
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
            var list = hooks[event] as? [[String: Any]] ?? []
            list.append(["hooks": [["type": "command", "command": command(kind: kind)]]])
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
