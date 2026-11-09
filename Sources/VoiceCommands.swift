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
