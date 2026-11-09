import AVFoundation
import Foundation

/// Los sonidos de la voz de Agent Bar, sintetizados aquí (sin archivos): uno al empezar a escuchar y otro al enviar.
/// Diego (09/11): «el usuario debe estar deseoso de hablar con el orbe». Nada de clics ni armónicos agudos: en los
/// altavoces del Mac el grave se pierde y lo agudo suena a «pi». Se eligen en Ajustes → Voz → Sonido.
@MainActor
enum Chime {
    enum Set: String, CaseIterable, Identifiable {
        case siri, messages, dictation, knock, marimba, bubble, none
        var id: String { rawValue }
        var title: String {
            switch self {
            case .siri: return "Siri"
            case .messages: return T.s("Messages", "Mensajes")
            case .dictation: return T.s("Dictation", "Dictado")
            case .knock: return T.s("Knock", "Toque")
            case .marimba: return T.s("Marimba", "Marimba")
            case .bubble: return T.s("Bubble", "Burbuja")
            case .none: return T.s("None", "Ninguno")
            }
        }
    }
    static let rate = 44_100.0
    static var current: Set {
        get { Set(rawValue: UserDefaults.standard.string(forKey: "voiceSound") ?? "") ?? (UserDefaults.standard.object(forKey: "voiceCues") as? Bool == false ? .none : .siri) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "voiceSound") }
    }
    private static var players: [String: AVAudioPlayer] = [:]
    /// Los sonidos de Apple ya instalados en macOS: se reproducen desde el sistema, sin copiarlos a la app.
    /// Si en alguna versión de macOS no están, suena el toque propio.
    static let systemFolder = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/"
    static func systemFiles(_ set: Set) -> (start: String, send: String)? {
        switch set {
        case .siri: return ("siri/jbl_begin_short.caf", "siri/jbl_confirm.caf")
        case .messages: return ("system/mic_unmute.caf", "system/SentMessage.caf")
        case .dictation: return ("system/begin_record.caf", "system/end_record.caf")
        default: return nil
        }
    }

    static func prepare() {
        for set in Set.allCases {
            guard let files = systemFiles(set) else { continue }
            for (cue, file) in [("start", files.start), ("send", files.send)] {
                if let p = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: systemFolder + file)) { p.volume = 0.6; p.prepareToPlay(); players[set.rawValue + "-" + cue] = p }
            }
        }
        for set in Set.allCases where set != .none && systemFiles(set) == nil {
            for (cue, samples) in [("start", samples(set, start: true)), ("send", samples(set, start: false))] {
                if let p = try? AVAudioPlayer(data: wav(samples)) { p.volume = 0.5; p.prepareToPlay(); players[set.rawValue + "-" + cue] = p }
            }
        }
    }
    static func play(_ cue: String, set chosen: Set? = nil) {
        let set = chosen ?? current
        guard set != .none else { return }
        if players.isEmpty { prepare() }
        guard let p = players[set.rawValue + "-" + cue] ?? players["knock-" + cue] else { return }
        p.stop(); p.currentTime = 0; p.play()
    }

    static func samples(_ set: Set, start: Bool) -> [Double] {
        var s = [Double](repeating: 0, count: Int(0.4 * rate))
        switch set {
        case .knock:
            // un «toc» de madera, redondo; el de enviar, un poco más grave y con un eco mínimo
            if start {
                // tres capas, como una tecla buena: el cuerpo grave que se siente, una octava corta para que se oiga en los
                // altavoces del Mac, y un roce de aire muy breve; con una sala mínima para que no suene a pitido de ordenador
                tone(from: 230, to: 175, at: 0, attack: 0.0015, decay: 0.04, gain: 1, glide: 0.025, into: &s)
                tone(from: 460, to: 360, at: 0, attack: 0.001, decay: 0.012, gain: 0.4, glide: 0.02, into: &s)
                air(at: 0, decay: 0.004, cutoff: 1400, gain: 0.18, into: &s)
                room(&s, taps: [(0.019, 0.16), (0.037, 0.09), (0.061, 0.04)])
            }
            else { tone(from: 245, to: 195, at: 0, attack: 0.002, decay: 0.032, gain: 1, into: &s)
                   tone(from: 245, to: 195, at: 0.075, attack: 0.002, decay: 0.022, gain: 0.2, into: &s) }
        case .marimba:
            // una tecla de marimba: fundamental + su parcial 4× que se apaga antes (lo que la hace «de madera» y dulce)
            let f = start ? 523.25 : 659.25   // do → mi
            tone(from: f, to: f, at: 0, attack: 0.003, decay: 0.11, gain: 1, into: &s)
            tone(from: f * 4, to: f * 4, at: 0, attack: 0.002, decay: 0.012, gain: 0.12, into: &s)
            if !start { tone(from: 783.99, to: 783.99, at: 0.06, attack: 0.003, decay: 0.09, gain: 0.55, into: &s) } // y sol: sube, «hecho»
        case .bubble:
            // una burbuja que sube; al enviar, más arriba y más rápida
            if start { tone(from: 240, to: 460, at: 0, attack: 0.004, decay: 0.05, gain: 1, glide: 0.035, into: &s) }
            else { tone(from: 380, to: 820, at: 0, attack: 0.003, decay: 0.045, gain: 1, glide: 0.025, into: &s) }
        case .siri, .messages, .dictation, .none: break
        }
        // recorta el silencio del final
        if let last = s.lastIndex(where: { abs($0) > 0.0005 }) { s = Array(s[...min(s.count - 1, last + Int(0.01 * rate))]) }
        return s
    }

    /// Un seno con deslizamiento de tono (de f0 a f1), ataque suave y caída exponencial. Sin ruido ni armónicos.
    static func tone(from f0: Double, to f1: Double, at t0: Double, attack: Double, decay: Double, gain: Double, glide: Double = 0.03, into s: inout [Double]) {
        let start = Int(t0 * rate), n = Int((decay * 7 + attack) * rate)
        var phase = 0.0
        for i in 0..<n where start + i < s.count {
            let t = Double(i) / rate
            let f = f1 + (f0 - f1) * exp(-t / glide)
            phase += 2 * .pi * f / rate
            let a = min(1, t / attack)
            let env = a * a * (3 - 2 * a) * exp(-t / decay)
            s[start + i] += sin(phase) * env * gain
        }
    }

    /// Un roce de aire: ruido suave filtrado, de pocos milisegundos (la «textura» de una tecla, sin clic).
    static func air(at t0: Double, decay: Double, cutoff: Double, gain: Double, into s: inout [Double]) {
        let start = Int(t0 * rate), n = Int(decay * 8 * rate)
        let a = 1 - exp(-2 * .pi * cutoff / rate)
        var y1 = 0.0, y2 = 0.0, seed: UInt32 = 424_242
        for i in 0..<n where start + i < s.count {
            let t = Double(i) / rate
            seed = seed &* 1_103_515_245 &+ 12345
            let x = Double(seed >> 16 & 0x7fff) / 16_384 - 1
            y1 += a * (x - y1); y2 += a * (y1 - y2)
            let att = min(1, t / 0.0008)
            s[start + i] += y2 * att * exp(-t / decay) * gain * 4
        }
    }
    /// Una sala mínima: ecos cortos y flojos que dan cuerpo sin cola.
    static func room(_ s: inout [Double], taps: [(Double, Double)]) {
        let dry = s
        for (delay, g) in taps {
            let d = Int(delay * rate)
            for i in d..<s.count { s[i] += dry[i - d] * g }
        }
    }

    /// WAV PCM de 16 bits, mono, con un fundido final para que no haga clic.
    static func wav(_ samples: [Double]) -> Data {
        let peak = max(samples.map { abs($0) }.max() ?? 1, 1e-6)
        let fade = min(Int(0.008 * rate), samples.count)
        var pcm = Data(capacity: samples.count * 2)
        for (i, v) in samples.enumerated() {
            let tail = i >= samples.count - fade ? Double(samples.count - i) / Double(max(fade, 1)) : 1
            var x = Int16(max(-1, min(1, v / peak * 0.9 * tail)) * 32_000).littleEndian
            withUnsafeBytes(of: &x) { pcm.append(contentsOf: $0) }
        }
        func u32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        func u16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        var d = Data("RIFF".utf8); d += u32(UInt32(36 + pcm.count)); d += Data("WAVE".utf8)
        d += Data("fmt ".utf8); d += u32(16); d += u16(1); d += u16(1); d += u32(UInt32(rate)); d += u32(UInt32(rate) * 2); d += u16(2); d += u16(16)
        d += Data("data".utf8); d += u32(UInt32(pcm.count)); d += pcm
        return d
    }
}
