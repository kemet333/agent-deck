import Foundation

/// El gancho de Claude Code de Agent Bar. Además del estado de cada sesión (para la franja de agentes: `status`, y también
/// en cada parada), en Stop y Notification:
/// 1. Si el piloto automático está en marcha y Claude solo pregunta si sigue, le contesta el mensaje
///    ({"decision":"block","reason":…}) y gasta una vuelta.
/// 2. Si no, o si hay que frenar, enciende el aviso en Agent Bar con lo que dijo Claude.
/// Y en PermissionRequest (`permission`): enseña la petición en Agent Bar y, si contestas allí, devuelve «allow» o «deny».
/// Sin respuesta en 60 s, no dice nada y Claude Code enseña su diálogo de siempre. Nunca aprueba nada por su cuenta.
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
        let event = j["hook_event_name"] as? String ?? ""

        // el estado de esta sesión para la franja de agentes (rápido: se llama en cada herramienta)
        Sessions.record(j, kind: kind, event: event, cwd: cwd, host: ProcessInfo.processInfo.environment["__CFBundleIdentifier"] ?? "")
        if kind == "status" { return }

        if kind == "permission" { permission(input: input, place: place, host: host); return }

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

    /// Claude Code pide permiso: tarjeta en Agent Bar con Permitir / Denegar / En Claude.
    static func permission(input: Data, place: String, host: String) {
        if FileManager.default.fileExists(atPath: Autopilot.folder.appendingPathComponent("alerts-off").path) { return }
        let dir = Autopilot.folder.appendingPathComponent("hooks")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "\(ProcessInfo.processInfo.processIdentifier)-\(Int.random(in: 1000...999_999)).json"
        try? input.write(to: dir.appendingPathComponent(name))
        open("agentdeck://alert?app=Claude%20Code&kind=permission&place=\(place)&file=\(name)&host=\(host)&wait=1")
        let wait = Double(ProcessInfo.processInfo.environment["AGENT_BAR_PERMISSION_WAIT"] ?? "") ?? 60
        let decision = dir.appendingPathComponent(name + ".decision")
        let end = Date().addingTimeInterval(wait)
        while Date() < end {
            if let d = try? Data(contentsOf: decision) {
                try? FileManager.default.removeItem(at: decision)
                let o = ((try? JSONSerialization.jsonObject(with: d)) as? [String: String]) ?? [:]
                var out: [String: Any]?
                if o["action"] == "allow" { out = ["behavior": "allow"] }
                if o["action"] == "deny" { out = ["behavior": "deny", "message": o["text"] ?? "Denied from Agent Bar."] }
                if let out, let data = try? JSONSerialization.data(withJSONObject: ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": out]]) {
                    FileHandle.standardOutput.write(data + Data([10]))
                }
                return
            }
            usleep(200_000)
        }
        open("agentdeck://released?file=\(name)") // sin respuesta: Claude Code enseña su diálogo
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

/// El estado de cada sesión de Claude Code, uno por archivo en Application Support/Agent Deck/sessions/<sesión>.json.
/// La app lo lee para la franja de agentes. Solo metadatos (carpeta, estado, herramienta): nunca el contenido.
enum Sessions {
    static func record(_ j: [String: Any], kind: String, event: String, cwd: String, host: String) {
        guard let id = (j["session_id"] as? String)?.filter({ $0.isLetter || $0.isNumber || $0 == "-" }), !id.isEmpty, id.count < 100 else { return }
        let dir = Autopilot.folder.appendingPathComponent("sessions")
        let file = dir.appendingPathComponent(id + ".json")
        if event == "SessionEnd" { try? FileManager.default.removeItem(at: file); return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Date().timeIntervalSince1970
        var o = ((try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        let was = o["state"] as? String ?? ""
        var state = "working"
        switch (kind, event) {
        case ("done", _): state = "done"
        case ("ask", _), ("permission", _): state = "needs"
        case (_, "SessionStart"): state = "idle"
        default: state = "working"
        }
        if state == "working" && was != "working" { o["started"] = now }
        o["id"] = id; o["cwd"] = cwd; o["place"] = URL(fileURLWithPath: cwd).lastPathComponent
        o["state"] = state; o["updated"] = now; if !host.isEmpty { o["host"] = host }
        if let tool = j["tool_name"] as? String { o["tool"] = tool; o["detail"] = detail(tool, j["tool_input"] as? [String: Any] ?? [:]) }
        else if event == "UserPromptSubmit" || state != "working" { o["tool"] = ""; o["detail"] = "" }
        if kind == "permission" { o["tool"] = j["tool_name"] as? String ?? "" }
        guard let data = try? JSONSerialization.data(withJSONObject: o) else { return }
        try? data.write(to: file, options: .atomic)
    }
    /// Una pista corta de lo que hace la herramienta: el archivo, la orden o lo que busca (sin contenidos).
    static func detail(_ tool: String, _ input: [String: Any]) -> String {
        let raw: String
        if let p = input["file_path"] as? String { raw = URL(fileURLWithPath: p).lastPathComponent }
        else if let c = input["command"] as? String { raw = c.split(separator: "\n").first.map(String.init) ?? c }
        else if let p = input["pattern"] as? String { raw = p }
        else if let u = input["url"] as? String { raw = URL(string: u)?.host ?? u }
        else if let d = input["description"] as? String { raw = d }
        else { raw = "" }
        return String(raw.prefix(80))
    }
}
