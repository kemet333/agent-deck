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
        apps = try c.decodeIfPresent([String].self, forKey: .apps) ?? []
        hold = try c.decodeIfPresent(String.self, forKey: .hold) ?? ""
        team = try c.decodeIfPresent(String.self, forKey: .team) ?? ""
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
    /// Solo en estas apps (bundle ids); vacío = en todas (0.16).
    var apps: [String] = []
    /// Lo que escribe al mantenerla pulsada (0.16); vacío = nada.
    var hold: String = ""
    /// El equipo del que viene (0.19); vacío = tuya. Las del equipo se cambian solas cuando su responsable las actualiza.
    var team: String = ""
    func shows(in bundle: String) -> Bool { apps.isEmpty || bundle.isEmpty || apps.contains(bundle) }
}
