import Foundation

/// El gancho de Claude Code de Agent Bar (Stop y Notification). En cada parada:
/// 1. Si el piloto automático está en marcha y Claude solo pregunta si sigue, le contesta el mensaje
///    ({"decision":"block","reason":…}) y gasta una vuelta.
/// 2. Si no, o si hay que frenar, enciende el aviso en Agent Bar con lo que dijo Claude.
/// Nunca aprueba permisos ni cambia nada de Claude Code. Si algo falla, no bloquea (sale sin decir nada).
@main
enum ClaudeHookMain {
    static func main() {
        var kind = CommandLine.arguments.dropFirst().first ?? "done"
        let input = (try? FileHandle.standardInput.read(upToCount: 1_048_576)) ?? Data()
        let j = ((try? JSONSerialization.jsonObject(with: input)) as? [String: Any]) ?? [:]
        let cwd = j["cwd"] as? String ?? FileManager.default.currentDirectoryPath
        let place = enc(URL(fileURLWithPath: cwd).lastPathComponent)
        let host = enc(ProcessInfo.processInfo.environment["__CFBundleIdentifier"] ?? "")

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

        // el aviso: lo que mandó Claude Code se deja en hooks/ para que la app lea su respuesta
        let dir = Autopilot.folder.appendingPathComponent("hooks")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "\(ProcessInfo.processInfo.processIdentifier)-\(Int.random(in: 1000...999_999)).json"
        try? input.write(to: dir.appendingPathComponent(name))
        open("agentdeck://alert?app=Claude%20Code&kind=\(kind)&place=\(place)&file=\(name)&host=\(host)")
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
