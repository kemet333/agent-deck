import AVFoundation
import Foundation

/// Los «toques» de la voz de Agent Bar, sintetizados aquí (sin archivos): no son melodías sino un golpe corto y grave
/// que se siente como una vibración (Diego, 09/11: «más importancia a la vibración, fíjate en la de Vowen»; Vowen no
/// vibra, usa un golpe de ~0,2 s alrededor de 300 Hz al empezar y 225 Hz al parar).
/// - start: un toque seco que baja de 340 a 290 Hz, al empezar a escuchar.
/// - send: un toque más grave (250 → 200 Hz) con un eco mínimo, al soltar y enviar.
@MainActor
enum Chime {
    static let rate = 44_100.0
    private static var players: [String: AVAudioPlayer] = [:]

    static func prepare() {
        for (name, samples) in [("start", start()), ("send", send())] {
            if let p = try? AVAudioPlayer(data: wav(samples)) { p.volume = 0.45; p.prepareToPlay(); players[name] = p }
        }
    }
    static func play(_ name: String) {
        if players.isEmpty { prepare() }
        guard let p = players[name] else { return }
        p.stop(); p.currentTime = 0; p.play()
    }

    // MARK: síntesis

    /// Una nota con un poco de segundo armónico (cuerpo), ataque de 4 ms y caída exponencial.
    static func note(_ f: Double, at t0: Double, length: Double, decay: Double, gain: Double, into s: inout [Double]) {
        let start = Int(t0 * rate), n = Int(length * rate)
        for i in 0..<n where start + i < s.count {
            let t = Double(i) / rate
            let env = min(1, t / 0.004) * exp(-t / decay)
            let v = sin(2 * .pi * f * t) + 0.18 * sin(2 * .pi * 2 * f * t) + 0.05 * sin(2 * .pi * 3 * f * t)
            s[start + i] += v * env * gain
        }
    }
    /// Un golpe: seno con caída de tono, ataque de 1,5 ms, caída rápida y un clic de 3 ms al principio (la «sensación» de tecla).
    static func knock(from f0: Double, to f1: Double, at t0: Double, decay: Double, gain: Double, into s: inout [Double]) {
        let start = Int(t0 * rate), n = Int((decay * 6) * rate)
        var phase = 0.0, seed: UInt32 = 12345
        for i in 0..<n where start + i < s.count {
            let t = Double(i) / rate
            let f = f1 + (f0 - f1) * exp(-t / 0.03)
            phase += 2 * .pi * f / rate
            let env = min(1, t / 0.0015) * exp(-t / decay)
            seed = seed &* 1_103_515_245 &+ 12345
            let noise = (Double(seed >> 16 & 0x7fff) / 16_384 - 1) * exp(-t / 0.0015) * 0.25
            s[start + i] += (sin(phase) + 0.25 * sin(2 * phase) + noise) * env * gain
        }
    }
    static func start() -> [Double] {
        var s = [Double](repeating: 0, count: Int(0.2 * rate))
        knock(from: 340, to: 290, at: 0, decay: 0.032, gain: 1, into: &s)
        return s
    }
    static func send() -> [Double] {
        var s = [Double](repeating: 0, count: Int(0.22 * rate))
        knock(from: 250, to: 200, at: 0, decay: 0.036, gain: 1, into: &s)
        knock(from: 250, to: 200, at: 0.07, decay: 0.025, gain: 0.22, into: &s)
        return s
    }

    /// WAV PCM de 16 bits, mono, con un fundido final para que no haga clic.
    static func wav(_ samples: [Double]) -> Data {
        let peak = max(samples.map { abs($0) }.max() ?? 1, 1e-6)
        let fade = Int(0.01 * rate)
        var pcm = Data(capacity: samples.count * 2)
        for (i, v) in samples.enumerated() {
            let tail = i >= samples.count - fade ? Double(samples.count - i) / Double(fade) : 1
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
