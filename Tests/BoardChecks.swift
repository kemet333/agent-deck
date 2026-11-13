import Foundation

// Agents board checks: real PTYs running small shell programs in place of the agent CLIs (never Claude Code or Codex,
// no plan spent), in a temporary folder. The same behaviour the Diego OS board checks (tablero-checks.mjs) prove.
@main
struct BoardChecks {
    static var passed = 0
    static func check(_ ok: Bool, _ what: String, file: StaticString = #file, line: UInt = #line) {
        if ok { passed += 1 } else { print("FAIL \(what) (línea \(line))"); exit(1) }
    }
    static func until(_ what: String, _ secs: Double = 8, _ cond: () -> Bool) {
        let end = Date().addingTimeInterval(secs)
        while Date() < end { if cond() { return }; RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        print("FAIL no se cumple a tiempo: \(what)"); exit(1)
    }
    static func wait(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

    static func main() {
        // pure parts
        check(BoardCore.sinAnsi("\u{1b}[32m✓\u{1b}[0m hola\r\nmundo\rx") == "✓ hola\nmundo\nx", "sin ANSI")
        let o = BoardCore.ordenes("@eco: primera\n@equipo, segunda\nsuelta\n@: nada")
        check(o.ordenes == [.init(destino: "eco", texto: "primera"), .init(destino: "equipo", texto: "segunda")] && o.sueltas == ["suelta", "@: nada"], "órdenes")
        check(BoardCore.nombreLibre("eco", usados: ["eco", "eco-2"]) == "eco-3", "nombres únicos")
        check(BoardCore.pidePermiso("Do you want to make this edit? (y/n)") && !BoardCore.pidePermiso("todo bien"), "pregunta")
        check(BoardCore.pidePermiso("Hooks need review\nPress enter to confirm or esc"), "aviso de Codex")

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("board-checks-\(UUID().uuidString)")
        let repo = dir.appendingPathComponent("repo"); try! FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let activity = dir.appendingPathComponent("activity.jsonl")
        var emitted: [(String, String)] = []
        let e = BoardEngine(folder: dir, activityFile: { activity })
        e.emit = { emitted.append(($0, $1)) }

        // a console in a real terminal of its size, typing and pasting
        let eco = try! e.lanzar([["nombre": "eco", "cli": "custom", "comando": "bash --norc -c 'stty size; while IFS= read -r l; do echo \"recibido:$l\"; done'", "equipo": "pruebas", "cwd": repo.path, "w": 672.0, "h": 478.0]])[0]
        until("tamaño") { e.ultimo(eco).contains("26 80") }
        _ = try! e.escribir(eco, "hola", intro: true)
        until("texto con Intro") { e.ultimo(eco).contains("recibido:hola") }
        try! e.teclear(eco, Data("a mano\r".utf8))
        until("teclas") { e.ultimo(eco).contains("recibido:a mano") }
        _ = try! e.escribir(eco, "sin intro", intro: false); wait(0.6)
        check(!e.ultimo(eco).contains("recibido:sin intro"), "el dictado solo escribe")
        _ = try! e.escribir(eco, "", intro: true)
        until("Intro después") { e.ultimo(eco).contains("recibido:sin intro") }
        check(emitted.contains { $0.0 == "o" && $0.1.hasPrefix(eco + " ") }, "la salida llega a la página")

        // states: working, waiting for you, at rest; a loop never answers a permission
        let pide = try! e.lanzar([["nombre": "pide", "cli": "custom", "comando": "bash --norc -c 'for i in 1 2 3 4 5 6; do echo trabajo $i; sleep 0.3; done; echo \"Do you want to make this edit? (y/n)\"; read r; echo vale:$r; sleep 30'", "cwd": repo.path]])[0]
        until("trabajando") { e.estado(pide) == .trabajando }
        until("te necesita") { e.estado(pide) == .te_necesita }
        let bp = try! e.nuevoBucle(["consola": pide, "mensaje": "y", "disparo": "cada", "segundos": 10.0, "max": 3])
        e.vueltaBucles(ahora: Date().timeIntervalSince1970 + 60)
        wait(0.5)
        check(!e.ultimo(pide).contains("vale:"), "un bucle no contesta a un permiso")
        _ = e.pararBucle(bp, quitar: true)
        try! e.teclear(pide, Data("y\r".utf8))
        until("contestada") { e.ultimo(pide).contains("vale:y") }
        until("ya no te necesita") { e.estado(pide) == .en_reposo }
        until("eco en reposo") { e.estado(eco) == .en_reposo }

        // Claude Code alerts Agent Bar records mark the consoles of that folder
        let line = "{\"t\":1,\"kind\":\"permission\",\"place\":\"repo\",\"text\":\"\"}\n"
        try! line.write(to: activity, atomically: true, encoding: .utf8)
        e.leerAvisos()
        check(e.estado(eco) == .en_reposo, "un aviso no marca una consola que no es de un agente")

        // orders by name and team; unknown names come back
        let r = e.orden("@eco: primera orden\n@pruebas, segunda orden\n@nadie: se pierde?\nsin destino")
        check((r["entregadas"] as? [String]) == ["eco", "eco"] && (r["sinDestino"] as? [String])?.count == 2, "órdenes")
        until("orden por equipo") { e.ultimo(eco).contains("recibido:segunda orden") && e.ultimo(eco).contains("recibido:primera orden") }

        // handoff
        let rev = try! e.lanzar([["nombre": "revisor", "cli": "custom", "comando": "bash --norc -c 'cat'", "cwd": repo.path]])[0]
        wait(0.5)
        check((try? e.traspaso(de: eco, a: rev, instruccion: "Revisa esto", intro: false)) == true, "traspaso")
        until("traspaso llega") { e.ultimo(rev).contains("--- Lo último de eco ---") && e.ultimo(rev).contains("recibido:hola") }

        // an orchestrator's lines become proposals, never sent on their own
        let orq = try! e.lanzar([["nombre": "orquestador", "cli": "custom", "comando": "bash --norc -c 'echo Plan:; echo \"@eco: escribe las pruebas\"; echo \"@nadie: no existe\"; sleep 30'", "cwd": repo.path]])[0]
        until("propuesta") { ((e.vista()["propuestas"] as? [[String: String]]) ?? []).count == 1 }
        check(((e.vista()["propuestas"] as? [[String: String]]) ?? []).first?["a"] == "eco", "propuesta a eco")
        wait(0.4); check(!e.ultimo(eco).contains("recibido:escribe las pruebas"), "una propuesta no se envía sola")
        try! e.cerrar(orq, confirmar: true)

        // a loop types when idle and retires itself when its goal command succeeds
        until("eco quieto") { e.estado(eco) == .en_reposo }
        let b = try! e.nuevoBucle(["consola": eco, "mensaje": "sigue", "disparo": "inactividad", "segundos": 10.0, "objetivo": "test -f listo", "max": 5])
        e.vueltaBucles(ahora: Date().timeIntervalSince1970 + 20)
        until("el bucle comprueba y escribe") { e.ultimo(eco).contains("recibido:sigue") }
        FileManager.default.createFile(atPath: repo.appendingPathComponent("listo").path, contents: Data())
        until("eco quieto 2") { e.estado(eco) == .en_reposo }
        e.vueltaBucles(ahora: Date().timeIntervalSince1970 + 40)
        until("objetivo cumplido") { e.state.bucles.first { $0.id == b }?.activo == false }
        check(e.state.bucles.first { $0.id == b }?.motivo.hasPrefix("Objetivo cumplido") == true, "motivo")

        // composer limits, placement without overlap
        check((try? e.lanzar(Array(repeating: ["cli": "shell"], count: 13))) == nil, "como mucho 12")
        check((try? e.lanzar([["cli": "custom"]])) == nil, "falta el comando")
        let anchas = try! e.lanzar([["nombre": "a", "cli": "custom", "comando": "sleep 30", "w": 780.0], ["nombre": "b", "cli": "custom", "comando": "sleep 30", "w": 700.0]])
        let ca = e.state.consolas.first { $0.id == anchas[0] }!, cb = e.state.consolas.first { $0.id == anchas[1] }!
        check(cb.x >= ca.x + ca.w, "sin solaparse")

        // a live console only closes when confirmed; the layout survives a restart, consoles come back asleep
        check((try? e.cerrar(rev, confirmar: false)) == nil, "pide confirmar")
        try! e.cerrar(rev, confirmar: true)
        try! e.mover(eco, ["x": 123.0, "y": 456.0, "w": 900.0])
        e.stopAll(); wait(0.5)
        let e2 = BoardEngine(folder: dir)
        check(e2.estado(eco) == .dormida && e2.state.consolas.first { $0.id == eco }?.w == 900, "vuelve dormida con su sitio")
        check((try? e2.reanudar(eco)) == true, "reanudar")
        until("reanudada") { e2.estado(eco) != .dormida }
        e2.stopAll(); wait(0.5)
        try? FileManager.default.removeItem(at: dir)
        print("board: \(passed) comprobaciones correctas")
        exit(0)
    }
}
