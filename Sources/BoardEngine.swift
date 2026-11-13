import Darwin
import Foundation

/// The agents board's engine: the consoles (each a BoardPty), their state, the composer, orders, handoffs, the
/// orchestrator's proposals and the loops. The window's page talks to it with `handle(path, body)` (the same paths the
/// Diego OS board served over HTTP) and receives the live output through `emit`. Layout, teams and loops are saved in
/// Application Support/Agent Deck/board.json (never the output). Claude Code alerts Agent Bar already records
/// (activity/<date>.jsonl: «ask», «permission», «done» with the project folder) tell the board which console waits for you.
final class BoardEngine {
    private struct Live {
        var pty: BoardPty
        var raw: [Data] = []
        var rawBytes = 0
        var texto = ""
        var desdeEntrada = ""
        var ultimaSalida: Double
        var inicio: Double
        var salida: Int32?
        var avisoPide = false
        var pausada = false
        var turnos = 0
        var ultimoEstado = ""
    }
    private(set) var state = BoardCore.State()
    private var vivos: [String: Live] = [:]
    private var colas: [String: [(Data, Bool)]] = [:]
    private var escribiendo: Set<String> = []
    private let file: URL
    private let activityFile: () -> URL?
    private var activityOffset: UInt64 = 0
    private var timer: Timer?
    private var comprobando: Set<String> = []
    /// (event, data) to the page: «o» "<id> <base64>", «nueva» "<id>", «fin» "<id> <code>"
    var emit: ((String, String) -> Void)?
    var now: () -> Double = { Date().timeIntervalSince1970 }

    init(folder: URL, activityFile: @escaping () -> URL? = { nil }) {
        file = folder.appendingPathComponent("board.json")
        self.activityFile = activityFile
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: file), let s = try? JSONDecoder().decode(BoardCore.State.self, from: d) { state = s }
        if let f = activityFile(), let a = try? FileManager.default.attributesOfItem(atPath: f.path), let n = a[.size] as? NSNumber { activityOffset = n.uint64Value }
    }
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
    }
    func stopAll() { timer?.invalidate(); timer = nil; for v in vivos.values { v.pty.kill() } }
    private func save() {
        if let d = try? JSONEncoder().encode(state) { try? d.write(to: file, options: .atomic) }
    }

    // MARK: state
    func estado(_ id: String) -> BoardCore.Estado {
        guard let v = vivos[id] else { return .dormida }
        return BoardCore.estado(vivo: true, salida: v.salida, ahora: now(), inicio: v.inicio, ultimaSalida: v.ultimaSalida, desdeEntrada: v.desdeEntrada, avisoPide: v.avisoPide, pausada: v.pausada)
    }
    func vista() -> [String: Any] {
        var cuenta: [String: Int] = ["trabajando": 0, "te_necesita": 0, "en_reposo": 0, "pausada": 0, "terminada": 0, "dormida": 0]
        let lista: [[String: Any]] = state.consolas.map { c in
            let e = estado(c.id); cuenta[e.rawValue, default: 0] += 1
            var o = dict(c)
            o["estado"] = e.rawValue; o["cliNombre"] = BoardCore.cliNombre(c)
            o["salida"] = vivos[c.id]?.salida.map { Int($0) } ?? NSNull()
            o["inicio"] = vivos[c.id]?.inicio ?? 0; o["turnos"] = vivos[c.id]?.turnos ?? 0
            return o
        }
        let nombres = state.consolas.map(\.nombre)
        let props = state.consolas.flatMap { c in vivos[c.id].map { BoardCore.propuestas(orquestador: c, desdeEntrada: $0.desdeEntrada, nombres: nombres) } ?? [] }
        return ["consolas": lista, "bucles": state.bucles.map(dict), "cuenta": cuenta, "max": BoardCore.maxLanzar, "ahora": now(), "turnos": vivos.values.reduce(0) { $0 + $1.turnos },
                "propuestas": props.suffix(12).map { ["de": $0.de, "deNombre": $0.deNombre, "a": $0.a, "texto": $0.texto] }]
    }
    private func dict<T: Encodable>(_ v: T) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(v))) as? [String: Any] ?? [:]
    }

    // MARK: consoles
    private func cwdValido(_ s: String?) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var p = (s ?? "").trimmingCharacters(in: .whitespaces)
        if p.isEmpty { return home }
        if p == "~" { p = home } else if p.hasPrefix("~/") { p = home + String(p.dropFirst(1)) }
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: p, isDirectory: &dir) && dir.boolValue ? p : home
    }
    @discardableResult
    func lanzar(_ lista: [[String: Any]]) throws -> [String] {
        guard !lista.isEmpty else { throw BoardError("No hay consolas que lanzar.") }
        guard lista.count <= BoardCore.maxLanzar else { throw BoardError("Como mucho \(BoardCore.maxLanzar) consolas de una vez.") }
        guard state.consolas.count + lista.count <= BoardCore.maxConsolas else { throw BoardError("El tablero admite \(BoardCore.maxConsolas) consolas; cierra alguna antes.") }
        var nuevas: [BoardCore.Console] = []
        for n in lista {
            let cliPedido = n["cli"] as? String ?? "claude"
            let cli = ["claude", "codex", "gemini", "shell", "custom"].contains(cliPedido) ? cliPedido : "claude"
            let comando = (n["comando"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            if cli == "custom" && comando.isEmpty { throw BoardError("Falta el comando de la consola.") }
            let base = (n["nombre"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let usados = (state.consolas + nuevas).map(\.nombre)
            let nombre = base.isEmpty ? BoardCore.personajeLibre(usados: usados) : BoardCore.nombreLibre(String(base.prefix(40)), usados: usados)
            let w = min(1600, max(380, (n["w"] as? Double) ?? 580)), h = min(1200, max(240, (n["h"] as? Double) ?? 410))
            let prompt = (n["prompt"] as? String).flatMap { $0.isEmpty ? nil : String($0.prefix(4000)) }
            nuevas.append(.init(id: UUID().uuidString.lowercased(), nombre: nombre, cli: cli, comando: cli == "custom" ? String(comando.prefix(500)) : nil,
                                rol: String((n["rol"] as? String ?? "").prefix(60)), equipo: String((n["equipo"] as? String ?? "").prefix(40)), cwd: cwdValido(n["cwd"] as? String),
                                prompt: prompt, x: 0, y: 0, w: w, h: h, creada: now()))
        }
        BoardCore.colocar(&nuevas, debajoDe: state.consolas)
        for (i, n) in lista.enumerated() { if let x = n["x"] as? Double, let y = n["y"] as? Double { nuevas[i].x = x; nuevas[i].y = y } }
        state.consolas += nuevas
        for c in nuevas { try arrancar(c) }
        save()
        return nuevas.map(\.id)
    }
    private func arrancar(_ c: BoardCore.Console, reanudar: Bool = false) throws {
        let cols = max(40, Int((c.w / 8.4).rounded())), rows = max(10, Int(((c.h - 34) / 17).rounded()))
        let pty = try BoardPty(linea: BoardCore.linea(c, reanudar: reanudar), cwd: c.cwd, cols: cols, rows: rows)
        let t = now()
        vivos[c.id] = Live(pty: pty, ultimaSalida: t, inicio: t)
        emit?("nueva", c.id)
        let id = c.id
        pty.onData = { [weak self] d in DispatchQueue.main.async { self?.recibir(id, d) } }
        pty.onExit = { [weak self] code in DispatchQueue.main.async { self?.vivos[id]?.salida = code; self?.emit?("fin", "\(id) \(code)") } }
    }
    private func recibir(_ id: String, _ d: Data) {
        guard var v = vivos[id] else { return }
        v.raw.append(d); v.rawBytes += d.count
        while v.rawBytes > BoardCore.rawMax && v.raw.count > 1 { v.rawBytes -= v.raw.removeFirst().count }
        let limpio = BoardCore.sinAnsi(String(decoding: d, as: UTF8.self))
        v.texto = String((v.texto + limpio).suffix(BoardCore.textoMax))
        v.desdeEntrada = String((v.desdeEntrada + limpio).suffix(BoardCore.textoMax))
        v.ultimaSalida = now()
        vivos[id] = v
        emit?("o", id + " " + d.base64EncodedString())
    }
    /// what a page that (re)opens needs: everything each live console has buffered, and which have finished
    func replay() {
        for (id, v) in vivos {
            if !v.raw.isEmpty { emit?("o", id + " " + v.raw.reduce(Data(), +).base64EncodedString()) }
            if let s = v.salida { emit?("fin", "\(id) \(s)") }
        }
    }
    private func buscar(_ id: String) throws -> BoardCore.Console {
        guard let c = state.consolas.first(where: { $0.id == id }) else { throw BoardError("Esa consola ya no está en el tablero.") }
        return c
    }
    func reanudar(_ id: String) throws -> Bool {
        let c = try buscar(id)
        if let v = vivos[id], v.salida == nil { return false }
        vivos[id] = nil
        try arrancar(c, reanudar: c.cli == "claude" || c.cli == "codex")
        return true
    }
    func mover(_ id: String, _ p: [String: Any]) throws {
        _ = try buscar(id)
        guard let i = state.consolas.firstIndex(where: { $0.id == id }) else { return }
        if let x = p["x"] as? Double { state.consolas[i].x = x.rounded() }
        if let y = p["y"] as? Double { state.consolas[i].y = y.rounded() }
        if let w = p["w"] as? Double { state.consolas[i].w = min(1600, max(380, w.rounded())) }
        if let h = p["h"] as? Double { state.consolas[i].h = min(1200, max(240, h.rounded())) }
        save()
    }
    func tam(_ id: String, cols: Int, rows: Int) { vivos[id]?.pty.resize(cols: cols, rows: rows) }
    /// raw keystrokes from the console's own terminal view
    func teclear(_ id: String, _ data: Data) throws { _ = try buscar(id); enviar(id, data) }
    private func enviar(_ id: String, _ data: Data) {
        guard var v = vivos[id], v.salida == nil else { return }
        v.desdeEntrada = ""; v.avisoPide = false; vivos[id] = v
        v.pty.write(data)
    }
    /// text from the person (dictation, an order, a handoff): one block; Enter only when `intro`. One message at a time
    /// per console: its text, a breath for the TUI, then its Enter, before the next one starts.
    @discardableResult
    func escribir(_ id: String, _ texto: String, intro: Bool) throws -> Bool {
        _ = try buscar(id)
        guard let v = vivos[id], v.salida == nil else { return false }
        let t = String(texto.prefix(20000))
        if t.isEmpty && !intro { return false }
        colas[id, default: []].append((Data(BoardCore.pegado(t).utf8), intro))
        if !escribiendo.contains(id) { siguiente(id) }
        return true
    }
    private func siguiente(_ id: String) {
        guard var cola = colas[id], !cola.isEmpty else { escribiendo.remove(id); return }
        escribiendo.insert(id)
        let (d, intro) = cola.removeFirst(); colas[id] = cola
        if !d.isEmpty { enviar(id, d) }
        let espera = intro ? (d.isEmpty ? 0.0 : 0.15) : 0.0
        DispatchQueue.main.asyncAfter(deadline: .now() + espera) { [weak self] in
            guard let self else { return }
            if intro { self.enviar(id, Data([13])) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { self.siguiente(id) }
        }
    }
    /// a live console only dies when confirmed; a dormant or finished one is just removed
    func cerrar(_ id: String, confirmar: Bool) throws {
        _ = try buscar(id)
        if let v = vivos[id], v.salida == nil {
            guard confirmar else { throw BoardError("La consola sigue viva: confirma para cerrarla.") }
            v.pty.kill()
        }
        vivos[id] = nil
        state.consolas.removeAll { $0.id == id }; state.bucles.removeAll { $0.consola == id }
        save()
    }
    func ultimo(_ id: String) -> String { BoardCore.ultimo(vivos[id]?.texto ?? "") }
    func traspaso(de: String, a: String, instruccion: String, intro: Bool) throws -> Bool {
        let origen = try buscar(de); _ = try buscar(a)
        let cuerpo = ultimo(de)
        guard !cuerpo.isEmpty else { throw BoardError("\(origen.nombre) todavía no ha escrito nada que pasar.") }
        let inst = instruccion.trimmingCharacters(in: .whitespacesAndNewlines)
        return try escribir(a, (inst.isEmpty ? "Sigue a partir de esto." : inst) + "\n\n--- Lo último de \(origen.nombre) ---\n" + cuerpo, intro: intro)
    }
    func orden(_ texto: String) -> [String: Any] {
        let (ordenes, sueltas) = BoardCore.ordenes(texto)
        var entregadas: [String] = [], sinDestino = sueltas
        for o in ordenes {
            let ds = BoardCore.destinos(o.destino, en: state.consolas)
            if ds.isEmpty { sinDestino.append("@\(o.destino): \(o.texto)"); continue }
            for c in ds where (try? escribir(c.id, o.texto, intro: true)) == true { entregadas.append(c.nombre) }
        }
        return ["entregadas": entregadas, "sinDestino": sinDestino]
    }

    // MARK: loops
    func nuevoBucle(_ b: [String: Any]) throws -> String {
        let consola = b["consola"] as? String ?? ""
        _ = try buscar(consola)
        let mensaje = (b["mensaje"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mensaje.isEmpty else { throw BoardError("El bucle necesita un mensaje.") }
        let bucle = BoardCore.Loop(id: UUID().uuidString.lowercased(), consola: consola, mensaje: String(mensaje.prefix(4000)), disparo: (b["disparo"] as? String) == "cada" ? "cada" : "inactividad",
                                   segundos: max(10, min(86400, b["segundos"] as? Double ?? 60)), objetivo: String((b["objetivo"] as? String ?? "").prefix(500)),
                                   max: max(1, min(200, b["max"] as? Int ?? 10)), vueltas: 0, activo: true, motivo: "", ultimo: now(), creado: now())
        state.bucles.append(bucle); save()
        return bucle.id
    }
    func pararBucle(_ id: String, quitar: Bool) -> Bool {
        guard let i = state.bucles.firstIndex(where: { $0.id == id }) else { return false }
        if quitar { state.bucles.remove(at: i) } else { state.bucles[i].activo = false; state.bucles[i].motivo = "Parado por ti." }
        save(); return true
    }
    /// one turn of every active loop (every 2 s, and from the tests with a chosen `ahora`)
    func vueltaBucles(ahora: Double? = nil, comprobar: ((String, String, @escaping (Bool) -> Void) -> Void)? = nil) {
        let t = ahora ?? now()
        for i in state.bucles.indices where state.bucles[i].activo {
            let b = state.bucles[i]
            guard let c = state.consolas.first(where: { $0.id == b.consola }) else { state.bucles[i].activo = false; continue }
            let v = vivos[c.id]
            switch BoardCore.paso(b, estado: estado(c.id), ultimaSalida: v?.ultimaSalida ?? 0, ahora: t) {
            case .esperar: continue
            case .consolaMuerta: state.bucles[i].activo = false; state.bucles[i].motivo = "La consola ya no está viva."; save()
            case .tope: state.bucles[i].activo = false; state.bucles[i].motivo = "Tope de \(b.max) vueltas."; save()
            case .escribir: state.bucles[i].ultimo = t; if (try? escribir(c.id, b.mensaje, intro: true)) == true { state.bucles[i].vueltas += 1 }; save()
            case .comprobarObjetivo:
                guard !comprobando.contains(b.id) else { continue }
                comprobando.insert(b.id); state.bucles[i].ultimo = t
                (comprobar ?? BoardEngine.comprobarComando)(b.objetivo, c.cwd) { [weak self] ok in
                    DispatchQueue.main.async {
                        guard let self, let j = self.state.bucles.firstIndex(where: { $0.id == b.id }) else { return }
                        self.comprobando.remove(b.id)
                        if ok { self.state.bucles[j].activo = false; self.state.bucles[j].motivo = "Objetivo cumplido: «\(b.objetivo)» ha salido bien." }
                        else if self.state.bucles[j].vueltas >= b.max { self.state.bucles[j].activo = false; self.state.bucles[j].motivo = "Tope de \(b.max) vueltas." }
                        else if (try? self.escribir(c.id, b.mensaje, intro: true)) == true { self.state.bucles[j].vueltas += 1 }
                        self.save()
                    }
                }
            }
        }
    }
    static func comprobarComando(_ cmd: String, _ cwd: String, _ done: @escaping (Bool) -> Void) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
        p.arguments = ["-l", "-c", cmd]; p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        p.terminationHandler = { done($0.terminationStatus == 0) }
        do { try p.run() } catch { done(false); return }
        DispatchQueue.global().asyncAfter(deadline: .now() + 180) { if p.isRunning { p.terminate() } }
    }

    // MARK: Claude Code alerts Agent Bar already records
    /// «ask»/«permission» for a project folder marks the live consoles in that folder as waiting for you (until input
    /// reaches them); «done» clears it. Read from where the last read stopped.
    func leerAvisos() {
        guard let f = activityFile(), let h = try? FileHandle(forReadingFrom: f) else { return }
        defer { try? h.close() }
        let fin = (try? h.seekToEnd()) ?? 0
        if fin < activityOffset { activityOffset = 0 }
        try? h.seek(toOffset: activityOffset)
        let d = h.readDataToEndOfFile(); activityOffset = fin
        for line in String(decoding: d, as: UTF8.self).split(separator: "\n") {
            guard let o = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let kind = o["kind"] as? String, let place = o["place"] as? String, !place.isEmpty else { continue }
            for c in state.consolas where (c.cwd as NSString).lastPathComponent.lowercased() == place.lowercased() && ["claude", "codex"].contains(c.cli) {
                if kind == "ask" || kind == "permission" { vivos[c.id]?.avisoPide = true }
                if kind == "done" || kind == "allowed" { vivos[c.id]?.avisoPide = false }
            }
        }
    }
    /// a turn is finished each time a console goes from working to waiting (at rest or needing you)
    func contarTurnos() {
        for id in vivos.keys {
            let e = estado(id).rawValue
            if vivos[id]!.ultimoEstado == "trabajando" && (e == "en_reposo" || e == "te_necesita") { vivos[id]!.turnos += 1 }
            vivos[id]!.ultimoEstado = e
        }
    }
    private func tick() { leerAvisos(); contarTurnos(); vueltaBucles() }
    /// pause or resume a console's whole session (SIGSTOP / SIGCONT): it keeps its place and its conversation
    func pausar(_ id: String, _ si: Bool) throws {
        _ = try buscar(id)
        guard let v = vivos[id], v.salida == nil else { return }
        _ = Darwin.kill(-v.pty.pid, si ? SIGSTOP : SIGCONT); _ = Darwin.kill(v.pty.pid, si ? SIGSTOP : SIGCONT)
        vivos[id]?.pausada = si
    }
    func todas(pausar si: Bool) { for c in state.consolas { try? pausar(c.id, si) } }
    func agrupar(_ ids: [String], equipo: String) {
        let nombre = String(equipo.trimmingCharacters(in: .whitespaces).prefix(40))
        for i in state.consolas.indices where ids.contains(state.consolas[i].id) { state.consolas[i].equipo = nombre }
        save()
    }

    // MARK: the page's calls
    func handle(_ path: String, _ m: [String: Any]) throws -> Any {
        let id = m["id"] as? String ?? ""
        switch path {
        case "": return vista()
        case "/lanzar": return ["ids": try lanzar((m["consolas"] as? [[String: Any]]) ?? [m])]
        case "/reanudar": return ["ok": try reanudar(id)]
        case "/mover": try mover(id, m); return ["ok": true]
        case "/tam": tam(id, cols: m["cols"] as? Int ?? 80, rows: m["rows"] as? Int ?? 24); return ["ok": true]
        case "/teclear": try teclear(id, Data(base64Encoded: m["d"] as? String ?? "") ?? Data()); return ["ok": true]
        case "/escribir": return ["ok": try escribir(id, m["texto"] as? String ?? "", intro: m["enviar"] as? Bool == true)]
        case "/cerrar": try cerrar(id, confirmar: m["confirmar"] as? Bool == true); return ["ok": true]
        case "/traspaso": return ["ok": try traspaso(de: m["de"] as? String ?? "", a: m["a"] as? String ?? "", instruccion: m["instruccion"] as? String ?? "", intro: m["enviar"] as? Bool == true)]
        case "/orden": return orden(m["texto"] as? String ?? "")
        case "/bucle": return ["id": try nuevoBucle(m)]
        case "/bucle/parar": return ["ok": pararBucle(id, quitar: m["quitar"] as? Bool == true)]
        case "/pausar": try pausar(id, m["si"] as? Bool != false); return ["ok": true]
        case "/todas": todas(pausar: m["pausar"] as? Bool == true); return ["ok": true]
        case "/agrupar": agrupar(m["ids"] as? [String] ?? [], equipo: m["equipo"] as? String ?? ""); return ["ok": true]
        case "/flujo": replay(); return ["ok": true]
        default: throw BoardError("No encontrado.")
        }
    }
}

struct BoardError: LocalizedError { let message: String; init(_ m: String) { message = m }; var errorDescription: String? { message } }
