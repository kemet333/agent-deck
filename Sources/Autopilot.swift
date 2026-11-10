import Foundation

/// Piloto automático para Claude Code: cuando Claude termina y solo pregunta si sigue, el gancho Stop le contesta
/// el mensaje (por defecto «continúa») hasta N veces. Se frena solo ante una pregunta de verdad o un permiso.
/// Lo comparten la app (que lo enciende) y AgentBarClaudeHook (que decide en cada parada).
struct AutopilotState: Codable, Equatable {
    var remaining: Int
    var message: String
    var until: Double   // caduca (2 h por defecto, o el tiempo que elijas) aunque no se gaste
    /// Objetivo (0.15): «tests» = para en cuanto Claude dice que todos los tests pasan.
    var goal: String? = nil
    /// Vueltas dadas, para el resumen del final.
    var turns: Int? = nil
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

    /// El estado aunque se haya gastado o caducado: así el gancho sabe por qué paró y lo resume.
    static func loadAny() -> AutopilotState? {
        guard let d = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(AutopilotState.self, from: d)
    }

    /// nil lo apaga. Con 0 vueltas se guarda gastado (load() ya no lo da) hasta la siguiente parada, que lo resume.
    static func save(_ s: AutopilotState?) {
        guard let s else { try? FileManager.default.removeItem(at: file); return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(s) { try? d.write(to: file, options: .atomic) }
    }

    static func start(_ count: Int, message: String, goal: String? = nil, hours: Double = 2) {
        save(AutopilotState(remaining: count, message: message, until: Date().timeIntervalSince1970 + hours * 3600, goal: goal, turns: 0))
    }

    /// ¿Ha llegado al objetivo? «tests»: Claude dice que pasan todos y no que alguno falle.
    static func goalReached(_ goal: String?, last: String) -> Bool {
        guard goal == "tests" else { return false }
        var t = " " + String(last.lowercased().suffix(1200)) + " "
        for ok in ["0 failed", "0 failures", "0 errors", "0 fallos", "0 fallidos", "no failures", "sin fallos", "ningún fallo", "ningun fallo", "no errors", "sin errores"] {
            t = t.replacingOccurrences(of: ok, with: " ")
        }
        let bad = ["fail", "falla", "fallan", "fallo", "rojo", "not all", "no todos", "broken", "rotos", "still", "todavía", "todavia", "except", "excepto", "menos uno", "but one"]
        if bad.contains(where: { t.contains($0) }) { return false }
        let good = ["all tests pass", "all the tests pass", "tests pass", "tests are passing", "tests passed", "all green", "tests green", "suite passes",
                    "todos los tests pasan", "los tests pasan", "pasan todos los tests", "pasan todos", "tests en verde", "todo en verde", "pruebas pasan",
                    "pasan todas las pruebas", "las pruebas pasan", "_ok", " passing", "✅"]
        return good.contains { t.contains($0) }
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


/// La cola de cada agente (0.15): lo que le dirás cuando termine. «Luego dile al de Kemet que pase los tests» lo deja aquí;
/// en la siguiente parada de esa carpeta, el gancho le manda el primero (salvo que Claude pregunte algo de verdad).
/// Un archivo por carpeta en Application Support/Agent Deck/queue/<clave>.json; la clave es el nombre sin tildes ni signos.
enum AgentQueue {
    struct Queue: Codable, Equatable { var key: String; var name: String; var items: [String] }
    static var folder: URL { Autopilot.folder.appendingPathComponent("queue") }
    static func key(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased().filter { $0.isLetter || $0.isNumber }
    }
    static func file(_ key: String) -> URL { folder.appendingPathComponent(key + ".json") }
    static func load(_ key: String) -> Queue? { (try? Data(contentsOf: file(key))).flatMap { try? JSONDecoder().decode(Queue.self, from: $0) } }
    static func save(_ q: Queue) {
        guard !q.key.isEmpty else { return }
        if q.items.isEmpty { try? FileManager.default.removeItem(at: file(q.key)); return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var q = q; q.items = Array(q.items.prefix(20))
        if let d = try? JSONEncoder().encode(q) { try? d.write(to: file(q.key), options: .atomic) }
    }
    /// Añade al final de la cola de esa carpeta; devuelve cuántos hay.
    @discardableResult static func add(_ place: String, _ text: String) -> Int {
        let k = key(place)
        var q = load(k) ?? Queue(key: k, name: place, items: [])
        q.items.append(String(text.prefix(4000))); save(q)
        return min(q.items.count, 20)
    }
    static func all() -> [Queue] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }.map { $0.deletingPathExtension().lastPathComponent }.sorted()
            .compactMap(load).filter { !$0.items.isEmpty }
    }
    /// La cola de esa carpeta: «kemet» vale para «Kemet-Capital».
    static func match(place: String) -> Queue? {
        let p = key(place)
        guard !p.isEmpty else { return nil }
        return all().first { p == $0.key || ($0.key.count >= 3 && p.contains($0.key)) }
    }
    /// Saca el primero de la cola de esa carpeta: (mensaje, cuántos quedan).
    static func pop(place: String) -> (text: String, left: Int)? {
        guard var q = match(place: place), !q.items.isEmpty else { return nil }
        let first = q.items.removeFirst(); save(q)
        return (first, q.items.count)
    }
}
