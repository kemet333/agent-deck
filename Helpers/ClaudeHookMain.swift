import Foundation

/// El gancho de Claude Code de Agent Bar (Stop, Notification y PermissionRequest). En cada parada:
/// 1. Si el piloto automático está en marcha y Claude solo pregunta si sigue, le contesta el mensaje
///    ({"decision":"block","reason":…}) y gasta una vuelta.
/// 2. Si no, o si hay que frenar, enciende el aviso en Agent Bar con lo que dijo Claude.
/// En un permiso (`permission`, 0.15): tarjeta en la barra; si contestas allí, devuelve «allow» o «deny» con tu motivo.
/// Sin respuesta en 60 s no dice nada y Claude Code enseña su diálogo de siempre. Nunca aprueba nada por su cuenta.
/// Si algo falla, no bloquea (sale sin decir nada).
@main
enum ClaudeHookMain {
    static func main() {
        var kind = CommandLine.arguments.dropFirst().first ?? "done"
        let input = (try? FileHandle.standardInput.read(upToCount: 1_048_576)) ?? Data()
        let j = ((try? JSONSerialization.jsonObject(with: input)) as? [String: Any]) ?? [:]
        let cwd = j["cwd"] as? String ?? FileManager.default.currentDirectoryPath
        let place = enc(URL(fileURLWithPath: cwd).lastPathComponent)
        let host = enc(ProcessInfo.processInfo.environment["__CFBundleIdentifier"] ?? "")
        // ganchos de la franja de agentes (aparcada el 10/11): si alguien los tuviera puestos, no hacen nada
        if kind == "status" { return }
        let session = (j["session_id"] as? String ?? "").filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(100)
        if kind == "permission" { permission(input: input, place: place, host: host, session: String(session)); return }
        // el aviso «Claude necesita tu permiso» de un permiso que ya está en la barra: no se repite ni para el piloto
        if kind == "ask", isPermissionNotice(j), !session.isEmpty, permissionPending(String(session)) { return }

        if kind == "done", let s = Autopilot.load() {
            let last = (j["last_assistant_message"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? Autopilot.lastAssistantText(transcript: j["transcript_path"] as? String ?? "")
            if !Autopilot.shouldBrake(last) {
                var next = s; next.remaining -= 1
                Autopilot.save(next)
                open("agentdeck://autopilot?left=\(next.remaining)&place=\(place)")
                let out = (try? JSONSerialization.data(withJSONObject: ["decision": "block", "reason": s.message])) ?? Data()
                FileHandle.standardOutput.write(out + Data([10]))
                return
            }
            // freno: una pregunta de verdad. El piloto se apaga y te avisa.
            Autopilot.save(nil)
            kind = "ask"
        } else if kind == "ask", Autopilot.load() != nil {
            Autopilot.save(nil) // un permiso o una pregunta de Claude Code: el piloto se para
        }

        // avisos apagados desde el menú: Claude Code para como siempre, sin aviso ni espera
        if FileManager.default.fileExists(atPath: Autopilot.folder.appendingPathComponent("alerts-off").path) { return }

        // el aviso: lo que mandó Claude Code se deja en hooks/ para que la app lea su respuesta
        let dir = Autopilot.folder.appendingPathComponent("hooks")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "\(ProcessInfo.processInfo.processIdentifier)-\(Int.random(in: 1000...999_999)).json"
        try? input.write(to: dir.appendingPathComponent(name))
        // una parada (Stop) puede seguir: el gancho espera lo que contestes en la tarjeta y se lo pasa a ESTA conversación
        let isStop = (j["hook_event_name"] as? String ?? "Stop") == "Stop"
        open("agentdeck://alert?app=Claude%20Code&kind=\(kind)&place=\(place)&file=\(name)&host=\(host)&wait=\(isStop ? "1" : "0")")
        guard isStop else { return }
        let wait = Double(ProcessInfo.processInfo.environment["AGENT_BAR_WAIT"] ?? "") ?? 600
        let decision = dir.appendingPathComponent(name + ".decision")
        // mientras espera, una marca: así quien conteste desde otro sitio (WhatsApp) sabe si aún llega a tiempo
        let waiting = dir.appendingPathComponent(name + ".waiting")
        try? Data().write(to: waiting)
        defer { try? FileManager.default.removeItem(at: waiting) }
        let end = Date().addingTimeInterval(wait)
        while Date() < end {
            if let d = try? Data(contentsOf: decision) {
                try? FileManager.default.removeItem(at: decision)
                let o = ((try? JSONSerialization.jsonObject(with: d)) as? [String: String]) ?? [:]
                if o["action"] == "continue", let t = o["text"]?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                    let out = (try? JSONSerialization.data(withJSONObject: ["decision": "block", "reason": t])) ?? Data()
                    FileHandle.standardOutput.write(out + Data([10]))
                }
                return
            }
            usleep(250_000)
        }
        open("agentdeck://released?file=\(name)") // ya no espera: contestar irá por la ventana
    }

    static var hooksDir: URL { Autopilot.folder.appendingPathComponent("hooks") }
    static func marker(_ session: String) -> URL { hooksDir.appendingPathComponent("perm-\(session).pending") }

    /// Claude Code pide permiso: tarjeta en Agent Bar con Permitir / No / Ver cambios. Mientras espera, una marca para que
    /// su aviso de Notification no salga repetido.
    static func permission(input: Data, place: String, host: String, session: String) {
        let off = ["alerts-off", "permissions-off"].contains { FileManager.default.fileExists(atPath: Autopilot.folder.appendingPathComponent($0).path) }
        if off { return }
        try? FileManager.default.createDirectory(at: hooksDir, withIntermediateDirectories: true)
        let name = "\(ProcessInfo.processInfo.processIdentifier)-\(Int.random(in: 1000...999_999)).json"
        try? input.write(to: hooksDir.appendingPathComponent(name))
        if !session.isEmpty { try? Data().write(to: marker(session)) }
        defer { if !session.isEmpty { try? FileManager.default.removeItem(at: marker(session)) } }
        open("agentdeck://alert?app=Claude%20Code&kind=permission&place=\(place)&file=\(name)&host=\(host)&wait=1")
        let wait = Double(ProcessInfo.processInfo.environment["AGENT_BAR_PERMISSION_WAIT"] ?? "") ?? 60
        let decision = hooksDir.appendingPathComponent(name + ".decision")
        let end = Date().addingTimeInterval(wait)
        while Date() < end {
            if let d = try? Data(contentsOf: decision) {
                try? FileManager.default.removeItem(at: decision)
                let o = ((try? JSONSerialization.jsonObject(with: d)) as? [String: String]) ?? [:]
                var out: [String: Any]?
                if o["action"] == "allow" { out = ["behavior": "allow"] }
                if o["action"] == "deny" {
                    let why = o["text"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    out = ["behavior": "deny", "message": why.isEmpty ? "The user said no from Agent Bar." : why]
                }
                if let out, let data = try? JSONSerialization.data(withJSONObject: ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": out]]) {
                    FileHandle.standardOutput.write(data + Data([10]))
                } else if Autopilot.load() != nil { Autopilot.save(nil) } // «En Claude»: lo decides allí; el piloto se para
                return
            }
            usleep(150_000)
        }
        Autopilot.save(nil) // sin respuesta: Claude Code enseña su diálogo y el piloto se para
        open("agentdeck://released?file=\(name)")
    }
    static func isPermissionNotice(_ j: [String: Any]) -> Bool {
        if (j["notification_type"] as? String) == "permission_prompt" { return true }
        return (j["message"] as? String ?? "").lowercased().contains("permission")
    }
    /// ¿Ese permiso está ya en la barra? El aviso puede llegar justo antes que la petición: se espera un poco.
    static func permissionPending(_ session: String) -> Bool {
        let settings = (try? String(contentsOf: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json"), encoding: .utf8)) ?? ""
        guard settings.contains("PermissionRequest"), settings.contains("AgentBarClaudeHook") else { return false }
        if FileManager.default.fileExists(atPath: Autopilot.folder.appendingPathComponent("permissions-off").path) { return false }
        for _ in 0..<10 {
            if FileManager.default.fileExists(atPath: marker(session).path) { return true }
            usleep(150_000)
        }
        return false
    }

    static func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._"))) ?? "" }

    static func open(_ url: String) {
        if ProcessInfo.processInfo.environment["AGENT_DECK_NO_OPEN"] == "1" { return } // pruebas
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-g", url]
        try? p.run()
        p.waitUntilExit()
    }
}
