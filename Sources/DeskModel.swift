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
    "doc.text.magnifyingglass", "hammer", "paperplane", "flag", "lightbulb", "scissors", "pencil", "text.quote", "sparkles",
]

/// Cómo se presenta el Desk: una barra pegada al borde inferior (dock) o una tarjeta flotante.
enum DeskMode: String, Codable, CaseIterable {
    case dock, card
}

/// Las teclas, guardadas en ~/Library/Application Support/Agent Desk/keys.json; el modo en UserDefaults.
final class DeskStore: ObservableObject {
    @Published var keys: [DeskKey] { didSet { save() } }
    @Published var mode: DeskMode { didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode") } }
    @Published var lastSent: String = ""
    @Published var editing: Bool = false
    /// Dictado: escuchando, texto parcial y nivel del micro (para el icono).
    @Published var listening: Bool = false
    @Published var partial: String = ""
    @Published var level: Float = 0
    @Published var dictationNote: String = ""
    private var dictation: Dictation?

    static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Agent Desk", isDirectory: true)
    }()
    static let file = folder.appendingPathComponent("keys.json")

    static let defaults: [DeskKey] = [
        DeskKey(label: "Continúa", text: "continúa", hotkey: 1, icon: "arrow.right.circle", group: "flujo"),
        DeskKey(label: "Siguiente", text: "siguiente", hotkey: 2, icon: "forward.end", group: "flujo"),
        DeskKey(label: "Dale caña", text: "dale caña", hotkey: 3, icon: "bolt.fill", group: "flujo"),
        DeskKey(label: "Hazlo", text: "hazlo", hotkey: 4, icon: "checkmark.circle", group: "flujo"),
        DeskKey(label: "Me gusta", text: "me gusta, continúa", hotkey: 5, icon: "hand.thumbsup", group: "control"),
        DeskKey(label: "Preview", text: "enséñame una preview antes de seguir", hotkey: 6, icon: "eye", group: "control"),
        DeskKey(label: "Resumen", text: "resumen corto: dónde estamos y qué falta", hotkey: 7, icon: "list.bullet.rectangle", group: "control"),
        DeskKey(label: "Para", text: "para, no sigas con eso", hotkey: 8, icon: "stop.circle", group: "control"),
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
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: DeskStore.folder, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(keys).write(to: DeskStore.file, options: .atomic)
        } catch {
            NSLog("Agent Desk: no se pudo guardar keys.json: \(error)")
        }
    }

    func press(_ key: DeskKey) {
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

    /// Dictar: una pulsación empieza a escuchar, otra para y envía lo oído al chat como una tecla más.
    @MainActor func toggleDictation() {
        if dictation == nil {
            let d = Dictation()
            d.onLevel = { [weak self] l in self?.level = l }
            d.onEvent = { [weak self] state, text, reason in
                guard let self = self else { return }
                switch state {
                case .listening: self.listening = true; self.partial = ""; self.dictationNote = ""
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
                    self.dictationNote = reason == "mic-denied" ? "Permite el micrófono" : reason == "speech-denied" ? "Permite el reconocimiento de voz" : "Dictado no disponible"
                }
            }
            dictation = d
        }
        if listening { dictation?.stop() } else { dictation?.start() }
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
