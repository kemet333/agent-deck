import Foundation

/// Una tecla del Desk: lo que se ve (label) y lo que se escribe en el chat (text).
struct DeskKey: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var label: String
    var text: String
    /// Atajo global ⌃⌥ + dígito (1…9); nil = sin atajo.
    var hotkey: Int?
    /// Pulsar Intro después de escribir (enviar el mensaje). Casi siempre sí.
    var sendEnter: Bool = true
}

/// Las teclas, guardadas en ~/Library/Application Support/Agent Desk/keys.json.
final class DeskStore: ObservableObject {
    @Published var keys: [DeskKey] { didSet { save() } }
    @Published var lastSent: String = ""
    @Published var editing: Bool = false

    static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Agent Desk", isDirectory: true)
    }()
    static let file = folder.appendingPathComponent("keys.json")

    static let defaults: [DeskKey] = [
        DeskKey(label: "Continúa", text: "continúa", hotkey: 1),
        DeskKey(label: "Siguiente", text: "siguiente", hotkey: 2),
        DeskKey(label: "Dale caña", text: "dale caña", hotkey: 3),
        DeskKey(label: "Hazlo", text: "hazlo", hotkey: 4),
        DeskKey(label: "Me gusta", text: "me gusta, continúa", hotkey: 5),
        DeskKey(label: "Preview", text: "enséñame una preview antes de seguir", hotkey: 6),
        DeskKey(label: "Resumen", text: "resumen corto: dónde estamos y qué falta", hotkey: 7),
        DeskKey(label: "Para", text: "para, no sigas con eso", hotkey: 8),
    ]

    init() {
        if let data = try? Data(contentsOf: DeskStore.file),
           let saved = try? JSONDecoder().decode([DeskKey].self, from: data), !saved.isEmpty {
            keys = saved
        } else {
            keys = DeskStore.defaults
        }
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

    func add(label: String, text: String, sendEnter: Bool) {
        let used = Set(keys.compactMap { $0.hotkey })
        let free = (1...9).first { !used.contains($0) }
        let clean = label.trimmingCharacters(in: .whitespaces)
        keys.append(DeskKey(label: clean.isEmpty ? String(text.prefix(18)) : clean, text: text, hotkey: free, sendEnter: sendEnter))
    }

    func update(_ key: DeskKey) {
        if let i = keys.firstIndex(where: { $0.id == key.id }) { keys[i] = key }
    }

    func remove(_ key: DeskKey) {
        keys.removeAll { $0.id == key.id }
    }

    func restoreDefaults() { keys = DeskStore.defaults }
}
