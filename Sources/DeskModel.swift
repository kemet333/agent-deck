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

/// Los avisos de Claude Code al grupo de WhatsApp «Alfred» de Diego OS, cuando no estás en el Mac. Solo si el puente
/// de WhatsApp de Diego OS está conectado; si no, no hace nada. Lo que contestes allí lo devuelve el puente al gancho
/// de esa misma conversación (ab:<archivo>).
enum WhatsAppRelay {
    static var folder: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.diegokmt.diegolifeos/Workspace/whatsapp") }
    static var connected: Bool {
        guard UserDefaults.standard.object(forKey: "whatsappAlerts") as? Bool ?? true,
              let d = try? Data(contentsOf: folder.appendingPathComponent("estado.json")),
              let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any], j["conectado"] as? Bool == true,
              j["agentBar"] as? Bool == true, // solo un puente que sabe devolver la respuesta a Claude Code
              let h = j["hora"] as? String, let t = ISO8601DateFormatter().date(from: h.replacingOccurrences(of: "\\.\\d+Z$", with: "Z", options: .regularExpression)) else { return false }
        return Date().timeIntervalSince(t) < 300
    }
    @MainActor static func send(_ a: AgentAlert) {
        guard connected, a.waiting, !a.token.isEmpty else { return }
        // el resumen (si la IA ya lo tiene) en lugar del texto entero
        let current = DeskStore.shared?.alerts.first(where: { $0.id == a.id })?.summary ?? a.summary
        let msg = current.isEmpty ? (a.message.count > 300 ? String(a.message.prefix(300)) + "…" : a.message) : current
        let texto = "🤖 \(a.title)" + (a.place.isEmpty ? "" : " · \(a.place)") + (msg.isEmpty ? "" : "\n\n\(msg)") + "\n\n" + T.s("Vote, or reply to this message to answer it.", "Vota, o responde a este mensaje para contestarle.")
        let ref = "ab:" + a.token
        let entry: [String: Any] = ["ref": ref, "responder": true, "texto": texto,
                                    "botones": [[["text": T.s("Continue", "Continúa"), "callback_data": ref + ":c"], ["text": T.s("Stop", "Para"), "callback_data": ref + ":p"]]]]
        let out = folder.appendingPathComponent("salida")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let name = "\(Int(Date().timeIntervalSince1970 * 1000))-agentbar.json"
        if let d = try? JSONSerialization.data(withJSONObject: entry) { try? d.write(to: out.appendingPathComponent(name), options: .atomic) }
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
    /// El archivo del gancho de esa conversación; si su gancho espera respuesta, contestar va justo a ella.
    var token: String = ""
    /// Lo que ha hecho y lo que necesita, en una frase (la IA lo resume; mientras, su primera frase).
    var summary: String = ""
    var waiting: Bool = false
    /// Un permiso de Claude Code (PermissionRequest): qué quiere hacer. Se contesta Permitir / No desde la tarjeta.
    var change: PermissionChange? = nil
    var permission: Bool { change != nil }
    /// Cómo acabó Autopilot en esta parada («Autopilot · tests en verde tras 7 vueltas»), si venía de él.
    var autopilotNote: String = ""
    var created = Date()
    let id = UUID()
    var title: String { ask ? T.s("\(app) is waiting for you", "\(app) te espera") : T.s("\(app) is done", "\(app) ha terminado") }
}

/// Las teclas, guardadas en ~/Library/Application Support/Agent Deck/keys.json; el modo en UserDefaults.
@MainActor
final class DeskStore: ObservableObject {
    /// La de la app (para el aviso de WhatsApp, que lee el resumen más reciente).
    static weak var shared: DeskStore?
    @Published var keys: [DeskKey] { didSet { save() } }
    @Published var mode: DeskMode { didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode") } }
    @Published var style: BarStyle { didSet { UserDefaults.standard.set(style.rawValue, forKey: "style") } }
    @Published var lastSent: String = ""
    /// Aviso de un agente: ha terminado o te espera. Lo trae agentdeck://alert (ganchos de Claude Code u otros).
    /// Un aviso por conversación (Claude Code puede tener varias terminando a la vez); el último, abajo.
    @Published var alerts: [AgentAlert] = []
    var alert: AgentAlert? { alerts.last }
    @Published var editing: Bool = false
    /// Dictado: escuchando, texto parcial y nivel del micro (para el icono).
    @Published var listening: Bool = false
    @Published var partial: String = ""
    @Published var level: Float = 0
    /// Cuentan los inicios y envíos de la voz: el orbe suelta una onda en cada uno.
    @Published var startPulse = 0
    private var listeningSince = Date.distantPast
    @Published var sendPulse = 0
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
        controller.routeToAgent = { [weak self] text in self?.routeToAgent(text) ?? false }
        controller.onDelivered = { [weak self, weak controller] text in
            let f=DateFormatter();f.dateFormat="HH:mm";self?.lastSent="\(f.string(from:Date())) · \(text)"
            if controller?.noisy == true {
                let n=T.s("Voices around: press Enter to send","Hay voces alrededor: pulsa Intro para enviar")
                self?.flash=n
                DispatchQueue.main.asyncAfter(deadline:.now()+3.5){ if self?.flash==n { self?.flash="" } }
            } else if let l=controller?.lastLatency {
                let n=String(format:T.s("Done in %.1f s","Listo en %.1f s"),l).replacingOccurrences(of:".",with:T.es ? "," : ".")
                self?.flash=n
                DispatchQueue.main.asyncAfter(deadline:.now()+2.2){ if self?.flash==n { self?.flash="" } }
            }
        }
        controller.objectWillChange.sink { [weak self, weak controller] in
            DispatchQueue.main.async {
                guard let self, let controller else { return }
                let now=controller.phase == .listening
                if now != self.listening {
                    if now { self.listeningSince = Date() }
                    DeskStore.voiceCue(start: now, sending: controller.working)
                    if now { self.startPulse += 1 } else if controller.working { self.sendPulse += 1 }
                }
                // solo se publica lo que cambia: antes cada muestra del micro (20 por segundo) «cambiaba» todo y la ventana
                // se recolocaba sin parar, y la cápsula entera temblaba (Diego, 09/11)
                if self.listening != now { self.listening=now }
                if self.voiceWorking != controller.working { self.voiceWorking=controller.working }
                let attention=controller.phase == .draft || controller.phase == .failed
                if self.voiceNeedsAttention != attention { self.voiceNeedsAttention=attention }
                let shown=controller.phase == .listening ? controller.partial : controller.label
                if self.partial != shown { self.partial=shown }
                // el micro también oye el sonido de empezar: sin esto el orbe da un salto raro justo al pulsar Fn
                let settled = Date().timeIntervalSince(self.listeningSince) > 0.35
                self.level=DeskStore.follow(self.level, DeskStore.loudness(now && settled ? controller.level : 0))
                let note=controller.phase == .idle ? "" : controller.label
                if self.dictationNote != note { self.dictationNote=note }
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
        defer { DeskStore.shared = self }
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

    /// Al empezar a escuchar y al enviar: el sonido elegido (Chime, Ajustes → Voz → Sonido) y el toque del trackpad si tienes
    /// el dedo encima. El orbe, además, suelta una onda (startPulse / sendPulse).
    static func voiceCue(start: Bool, sending: Bool) {
        if start { Chime.play("start"); haptic(.generic) }
        else if sending { Chime.play("send"); haptic(.generic) }
    }

    /// Volumen del micro (amplitud lineal) → 0…1 en decibelios, como un vúmetro: -52 dB (silencio de sala) = 0, -14 dB (voz cerca) = 1.
    /// En lineal la voz normal ya llenaba el orbe y el ruido de fondo lo hacía temblar (Diego, 09/11: «no reacciona acorde con la voz»).
    nonisolated static func loudness(_ linear: Float) -> Float {
        guard linear > 0 else { return 0 }
        let db = 20 * log10(linear)
        let x = max(0, min(1, (db + 52) / 38))
        return x * x * (3 - 2 * x)   // curva suave en los extremos
    }
    /// Sube rápido cuando hablas y baja con calma: sin saltos entre muestras.
    nonisolated static func follow(_ current: Float, _ target: Float) -> Float {
        let next = current + (target - current) * (target > current ? 0.6 : 0.22)
        return next < 0.01 ? 0 : next
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
            NSLog("Agent Bar: no se pudo guardar keys.json: \(error)")
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

    /// Tus teclas como pack, para compartirlas con un enlace.
    var currentPack: KeyPack {
        KeyPack(name: T.s("My keys", "Mis teclas"), keys: keys.prefix(12).map { KeyPack.Key(label: String($0.label.prefix(24)), text: String($0.text.prefix(2000)), icon: $0.icon, enter: $0.sendEnter) })
    }
    /// Instala un pack: «reemplazar» deja solo sus teclas (⌃⌥1…); «añadir» las pone detrás, con los atajos que queden libres.
    func install(_ pack: KeyPack, replace: Bool) {
        let group = String(pack.name.prefix(40))
        var new: [DeskKey] = replace ? [] : keys
        var used = Set(new.compactMap { $0.hotkey })
        for k in pack.keys {
            let free = (1...9).first { !used.contains($0) }
            if let f = free { used.insert(f) }
            new.append(DeskKey(label: k.label.isEmpty ? String(k.text.prefix(16)) : k.label, text: k.text, hotkey: free, sendEnter: k.enter, icon: k.icon.isEmpty ? "sparkles" : k.icon, group: group))
        }
        keys = new
        flashNote(T.s("Pack «\(group)» added", "Pack «\(group)» añadido"))
    }

    /// Enciende el aviso con un sonido; se va al tocarlo o a los 25 s (salvo que llegue otro).
    func raiseAlert(app: String, ask: Bool, place: String, message: String = "", host: String = "", token: String = "", waiting: Bool = false, change: PermissionChange? = nil, autopilotEnd: String = "", turns: Int = 0) {
        var a = AgentAlert(app: app.isEmpty ? T.s("Your agent", "Tu agente") : String(app.prefix(40)), ask: ask, place: String(place.prefix(40)),
                           message: String(message.prefix(4000)), host: String(host.prefix(120)), token: token, waiting: waiting && !token.isEmpty)
        a.change = change
        a.autopilotNote = Self.autopilotNote(autopilotEnd, turns: turns)
        if !autopilotEnd.isEmpty { autopilotLeft = 0 }
        // «Claude necesita tu permiso» de un permiso que ya está en la barra: no se repite
        let permissionNotice = !a.permission && a.ask && a.message.lowercased().contains("permission")
        if permissionNotice, alerts.contains(where: { $0.permission && $0.place == a.place }) { return }
        if a.permission { alerts.removeAll { !$0.permission && $0.ask && $0.place == a.place && $0.message.lowercased().contains("permission") && Date().timeIntervalSince($0.created) < 10 } }
        a.summary = a.permission ? a.message : Self.firstSentence(a.message)
        alerts.append(a)
        if !a.permission { summarize(a) }
        Activity.log(a.permission ? "permission" : a.ask ? "ask" : "done", place: a.place, text: a.permission ? "" : Self.firstSentence(a.message))
        // como mucho 4: el más antiguo se suelta (su conversación se para como siempre)
        while alerts.count > 4 { let old = alerts.removeFirst(); release(old) }
        NSSound(named: ask ? "Ping" : "Glass")?.play()
        DeskStore.haptic(.levelChange)
        // sin mensaje se va solo; con mensaje se queda hasta que contestes o lo cierres
        // si en 45 s no la has contestado (no estás en el Mac), también va a tu WhatsApp, si tienes el puente de Alfred
        if a.waiting && !a.permission { DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [weak self] in
            guard let self, self.alerts.contains(where: { $0.id == a.id }) else { return }
            WhatsAppRelay.send(a)
        } }
        if a.message.isEmpty && !a.waiting { DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in self?.alerts.removeAll { $0.id == a.id } } }
    }

    // MARK: - Piloto automático (Claude Code)

    /// Vueltas que le quedan al piloto; 0 = apagado.
    @Published var autopilotLeft: Int = Autopilot.load()?.remaining ?? 0

    /// Objetivo de Autopilot (Ajustes): «» sin objetivo, «tests» hasta que pasen todos. Y el tiempo máximo, en horas.
    static var autopilotGoal: String {
        get { UserDefaults.standard.string(forKey: "autopilotGoal") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "autopilotGoal") }
    }
    static var autopilotHours: Double {
        get { (UserDefaults.standard.object(forKey: "autopilotHours") as? Double) ?? 2 }
        set { UserDefaults.standard.set(newValue, forKey: "autopilotHours") }
    }
    /// Lo que Autopilot le dice a Claude en cada vuelta: tu primera tecla, o «hasta que pasen los tests» con ese objetivo.
    var autopilotMessage: String {
        DeskStore.autopilotGoal == "tests"
            ? T.s("Continue until all the tests pass. When they all pass, say so clearly.", "Continúa hasta que pasen todos los tests. Cuando pasen todos, dilo claramente.")
            : keys.first?.text ?? T.s("continue", "continúa")
    }

    /// Enciende el piloto con N vueltas (con el objetivo y el tiempo de Ajustes) o lo apaga con 0.
    func setAutopilot(_ n: Int) {
        if n > 0 { Autopilot.start(n, message: autopilotMessage, goal: DeskStore.autopilotGoal.isEmpty ? nil : DeskStore.autopilotGoal, hours: DeskStore.autopilotHours) }
        else { Autopilot.save(nil) }
        autopilotLeft = n
        let goal = DeskStore.autopilotGoal == "tests" ? T.s(", until the tests pass", ", hasta que pasen los tests") : ""
        flashNote(n > 0 ? T.s("Autopilot: \(n) turns\(goal)", "Autopilot: \(n) vueltas\(goal)") : T.s("Autopilot off", "Autopilot apagado"))
    }
    static func autopilotNote(_ end: String, turns: Int) -> String {
        let n = T.s(turns == 1 ? "1 turn" : "\(turns) turns", turns == 1 ? "1 vuelta" : "\(turns) vueltas")
        switch end {
        case "tests": return T.s("Autopilot · tests green after \(n)", "Autopilot · tests en verde tras \(n)")
        case "turns": return T.s("Autopilot · used its \(n)", "Autopilot · ha dado sus \(n)")
        case "time": return T.s("Autopilot · time's up after \(n)", "Autopilot · se acabó el tiempo tras \(n)")
        case "brake": return T.s("Autopilot · stopped for a real question after \(n)", "Autopilot · parado por una pregunta tras \(n)")
        default: return ""
        }
    }

    // MARK: - Cola por agente

    /// Las colas, para Ajustes.
    @Published var queues: [AgentQueue.Queue] = AgentQueue.all()
    func refreshQueues() { queues = AgentQueue.all() }
    func queueSent(place: String, left: Int) {
        refreshQueues()
        Activity.log("queued", place: place)
        flashNote(left > 0 ? T.s("\(place): next from its queue (\(left) left)", "\(place): lo siguiente de su cola (quedan \(left))") : T.s("\(place): last one from its queue", "\(place): lo último de su cola"), for: 3)
    }
    /// Los nombres de carpeta conocidos (avisos de ahora y de los últimos días), para que «Kemet» se guarde como «Kemet-Capital».
    func knownPlaces() -> [String] {
        var seen = Set<String>()
        return (alerts.map(\.place) + Activity.recentPlaces()).filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    /// Lo pone el AppDelegate: abre la ventana de Pro.
    var showPro: (() -> Void)?
    func toggleAutopilot() {
        if autopilotLeft == 0 && !License.shared.unlocked { showPro?(); return }
        if autopilotLeft == 0 && !ClaudeHooks.installed { flashNote(T.s("Turn on Claude Code alerts first (menu)", "Activa antes los avisos de Claude Code (menú)"), for: 3.5); return }
        setAutopilot(autopilotLeft > 0 ? 0 : 5)
    }
    /// Lo cuenta el gancho cada vez que sigue solo.
    func autopilotTurn(left: Int, place: String) {
        autopilotLeft = left
        Activity.log("autopilot", place: place)
        flashNote(left > 0 ? T.s("Autopilot · \(left) left", "Autopilot · quedan \(left)") : T.s("Autopilot done", "Autopilot terminado"), for: 3)
    }

    // MARK: - Sobre lo seleccionado o en pantalla

    /// El último chat de IA que tuviste delante: ahí van «Explica» y «Captura».
    var lastAIApp: String?
    func noteActivated(_ bundle: String?) { if let b = bundle, VoicePreferences.aiApps.contains(b) { lastAIApp = b } }

    private func aiTarget() -> NSRunningApplication? {
        let order = [lastAIApp].compactMap { $0 } + ["com.anthropic.claudefordesktop", "com.openai.chat", "com.todesktop.230313mzl4w4u92", "com.openai.codex"]
        for b in order { if let a = NSRunningApplication.runningApplications(withBundleIdentifier: b).first { return a } }
        return nil
    }

    func flashNote(_ text: String, for seconds: Double = 2.4) {
        flash = text
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in if self?.flash == text { self?.flash = "" } }
    }

    /// Lleva a tu chat de IA y hace algo: si ya estás en uno, ahí mismo; si no, trae delante el último que usaste.
    private func inAIChat(from front: String?, _ action: @escaping () -> Void) {
        if let f = front, VoicePreferences.aiApps.contains(f) { action(); return }
        guard let app = aiTarget() else { flashNote(T.s("Open your AI chat first", "Abre antes tu chat de IA")); return }
        app.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: action)
    }

    /// «Explica»: lo seleccionado en cualquier app, a tu chat de IA, con «explícame esto y dime qué hacer».
    @MainActor func explainSelection() {
        DeskStore.haptic()
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        Sender.copySelection { [weak self] sel in
            guard let self else { return }
            guard let sel, !sel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { self.flashNote(T.s("Select some text first", "Selecciona antes un texto")); return }
            let clip = String(sel.prefix(12_000))
            let prompt = T.s("Explain this in two lines and tell me what to do:\n\n```\n\(clip)\n```", "Explícame esto en dos líneas y dime qué hacer:\n\n```\n\(clip)\n```")
            self.inAIChat(from: front) { Sender.send(prompt, enter: true) }
        }
    }

    /// «Captura»: eliges una zona de la pantalla y va a tu chat de IA con «¿qué falla aquí?». Esc no manda nada.
    @MainActor func snapScreen() {
        DeskStore.haptic()
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let pb = NSPasteboard.general, before = pb.changeCount
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-i", "-c", "-x"] // zona a elegir, al portapapeles, sin sonido
        p.terminationHandler = { _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, pb.changeCount != before, pb.data(forType: .png) != nil || pb.data(forType: .tiff) != nil else { return }
                self.inAIChat(from: front) {
                    Sender.tap(Sender.keyV, flags: .maskCommand) // la imagen
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { Sender.send(T.s("What's wrong here?", "¿Qué falla aquí?"), enter: true) }
                }
            }
        }
        do { try p.run() } catch { flashNote(T.s("Couldn't take the screenshot", "No se ha podido hacer la captura")) }
    }

    // MARK: - Resumen y voz de los avisos

    static func firstSentence(_ t: String) -> String {
        let s = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        if let r = s.range(of: "[.!?](\\s|$)", options: .regularExpression) { return String(s[..<r.upperBound]).trimmingCharacters(in: .whitespaces) }
        return s.count > 140 ? String(s.prefix(140)) + "…" : s
    }

    /// Una frase con lo que ha hecho y lo que necesita, con tu clave de OpenAI (unas centésimas de céntimo); sin clave, su primera frase.
    func summarize(_ a: AgentAlert) {
        guard a.message.count > 90, let key = VoiceKeychain.read(), !key.isEmpty else { return }
        let model = voice.preferences.textModel
        let task = "Summarize what this AI coding agent just reported in ONE short sentence (max 14 words) in the same language as the text: what it did and, if it asks or needs something from the user, end with that question. No preamble, no quotes."
        Task { [weak self] in
            var req = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!); req.httpMethod = "POST"; req.timeoutInterval = 8
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization"); req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var body: [String: Any] = ["model": model, "instructions": task, "input": String(a.message.suffix(6000)), "max_output_tokens": 120, "store": false]
            if let e = OpenAIVoiceClient.efforts.first { body["reasoning"] = ["effort": e] }
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            guard let (d, r) = try? await URLSession.shared.data(for: req), (r as? HTTPURLResponse)?.statusCode == 200,
                  let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                  let out = o["output"] as? [[String: Any]] else { return }
            let text = out.filter { $0["type"] as? String == "message" }.flatMap { $0["content"] as? [[String: Any]] ?? [] }
                .compactMap { $0["text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            await MainActor.run { if let i = self?.alerts.firstIndex(where: { $0.id == a.id }) { self?.alerts[i].summary = String(text.prefix(200)) } }
        }
    }

    /// Contestar hablando a un aviso: tocar el micro empieza, tocarlo otra vez envía lo dicho a esa conversación.
    @Published var alertListening: UUID?
    @Published var alertLevel: Float = 0
    private var alertLive: RealtimeTranscriber?
    private var alertApple: Dictation?
    private var alertHeard = ""

    @MainActor func talkToAlert(_ a: AgentAlert) {
        if alertListening == a.id { finishAlertVoice(a); return }
        if alertListening != nil { cancelAlertVoice() }
        alertHeard = ""; alertListening = a.id; DeskStore.haptic(.levelChange)
        if voice.preferences.engine == .openAI, let k = VoiceKeychain.read(), !k.isEmpty {
            let live = RealtimeTranscriber(); alertLive = live
            live.onPartial = { [weak self] t in self?.alertHeard = t }
            if !live.start(key: k, model: voice.preferences.liveModel, languages: voice.preferences.spokenLanguages, keywords: voice.preferences.keywords) {
                alertListening = nil; flashNote(T.s("The microphone couldn't start", "No se ha podido abrir el micrófono"))
            }
        } else {
            let d = Dictation(); alertApple = d
            d.onLevel = { [weak self] l in guard let self else { return }; self.alertLevel = DeskStore.follow(self.alertLevel, DeskStore.loudness(l)) }
            d.onEvent = { [weak self] state, text, _ in
                guard let self else { return }
                switch state {
                case .partial: self.alertHeard = text ?? ""
                case .final: self.alertHeard = text ?? self.alertHeard; self.sendAlertVoice(a)
                case .unavailable: self.alertListening = nil; self.flashNote(T.s("Voice isn't available: check the microphone", "La voz no está disponible: revisa el micrófono"))
                default: break
                }
            }
            d.start()
        }
    }
    @MainActor private func finishAlertVoice(_ a: AgentAlert) {
        if let live = alertLive {
            live.finish(timeout: 3) { [weak self] text in
                guard let self else { return }
                if let text, !text.isEmpty { self.alertHeard = text }
                self.alertLive = nil; self.sendAlertVoice(a)
            }
        } else { alertApple?.stop() }   // el final llega por onEvent
    }
    @MainActor private func sendAlertVoice(_ a: AgentAlert) {
        alertListening = nil; alertLevel = 0; alertApple = nil
        let t = alertHeard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { flashNote(T.s("I didn't hear anything", "No he oído nada")); return }
        reply(t, to: a)
    }
    @MainActor private func cancelAlertVoice() { alertLive?.cancel(); alertLive = nil; alertApple?.cancel(); alertApple = nil; alertListening = nil; alertLevel = 0 }

    /// La respuesta para el gancho que espera en esa conversación: Application Support/Agent Deck/hooks/<archivo>.decision
    private func decide(_ a: AgentAlert, _ obj: [String: String]) -> Bool {
        guard a.waiting, a.token.range(of: "^[0-9]+-[0-9]+\\.json$", options: .regularExpression) != nil,
              Date().timeIntervalSince(a.created) < ClaudeHooks.waitSeconds - 5,
              let d = try? JSONSerialization.data(withJSONObject: obj) else { return false }
        let url = Self.folder.appendingPathComponent("hooks").appendingPathComponent(a.token + ".decision")
        return (try? d.write(to: url, options: .atomic)) != nil
    }
    // MARK: - Permisos desde la barra

    /// Permitir o no desde la tarjeta (o la voz): va al gancho PermissionRequest de esa sesión. El motivo del no lo lee Claude.
    /// Si el gancho ya no espera (pasaron 60 s), se trae su app delante: allí está el diálogo.
    func answerPermission(_ a: AgentAlert, allow: Bool, reason: String = "") {
        alerts.removeAll { $0.id == a.id }
        let who = a.place.isEmpty ? a.app : a.place
        if decide(a, ["action": allow ? "allow" : "deny", "text": reason]) {
            if allow { Activity.log("allowed", place: a.place) }
            flashNote(allow ? T.s("Allowed · \(who)", "Permitido · \(who)") : reason.isEmpty ? T.s("Refused · \(who)", "No · \(who)") : T.s("No, with your reason · \(who)", "No, con tu motivo · \(who)"))
        } else { openHost(a) }
    }
    /// «En Claude»: se suelta el gancho (Claude enseña su diálogo) y se trae su app delante.
    func permissionInApp(_ a: AgentAlert) { dismissAlert(a); openHost(a) }
    func openHost(_ a: AgentAlert) {
        guard !a.host.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: a.host) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
    @MainActor func showChanges(_ a: AgentAlert) {
        guard let c = a.change else { return }
        ChangesWindow.show(c, place: a.place, allow: { [weak self] in self?.answerPermission(a, allow: true) },
                           deny: { [weak self] in self?.answerPermission(a, allow: false) })
    }

    /// Lo dictado con Fn que va a un agente de la barra: «dile al de Kemet que siga», o «permítelo» con un permiso esperando.
    /// Solo si de verdad hay un agente que encaje; si no, se escribe como siempre.
    func routeToAgent(_ text: String) -> Bool {
        if queueForAgent(text) { return true }
        let waiting = alerts.filter { $0.waiting }
        guard !waiting.isEmpty else { return false }
        if let allow = AgentCommand.permissionShortcut(text), let p = waiting.last(where: { $0.permission }) {
            answerPermission(p, allow: allow); return true
        }
        guard let cmd = AgentCommand.parse(text), let a = waiting.last(where: { AgentCommand.matches(cmd.who, place: $0.place) }) else { return false }
        reply(cmd.say, to: a)
        return true
    }
    /// «Luego dile al de Kemet que pase los tests»: si ese agente ya te espera, va ahora; si no, a su cola.
    func queueForAgent(_ text: String) -> Bool {
        guard let cmd = AgentCommand.parse(text, later: true) else { return false }
        if let a = alerts.last(where: { $0.waiting && AgentCommand.matches(cmd.who, place: $0.place) }) { reply(cmd.say, to: a); return true }
        // solo a un agente que conozcas (avisos de estos días o tus proyectos con git): «luego dile a mi madre…» se escribe como siempre
        guard let place = (knownPlaces() + LearnedVocabulary.cached).first(where: { AgentCommand.matches(cmd.who, place: $0) }) else { return false }
        let n = AgentQueue.add(place, cmd.say)
        refreshQueues()
        flashNote(T.s("Queued for \(place) (\(n))", "En la cola de \(place) (\(n))"), for: 3)
        return true
    }

    /// Cerrar un aviso: si su gancho esperaba, se le suelta y esa conversación se para como siempre.
    func dismissAlert(_ a: AgentAlert) { alerts.removeAll { $0.id == a.id }; release(a) }
    private func release(_ a: AgentAlert) { _ = decide(a, ["action": "release"]) }
    /// El gancho dejó de esperar (pasó el tiempo): contestar irá por la ventana.
    func alertReleased(token: String) { if let i = alerts.firstIndex(where: { $0.token == token }) { alerts[i].waiting = false } }

    /// Contestar desde el aviso. Si su gancho espera, la respuesta va por él a esa misma conversación de Claude Code,
    /// tengas delante la ventana que tengas. Si no, trae delante su app y la escribe allí.
    func reply(_ text: String, to a: AgentAlert) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if a.permission { let r = AgentCommand.permissionAnswer(t); answerPermission(a, allow: r.allow, reason: r.reason); return }
        alerts.removeAll { $0.id == a.id }
        if decide(a, ["action": "continue", "text": t]) {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            lastSent = "\(f.string(from: Date())) · \(t)"
            flashNote(T.s("Sent to \(a.place.isEmpty ? a.app : a.place)", "Enviado a \(a.place.isEmpty ? a.app : a.place)"))
            return
        }
        let app = a.host.isEmpty ? nil : NSRunningApplication.runningApplications(withBundleIdentifier: a.host).first
        app?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + (app == nil ? 0.05 : 0.35)) {
            Sender.send(t, enter: true)
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            self.lastSent = "\(f.string(from: Date())) · \(t)"
        }
    }

    static func dropHookFile(_ name: String) {
        guard name.range(of: "^[0-9]+-[0-9]+\\.json$", options: .regularExpression) != nil else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("hooks").appendingPathComponent(name))
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
        return Autopilot.lastAssistantText(transcript: j["transcript_path"] as? String ?? "")
    }
}
