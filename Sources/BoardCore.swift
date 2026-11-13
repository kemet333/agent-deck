import Foundation

/// Agents board, the pure part (no AppKit, no processes): what a console is, how its state is read from what it prints,
/// orders by name, an orchestrator's proposals, where new consoles go, and what a loop does on each turn.
/// Ported from the board first built in Diego OS (local-workspace/tablero.ts, 12/11/2026), so both behave the same.
/// Rules: dictation and keys only type; an order is sent because the person gave it; a loop never answers a permission
/// nor interrupts; a live console only closes when confirmed.
enum BoardCore {
    struct Console: Codable, Equatable {
        var id: String
        var nombre: String
        var cli: String          // claude · codex · gemini · shell · custom
        var comando: String?
        var rol: String
        var equipo: String
        var cwd: String
        var prompt: String?
        var x: Double, y: Double, w: Double, h: Double
        var creada: Double
    }
    struct Loop: Codable, Equatable {
        var id: String
        var consola: String
        var mensaje: String
        var disparo: String      // inactividad · cada
        var segundos: Double
        var objetivo: String
        var max: Int
        var vueltas: Int
        var activo: Bool
        var motivo: String
        var ultimo: Double
        var creado: Double
    }
    struct State: Codable { var consolas: [Console] = []; var bucles: [Loop] = [] }

    static let clis: [(id: String, nombre: String, cmd: String, continuar: String)] = [
        ("claude", "Claude Code", "claude", "claude --continue"),
        ("codex", "Codex", "codex", "codex resume --last"),
        ("gemini", "Gemini CLI", "gemini", "gemini"),
        ("shell", "Terminal", "", ""),
    ]
    /// every agent gets a character name, so a board of twelve reads like a crew, not a list of «claude-7»
    static let personajes = ["Mila", "Ren", "Juno", "Ada", "Bex", "Cy", "Pip", "Otto", "Nova", "Lia", "Kai", "Zoe", "Ivo", "Uma", "Teo", "Nia", "Rui", "Eli", "Sol", "Vera", "Leo", "Ona", "Gus", "Max"]
    static func personajeLibre(usados: [String]) -> String {
        let u = Set(usados.map { $0.lowercased() })
        if let p = personajes.first(where: { !u.contains($0.lowercased()) }) { return p }
        return nombreLibre(personajes[usados.count % personajes.count], usados: usados)
    }
    static let maxLanzar = 12, maxConsolas = 24, rawMax = 512 * 1024, textoMax = 8000
    static let trabajandoSegundos = 2.5

    // MARK: text
    private static let ansi = try! NSRegularExpression(pattern: "\u{1b}\\[[0-?]*[ -/]*[@-~]|\u{1b}\\][^\u{07}\u{1b}]*(\u{07}|\u{1b}\\\\)|\u{1b}[()][A-Za-z0-9]|\u{1b}[=>78]")
    /// what a terminal printed, as plain text (no colours, no cursor moves; a lone \r becomes a new line)
    static func sinAnsi(_ s: String) -> String {
        var t = ansi.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        t = t.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return String(t.unicodeScalars.filter { $0 == "\n" || $0 == "\t" || $0.value >= 0x20 && $0.value != 0x7f })
    }
    /// What an agent CLI prints when it waits for a person (a permission, a choice, a question). Read only on what it
    /// printed since the last input reached it: once answered, the old question still on screen no longer counts.
    private static let pide = try! NSRegularExpression(pattern: "(Do you want to|Would you like to|\\(y/n\\)|\\[y/N\\]|\\[Y/n\\]|❯\\s*1\\.\\s*Yes|Allow (once|always)|Approve|requires (your )?approval|Press Enter to (continue|confirm)|Enter to confirm|needs? (your )?review|Trust (this|all)|waiting for (your )?(input|approval)|¿Quieres|Permitir)", options: [.caseInsensitive])
    static func pidePermiso(_ textoDesdeEntrada: String) -> Bool {
        let tail = String(textoDesdeEntrada.suffix(900))
        return pide.firstMatch(in: tail, range: NSRange(tail.startIndex..., in: tail)) != nil
    }
    enum Estado: String { case trabajando, te_necesita, en_reposo, pausada, terminada, dormida }
    static func estado(vivo: Bool, salida: Int32?, ahora: Double, inicio: Double, ultimaSalida: Double, desdeEntrada: String, avisoPide: Bool = false, pausada: Bool = false) -> Estado {
        if !vivo { return .dormida }
        if salida != nil { return .terminada }
        if pausada { return .pausada }
        if ahora - ultimaSalida < trabajandoSegundos && ahora - inicio > 1.5 { return .trabajando }
        return avisoPide || pidePermiso(desdeEntrada) ? .te_necesita : .en_reposo
    }

    // MARK: consoles
    static func comillas(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    /// the command a console runs inside a login shell, so the CLIs on the person's PATH are found from the app too
    static func linea(_ c: Console, reanudar: Bool = false) -> String {
        if c.cli == "custom" { return c.comando ?? "" }
        guard let def = clis.first(where: { $0.id == c.cli }), !def.cmd.isEmpty else { return "" }
        let base = reanudar ? def.continuar : def.cmd
        if let p = c.prompt, !p.isEmpty, !reanudar { return base + " " + comillas(p) }
        return base
    }
    static func cliNombre(_ c: Console) -> String { c.cli == "custom" ? "Comando" : clis.first(where: { $0.id == c.cli })?.nombre ?? c.cli }
    /// a unique name: «claude», «claude-2»…
    static func nombreLibre(_ pedido: String, usados: [String]) -> String {
        let u = Set(usados.map { $0.lowercased() })
        guard u.contains(pedido.lowercased()) else { return pedido }
        var k = 2
        while u.contains("\(pedido)-\(k)".lowercased()) { k += 1 }
        return "\(pedido)-\(k)"
    }
    /// new consoles left to right by their real width, three per row, below what is already on the board
    static func colocar(_ nuevas: inout [Console], debajoDe existentes: [Console]) {
        var y = existentes.isEmpty ? 24 : (existentes.map { $0.y + $0.h }.max() ?? 0) + 24
        var x = 24.0, alto = 0.0, enFila = 0
        for i in nuevas.indices {
            if enFila == 3 { y += alto + 24; x = 24; alto = 0; enFila = 0 }
            nuevas[i].x = x; nuevas[i].y = y
            x += nuevas[i].w + 24; alto = max(alto, nuevas[i].h); enFila += 1
        }
    }

    // MARK: orders and proposals
    struct Orden: Equatable { var destino: String; var texto: String }
    /// «@nombre: texto» one per line (also «@equipo», «@todos»); lines without a name come back unsent
    static func ordenes(_ texto: String) -> (ordenes: [Orden], sueltas: [String]) {
        var out: [Orden] = [], sueltas: [String] = []
        for raw in texto.split(separator: "\n") {
            let linea = raw.trimmingCharacters(in: .whitespaces)
            guard !linea.isEmpty else { continue }
            guard linea.hasPrefix("@"), let fin = linea.firstIndex(where: { $0 == ":" || $0 == "," || $0 == " " }) else { sueltas.append(linea); continue }
            let nombre = String(linea[linea.index(after: linea.startIndex)..<fin])
            let resto = linea[fin...].drop(while: { $0 == ":" || $0 == "," || $0 == " " })
            if nombre.isEmpty || resto.isEmpty { sueltas.append(linea); continue }
            out.append(Orden(destino: nombre, texto: String(resto)))
        }
        return (out, sueltas)
    }
    static func destinos(_ nombre: String, en consolas: [Console]) -> [Console] {
        let q = nombre.lowercased()
        return consolas.filter { q == "todos" || $0.nombre.lowercased() == q || (!$0.equipo.isEmpty && $0.equipo.lowercased() == q) }
    }
    struct Propuesta: Equatable { var de: String; var deNombre: String; var a: String; var texto: String }
    /// what an orchestrator console (rol or nombre «orquestador») wrote as «@nombre: tarea» since its last input, for
    /// consoles that exist; shown with a send button, never sent on their own
    static func propuestas(orquestador c: Console, desdeEntrada: String, nombres: [String]) -> [Propuesta] {
        guard (c.rol + " " + c.nombre).lowercased().contains("orquest") else { return [] }
        let validos = Set(nombres.map { $0.lowercased() })
        var out: [Propuesta] = []
        for raw in desdeEntrada.components(separatedBy: "\n") {
            let linea = raw.drop(while: { " │|>*•⏺-".contains($0) })
            guard linea.hasPrefix("@"), let dp = linea.firstIndex(of: ":") else { continue }
            let a = String(linea[linea.index(after: linea.startIndex)..<dp]).trimmingCharacters(in: .whitespaces)
            let texto = linea[linea.index(after: dp)...].trimmingCharacters(in: .whitespaces)
            guard texto.count >= 3, validos.contains(a.lowercased()), a.lowercased() != c.nombre.lowercased() else { continue }
            let p = Propuesta(de: c.id, deNombre: c.nombre, a: a, texto: String(texto.prefix(2000)))
            if !out.contains(p) { out.append(p) }
        }
        return Array(out.suffix(12))
    }

    // MARK: loops
    enum PasoBucle: Equatable { case esperar, comprobarObjetivo, escribir, tope, consolaMuerta }
    /// what a loop does now: never while its console works or waits for a permission
    static func paso(_ b: Loop, estado: Estado, ultimaSalida: Double, ahora: Double) -> PasoBucle {
        if estado == .terminada || estado == .dormida { return .consolaMuerta }
        if estado == .te_necesita || estado == .trabajando { return .esperar }
        let listo = b.disparo == "cada" ? ahora - b.ultimo >= b.segundos : ahora - max(ultimaSalida, b.ultimo) >= b.segundos
        if !listo { return .esperar }
        if !b.objetivo.isEmpty { return .comprobarObjetivo }
        return b.vueltas >= b.max ? .tope : .escribir
    }

    /// text Diego sends (dictation, an order, a handoff) pasted as one block when it has several lines
    static func pegado(_ t: String) -> String { t.contains("\n") ? "\u{1b}[200~" + t + "\u{1b}[201~" : t }
    /// the last screenfuls of a console as plain text, blank runs collapsed (what a handoff carries)
    static func ultimo(_ texto: String, chars: Int = 3000) -> String {
        var lines: [String] = []
        for l in texto.components(separatedBy: "\n").map({ $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }) {
            if l.isEmpty && (lines.last ?? "").isEmpty { continue }
            lines.append(l)
        }
        return String(lines.joined(separator: "\n").suffix(chars)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
