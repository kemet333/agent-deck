import AppKit
import Foundation
import Combine

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

/// Las teclas, guardadas en ~/Library/Application Support/Agent Deck/keys.json; el modo en UserDefaults.
@MainActor
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
    @Published var voiceWorking = false
    @Published var voiceNeedsAttention = false
    var voiceExpanded: Bool { listening || voiceWorking || voiceNeedsAttention }
    private var voiceBag = Set<AnyCancellable>()
    lazy var flows = FlowController()
    var showFlows: (() -> Void)?
    lazy var voice: VoiceController = {
        let controller = VoiceController(storage: VoiceStorage(folder: Self.folder))
        controller.onDelivered = { [weak self] text in
            let f=DateFormatter();f.dateFormat="HH:mm";self?.lastSent="\(f.string(from:Date())) · \(text)"
        }
        controller.objectWillChange.sink { [weak self, weak controller] in
            DispatchQueue.main.async {
                guard let self, let controller else { return }
                self.listening=controller.phase == .listening
                self.voiceWorking=controller.working
                self.voiceNeedsAttention=controller.phase == .draft || controller.phase == .failed
                self.partial=controller.phase == .listening ? controller.partial : controller.label
                self.level=controller.level
                self.dictationNote=controller.phase == .idle ? "" : controller.label
            }
        }.store(in:&voiceBag)
        return controller
    }()
    /// Plegada a un orbe (el copiloto) o desplegada. Se recuerda entre sesiones.
    @Published var collapsed: Bool { didSet { UserDefaults.standard.set(collapsed, forKey: "collapsed") } }
    /// Cuenta pulsaciones para disparar la animación de la última tecla pulsada.
    @Published var lastPressedId: UUID? = nil
    @Published var pulse: Int = 0

    static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let new = base.appendingPathComponent("Agent Deck", isDirectory: true)
        let old = base.appendingPathComponent("Agent Desk", isDirectory: true)
        if !FileManager.default.fileExists(atPath: new.path), FileManager.default.fileExists(atPath: old.path) {
            try? FileManager.default.moveItem(at: old, to: new)
        }
        return new
    }()
    static let file = folder.appendingPathComponent("keys.json")

    static let defaults: [DeskKey] = T.es ? [
        DeskKey(label: "Continúa", text: "continúa", hotkey: 1, icon: "arrow.right.circle", group: "flujo"),
        DeskKey(label: "Siguiente", text: "siguiente", hotkey: 2, icon: "forward.end", group: "flujo"),
        DeskKey(label: "Dale caña", text: "dale caña", hotkey: 3, icon: "bolt.fill", group: "flujo"),
        DeskKey(label: "Hazlo", text: "hazlo", hotkey: 4, icon: "checkmark.circle", group: "flujo"),
        DeskKey(label: "Me gusta", text: "me gusta, continúa", hotkey: 5, icon: "hand.thumbsup", group: "control"),
        DeskKey(label: "Preview", text: "enséñame una preview antes de seguir", hotkey: 6, icon: "eye", group: "control"),
        DeskKey(label: "Resumen", text: "resumen corto: dónde estamos y qué falta", hotkey: 7, icon: "list.bullet.rectangle", group: "control"),
        DeskKey(label: "Para", text: "para, no sigas con eso", hotkey: 8, icon: "stop.circle", group: "control"),
    ] : [
        DeskKey(label: "Continue", text: "continue", hotkey: 1, icon: "arrow.right.circle", group: "flujo"),
        DeskKey(label: "Next", text: "next", hotkey: 2, icon: "forward.end", group: "flujo"),
        DeskKey(label: "Go hard", text: "go hard", hotkey: 3, icon: "bolt.fill", group: "flujo"),
        DeskKey(label: "Do it", text: "do it", hotkey: 4, icon: "checkmark.circle", group: "flujo"),
        DeskKey(label: "I like it", text: "I like it, continue", hotkey: 5, icon: "hand.thumbsup", group: "control"),
        DeskKey(label: "Preview", text: "show me a preview before you go on", hotkey: 6, icon: "eye", group: "control"),
        DeskKey(label: "Recap", text: "short recap: where are we and what's left", hotkey: 7, icon: "list.bullet.rectangle", group: "control"),
        DeskKey(label: "Stop", text: "stop, don't go on with that", hotkey: 8, icon: "stop.circle", group: "control"),
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
        Sender.send(key.text, enter: key.sendEnter) { [weak self] result in
            switch result { case .success: let f=DateFormatter();f.dateFormat="HH:mm";self?.lastSent="\(f.string(from:Date())) · \(key.text)"
            case .failure(let error): self?.voice.note(error.localizedDescription) }
        }
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

    /// Same entry point for the bar, menu, URL scheme and the existing ⌃⌥M shortcut.
    @MainActor func toggleDictation() { voice.toggle() }

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
        Sender.send(text, enter: true) { [weak self] result in
            if case .success = result {
                let f=DateFormatter();f.dateFormat="HH:mm";self?.lastSent="\(f.string(from:Date())) · \(text)"
                // Do not erase a newer inbox note that arrived while inserting the previous one.
                if (try? String(contentsOf:Self.lastVoice,encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines)) == text { try? "".write(to:Self.lastVoice,atomically:true,encoding:.utf8) }
            } else if case .failure(let error) = result { self?.voice.note(error.localizedDescription) }
        }
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
