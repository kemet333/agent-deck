import Foundation

/// La tecla para hablar (0.20). Fn por defecto; pero el Fn de muchos teclados de fuera (Aula F75, Keychron…) lo
/// resuelve el propio teclado y nunca llega al Mac, así que se puede elegir otra: una tecla modificadora de un lado
/// (⌥ derecha, ⌘ derecha, ⌃ derecha, ⇧ derecha…) o una tecla sin uso al escribir (F1–F20, Inicio, Fin…).
/// Mantener = hablar, doble toque = manos libres, Escape cancela; con Fn también Fn+Control y Fn+Opción.
struct TalkKey: Codable, Equatable, Hashable {
    enum Kind: String, Codable { case fn, modifier, key }
    var kind: Kind
    var code: Int

    static let fn = TalkKey(kind: .fn, code: 63)
    static let rightOption = TalkKey(kind: .modifier, code: 61)
    static let rightCommand = TalkKey(kind: .modifier, code: 54)
    static let rightControl = TalkKey(kind: .modifier, code: 62)
    static let rightShift = TalkKey(kind: .modifier, code: 60)
    /// Lo que sale en el menú; «Pulsar otra…» captura cualquiera de las válidas.
    static let presets: [TalkKey] = [.fn, .rightOption, .rightCommand, .rightControl, .rightShift]

    /// Bits de lado de cada modificadora (los «device dependent» de NX: distinguen la izquierda de la derecha).
    static let sideBits: [Int: UInt64] = [58: 0x20, 61: 0x40, 55: 0x08, 54: 0x10, 59: 0x01, 62: 0x2000, 56: 0x02, 60: 0x04]
    /// La bandera general de cada modificadora (Option, Command, Control, Shift) en CGEventFlags.
    static let familyBits: [Int: UInt64] = [58: 0x80000, 61: 0x80000, 55: 0x100000, 54: 0x100000, 59: 0x40000, 62: 0x40000, 56: 0x20000, 60: 0x20000]
    static let functionKeys: [Int: String] = [122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
                                              103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"]
    static let otherKeys: [Int: String] = [114: T.s("Insert/Help", "Insert/Ayuda"), 115: T.s("Home", "Inicio"), 119: T.s("End", "Fin"),
                                           116: T.s("Page Up", "Re Pág"), 121: T.s("Page Down", "Av Pág")]

    /// ¿Se puede usar para hablar? Las modificadoras de un lado y las teclas que no escriben nada; nunca letras, números,
    /// espacio, Intro, Tab, borrar, Escape ni Bloq Mayús (romperían la escritura).
    static func usable(code: Int, isModifier: Bool) -> TalkKey? {
        if code == 63 { return .fn }
        if isModifier { return sideBits[code] != nil ? TalkKey(kind: .modifier, code: code) : nil }
        return functionKeys[code] != nil || otherKeys[code] != nil ? TalkKey(kind: .key, code: code) : nil
    }

    var name: String {
        switch code {
        case 63: return "Fn"
        case 61: return T.s("Right ⌥ Option", "⌥ Opción derecha")
        case 58: return T.s("Left ⌥ Option", "⌥ Opción izquierda")
        case 54: return T.s("Right ⌘ Command", "⌘ Comando derecha")
        case 55: return T.s("Left ⌘ Command", "⌘ Comando izquierda")
        case 62: return T.s("Right ⌃ Control", "⌃ Control derecha")
        case 59: return T.s("Left ⌃ Control", "⌃ Control izquierda")
        case 60: return T.s("Right ⇧ Shift", "⇧ Mayúsculas derecha")
        case 56: return T.s("Left ⇧ Shift", "⇧ Mayúsculas izquierda")
        default: return Self.functionKeys[code] ?? Self.otherKeys[code] ?? T.s("Key \(code)", "Tecla \(code)")
        }
    }
    /// Para frases cortas: «Mantén ⌥ Opción derecha y habla».
    var short: String { kind == .fn ? "Fn" : name }

    /// Un cambio de modificadoras: ¿nuestra tecla está ahora pulsada? Mira su lado exacto (la ⌥ izquierda no cuenta).
    func modifierDown(eventCode: Int, flags: UInt64) -> Bool? {
        guard kind == .modifier, eventCode == code, let side = Self.sideBits[code] else { return nil }
        return flags & side != 0
    }
    /// Otras modificadoras pulsadas a la vez que la nuestra (⌥ derecha + ⇧ para un carácter, por ejemplo): entonces no es para hablar.
    func othersHeld(flags: UInt64) -> Bool {
        let mine = Self.familyBits[code] ?? 0
        let all: UInt64 = 0x80000 | 0x100000 | 0x40000 | 0x20000
        return flags & all & ~mine != 0
    }
}
