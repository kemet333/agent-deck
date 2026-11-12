import Foundation

/// Mac despierto mientras trabajan tus agentes (0.20, idea de Diego del 12/11 a partir de Insomnia): si Claude Code,
/// Codex u otro agente de terminal está trabajando, el Mac no se duerme por inactividad; cuando paran todos, a los
/// 5 minutos vuelve a poder dormirse. «Trabajando» = el agente y lo que ha lanzado (tests, compilaciones…) gastan CPU:
/// esperando tu mensaje no gastan nada. Nunca con poca batería ni con el Mac muy caliente. Con la tapa cerrada el
/// Mac se duerme igual (eso necesitaría la contraseña de administrador; no se toca).
enum AgentAwake {
    struct Proc: Equatable { let pid: Int32; let ppid: Int32; let cpu: Double; let name: String }

    /// Los agentes que se reconocen por el nombre de su programa (el de la app de Claude es «Claude» y no cuenta).
    static let agents: [String: String] = [
        "claude": "Claude Code", "codex": "Codex", "gemini": "Gemini", "aider": "Aider", "opencode": "OpenCode",
        "goose": "Goose", "amp": "Amp", "cursor-agent": "Cursor", "qwen": "Qwen", "crush": "Crush", "droid": "Droid",
    ]

    /// `ps -axo pid=,ppid=,time=,comm=`: «  123   1   1:02.50 /ruta/al/programa con espacios».
    static func parse(_ ps: String) -> [Proc] {
        ps.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let ppid = Int32(parts[1]), let cpu = seconds(String(parts[2])) else { return nil }
            let path = String(parts[3]).trimmingCharacters(in: .whitespaces)
            return Proc(pid: pid, ppid: ppid, cpu: cpu, name: (path as NSString).lastPathComponent)
        }
    }
    /// «1:02.50» → 62,5 · «1-02:03:04» (días) también.
    static func seconds(_ s: String) -> Double? {
        var days = 0.0, rest = Substring(s)
        if let d = s.firstIndex(of: "-") { days = Double(s[..<d]) ?? 0; rest = s[s.index(after: d)...] }
        var total = 0.0
        for part in rest.split(separator: ":") { guard let v = Double(part) else { return nil }; total = total * 60 + v }
        return days * 86_400 + total
    }

    struct Tree: Equatable { var name: String; var cpu: Double; var pids: Set<Int32> = [] }
    /// Cada agente (el de más arriba, si uno lanza otro) con la CPU suya y la de todo lo que cuelga de él.
    /// `nodeAgents`: procesos node que son un agente (Gemini corre en node), por pid.
    static func agentTrees(_ procs: [Proc], nodeAgents: [Int32: String] = [:]) -> [Int32: Tree] {
        var byPid: [Int32: Proc] = [:], children: [Int32: [Int32]] = [:]
        for p in procs { byPid[p.pid] = p; children[p.ppid, default: []].append(p.pid) }
        func agentName(_ p: Proc) -> String? { agents[p.name] ?? nodeAgents[p.pid] }
        func underAgent(_ p: Proc) -> Bool {
            var seen = Set<Int32>(), cur = byPid[p.ppid]
            while let c = cur, seen.insert(c.pid).inserted { if agentName(c) != nil { return true }; cur = byPid[c.ppid] }
            return false
        }
        var out: [Int32: Tree] = [:]
        for p in procs {
            guard let name = agentName(p), !underAgent(p) else { continue }
            var total = 0.0, stack = [p.pid], seen = Set<Int32>()
            while let pid = stack.popLast(), seen.insert(pid).inserted {
                total += byPid[pid]?.cpu ?? 0
                stack += children[pid] ?? []
            }
            seen.remove(p.pid)
            out[p.pid] = Tree(name: name, cpu: total, pids: seen)
        }
        return out
    }

    /// Los que han trabajado entre dos muestras: han gastado al menos `threshold` segundos de CPU o han lanzado algo
    /// nuevo (un comando, un test, una compilación). Hace falta lo segundo porque macOS no le suma al agente la CPU de lo
    /// que lanza cuando termina: un test de 3 s entre dos muestras no se vería. Esperando tu mensaje, ni gastan ni lanzan.
    /// Un agente que aparece entre dos muestras empieza a contar en la siguiente.
    static func working(before: [Int32: Tree], now: [Int32: Tree], threshold: Double = 0.15) -> [String] {
        now.compactMap { pid, a in
            guard let b = before[pid], b.name == a.name else { return nil }
            return a.cpu - b.cpu >= threshold || !a.pids.isSubset(of: b.pids) ? a.name : nil
        }.sorted()
    }

    struct Power: Equatable { var onBattery: Bool; var level: Int; var hot: Bool }
    enum Decision: Equatable { case awake([String]), idle, blocked(String) }
    /// Mantener despierto si alguien ha trabajado en los últimos `grace` segundos, salvo batería baja o calor.
    static func decide(enabled: Bool, lastWork: Date?, names: [String], now: Date, power: Power, batteryFloor: Int = 30, grace: TimeInterval = 300) -> Decision {
        guard enabled, let last = lastWork, now.timeIntervalSince(last) <= grace else { return .idle }
        if power.hot { return .blocked(T.s("the Mac is very hot", "el Mac está muy caliente")) }
        if power.onBattery && power.level < batteryFloor { return .blocked(T.s("battery below \(batteryFloor) %", "batería por debajo del \(batteryFloor) %")) }
        return .awake(names)
    }

    /// «Claude Code y Codex» / «Claude Code, Codex y Gemini».
    static func list(_ names: [String]) -> String {
        let u = names.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        guard u.count > 1 else { return u.first ?? "" }
        return u.dropLast().joined(separator: ", ") + T.s(" and ", " y ") + u.last!
    }
}
