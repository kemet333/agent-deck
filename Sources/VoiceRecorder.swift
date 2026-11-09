import AVFoundation
import Foundation

@MainActor
protocol VoiceRecording: AnyObject {
    var onLevel: ((Float)->Void)? {get set}
    var onLimit: (()->Void)? {get set}
    var onFailure: (()->Void)? {get set}
    func start() throws
    func finish() throws -> Data
    func cancel()
    /// El momento más fuerte de esta grabación, en dB (-160 si no ha grabado).
    var peakDB: Float { get }
}
extension VoiceRecording { var peakDB: Float { -160 } }
@MainActor
final class VoiceRecorder: NSObject, AVAudioRecorderDelegate, VoiceRecording {
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var folder: URL?
    private var peak: Float = -160
    var peakDB: Float { peak }
    var onLevel: ((Float)->Void)?
    var onLimit: (()->Void)?
    var onFailure: (()->Void)?
    func start() throws {
        cancel()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("agentdeck-voice-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        self.folder = folder
        let path = folder.appendingPathComponent("recording.m4a")
        do {
            let r = try AVAudioRecorder(url:path,settings:[AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:44100,AVNumberOfChannelsKey:1,AVEncoderBitRateKey:64000])
            r.delegate = self;r.isMeteringEnabled = true
            guard r.prepareToRecord(),r.record() else { throw VoiceServiceError(message:T.s("The microphone could not start.","No se ha podido iniciar el micrófono.")) }
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:path.path)
            recorder = r;peak = -160
            timer = Timer.scheduledTimer(withTimeInterval:0.05,repeats:true){[weak self] _ in
                MainActor.assumeIsolated {
                    guard let self,let r = self.recorder else { return };r.updateMeters()
                    let power = r.averagePower(forChannel:0);self.peak = max(self.peak,power)
                    self.onLevel?(pow(10,power/20))
                    if r.currentTime >= 180 { self.onLimit?() }
                }
            }
        } catch { cleanup();throw error }
    }
    func finish() throws -> Data {
        guard let r = recorder else { throw VoiceServiceError(message:T.s("There is no active recording.","No hay una grabación activa.")) }
        let seconds = r.currentTime,hasSpeech = peak > -55
        r.stop();timer?.invalidate();timer = nil;recorder = nil
        defer { cleanup() }
        guard seconds >= 0.2,hasSpeech else { throw VoiceServiceError(message:T.s("No speech detected. Nothing was sent.","No se ha detectado voz. No se ha enviado nada.")) }
        let attrs = try FileManager.default.attributesOfItem(atPath:r.url.path)
        guard ((attrs[.size] as? NSNumber)?.intValue ?? 0) <= 25_000_000 else { throw VoiceServiceError(message:T.s("Recording too large.","La grabación es demasiado grande.")) }
        return try Data(contentsOf:r.url)
    }
    func cancel() { recorder?.stop();recorder = nil;timer?.invalidate();timer = nil;cleanup() }
    private func cleanup() { if let folder { try? FileManager.default.removeItem(at:folder) };folder = nil }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder:AVAudioRecorder,error:Error?) { let id=ObjectIdentifier(recorder);Task{@MainActor [weak self] in guard let self,let current=self.recorder,ObjectIdentifier(current)==id else{return};self.cancel();self.onFailure?()} }
}
