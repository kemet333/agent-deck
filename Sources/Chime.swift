import AVFoundation
import Foundation

/// Los sonidos de la voz de Agent Bar, sintetizados aquí (sin archivos): uno al empezar a escuchar y otro al enviar.
/// Diego (09/11): «el usuario debe estar deseoso de hablar con el orbe». Nada de clics ni armónicos agudos: en los
/// altavoces del Mac el grave se pierde y lo agudo suena a «pi». Se eligen en Ajustes → Voz → Sonido.
@MainActor
enum Chime {
    enum Set: String, CaseIterable, Identifiable {
        case knock, marimba, bubble, none
        var id: String { rawValue }
        var title: String {
            switch self {
            case .knock: return T.s("Knock", "Toque")
            case .marimba: return T.s("Marimba", "Marimba")
            case .bubble: return T.s("Bubble", "Burbuja")
            case .none: return T.s("None", "Ninguno")
            }
        }
    }
    static let rate = 44_100.0
    static var current: Set {
        get { Set(rawValue: UserDefaults.standard.string(forKey: "voiceSound") ?? "") ?? (UserDefaults.standard.object(forKey: "voiceCues") as? Bool == false ? .none : .knock) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "voiceSound") }
    }
    private static var players: [String: AVAudioPlayer] = [:]

    static func prepare() {
        for set in Set.allCases where set != .none {
            for (cue, samples) in [("start", samples(set, start: true)), ("send", samples(set, start: false))] {
                if let p = try? AVAudioPlayer(data: wav(samples)) { p.volume = 0.5; p.prepareToPlay(); players[set.rawValue + "-" + cue] = p }
            }
        }
    }
    static func play(_ cue: String, set chosen: Set? = nil) {
        let set = chosen ?? current
        guard set != .none else { return }
        if players.isEmpty { prepare() }
        guard let p = players[set.rawValue + "-" + cue] else { return }
        p.stop(); p.currentTime = 0; p.play()
    }

    static func samples(_ set: Set, start: Bool) -> [Double] {
        var s = [Double](repeating: 0, count: Int(0.4 * rate))
        switch set {
        case .knock:
            // un «toc» de madera, redondo; el de enviar, un poco más grave y con un eco mínimo
            if start { tone(from: 290, to: 235, at: 0, attack: 0.002, decay: 0.026, gain: 1, into: &s) }
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
        case .none: break
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
