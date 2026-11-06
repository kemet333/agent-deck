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

/// Un aviso de un agente: «Claude Code ha terminado · Diego-OS» o «Claude Code te espera».
struct AgentAlert: Equatable {
    let app: String
    let ask: Bool
    let place: String
    /// Lo último que dijo el agente (o lo que pide), para leerlo sin cambiar de ventana.
    var message: String = ""
    /// La app donde corre esa sesión (bundle id), para contestar allí.
    var host: String = ""
    let id = UUID()
    var title: String { ask ? T.s("\(app) is waiting for you", "\(app) te espera") : T.s("\(app) is done", "\(app) ha terminado") }
}

/// Las teclas, guardadas en ~/Library/Application Support/Agent Deck/keys.json; el modo en UserDefaults.
@MainActor
final class DeskStore: ObservableObject {
    @Published var keys: [DeskKey] { didSet { save() } }
    @Published var mode: DeskMode { didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode") } }
    @Published var style: BarStyle { didSet { UserDefaults.standard.set(style.rawValue, forKey: "style") } }
    @Published var lastSent: String = ""
    /// Aviso de un agente: ha terminado o te espera. Lo trae agentdeck://alert (ganchos de Claude Code u otros).
    @Published var alert: AgentAlert?
    @Published var editing: Bool = false
    /// Dictado: escuchando, texto parcial y nivel del micro (para el icono).
    @Published var listening: Bool = false
    @Published var partial: String = ""
    @Published var level: Float = 0
    @Published var dictationNote: String = ""
    @Published var voiceWorking = false
    @Published var voiceNeedsAttention = false
    var voiceExpanded: Bool { listening || voiceWorking || voiceNeedsAttention || !flash.isEmpty }
    /// Un aviso de un instante en el orbe o el micro, como «Listo en 0,4 s».
    @Published var flash: String = ""
    private var voiceBag = Set<AnyCancellable>()
    lazy var flows = FlowController()
    var showFlows: (() -> Void)?
    lazy var voice: VoiceController = {
        let controller = VoiceController(storage: VoiceStorage(folder: Self.folder))
        controller.onDelivered = { [weak self, weak controller] text in
            let f=DateFormatter();f.dateFormat="HH:mm";self?.lastSent="\(f.string(from:Date())) · \(text)"
            if let l=controller?.lastLatency {
                let n=String(format:T.s("Done in %.1f s","Listo en %.1f s"),l).replacingOccurrences(of:".",with:T.es ? "," : ".")
                self?.flash=n
                DispatchQueue.main.asyncAfter(deadline:.now()+2.2){ if self?.flash==n { self?.flash="" } }
            }
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

    /// Enciende el aviso con un sonido; se va al tocarlo o a los 25 s (salvo que llegue otro).
    func raiseAlert(app: String, ask: Bool, place: String, message: String = "", host: String = "") {
        let a = AgentAlert(app: app.isEmpty ? T.s("Your agent", "Tu agente") : String(app.prefix(40)), ask: ask, place: String(place.prefix(40)),
                           message: String(message.prefix(4000)), host: String(host.prefix(120)))
        alert = a
        NSSound(named: ask ? "Ping" : "Glass")?.play()
        DeskStore.haptic(.levelChange)
        // sin mensaje se va solo; con mensaje se queda hasta que contestes o lo cierres
        if a.message.isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in if self?.alert == a { self?.alert = nil } } }
    }

    /// Contestar desde el aviso: trae delante la app de esa sesión, escribe la respuesta y la envía.
    func reply(_ text: String, to a: AgentAlert) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        alert = nil
        let app = a.host.isEmpty ? nil : NSRunningApplication.runningApplications(withBundleIdentifier: a.host).first
        app?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + (app == nil ? 0.05 : 0.35)) {
            Sender.send(t, enter: true)
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            self.lastSent = "\(f.string(from: Date())) · \(t)"
        }
    }

    /// Lo que dejó un gancho de Claude Code en Application Support/Agent Deck/hooks/<n>.json: la última respuesta
    /// del agente (de su transcripción) o el aviso que manda. Se lee una vez y se borra.
    static func hookMessage(file name: String) -> String {
        guard name.range(of: "^[0-9]+-[0-9]+\\.json$", options: .regularExpression) != nil else { return "" }
        let url = folder.appendingPathComponent("hooks").appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let data = try? Data(contentsOf: url), data.count < 1_000_000,
              let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return "" }
        if let m = j["last_assistant_message"] as? String, !m.isEmpty { return m }
        if let m = j["message"] as? String, !m.isEmpty, j["hook_event_name"] as? String == "Notification" { return m }
        // la transcripción de Claude Code: solo dentro de ~/.claude, y solo el final del archivo
        guard let tp = j["transcript_path"] as? String, tp.hasSuffix(".jsonl"),
              tp.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude").path),
              let h = FileHandle(forReadingAtPath: tp) else { return "" }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > 2_000_000 ? size - 2_000_000 : 0)
        guard let tail = try? h.readToEnd(), let text = String(data: tail, encoding: .utf8) else { return "" }
        for line in text.split(separator: "\n").reversed() {
            guard let o = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any], o["type"] as? String == "assistant",
                  let msg = o["message"] as? [String: Any], let parts = msg["content"] as? [[String: Any]] else { continue }
            let t = parts.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return ""
    }
}
