import AVFoundation
import Speech

/// Dictado para el Desk: español de España, en el propio Mac siempre que macOS lo permita.
/// El audio vive solo en memoria para el reconocedor; esta app no guarda ni envía nada.
/// (Mismo motor que el dictado de Alfred en el Diego Operating System.)
@MainActor
final class Dictation {
    enum State: String { case listening, partial, final, idle, unavailable }
    var onEvent: ((State, String?, String?) -> Void)?
    var onLevel: ((Float) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: T.speechLocale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latest = ""
    private var tapInstalled = false
    private var finishing: DispatchWorkItem?
    private var stopRequested = false
    private(set) var active = false

    func start() {
        guard !active else { return }
        stopRequested = false
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: break
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    if status == .authorized { self?.start() } else { self?.onEvent?(.unavailable, nil, "speech-denied") }
                }
            }
            return
        default: onEvent?(.unavailable, nil, "speech-denied"); return
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.start() } else { self?.onEvent?(.unavailable, nil, "mic-denied") }
                }
            }
            return
        default: onEvent?(.unavailable, nil, "mic-denied"); return
        }
        guard let recognizer, recognizer.isAvailable else { onEvent?(.unavailable, nil, "recognizer-unavailable"); return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { onEvent?(.unavailable, nil, "no-input"); return }
        var lastLevel = Date.distantPast
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0,
                  Date().timeIntervalSince(lastLevel) >= 0.05 else { return }
            lastLevel = Date()
            var sum: Float = 0
            for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
            let rms = (sum / Float(buffer.frameLength)).squareRoot()
            DispatchQueue.main.async { self?.onLevel?(rms) }
        }
        tapInstalled = true
        do {
            engine.prepare()
            try engine.start()
        } catch {
            teardown()
            onEvent?(.unavailable, nil, "no-input")
            return
        }
        self.request = request
        latest = ""
        active = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            DispatchQueue.main.async { self?.handle(text: text, isFinal: isFinal, failed: failed) }
        }
        onEvent?(.listening, nil, nil)
    }

    /// Deja de escuchar y entrega lo oído.
    func stop() {
        guard active, !stopRequested else { return }
        stopRequested = true
        stopAudio()
        request?.endAudio()
        let fallback = DispatchWorkItem { [weak self] in self?.finish() }
        finishing = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: fallback)
    }

    func cancel() {
        guard active else { return }
        task?.cancel()
        teardown()
        onEvent?(.idle, nil, "cancelled")
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool) {
        guard active else { return }
        if let text { latest = text }
        if isFinal || (failed && stopRequested) { finish(); return }
        if failed { cancel(); return }
        if let text, !stopRequested { onEvent?(.partial, text, nil) }
    }

    private func finish() {
        guard active else { return }
        let text = latest.trimmingCharacters(in: .whitespacesAndNewlines)
        task?.finish()
        teardown()
        onEvent?(.final, text, nil)
    }

    private func stopAudio() {
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
    }

    private func teardown() {
        finishing?.cancel(); finishing = nil
        stopAudio()
        request = nil
        task = nil
        active = false
        stopRequested = false
    }
}
