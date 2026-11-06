import Foundation

/// Piloto automático para Claude Code: cuando Claude termina y solo pregunta si sigue, el gancho Stop le contesta
/// el mensaje (por defecto «continúa») hasta N veces. Se frena solo ante una pregunta de verdad o un permiso.
/// Lo comparten la app (que lo enciende) y AgentBarClaudeHook (que decide en cada parada).
struct AutopilotState: Codable, Equatable {
    var remaining: Int
    var message: String
    var until: Double   // caduca a las 2 h aunque no se gaste
}

enum Autopilot {
    static var folder: URL {
        if let t = ProcessInfo.processInfo.environment["AGENT_DECK_FOLDER"], !t.isEmpty { return URL(fileURLWithPath: t, isDirectory: true) }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Agent Deck", isDirectory: true)
    }
    static var file: URL { folder.appendingPathComponent("autopilot.json") }

    /// El piloto en marcha, o nil si está apagado, gastado o caducado.
    static func load(now: Double = Date().timeIntervalSince1970) -> AutopilotState? {
        guard let d = try? Data(contentsOf: file), let s = try? JSONDecoder().decode(AutopilotState.self, from: d),
              s.remaining > 0, s.until > now else { return nil }
        return s
    }

    static func save(_ s: AutopilotState?) {
        guard let s, s.remaining > 0 else { try? FileManager.default.removeItem(at: file); return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(s) { try? d.write(to: file, options: .atomic) }
    }

    static func start(_ count: Int, message: String) {
        save(AutopilotState(remaining: count, message: message, until: Date().timeIntervalSince1970 + 2 * 3600))
    }

    /// ¿Hay que parar? Sí ante una pregunta de verdad (elegir, confirmar, una clave…) o una pregunta que no sea
    /// «¿sigo?». No, si no pregunta nada o solo pide permiso para continuar.
    static func shouldBrake(_ last: String) -> Bool {
        let tail = String(last.lowercased().suffix(500))
        guard tail.contains("?") else { return false }
        let real = ["which ", "which?", "choose", "option", "prefer", "confirm", "what do you", "how would you", "would you like me to use",
                    "password", "credential", "api key", "approve", "¿cuál", "cuál prefieres", "elige", "prefieres", "confirma",
                    "¿qué prefieres", "¿cómo quieres", "contraseña", "clave", "apruebas", "¿qué opción", "¿a o b", "a or b"]
        if real.contains(where: { tail.contains($0) }) { return true }
        // la frase de la pregunta: si ofrece una elección («¿A o B?», «X or Y?»), para
        if let q = tail.lastIndex(of: "?") {
            let head = tail[..<q]
            let start = head.lastIndex(where: { ".!\n¿".contains($0) }).map { head.index(after: $0) } ?? head.startIndex
            let question = " " + head[start...] + " "
            if question.contains(" or ") || question.contains(" o ") { return true }
        }
        let onlyContinue = ["continue", "keep going", "go on", "proceed", "next step", "shall i", "should i", "want me to", "move on",
                            "¿sigo", "sigo con", "¿continúo", "¿continuo", "continúo con", "¿quieres que siga", "¿quieres que continúe",
                            "¿avanzo", "¿paso a", "¿lo hago", "¿me pongo"]
        if onlyContinue.contains(where: { tail.contains($0) }) { return false }
        return true
    }

    /// Lo último que dijo Claude en su transcripción (solo dentro de ~/.claude y solo el final del archivo).
    static func lastAssistantText(transcript path: String) -> String {
        guard path.hasSuffix(".jsonl"),
              path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude").path),
              let h = FileHandle(forReadingAtPath: path) else { return "" }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > 2_000_000 ? size - 2_000_000 : 0)
        guard let tail = try? h.readToEnd(), let text = String(data: tail, encoding: .utf8) else { return "" }
        for line in text.split(separator: "\n").reversed() {
            guard let o = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any], o["type"] as? String == "assistant",
                  let msg = o["message"] as? [String: Any], let parts = msg["content"] as? [[String: Any]] else { continue }
            let t = parts.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return ""
    }
}
