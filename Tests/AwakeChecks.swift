import Foundation

/// Mac despierto (0.20): qué es un agente, qué cuenta como trabajar y cuándo se deja dormir al Mac.
@main
struct AwakeChecks {
    static var failures = 0
    static func check(_ ok: Bool, _ what: String) { if !ok { failures += 1; print("FALLA: \(what)") } }

    static func main() {
        // ps real: rutas con espacios, la app de Claude («Claude») no es un agente, el CLI («claude») sí
        let ps = """
          80003     1   2:06.82 /Applications/Claude.app/Contents/MacOS/Claude
          81775 81774   0:08.46 /Users/diego/Library/Application Support/Claude/claude-code/2.1.321/x/claude.app/Contents/MacOS/claude
          81900 81775   0:20.00 /usr/bin/swift-frontend
          35145 34656   4:41.44 /Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex
          37631 35145   0:04.31 /Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex-code-mode-host
          36826 35967   0:32.07 /Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex
          36900 36826   0:01.00 /Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex
           5000     1   1-02:03:04 /bin/zsh
          basura
        """
        let procs = AwakeChecksHelpers.procs(ps)
        check(procs.count == 8, "8 procesos leídos: \(procs.count)")
        check(procs.first { $0.pid == 81775 }?.name == "claude", "nombre del CLI con espacios en la ruta")
        check(AgentAwake.seconds("1-02:03:04") == 93_784, "días en la CPU")
        check(AgentAwake.seconds("4:41.44").map { abs($0 - 281.44) < 0.001 } == true, "minutos y segundos")

        let t = AgentAwake.agentTrees(procs)
        check(t[80003] == nil, "la app de Claude no es un agente")
        check(t[81775]?.name == "Claude Code" && abs((t[81775]?.cpu ?? 0) - 28.46) < 0.001 && t[81775]?.pids == [81900], "Claude Code suma lo que lanza: \(t[81775]?.cpu ?? 0)")
        check(t[36900] == nil && t[36826] != nil, "un codex dentro de otro cuenta una vez")
        check(t[35145]?.name == "Codex" && t.count == 3, "tres agentes: \(t.count)")
        // Gemini corre en node
        let node = AgentAwake.agentTrees([AgentAwake.Proc(pid: 9, ppid: 1, cpu: 3, name: "node")], nodeAgents: [9: "Gemini"])
        check(node[9]?.name == "Gemini", "Gemini en node")

        // trabajar = gastar CPU entre dos muestras; esperando tu mensaje, nada
        var later = t
        later[81775]!.cpu += 3.0      // compilando
        later[35145]!.cpu += 0.05     // en reposo
        check(AgentAwake.working(before: t, now: later) == ["Claude Code"], "solo el que gasta: \(AgentAwake.working(before: t, now: later))")
        check(AgentAwake.working(before: [:], now: later).isEmpty, "la primera muestra no cuenta")
        var spawned = later; spawned[35145]!.pids.insert(99999)
        check(AgentAwake.working(before: later, now: spawned) == ["Codex"], "lanzar un comando cuenta aunque apenas gaste")
        var ended = later; ended[81775]!.pids = []
        check(AgentAwake.working(before: later, now: ended).isEmpty, "que termine un proceso no cuenta")
        var fresh = later; fresh[777] = AgentAwake.Tree(name: "Codex", cpu: 500)
        check(!AgentAwake.working(before: later, now: fresh).contains("Codex"), "uno nuevo empieza a contar en la siguiente")
        var reused = later; reused[35145] = AgentAwake.Tree(name: "Claude Code", cpu: 900)
        check(!AgentAwake.working(before: later, now: reused).contains("Claude Code") || reused[81775]!.cpu - later[81775]!.cpu >= 0.4, "pid reutilizado por otro programa no cuenta")

        // decidir
        let now = Date(), plug = AgentAwake.Power(onBattery: false, level: 100, hot: false)
        check(AgentAwake.decide(enabled: true, lastWork: now.addingTimeInterval(-60), names: ["Codex"], now: now, power: plug) == .awake(["Codex"]), "trabajando hace 1 min: despierto")
        check(AgentAwake.decide(enabled: true, lastWork: now.addingTimeInterval(-301), names: ["Codex"], now: now, power: plug) == .idle, "parados hace más de 5 min: a dormir")
        check(AgentAwake.decide(enabled: false, lastWork: now, names: ["Codex"], now: now, power: plug) == .idle, "apagado: nada")
        check(AgentAwake.decide(enabled: true, lastWork: now, names: ["Codex"], now: now, power: .init(onBattery: true, level: 25, hot: false)) != .awake(["Codex"]), "batería baja: no")
        check(AgentAwake.decide(enabled: true, lastWork: now, names: ["Codex"], now: now, power: .init(onBattery: true, level: 80, hot: false)) == .awake(["Codex"]), "batería con carga: sí")
        check(AgentAwake.decide(enabled: true, lastWork: now, names: ["Codex"], now: now, power: .init(onBattery: false, level: 100, hot: true)) != .awake(["Codex"]), "muy caliente: no")
        check(AgentAwake.list(["Claude Code", "Codex", "Claude Code", "Gemini"]).hasPrefix("Claude Code, Codex"), "lista sin repetidos: \(AgentAwake.list(["Claude Code", "Codex", "Claude Code", "Gemini"]))")

        if failures > 0 { print("AWAKE_FAIL \(failures)"); exit(1) }
        print("AWAKE_OK")
    }
}

enum AwakeChecksHelpers {
    static func procs(_ s: String) -> [AgentAwake.Proc] { AgentAwake.parse(s) }
}
