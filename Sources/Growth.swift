import Foundation

// Crecer (0.19): galería de packs curada, pack de equipo por enlace e invitaciones con afiliados de Lemon Squeezy.
// Todo sin servidor propio (decidido por Diego el 10/11/2026): la galería es un archivo en la web, el equipo es un
// archivo que publica su responsable y las invitaciones las cuenta y las paga Lemon Squeezy.

// MARK: galería

/// Un pack de la galería de getagentbar.com/packs (packs.json), en inglés y, si lo tiene, en español.
struct GalleryPack: Codable, Equatable, Identifiable {
    struct Local: Codable, Equatable { var name: String?; var about: String?; var keys: [KeyPack.Key]? }
    var id: String
    var name: String
    var by: String
    var tool: String
    var about: String
    var keys: [KeyPack.Key]
    var es: Local?

    func pack(spanish: Bool) -> KeyPack {
        KeyPack(name: spanish ? (es?.name ?? name) : name, keys: spanish ? (es?.keys ?? keys) : keys)
    }
    func summary(spanish: Bool) -> String { spanish ? (es?.about ?? about) : about }
    /// Para buscar: nombre, herramienta, descripción y teclas, en los dos idiomas.
    var haystack: String {
        var parts: [String] = [name, tool, about, es?.name ?? "", es?.about ?? ""]
        for k in keys + (es?.keys ?? []) { parts.append(k.label); parts.append(k.text) }
        return parts.joined(separator: " ").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }
}

enum Gallery {
    static let url = URL(string: "https://getagentbar.com/packs/packs.json")!
    static let contact = "hello@workwithprompted.com"
    struct Catalog: Codable { var version: Int; var packs: [GalleryPack] }

    /// Los packs válidos del catálogo (los rotos se saltan, ids repetidos fuera, como mucho 60).
    static func parse(_ data: Data) -> [GalleryPack] {
        guard data.count < 1_000_000, let c = try? JSONDecoder().decode(Catalog.self, from: data), c.version == 1 else { return [] }
        var seen = Set<String>()
        return c.packs.filter { p in
            let ok = !p.id.isEmpty && p.id.count <= 40 && p.by.count <= 40 && p.tool.count <= 30 && p.about.count <= 200
                && p.pack(spanish: false).valid && (p.es?.keys == nil || p.pack(spanish: true).valid)
            return ok && seen.insert(p.id).inserted
        }.prefix(60).map { $0 }
    }
    /// Buscar por palabras (todas tienen que estar) y por herramienta.
    static func filter(_ packs: [GalleryPack], query: String, tool: String? = nil) -> [GalleryPack] {
        let words = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).split(separator: " ").map(String.init)
        return packs.filter { p in (tool == nil || p.tool == tool) && words.allSatisfy { p.haystack.contains($0) } }
    }
    /// El nombre de una herramienta para la pantalla («Any chat» → «Cualquier chat»).
    static func toolName(_ t: String) -> String { t == "Any chat" ? T.s("Any chat", "Cualquier chat") : t }
    /// Las herramientas que hay, en el orden en que salen.
    static func tools(_ packs: [GalleryPack]) -> [String] {
        var seen = Set<String>(); return packs.map(\.tool).filter { seen.insert($0).inserted }
    }
    /// Proponer un pack: un correo con su enlace que el usuario lee y envía. Se revisa a mano antes de entrar.
    static func proposal(_ pack: KeyPack, by: String = "") -> URL? {
        let subject = "Agent Bar pack: \(pack.name)"
        let body = """
        \(T.s("I'd like to propose this pack for the gallery.", "Me gustaría proponer este pack para la galería."))

        \(T.s("Name", "Nombre")): \(pack.name)
        \(T.s("What it's for", "Para qué sirve")):
        \(T.s("Tool", "Herramienta")):
        \(T.s("Signed as", "Firmado como")): \(by)

        \(pack.keys.map { "• \($0.label): «\($0.text)»" }.joined(separator: "\n"))

        \(pack.shareURL)
        """
        var c = URLComponents(); c.scheme = "mailto"; c.path = contact
        c.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        return c.url
    }
}

// MARK: equipo

/// El pack de un equipo: lo publica su responsable (un archivo en una carpeta compartida o una URL) y cada Mac del
/// equipo lo sigue: sus teclas, el vocabulario (nombres de clientes, productos, proyectos) y un mensaje corto.
struct TeamPack: Codable, Equatable {
    struct Key: Codable, Equatable {
        var label: String
        var text: String
        var icon: String?
        var enter: Bool?
        var apps: [String]?
        var hold: String?
    }
    var agentbar_team: Int
    var name: String
    var updated: String?
    var message: String?
    var keys: [Key]
    var vocabulary: [String]?

    var words: [String] { vocabulary ?? [] }
}

enum Team {
    static let maxKeys = 24, maxWords = 200, maxBytes = 200_000

    /// Lee y comprueba el archivo del equipo. Nada raro entra: textos cortos, ≤24 teclas, ≤200 palabras.
    static func parse(_ data: Data) -> TeamPack? {
        guard data.count <= maxBytes, var t = try? JSONDecoder().decode(TeamPack.self, from: data), t.agentbar_team == 1 else { return nil }
        t.name = t.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.name.isEmpty, t.name.count <= 40, t.keys.count <= maxKeys, (t.message ?? "").count <= 280 else { return nil }
        for k in t.keys {
            guard !k.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, k.text.count <= 2000, k.label.count <= 24,
                  (k.icon ?? "").count <= 60, (k.hold ?? "").count <= 2000, (k.apps ?? []).count <= 20 else { return nil }
        }
        var seen = Set<String>()
        t.vocabulary = t.words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 60 && !$0.contains("<") && seen.insert($0.lowercased()).inserted }
            .prefix(maxWords).map { $0 }
        guard !t.keys.isEmpty || !t.words.isEmpty else { return nil }
        return t
    }

    /// De lo que pega el usuario a una dirección que se puede descargar. Solo https o un archivo; los enlaces de
    /// compartir de Dropbox, Google Drive y GitHub se cambian por su descarga directa.
    static func source(_ raw: String) -> URL? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("/") || s.hasPrefix("~") { return URL(fileURLWithPath: (s as NSString).expandingTildeInPath) }
        guard var c = URLComponents(string: s), let scheme = c.scheme?.lowercased() else { return nil }
        if scheme == "file" { return c.url }
        guard scheme == "https", let host = c.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasSuffix("dropbox.com") {
            var q = (c.queryItems ?? []).filter { $0.name != "dl" }; q.append(URLQueryItem(name: "dl", value: "1")); c.queryItems = q
        } else if host == "drive.google.com", let r = c.path.range(of: "/file/d/") {
            let id = c.path[r.upperBound...].split(separator: "/").first.map(String.init) ?? ""
            if !id.isEmpty { return URL(string: "https://drive.google.com/uc?export=download&id=\(id)") }
        } else if host == "github.com", c.path.contains("/blob/") {
            c.host = "raw.githubusercontent.com"; c.path = c.path.replacingOccurrences(of: "/blob/", with: "/")
        } else if host == "gist.github.com", !c.path.hasSuffix("/raw") {
            c.host = "gist.githubusercontent.com"; c.path += "/raw"
        }
        return c.url
    }

    /// Pone las teclas del equipo en la barra: quita las del equipo anterior y añade las nuevas detrás de las tuyas.
    /// Una tecla del equipo que ya estaba (misma etiqueta) conserva su atajo, para que ⌃⌥N no cambie en cada actualización.
    static func merge(_ keys: [DeskKey], _ team: TeamPack) -> [DeskKey] {
        let mine = keys.filter { $0.team.isEmpty }, old = keys.filter { !$0.team.isEmpty }
        var used = Set(mine.compactMap(\.hotkey))
        var out = mine
        let newKeys = team.keys
        // primero los atajos que ya tenían, luego los libres
        var hotkeys: [Int?] = newKeys.map { k in
            guard let h = old.first(where: { $0.label == k.label })?.hotkey, !used.contains(h) else { return nil }
            used.insert(h); return h
        }
        for i in hotkeys.indices where hotkeys[i] == nil {
            if let f = (1...9).first(where: { !used.contains($0) }) { used.insert(f); hotkeys[i] = f }
        }
        for (i, k) in newKeys.enumerated() {
            let prev = old.first { $0.label == k.label }
            var d = DeskKey(id: prev?.id ?? UUID(), label: k.label.isEmpty ? String(k.text.prefix(16)) : k.label, text: k.text,
                            hotkey: hotkeys[i], sendEnter: k.enter ?? true, icon: (k.icon ?? "").isEmpty ? "person.2" : k.icon!, group: team.name)
            d.apps = k.apps ?? []; d.hold = k.hold ?? ""; d.team = team.name
            out.append(d)
        }
        return out
    }
    /// Quita las teclas del equipo (al salir de él).
    static func strip(_ keys: [DeskKey]) -> [DeskKey] { keys.filter { $0.team.isEmpty } }

    /// Qué ha cambiado, para la nota de la barra: «2 teclas nuevas, 1 cambiada».
    static func changes(old: [DeskKey], new: TeamPack) -> (added: Int, changed: Int, removed: Int) {
        let before = Dictionary(old.filter { !$0.team.isEmpty }.map { ($0.label, $0.text) }, uniquingKeysWith: { a, _ in a })
        let after = Dictionary(new.keys.map { ($0.label, $0.text) }, uniquingKeysWith: { a, _ in a })
        let added = after.keys.filter { before[$0] == nil }.count
        let changed = after.filter { before[$0.key] != nil && before[$0.key] != $0.value }.count
        let removed = before.keys.filter { after[$0] == nil }.count
        return (added, changed, removed)
    }
    static func changeNote(_ c: (added: Int, changed: Int, removed: Int), team: String) -> String? {
        var parts: [String] = []
        if c.added > 0 { parts.append(c.added == 1 ? T.s("1 new key", "1 tecla nueva") : T.s("\(c.added) new keys", "\(c.added) teclas nuevas")) }
        if c.changed > 0 { parts.append(c.changed == 1 ? T.s("1 changed", "1 cambiada") : T.s("\(c.changed) changed", "\(c.changed) cambiadas")) }
        if c.removed > 0 { parts.append(c.removed == 1 ? T.s("1 removed", "1 quitada") : T.s("\(c.removed) removed", "\(c.removed) quitadas")) }
        return parts.isEmpty ? nil : "\(team): " + parts.joined(separator: ", ")
    }

    /// El archivo que publica el responsable: sus teclas (no las de otro equipo) y su vocabulario.
    static func export(name: String, keys: [DeskKey], vocabulary: [String], message: String = "", now: Date = Date()) -> Data {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
        let t = TeamPack(agentbar_team: 1, name: String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)), updated: f.string(from: now),
                         message: message.isEmpty ? nil : String(message.prefix(280)),
                         keys: keys.filter { $0.team.isEmpty }.prefix(maxKeys).map {
                             TeamPack.Key(label: String($0.label.prefix(24)), text: String($0.text.prefix(2000)), icon: $0.icon, enter: $0.sendEnter,
                                          apps: $0.apps.isEmpty ? nil : $0.apps, hold: $0.hold.isEmpty ? nil : $0.hold)
                         },
                         vocabulary: Array(vocabulary.prefix(maxWords)))
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? e.encode(t)) ?? Data()
    }

    /// El enlace para que otro se una: la página de la web abre agentdeck://team?url=… (y ofrece la descarga).
    static func joinLink(_ source: URL) -> String? {
        guard source.scheme == "https" else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return "https://getagentbar.com/team/#" + (source.absoluteString.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
    }
}

// MARK: invitaciones

/// Invitar con el programa de afiliados de Lemon Squeezy: cada usuario se apunta como afiliado de la tienda, recibe su
/// código y sus enlaces lo llevan (getagentbar.com/?aff=CÓDIGO). Lemon Squeezy cuenta las compras y paga la comisión
/// que fije Diego; la app solo guarda el código y lo pone en los enlaces que comparte.
enum Invite {
    /// El subdominio de la tienda de Lemon Squeezy (xxx.lemonsqueezy.com); vacío mientras no exista: sin alta de afiliados.
    static let storeSlug = ""
    static var signup: URL? { storeSlug.isEmpty ? nil : URL(string: "https://\(storeSlug).lemonsqueezy.com/affiliates") }

    /// Un código de afiliado limpio (lo que va detrás de aff=). Acepta el enlace entero pegado.
    static func clean(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = s.range(of: "aff=") { s = String(s[r.upperBound...]) }
        s = String(s.prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        return s.count <= 40 ? s : ""
    }
    /// La invitación: la web con el código y, si se pasa, un pack.
    static func link(code: String, pack: KeyPack? = nil) -> String {
        let c = clean(code), q = c.isEmpty ? "" : "?aff=\(c)"
        if let pack { return "https://getagentbar.com/p/\(q)#\(pack.encoded)" }
        return "https://getagentbar.com/\(q)"
    }
    /// El texto que se comparte.
    static func message(code: String, pack: KeyPack?) -> String {
        T.s("I use Agent Bar to talk to my AI agents with my voice and one-click keys. It's free for Mac: ",
            "Uso Agent Bar para hablar con mis agentes de IA con la voz y con teclas de un clic. Es gratis para Mac: ") + link(code: code, pack: pack)
    }
}
