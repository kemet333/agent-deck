import AVFoundation
import Foundation

/// Los sonidos de la voz de Agent Bar, sintetizados aquí (sin archivos ni sonidos del sistema):
/// - start: dos notas cálidas que suben (re → la), cortas y suaves, cuando el orbe empieza a escuchar.
/// - send: un «blup» que sube y se apaga, cuando suelta y envía.
/// Se preparan al arrancar para que suenen en el mismo instante, y van bajitos.
@MainActor
enum Chime {
    static let rate = 44_100.0
    private static var players: [String: AVAudioPlayer] = [:]

    static func prepare() {
        for (name, samples) in [("start", start()), ("send", send())] {
            if let p = try? AVAudioPlayer(data: wav(samples)) { p.volume = 0.32; p.prepareToPlay(); players[name] = p }
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
    static func start() -> [Double] {
        var s = [Double](repeating: 0, count: Int(0.42 * rate))
        note(587.33, at: 0, length: 0.40, decay: 0.07, gain: 0.55, into: &s)      // re
        note(880.00, at: 0.065, length: 0.36, decay: 0.09, gain: 0.5, into: &s)   // la
        // un eco muy bajo: espacio, no ruido
        note(880.00, at: 0.15, length: 0.27, decay: 0.08, gain: 0.08, into: &s)
        return s
    }
    static func send() -> [Double] {
        let n = Int(0.26 * rate)
        var s = [Double](repeating: 0, count: n)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / rate
            // barrido 520 → 1180 Hz en 70 ms: la burbuja que sube
            let f = 520 + 660 * (1 - exp(-t / 0.028))
            phase += 2 * .pi * f / rate
            let env = min(1, t / 0.003) * exp(-t / 0.055)
            s[i] = (sin(phase) + 0.12 * sin(2 * phase)) * env * 0.6
        }
        note(1567.98, at: 0.05, length: 0.2, decay: 0.05, gain: 0.12, into: &s)   // un brillo arriba (sol)
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
