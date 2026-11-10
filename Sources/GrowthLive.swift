import AppKit
import UniformTypeIdentifiers
import Foundation

/// La galería de packs: se baja de getagentbar.com/packs/packs.json, se guarda una copia y, sin conexión, se usa esa
/// copia o la que va dentro de la app. Así se añaden packs sin sacar una versión nueva.
@MainActor
final class GalleryStore: ObservableObject {
    static let shared = GalleryStore()
    @Published private(set) var packs: [GalleryPack] = []
    @Published private(set) var loading = false
    @Published private(set) var online = false
    private var fetched = Date.distantPast
    private var cache: URL { Autopilot.folder.appendingPathComponent("gallery.json") }

    init() {
        let local = (try? Data(contentsOf: cache)).map(Gallery.parse) ?? []
        packs = local.isEmpty ? Self.bundled : local
        // sin copia ni catálogo dentro (una compilación de prueba): los packs de siempre
        if packs.isEmpty {
            packs = KeyPack.builtIn.enumerated().map { i, p in
                GalleryPack(id: "builtin-\(i)", name: p.name, by: "PROMPTED", tool: p.name, about: "", keys: p.keys, es: nil)
            }
        }
    }
    /// La copia que viaja dentro de la app (la misma packs.json de la web, copiada al compilar).
    static var bundled: [GalleryPack] {
        Bundle.main.url(forResource: "packs", withExtension: "json").flatMap { try? Data(contentsOf: $0) }.map(Gallery.parse) ?? []
    }

    /// Como mucho una vez cada 6 h (o cuando se pide).
    func refresh(force: Bool = false) {
        guard !loading, force || Date().timeIntervalSince(fetched) > 6 * 3600 else { return }
        loading = true
        var req = URLRequest(url: Gallery.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        req.setValue("AgentBar/\(Updater.current)", forHTTPHeaderField: "User-Agent")
        Task {
            let data = try? await URLSession.shared.data(for: req).0
            let fresh = data.map(Gallery.parse) ?? []
            loading = false; fetched = Date()
            guard let data, !fresh.isEmpty else { online = false; return }
            online = true; packs = fresh
            try? FileManager.default.createDirectory(at: Autopilot.folder, withIntermediateDirectories: true)
            try? data.write(to: cache, options: .atomic)
        }
    }
}

/// El equipo que sigue este Mac: de dónde se baja su pack, lo último que llegó y cuándo. Se mira al abrir la app y cada
/// 12 h; si el responsable cambia el archivo, las teclas del equipo se cambian solas (las tuyas no se tocan).
@MainActor
final class TeamSync: ObservableObject {
    static let shared = TeamSync()
    @Published private(set) var source: URL?
    @Published private(set) var team: TeamPack?
    @Published private(set) var checked: Date?
    @Published private(set) var problem = ""
    @Published private(set) var working = false
    private var timer: Timer?
    private var cache: URL { Autopilot.folder.appendingPathComponent("team.json") }

    init() {
        source = UserDefaults.standard.string(forKey: "teamSource").flatMap(URL.init(string:))
        checked = UserDefaults.standard.object(forKey: "teamChecked") as? Date
        if source != nil { team = (try? Data(contentsOf: cache)).flatMap(Team.parse) }
    }

    func start() {
        guard timer == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.refreshIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in Task { @MainActor in self?.refreshIfDue() } }
    }
    private func refreshIfDue() {
        guard source != nil, Date().timeIntervalSince(checked ?? .distantPast) > 12 * 3600 else { return }
        Task { await refresh(quiet: true) }
    }

    /// Baja el pack (https o archivo). nil y `problem` si no se puede o no es un pack de equipo.
    func fetch(_ url: URL) async -> TeamPack? {
        let data: Data?
        if url.isFileURL {
            data = try? Data(contentsOf: url)
        } else {
            var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            req.setValue("AgentBar/\(Updater.current)", forHTTPHeaderField: "User-Agent")
            data = try? await URLSession.shared.data(for: req).0
        }
        guard let data else { problem = T.s("Couldn't reach the team file", "No se pudo llegar al archivo del equipo"); return nil }
        guard let t = Team.parse(data) else { problem = T.s("That isn't an Agent Bar team file", "Eso no es un archivo de equipo de Agent Bar"); return nil }
        problem = ""; return t
    }

    /// Unirse: guarda la fuente y pone sus teclas y su vocabulario.
    func join(_ url: URL, _ t: TeamPack) {
        source = url
        UserDefaults.standard.set(url.absoluteString, forKey: "teamSource")
        apply(t, announce: false)
        DeskStore.shared?.flashNote(T.s("You're in «\(t.name)»: \(t.keys.count) keys", "Ya estás en «\(t.name)»: \(t.keys.count) teclas"), for: 4)
    }

    func refresh(quiet: Bool = false) async {
        guard let source, !working else { return }
        working = true; defer { working = false }
        guard let t = await fetch(source) else {
            checked = Date(); UserDefaults.standard.set(checked, forKey: "teamChecked")
            if !quiet { DeskStore.shared?.flashNote(problem, for: 4) }
            return
        }
        apply(t, announce: true)
        if !quiet, t == team { DeskStore.shared?.flashNote(T.s("«\(t.name)» is up to date", "«\(t.name)» está al día"), for: 3) }
    }

    private func apply(_ t: TeamPack, announce: Bool) {
        if let store = DeskStore.shared {
            let note = Team.changeNote(Team.changes(old: store.keys, new: t), team: t.name)
            let merged = Team.merge(store.keys, t)
            if merged != store.keys { store.keys = merged }
            if announce, let note, team != nil { store.flashNote(note, for: 5) }
        }
        team = t
        TeamVocabulary.cached = t.words
        checked = Date(); UserDefaults.standard.set(checked, forKey: "teamChecked")
        try? FileManager.default.createDirectory(at: Autopilot.folder, withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(t) { try? d.write(to: cache, options: .atomic) }
    }

    /// Salir del equipo: sus teclas y su vocabulario se van; las tuyas se quedan.
    func leave() {
        if let store = DeskStore.shared { store.keys = Team.strip(store.keys) }
        source = nil; team = nil; checked = nil; problem = ""
        TeamVocabulary.cached = []
        UserDefaults.standard.removeObject(forKey: "teamSource"); UserDefaults.standard.removeObject(forKey: "teamChecked")
        try? FileManager.default.removeItem(at: cache)
    }

    /// Lo que se ve de la fuente, sin la carpeta personal.
    var sourceLabel: String {
        guard let source else { return "" }
        return source.isFileURL ? source.pathComponents.suffix(2).joined(separator: "/") : (source.host ?? source.absoluteString)
    }

    // MARK: diálogos (los usa la app y Ajustes)

    /// Pregunta antes de unirse, con lo que trae el equipo.
    static func confirmJoin(_ url: URL, _ t: TeamPack) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = T.s("Join the «\(t.name)» team?", "¿Unirte al equipo «\(t.name)»?")
        var lines: [String] = []
        if let m = t.message, !m.isEmpty { lines.append(m); lines.append("") }
        lines.append(T.s("\(t.keys.count) keys and \(t.words.count) words for your voice. Your own keys stay. When the team updates its file, these keys update by themselves.",
                         "\(t.keys.count) teclas y \(t.words.count) palabras para tu voz. Tus teclas se quedan. Cuando el equipo cambie su archivo, estas teclas se cambian solas."))
        lines.append("")
        lines += t.keys.prefix(8).map { "• \($0.label) — «\($0.text.prefix(70))»" }
        if t.keys.count > 8 { lines.append("…") }
        a.informativeText = lines.joined(separator: "\n")
        a.addButton(withTitle: T.s("Join", "Unirme"))
        a.addButton(withTitle: T.s("Cancel", "Cancelar"))
        return a.runModal() == .alertFirstButtonReturn
    }

    /// Unirse desde un enlace o una ruta: baja, enseña y pregunta.
    func offer(_ raw: String) async {
        guard let url = Team.source(raw) else {
            problem = T.s("Paste an https link or choose a file", "Pega un enlace https o elige un archivo")
            DeskStore.shared?.flashNote(problem, for: 4); return
        }
        working = true
        let t = await fetch(url)
        working = false
        guard let t else { DeskStore.shared?.flashNote(problem, for: 4); return }
        if Self.confirmJoin(url, t) { join(url, t) }
    }

    /// Para el responsable: guarda tus teclas y tu vocabulario como archivo de equipo.
    static func exportDialog(keys: [DeskKey], vocabulary: [String]) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = T.s("Create a team file", "Crear un archivo de equipo")
        a.informativeText = T.s("It carries your keys and your voice dictionary. Put it in a shared folder (iCloud Drive, Dropbox, Google Drive) or online, and send your team the link.",
                                "Lleva tus teclas y tu diccionario de voz. Ponlo en una carpeta compartida (iCloud Drive, Dropbox, Google Drive) o en la web y manda el enlace a tu equipo.")
        let name = NSTextField(frame: NSRect(x: 0, y: 30, width: 280, height: 24)); name.placeholderString = T.s("Team name", "Nombre del equipo")
        let msg = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24)); msg.placeholderString = T.s("A short message (optional)", "Un mensaje corto (opcional)")
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 54)); box.addSubview(name); box.addSubview(msg)
        a.accessoryView = box; a.window.initialFirstResponder = name
        a.addButton(withTitle: T.s("Save…", "Guardar…")); a.addButton(withTitle: T.s("Cancel", "Cancelar"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let team = name.stringValue.trimmingCharacters(in: .whitespaces).isEmpty ? T.s("My team", "Mi equipo") : name.stringValue
        let p = NSSavePanel()
        p.nameFieldStringValue = team.replacingOccurrences(of: "/", with: "-") + ".agentbar-team.json"
        p.allowedContentTypes = [.json]
        guard p.runModal() == .OK, let url = p.url else { return }
        do {
            try Team.export(name: team, keys: keys, vocabulary: vocabulary, message: msg.stringValue).write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            let e = NSAlert(); e.messageText = T.s("Couldn't save it", "No se pudo guardar"); e.informativeText = error.localizedDescription; e.runModal()
        }
    }

    /// Elegir el archivo del equipo (de una carpeta compartida).
    func chooseFile() {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSOpenPanel(); p.allowedContentTypes = [.json]; p.canChooseDirectories = false; p.allowsMultipleSelection = false
        p.message = T.s("Choose your team's .agentbar-team.json", "Elige el .agentbar-team.json de tu equipo")
        guard p.runModal() == .OK, let url = p.url else { return }
        Task { await offer(url.path) }
    }
}

/// El código de afiliado del usuario (lo pega una vez; va en sus enlaces de invitación y de packs).
enum InviteLive {
    static var code: String {
        get { UserDefaults.standard.string(forKey: "affiliateCode") ?? "" }
        set { UserDefaults.standard.set(Invite.clean(newValue), forKey: "affiliateCode") }
    }
}
