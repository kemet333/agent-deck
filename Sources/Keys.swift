import Foundation

/// Lo que escribe una tecla (0.16): variables que se rellenan al pulsarla y pasos en cadena.
///
/// Variables: {selección} / {selection}: lo seleccionado en la app de delante · {portapapeles} / {clipboard} ·
/// {app}: la app de delante · {archivo} / {file}: el documento o la ventana de delante · {fecha} / {date} · {hora} / {time}.
/// Cadena: una línea con solo «---» separa pasos; cada paso se envía cuando el anterior ha entrado (Claude Code los pone
/// en cola mientras trabaja). Una línea «{espera 5}» / «{wait 5}» espera esos segundos antes del siguiente paso.
enum KeyText {
    enum Var: String, CaseIterable { case selection, clipboard, app, file, date, time }
    static let names: [String: Var] = [
        "seleccion": .selection, "selection": .selection, "portapapeles": .clipboard, "clipboard": .clipboard,
        "app": .app, "archivo": .file, "file": .file, "fecha": .date, "date": .date, "hora": .time, "time": .time,
    ]
    /// Lo que se ofrece en el editor, en el idioma de la app.
    static var palette: [(token: String, help: String)] {
        T.es ? [("{selección}", "lo seleccionado"), ("{portapapeles}", "lo copiado"), ("{archivo}", "el archivo de delante"),
                ("{app}", "la app de delante"), ("{fecha}", "hoy"), ("{hora}", "ahora")]
             : [("{selection}", "what's selected"), ("{clipboard}", "what's copied"), ("{file}", "the file in front"),
                ("{app}", "the app in front"), ("{date}", "today"), ("{time}", "now")]
    }

    private static func key(_ raw: Substring) -> String {
        raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased().trimmingCharacters(in: .whitespaces)
    }
    private static let pattern = try! NSRegularExpression(pattern: "\\{([^{}\\n]{1,20})\\}")

    /// Las variables que usa un texto.
    static func uses(_ text: String) -> Set<Var> {
        var out = Set<Var>()
        for m in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let r = Range(m.range(at: 1), in: text), let v = names[key(text[r])] { out.insert(v) }
        }
        return out
    }
    /// Cambia cada variable por su valor; las que no conoce las deja tal cual.
    static func fill(_ text: String, _ values: [Var: String]) -> String {
        var out = "", last = text.startIndex
        for m in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(m.range, in: text), let inner = Range(m.range(at: 1), in: text) else { continue }
            out += text[last..<whole.lowerBound]
            if let v = names[key(text[inner])] { out += values[v] ?? "" } else { out += text[whole] }
            last = whole.upperBound
        }
        return out + text[last...]
    }

    /// Una combinación de teclas que se pulsa en vez de escribir (0.21, Agent Bar para traders): «{pulsa ⇧B}».
    struct Combo: Equatable { var key: UInt16; var flags: UInt64; var label: String }
    struct Step: Equatable { var text: String; var wait: Double; var press: Combo? = nil }

    static let shiftBit: UInt64 = 0x20000, controlBit: UInt64 = 0x40000, optionBit: UInt64 = 0x80000, commandBit: UInt64 = 0x100000
    /// Teclas por su posición (las letras están en el mismo sitio en el teclado español que en el inglés).
    static let keyCodes: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29, "o": 31, "u": 32,
        "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        "intro": 36, "enter": 36, "return": 36, "tab": 48, "espacio": 49, "space": 49, "esc": 53, "escape": 53,
        "izquierda": 123, "left": 123, "derecha": 124, "right": 124, "abajo": 125, "down": 125, "arriba": 126, "up": 126,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]
    /// «⇧B», «⇧⌥S», «shift+b», «mayús+alt+s», «cmd+enter» → la combinación. nil si no se entiende.
    static func combo(_ raw: String) -> Combo? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        var flags: UInt64 = 0
        let symbols: [(Character, UInt64)] = [("⇧", shiftBit), ("⌥", optionBit), ("⌘", commandBit), ("⌃", controlBit)]
        while let c = s.first, let f = symbols.first(where: { $0.0 == c }) { flags |= f.1; s.removeFirst(); s = s.trimmingCharacters(in: .whitespaces) }
        let parts = key(Substring(s)).split(whereSeparator: { $0 == "+" || $0 == " " }).map(String.init).filter { !$0.isEmpty }
        guard let last = parts.last else { return nil }
        let words: [String: UInt64] = ["shift": shiftBit, "mayus": shiftBit, "mayusculas": shiftBit, "alt": optionBit, "option": optionBit, "opt": optionBit,
                                       "opcion": optionBit, "cmd": commandBit, "command": commandBit, "comando": commandBit, "ctrl": controlBit, "control": controlBit]
        for w in parts.dropLast() { guard let f = words[w] else { return nil }; flags |= f }
        guard let code = keyCodes[last] else { return nil }
        var label = ""
        if flags & controlBit != 0 { label += "⌃" }; if flags & optionBit != 0 { label += "⌥" }
        if flags & shiftBit != 0 { label += "⇧" }; if flags & commandBit != 0 { label += "⌘" }
        return Combo(key: code, flags: flags, label: label + (last.count == 1 ? last.uppercased() : last.capitalized))
    }
    /// «{pulsa ⇧B}» / «{press shift+b}» en una línea sola.
    private static func pressCombo(_ line: String) -> Combo? {
        let k = line.trimmingCharacters(in: .whitespaces)
        guard k.hasPrefix("{"), k.hasSuffix("}") else { return nil }
        let inner = String(k.dropFirst().dropLast())
        for p in ["pulsa ", "press "] where key(Substring(inner)).hasPrefix(p) { return combo(String(inner.dropFirst(p.count))) }
        return nil
    }
    /// Los pasos de una tecla en cadena. Sin «---», un solo paso.
    static func steps(_ text: String) -> [Step] {
        var steps: [Step] = [], current: [String] = [], wait = 0.0
        func flush() {
            let t = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { steps.append(Step(text: t, wait: wait)) }
            current = []; wait = 0
        }
        for line in text.components(separatedBy: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l == "---" { flush(); continue }
            if let c = pressCombo(l) {
                if !current.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { flush() }
                steps.append(Step(text: "", wait: wait, press: c)); wait = 0; continue
            }
            if let w = waitSeconds(l) {
                if !current.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { flush() }
                wait = min(600, wait + w); continue
            }
            current.append(line)
        }
        flush()
        return steps
    }
    private static func waitSeconds(_ line: String) -> Double? {
        let k = key(Substring(line))
        for p in ["{espera ", "{wait "] where k.hasPrefix(p) && k.hasSuffix("}") {
            return Double(k.dropFirst(p.count).dropLast().replacingOccurrences(of: "s", with: "").replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
    /// Un resumen corto para la lista de teclas: «3 pasos» o el texto.
    static func preview(_ text: String) -> String {
        let s = steps(text)
        let shown = s.map { $0.press.map { T.s("press ", "pulsa ") + $0.label } ?? String($0.text.prefix(24)) }
        if s.count == 1, let c = s.first?.press { return T.s("Presses ", "Pulsa ") + c.label }
        return s.count > 1 ? T.s("\(s.count) steps: ", "\(s.count) pasos: ") + shown.joined(separator: " → ") : text
    }
}

/// Sugerencias de teclas (0.16): lo que has dictado tres veces o más y aún no es una tecla.
enum KeySuggestions {
    static func norm(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
            .unicodeScalars.filter { CharacterSet.letters.union(.decimalDigits).union(.whitespaces).contains($0) }.map(String.init).joined()
            .split(separator: " ").joined(separator: " ")
    }
    /// (frase, veces), la más repetida primero. Solo frases cortas (2–14 palabras).
    static func from(history: [String], existing: [String], min: Int = 3, limit: Int = 4) -> [(text: String, count: Int)] {
        let have = Set(existing.map(norm))
        var count: [String: Int] = [:], sample: [String: String] = [:]
        for h in history {
            let t = h.trimmingCharacters(in: .whitespacesAndNewlines)
            let n = norm(t), words = n.split(separator: " ").count
            guard (2...14).contains(words), t.count <= 120, !have.contains(n) else { continue }
            count[n, default: 0] += 1
            if sample[n] == nil { sample[n] = t }
        }
        return count.filter { $0.value >= min }.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(limit).map { (sample[$0.key]!, $0.value) }
    }
    /// Un nombre corto para la tecla: las dos primeras palabras.
    static func label(_ text: String) -> String {
        let w = text.split(separator: " ").prefix(2).joined(separator: " ")
        let clean = w.trimmingCharacters(in: CharacterSet.punctuationCharacters)
        return String(clean.prefix(1).uppercased() + clean.dropFirst()).prefix(16).description
    }
}

/// Tiempo ahorrado (0.17), estimado y a la vista de cómo se calcula: escribir a 40 palabras por minuto (1,5 s cada una)
/// frente a hablar (0,4 s) o pulsar una tecla (1 s); cada vuelta de Autopilot o paso de una cola, 15 s de leer y contestar;
/// cada permiso desde la barra, 5 s de buscar el diálogo. Se guarda por día en Application Support/Agent Deck/savings.json.
enum Savings {
    enum Kind: String, CaseIterable { case keys, keyWords, dictWords, autopilot, queued, permissions }
    struct Totals: Equatable { var c: [Kind: Int] = [:]; subscript(_ k: Kind) -> Int { c[k] ?? 0 } }
    static var file: URL { Autopilot.folder.appendingPathComponent("savings.json") }
    static func day(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f.string(from: d) }
    static func load() -> [String: [String: Int]] {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: [String: Int]].self, from: $0) } ?? [:]
    }
    static func add(_ kind: Kind, _ n: Int = 1, on date: Date = Date()) {
        guard n > 0 else { return }
        var all = load()
        all[day(date), default: [:]][kind.rawValue, default: 0] += n
        // solo los últimos 60 días
        let now = Date(), keep = Set((0..<60).map { day(now.addingTimeInterval(Double(-$0) * 86_400)) })
        all = all.filter { keep.contains($0.key) }
        try? FileManager.default.createDirectory(at: Autopilot.folder, withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(all) { try? d.write(to: file, options: .atomic) }
    }
    /// Lo de los últimos `days` días, hoy incluido.
    static func totals(days: Int = 7, until date: Date = Date()) -> Totals {
        let all = load(); var t = Totals()
        for i in 0..<days {
            for (k, v) in all[day(date.addingTimeInterval(Double(-i) * 86_400))] ?? [:] { if let kind = Kind(rawValue: k) { t.c[kind, default: 0] += v } }
        }
        return t
    }
    static func seconds(_ t: Totals) -> Double {
        let keys = max(0, Double(t[.keyWords]) * 1.5 - Double(t[.keys]) * 1.0)
        return keys + Double(t[.dictWords]) * 1.1 + Double(t[.autopilot] + t[.queued]) * 15 + Double(t[.permissions]) * 5
    }
    static func words(_ s: String) -> Int { s.split(whereSeparator: { $0.isWhitespace }).count }
    /// «1 h 12 min», «8 min», «40 s».
    static func duration(_ s: Double) -> String {
        let m = Int(s / 60)
        if m >= 60 { return "\(m / 60) h \(m % 60) min" }
        if m >= 1 { return "\(m) min" }
        return "\(Int(s)) s"
    }
}
