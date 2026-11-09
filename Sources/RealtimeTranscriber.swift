import AVFoundation
import Foundation

/// Transcribe mientras hablas (Realtime de OpenAI, modo solo transcripción, gpt-live-transcribe):
/// el micro va en trozos de 100 ms por una conexión abierta al bajar Fn, el texto parcial llega mientras hablas
/// y al soltar se pide el final, que ya está casi hecho. Si algo falla, quien lo usa tira de la grabación normal.
/// Protocolo según developers.openai.com/api/docs/guides/realtime-transcription (06/11/2026).
@MainActor
final class RealtimeTranscriber {
    var onPartial: ((String) -> Void)?
    private var task: URLSessionWebSocketTask?
    private let engine = AVAudioEngine()
    private let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true)!
    private var pending: [Data] = []          // audio grabado antes de que la conexión esté lista
    private var ready = false
    private var failed = false
    private var text = ""                     // lo que va llegando
    private var finalText: String?
    private var waiters: [(String?) -> Void] = []
    private(set) var running = false

    /// Empieza a escuchar y a mandar. Devuelve false si no se pudo abrir el micro.
    func start(key: String, model: String = "gpt-live-transcribe", languages: [String] = [], keywords: [String] = []) -> Bool {
        guard !running else { return true }
        var req = URLRequest(url: URL(string: "wss://api.openai.com/v1/realtime?intent=transcription")!)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        // un permiso temporal (ek_…, de la voz incluida de Pro) también va como subprotocolo, que es como lo documenta OpenAI
        if key.hasPrefix("ek_") { req.setValue("realtime, openai-insecure-api-key." + key, forHTTPHeaderField: "Sec-WebSocket-Protocol") }
        let t = URLSession.shared.webSocketTask(with: req)
        task = t; ready = false; failed = false; text = ""; finalText = nil; pending = []
        t.resume()
        var transcription: [String: Any] = ["model": model]
        let langs = languages.map { $0.lowercased() }.filter { $0.count == 2 }
        if !langs.isEmpty { transcription["languages"] = langs }
        let kw = keywords.filter { !$0.contains("<") && !$0.contains(">") && !$0.contains("\n") && !$0.contains("\r") }.prefix(50)
        if !kw.isEmpty { transcription["keywords"] = Array(kw) }
        let update: [String: Any] = ["type": "session.update", "session": ["type": "transcription", "audio": ["input": [
            "format": ["type": "audio/pcm", "rate": 24_000], "transcription": transcription, "turn_detection": NSNull()]]]]
        send(update) { [weak self] ok in
            guard let self else { return }
            if ok { self.ready = true; let queued = self.pending; self.pending = []; queued.forEach { self.sendAudio($0) } } else { self.fail() }
        }
        receive()
        // el micro: lo que llegue antes de que conecte espera en «pending»
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, let conv = AVAudioConverter(from: inFormat, to: outFormat) else { stopSocket(); return false }
        let outF = outFormat
        input.installTap(onBus: 0, bufferSize: 2400, format: inFormat) { [weak self] buffer, _ in
            guard let data = RealtimeTranscriber.convert(buffer, conv, outF) else { return }
            Task { @MainActor in self?.push(data) }
        }
        do { engine.prepare(); try engine.start() } catch { input.removeTap(onBus: 0); stopSocket(); return false }
        running = true
        return true
    }

    /// Para el micro, cierra el turno y espera el texto final (como mucho `timeout`). nil = no hubo texto: usa la grabación.
    func finish(timeout: TimeInterval = 3, _ done: @escaping (String?) -> Void) {
        stopAudio()
        guard !failed, task != nil else { done(nil); stopSocket(); return }
        if let f = finalText { done(f); stopSocket(); return }
        waiters.append(done)
        let commit = { [weak self] in self?.send(["type": "input_audio_buffer.commit"]) { _ in } }
        if ready { commit() } else {
            // aún conectando: se manda en cuanto esté lista
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in if self?.ready == true { commit() } else { self?.fail() } }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in self?.resolve(nil) }
    }

    func cancel() { stopAudio(); waiters = []; stopSocket() }

    // MARK: -

    /// A 24 kHz mono PCM16, en el hilo del micro (no toca nada de la app).
    nonisolated static func convert(_ buffer: AVAudioPCMBuffer, _ conv: AVAudioConverter, _ outF: AVAudioFormat) -> Data? {
        let ratio = outF.sampleRate / buffer.format.sampleRate
        guard let out = AVAudioPCMBuffer(pcmFormat: outF, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32) else { return nil }
        var given = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if given { status.pointee = .noDataNow; return nil }
            given = true; status.pointee = .haveData; return buffer
        }
        guard err == nil, out.frameLength > 0, let p = out.int16ChannelData?[0] else { return nil }
        return Data(bytes: p, count: Int(out.frameLength) * 2)
    }

    private func push(_ data: Data) {
        guard running, !failed else { return }
        if ready { sendAudio(data) } else if pending.count < 600 { pending.append(data) }
    }

    private func sendAudio(_ data: Data) {
        send(["type": "input_audio_buffer.append", "audio": data.base64EncodedString()]) { _ in }
    }

    private func send(_ obj: [String: Any], _ done: @escaping (Bool) -> Void) {
        guard let t = task, let d = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: d, encoding: .utf8) else { done(false); return }
        t.send(.string(s)) { error in Task { @MainActor in done(error == nil) } }
    }

    private func receive() {
        task?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .failure: self.fail()
                case .success(let msg):
                    if case .string(let s) = msg, let o = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] { self.handle(o) }
                    if self.task != nil { self.receive() }
                }
            }
        }
    }

    private func handle(_ o: [String: Any]) {
        switch o["type"] as? String ?? "" {
        case "conversation.item.input_audio_transcription.delta":
            text += o["delta"] as? String ?? ""
            onPartial?(text)
        case "conversation.item.input_audio_transcription.completed":
            let t = (o["transcript"] as? String ?? text).trimmingCharacters(in: .whitespacesAndNewlines)
            finalText = t
            resolve(t.isEmpty ? nil : t)
        case "conversation.item.input_audio_transcription.failed", "error":
            let e = (o["error"] as? [String: Any])?["message"] as? String ?? ""
            VoiceServiceError.lastDetail = "realtime: " + String(e.prefix(200))
            fail()
        default: break
        }
    }

    private func resolve(_ value: String?) {
        guard !waiters.isEmpty else { return }
        let w = waiters; waiters = []
        w.forEach { $0(value) }
        stopSocket()
    }

    private func fail() { failed = true; resolve(nil) }

    private func stopAudio() {
        guard running else { return }
        running = false
        engine.stop(); engine.inputNode.removeTap(onBus: 0)
    }

    private func stopSocket() { task?.cancel(with: .normalClosure, reason: nil); task = nil; ready = false }
}
