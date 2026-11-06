import AppKit
import Foundation

/// Una tecla del Desk: lo que se ve (label) y lo que se escribe en el chat (text).
struct DeskKey: Codable, Identifiable, Equatable {
    init(id: UUID = UUID(), label: String, text: String, hotkey: Int? = nil, sendEnter: Bool = true, icon: String = "circle", group: String = "mías") {
        self.id = id; self.label = label; self.text = text; self.hotkey = hotkey; self.sendEnter = sendEnter; self.icon = icon; self.group = group
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        label = try c.decode(String.self, forKey: .label)
        text = try c.decode(String.self, forKey: .text)
        hotkey = try c.decodeIfPresent(Int.self, forKey: .hotkey)
        sendEnter = try c.decodeIfPresent(Bool.self, forKey: .sendEnter) ?? true
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "circle"
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? "mías"
    }
    var id: UUID = UUID()
    var label: String
    var text: String
    /// Atajo global ⌃⌥ + dígito (1…9); nil = sin atajo.
    var hotkey: Int?
    /// Pulsar Intro después de escribir (enviar el mensaje). Casi siempre sí.
    var sendEnter: Bool = true
    /// Símbolo SF del icono (p. ej. "arrow.right.circle").
    var icon: String = "circle"
    /// Grupo en la barra: las teclas del mismo grupo van juntas, separadas por una línea.
    var group: String = "mías"
}

/// Iconos que ofrece el editor (nombres de SF Symbols).
let deskIcons: [String] = [
    "arrow.right.circle", "forward.end", "bolt.fill", "checkmark.circle", "hand.thumbsup", "eye",
    "list.bullet.rectangle", "stop.circle", "arrow.counterclockwise", "questionmark.circle", "wand.and.stars",
    "doc.text.magnifyingglass", "hammer", "testtube.2", "wrench.and.screwdriver", "arrow.uturn.backward.circle", "paperplane", "flag", "lightbulb", "scissors", "pencil", "text.quote", "sparkles",
]

/// Cómo se presenta el Desk: una barra pegada al borde inferior (dock) o una tarjeta flotante.
enum DeskMode: String, Codable, CaseIterable {
    case dock, card
}

/// El aspecto de la barra: el de siempre, cristal translúcido (como Alfred) o metal con la tecla naranja (como el Pad físico).
enum BarStyle: String, Codable, CaseIterable {
    case classic, glass, metal
    var title: String {
        switch self {
        case .classic: return T.s("Classic", "Clásico")
        case .glass: return T.s("Glass", "Cristal")
        case .metal: return T.s("Metal", "Metal")
        }
    }
}

/// Las teclas, guardadas en ~/Library/Application Support/Agent Deck/keys.json; el modo en UserDefaults.
final class DeskStore: ObservableObject {
    @Published var keys: [DeskKey] { didSet { save() } }
    @Published var mode: DeskMode { didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode") } }
    @Published var style: BarStyle { didSet { UserDefaults.standard.set(style.rawValue, forKey: "style") } }
    @Published var lastSent: String = ""
    @Published var editing: Bool = false
    /// Dictado: escuchando, texto parcial y nivel del micro (para el icono).
    @Published var listening: Bool = false
    @Published var partial: String = ""
    @Published var level: Float = 0
    @Published var dictationNote: String = ""
    private var dictation: Dictation?
    /// Plegada a un orbe (el copiloto) o desplegada. Se recuerda entre sesiones.
    @Published var collapsed: Bool { didSet { UserDefaults.standard.set(collapsed, forKey: "collapsed") } }
    /// Cuenta pulsaciones para disparar la animación de la última tecla pulsada.
    @Published var lastPressedId: UUID? = nil
    @Published var pulse: Int = 0

    static let folder: URL = {
        // pruebas y capturas: una carpeta aparte, nunca las teclas de verdad
        if let test = ProcessInfo.processInfo.environment["AGENT_DECK_FOLDER"], !test.isEmpty { return URL(fileURLWithPath: test, isDirectory: true) }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let new = base.appendingPathComponent("Agent Deck", isDirectory: true)
        let old = base.appendingPathComponent("Agent Desk", isDirectory: true)
        if !FileManager.default.fileExists(atPath: new.path), FileManager.default.fileExists(atPath: old.path) {
            try? FileManager.default.moveItem(at: old, to: new)
        }
        return new
    }()
    static let file = folder.appendingPathComponent("keys.json")

    /// Las teclas de fábrica: seis cosas distintas que se le dicen a un agente (como en getagentbar.com).
    static let defaults: [DeskKey] = T.es ? [
        DeskKey(label: "Continúa", text: "continúa", hotkey: 1, icon: "arrow.right.circle", group: "flujo"),
        DeskKey(label: "Pruébalo", text: "pasa los tests y dime qué falla", hotkey: 2, icon: "testtube.2", group: "flujo"),
        DeskKey(label: "Arréglalo", text: "arregla esos errores y sigue", hotkey: 3, icon: "wrench.and.screwdriver", group: "flujo"),
        DeskKey(label: "Preview", text: "enséñame una preview antes de seguir", hotkey: 4, icon: "eye", group: "control"),
        DeskKey(label: "Deshaz", text: "deshaz el último cambio", hotkey: 5, icon: "arrow.uturn.backward.circle", group: "control"),
        DeskKey(label: "Para", text: "para, no sigas con eso", hotkey: 6, icon: "stop.circle", group: "control"),
    ] : [
        DeskKey(label: "Continue", text: "continue", hotkey: 1, icon: "arrow.right.circle", group: "flujo"),
        DeskKey(label: "Test it", text: "run the tests and tell me what fails", hotkey: 2, icon: "testtube.2", group: "flujo"),
        DeskKey(label: "Fix it", text: "fix those errors, then continue", hotkey: 3, icon: "wrench.and.screwdriver", group: "flujo"),
        DeskKey(label: "Preview", text: "show me a preview before you go on", hotkey: 4, icon: "eye", group: "control"),
        DeskKey(label: "Undo", text: "undo that last change", hotkey: 5, icon: "arrow.uturn.backward.circle", group: "control"),
        DeskKey(label: "Stop", text: "stop, don't go on with that", hotkey: 6, icon: "stop.circle", group: "control"),
    ]

    init() {
        if let data = try? Data(contentsOf: DeskStore.file),
           let saved = try? JSONDecoder().decode([DeskKey].self, from: data), !saved.isEmpty {
            // archivos de la primera versión (sin icono ni grupo): se completan desde las teclas de fábrica
            keys = saved.map { k in
                guard k.icon == "circle", let d = DeskStore.defaults.first(where: { $0.text == k.text }) else { return k }
                var m = k; m.icon = d.icon; m.group = d.group; return m
            }
        } else {
            keys = DeskStore.defaults
        }
        mode = DeskMode(rawValue: UserDefaults.standard.string(forKey: "mode") ?? "") ?? .dock
        collapsed = UserDefaults.standard.bool(forKey: "collapsed")
        style = BarStyle(rawValue: UserDefaults.standard.string(forKey: "style") ?? "") ?? .glass
    }

    static func haptic(_ kind: NSHapticFeedbackManager.FeedbackPattern = .alignment) {
        NSHapticFeedbackManager.defaultPerformer.perform(kind, performanceTime: .now)
    }

    func toggleCollapsed() {
        DeskStore.haptic(.levelChange)
        collapsed.toggle()
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: DeskStore.folder, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(keys).write(to: DeskStore.file, options: .atomic)
        } catch {
            NSLog("Agent Deck: no se pudo guardar keys.json: \(error)")
        }
    }

    func press(_ key: DeskKey) {
        DeskStore.haptic()
        lastPressedId = key.id
        pulse += 1
        Sender.send(key.text, enter: key.sendEnter)
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        lastSent = "\(f.string(from: Date())) · \(key.text)"
    }

    func press(hotkey: Int) {
        if let key = keys.first(where: { $0.hotkey == hotkey }) { press(key) }
    }

    func add(_ draft: DeskKey) {
        let used = Set(keys.compactMap { $0.hotkey })
        let free = (1...9).first { !used.contains($0) }
        var key = draft
        key.id = UUID()
        key.hotkey = free
        key.group = "mías"
        let clean = key.label.trimmingCharacters(in: .whitespaces)
        if clean.isEmpty { key.label = String(key.text.prefix(16)) }
        keys.append(key)
    }

    /// Grupos en orden de aparición, cada uno con sus teclas.
    var groups: [(name: String, keys: [DeskKey])] {
        var order: [String] = []
        var byName: [String: [DeskKey]] = [:]
        for k in keys {
            if byName[k.group] == nil { order.append(k.group); byName[k.group] = [] }
            byName[k.group]!.append(k)
        }
        return order.map { ($0, byName[$0]!) }
    }

    /// Mantener Fn: escucha mientras está pulsada (fnHeld) y, al soltar, envía. Si el permiso tarda y Fn
    /// ya se ha soltado cuando empieza a escuchar, para enseguida y envía lo poco que haya.
    private var fnHeld = false
    /// La escucha la empezó Fn (no el botón ni ⌃⌥M).
    private var fnSession = false

    @MainActor func holdToTalk(_ down: Bool) {
        fnHeld = down
        if down { fnSession = true }
        let d = ensureDictation()
        if down { if !listening { d.start() } } else if listening { d.stop() }
    }

    @MainActor func cancelDictation() { fnHeld = false; dictation?.cancel() }

    /// Dictar: una pulsación empieza a escuchar, otra para y envía lo oído al chat como una tecla más.
    @MainActor func toggleDictation() {
        fnSession = false
        let d = ensureDictation()
        if listening { d.stop() } else { d.start() }
    }

    @MainActor private func ensureDictation() -> Dictation {
        if dictation == nil {
            let d = Dictation()
            d.onLevel = { [weak self] l in self?.level = l }
            d.onEvent = { [weak self] state, text, reason in
                guard let self = self else { return }
                switch state {
                case .listening:
                    self.listening = true; self.partial = ""; self.dictationNote = ""
                    if !self.fnHeld, self.fnSession { self.dictation?.stop() }
                case .partial: self.partial = text ?? ""
                case .final:
                    self.listening = false; self.partial = ""
                    if let t = text, !t.isEmpty {
                        Sender.send(t, enter: true)
                        let f = DateFormatter(); f.dateFormat = "HH:mm"
                        self.lastSent = "\(f.string(from: Date())) · \(t)"
                    }
                case .idle: self.listening = false; self.partial = ""
                case .unavailable:
                    self.listening = false; self.partial = ""
                    self.dictationNote = reason == "mic-denied" ? T.s("Allow the microphone", "Permite el micrófono") : reason == "speech-denied" ? T.s("Allow speech recognition", "Permite el reconocimiento de voz") : T.s("Dictation unavailable", "Dictado no disponible")
                }
            }
            dictation = d
        }
        return dictation!
    }

    /// Última nota de voz transcrita por el inbox de Telegram (la escribe inbox-telegram.py).
    static let lastVoice = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/diego-inbox/last-voice.txt")

    /// Tecla Inbox: manda al chat la última transcripción y la marca como usada.
    func sendInbox() {
        DeskStore.haptic()
        guard let text = try? String(contentsOf: DeskStore.lastVoice, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            dictationNote = T.s("Inbox empty", "Inbox vacío")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.dictationNote = "" }
            return
        }
        Sender.send(text, enter: true)
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        lastSent = "\(f.string(from: Date())) · \(text)"
        try? "".write(to: DeskStore.lastVoice, atomically: true, encoding: .utf8)
    }

    /// Lo pone el AppDelegate: abre el menú de la app desde el engranaje de la barra.
    var showMenu: (() -> Void)?
    /// Lo pone el AppDelegate: esconde la barra (⌃⌥D la devuelve).
    var hide: (() -> Void)?

    func update(_ key: DeskKey) {
        if let i = keys.firstIndex(where: { $0.id == key.id }) { keys[i] = key }
    }

    func remove(_ key: DeskKey) {
        keys.removeAll { $0.id == key.id }
    }

    func restoreDefaults() { keys = DeskStore.defaults }
}
