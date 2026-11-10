import Foundation

/// Órdenes dichas al final de un dictado (Diego, 10/11): «… y envía», «… no lo envíes», «cancela», «nueva línea»,
/// «… hazlo más corto», «… en inglés». Se quitan del texto antes de limpiarlo, y deciden si se envía o cómo se reescribe.
struct SpokenCommands: Equatable {
    var text: String
    /// true: enviar aunque haya ruido; false: dejarlo escrito sin Intro; nil: lo de siempre.
    var send: Bool? = nil
    var cancel = false
    /// Lo que hay que hacerle al texto («Make it shorter.»), para el modelo que lo limpia.
    var rewrite: String? = nil

    static func parse(_ raw: String) -> SpokenCommands {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var out = SpokenCommands(text: text)
        // solo «cancela» (o al final, tras una coma): no se manda nada
        let whole = norm(text)
        if ["cancela", "cancelar", "cancelalo", "olvidalo", "dejalo", "cancel", "cancel it", "never mind", "forget it"].contains(whole) { out.cancel = true; out.text = ""; return out }
        // varias órdenes seguidas al final: «… hazlo más corto y no lo envíes»
        var changed = true
        while changed {
            changed = false
            for (phrases, apply) in endings {
                if let cut = strip(text, phrases) { text = cut; apply(&out); changed = true; break }
            }
        }
        if out.cancel { out.text = ""; return out }
        // «nueva línea» / «punto y aparte» en cualquier sitio
        for p in ["punto y aparte", "nueva linea", "new line", "new paragraph"] {
            text = replace(text, phrase: p, with: "\n")
        }
        out.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return out
    }

    private static let endings: [([String], (inout SpokenCommands) -> Void)] = [
        (["no lo envies", "no envies", "sin enviar", "no lo mandes", "dont send", "do not send", "dont send it"], { $0.send = false }),
        (["y envialo", "y envia", "envialo", "y mandalo", "mandalo", "and send it", "and send", "send it"], { $0.send = true }),
        (["cancela", "cancelalo", "olvidalo", "cancel that", "cancel"], { $0.cancel = true }),
        (["hazlo mas corto", "mas corto", "acortalo", "make it shorter", "shorter"], { $0.rewrite = add($0.rewrite, "Make it shorter, keeping every requirement.") }),
        (["hazlo mas formal", "mas formal", "make it more formal"], { $0.rewrite = add($0.rewrite, "Make it more formal.") }),
        (["en ingles", "traducelo al ingles", "in english", "translate to english"], { $0.rewrite = add($0.rewrite, "Translate it into English.") }),
        (["en espanol", "en castellano", "in spanish"], { $0.rewrite = add($0.rewrite, "Translate it into Spanish (Spain).") }),
    ]
    private static func add(_ a: String?, _ b: String) -> String { a.map { $0 + " " + b } ?? b }

    /// Sin tildes, minúsculas, sin puntuación: para comparar lo dicho.
    static func norm(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
        return folded.unicodeScalars.map { CharacterSet.letters.union(.decimalDigits).contains($0) || $0 == " " ? String($0) : " " }.joined()
            .split(separator: " ").joined(separator: " ")
    }
    /// Si el texto acaba en una de esas frases (con o sin coma, «y», punto), devuelve el texto sin ella.
    private static func strip(_ text: String, _ phrases: [String]) -> String? {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        for p in phrases {
            let n = p.split(separator: " ").count
            guard words.count >= n else { continue }
            let tail = norm(words.suffix(n).joined(separator: " "))
            if tail == p {
                var rest = words.dropLast(n).joined(separator: " ")
                while let last = rest.last, ",;:-–—".contains(last) || last == " " { rest.removeLast() }
                if norm(String(rest.split(separator: " ").last ?? "")) == "y" || norm(String(rest.split(separator: " ").last ?? "")) == "and" {
                    rest = rest.split(separator: " ").dropLast().joined(separator: " ")
                    while let last = rest.last, ",;:".contains(last) { rest.removeLast() }
                }
                return rest
            }
        }
        return nil
    }
    private static func replace(_ text: String, phrase: String, with sub: String) -> String {
        var words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let n = phrase.split(separator: " ").count
        var i = 0
        while i + n <= words.count {
            if norm(words[i..<i + n].joined(separator: " ")) == phrase {
                words.replaceSubrange(i..<i + n, with: [sub]); i += 1
            } else { i += 1 }
        }
        return words.joined(separator: " ").replacingOccurrences(of: " \n ", with: "\n").replacingOccurrences(of: " \n", with: "\n").replacingOccurrences(of: "\n ", with: "\n")
    }
}

/// Nombres de tus proyectos (carpetas con git en tu carpeta personal y, si existe, los proyectos de tu vault), para que la
/// transcripción los escriba bien: Kemet, Groundwork, PostOnce… Se calcula al abrir y se guarda; nunca sale nada del Mac
/// salvo esos nombres, como pista para OpenAI.
enum LearnedVocabulary {
    /// Los últimos nombres aprendidos (se guardan para no buscar en cada dictado).
    static var cached: [String] { UserDefaults.standard.stringArray(forKey: "learnedVocabulary") ?? [] }
    static func refresh() {
        DispatchQueue.global(qos: .utility).async {
            let names = scan()
            UserDefaults.standard.set(names, forKey: "learnedVocabulary")
        }
    }
    static func scan() -> [String] {
        let fm = FileManager.default, home = fm.homeDirectoryForCurrentUser
        var names: [String] = []
        let skip: Set<String> = ["Library", "Applications", "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public", "node_modules"] // las carpetas protegidas de macOS no se miran: pedirían permiso
        for top in (try? fm.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)) ?? [] where !top.lastPathComponent.hasPrefix(".") && !skip.contains(top.lastPathComponent) {
            if isRepo(top) { names.append(top.lastPathComponent) }
            for sub in (try? fm.contentsOfDirectory(at: top, includingPropertiesForKeys: nil)) ?? [] where isRepo(sub) {
                names.append(sub.lastPathComponent)
            }
        }
        let clean = names.map { $0.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ") }
            .filter { $0.count >= 3 && $0.count <= 30 && $0.rangeOfCharacter(from: .letters) != nil }
        var seen = Set<String>()
        let unique = clean.filter { seen.insert($0.lowercased()).inserted }
        // «Kemet Capital prod», «Kemet Capital sync oct6»…: copias de trabajo de «Kemet Capital»; basta el nombre corto
        let kept = unique.filter { n in !unique.contains { $0 != n && n.lowercased().hasPrefix($0.lowercased() + " ") } }
        return Array(kept.prefix(40))
    }
    /// Un repositorio de verdad (.git es una carpeta), no una copia de trabajo de otro (.git es un archivo).
    private static func isRepo(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path, isDirectory: &dir) && dir.boolValue
    }
}

/// El vocabulario del equipo que sigues (0.19): lo guarda TeamSync al actualizar el pack del equipo.
enum TeamVocabulary {
    static var cached: [String] {
        get { UserDefaults.standard.stringArray(forKey: "teamVocabulary") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "teamVocabulary") }
    }
}

/// Hablarle a un agente concreto (0.15): «dile al de Kemet que siga», «tell the Kemet one to run the tests».
/// Y contestar a un permiso hablando: «sí» / «permítelo» lo permite; cualquier otra cosa es un no con tu motivo,
/// que Claude lee y con el que se adapta («no, usa la rama equipo»).
enum AgentCommand {
    struct Parsed: Equatable { let who: String; let say: String }

    /// Con `later`, solo lo que empieza por «luego», «después», «cuando acabe» o «then»: va a la cola de ese agente.
    static func parse(_ raw: String, later: Bool = false) -> Parsed? {
        var words = raw.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if later {
            let lead = [["cuando", "acabe"], ["cuando", "termine"], ["and", "then"], ["after", "that"], ["luego"], ["despues"], ["then"], ["later"], ["next"], ["y", "luego"], ["y", "despues"]]
            let n = words.map { SpokenCommands.norm($0) }
            guard let l = lead.first(where: { $0.count < n.count && Array(n.prefix($0.count)) == $0 }) else { return nil }
            words.removeFirst(l.count)
        }
        let n = words.map { SpokenCommands.norm($0) }
        guard words.count >= 4 else { return nil }
        let spanish = ["dile", "digale", "dila"].contains(n[0]) || (n[0] == "pidele")
        let english = n[0] == "tell" || (n[0] == "ask" && n.count > 4)
        guard spanish || english else { return nil }
        let filler: Set<String> = spanish ? ["al", "a", "la", "el", "los", "agente", "de", "del", "sesion", "chat", "proyecto"]
                                          : ["the", "agent", "of", "session", "chat", "project", "my", "in"]
        let tailFiller: Set<String> = spanish ? ["agente", "sesion", "chat"] : ["one", "agent", "session", "chat", "project"]
        let joiner = spanish ? "que" : "to"
        var i = 1
        while i < n.count, filler.contains(n[i]) { i += 1 }
        guard let j = n[i...].firstIndex(of: joiner), j > i, j - i <= 4, j + 1 < words.count else { return nil }
        var name = Array(words[i..<j])
        while let last = name.last, tailFiller.contains(SpokenCommands.norm(last)) { name.removeLast() }
        let who = name.joined(separator: " ").trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        var say = words[(j + 1)...].joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !who.isEmpty, !say.isEmpty else { return nil }
        say = say.prefix(1).uppercased() + say.dropFirst()
        return Parsed(who: who, say: say)
    }

    /// ¿Habla de esa carpeta? «kemet» → «Kemet-Capital»; «diego» → «Diego-Operating-System».
    static func matches(_ who: String, place: String) -> Bool {
        let key = SpokenCommands.norm(who), p = SpokenCommands.norm(place.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " "))
        guard !key.isEmpty, !p.isEmpty else { return false }
        if p.contains(key) || p.replacingOccurrences(of: " ", with: "").contains(key.replacingOccurrences(of: " ", with: "")) { return true }
        let pw = p.split(separator: " ")
        return key.split(separator: " ").contains { k in k.count >= 3 && pw.contains { $0.hasPrefix(k) } }
    }

    private static let yes: Set<String> = ["si", "vale", "ok", "okay", "permite", "permitelo", "permiteselo", "permitir", "adelante", "dale", "hazlo",
                                           "venga", "claro", "yes", "yeah", "yep", "allow", "sure", "go", "ahead", "do", "it", "lo", "le", "se",
                                           "eso", "that", "please", "por", "favor", "sigue", "continua", "approve", "approved"]
    /// La respuesta a un permiso: (permitir, motivo del no).
    static func permissionAnswer(_ raw: String) -> (allow: Bool, reason: String) {
        let w = SpokenCommands.norm(raw).split(separator: " ").map(String.init)
        if !w.isEmpty, w.count <= 5, w.allSatisfy({ yes.contains($0) }), w.contains(where: { !["lo", "le", "se", "eso", "it", "that", "please", "por", "favor"].contains($0) }) {
            return (true, "")
        }
        var words = raw.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        while let f = words.first, ["no", "nope", "nah"].contains(SpokenCommands.norm(f)) { words.removeFirst() }
        let reason = words.joined(separator: " ").trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        return (false, reason.isEmpty ? "" : reason.prefix(1).uppercased() + reason.dropFirst())
    }
    /// Pulsar Fn con un permiso en la barra y decir solo «permítelo» / «no lo permitas»: va a ese permiso.
    static func permissionShortcut(_ raw: String) -> Bool? {
        let s = SpokenCommands.norm(raw)
        if ["permitelo", "permite", "permitir", "permiteselo", "si permitelo", "vale permitelo", "allow", "allow it", "approve", "approve it"].contains(s) { return true }
        if ["no lo permitas", "deniegalo", "deniega", "no permitas", "deny", "deny it", "dont allow", "dont allow it", "do not allow"].contains(s) { return false }
        return nil
    }
}
