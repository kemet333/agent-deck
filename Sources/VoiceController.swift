import AppKit
import AVFoundation
import Combine

@MainActor
final class VoiceController: ObservableObject {
    @Published var preferences: VoicePreferences { didSet { savePreferences();if oldValue.fnEnabled != preferences.fnEnabled { onShortcutsChanged?() } } }
    @Published private(set) var history: [VoiceRecord]
    @Published private(set) var phase: VoicePhase = .idle
    @Published var draft = "" { didSet { persistDraft() } }
    @Published private(set) var raw = ""
    @Published private(set) var partial = ""
    @Published private(set) var level: Float = 0
    @Published private(set) var message = ""
    @Published private(set) var keyConfigured = false
    @Published var shortcutStatus = ""
    var onShortcutsChanged: (()->Void)?
    var onDelivered: ((String)->Void)?
    var showWorkspace: (()->Void)?
    var showDeck: (()->Void)?
    private let saveCredential:(String)throws->Void
    private let removeCredential:()throws->Void
    private let frontApp:()->(name:String,bundle:String?)
    private var capturedBundle:String?
    var canInsertOriginal:Bool{target != nil && sessionID != nil}
    private let captureTarget:(Bool)throws->TextTarget
    private let deliverText:VoiceDelivery
    private let storage: VoiceStorage
    private let client: OpenAIVoiceClient
    private let recorder: any VoiceRecording
    private let keyProvider: ()->String
    private let microphonePermission: () async -> Bool
    private var apple: Dictation?
    private var target: TextTarget?
    private var sessionID: UUID?
    private var operation: Task<Void,Never>?
    private var audio: Data?
    private var filename = "recording.m4a"
    private var source = ""
    private var purpose: VoicePurpose = .dictation
    private var snapshot = VoicePreferences()
    private var recordedID: UUID?
    var working: Bool { [.permission,.transcribing,.cleaning,.inserting].contains(phase) }
    var active: Bool { working || phase == .listening }
    var canRetry: Bool { !active && sessionID != nil && (audio != nil || !raw.isEmpty) }
    var label: String {
        switch phase {
        case .permission: return T.s("Microphone permission…","Permiso de micrófono…")
        case .listening: return partial.isEmpty ? T.s("Listening…","Escuchando…") : partial
        case .transcribing: return T.s("Transcribing…","Transcribiendo…")
        case .cleaning: return T.s("Preparing text…","Preparando texto…")
        case .inserting: return T.s("Inserting…","Insertando…")
        case .draft: return T.s("Draft ready","Borrador listo")
        case .failed: return T.s("Review voice","Revisar voz")
        case .idle: return T.s("Dictate","Dictar")
        }
    }
    init(storage:VoiceStorage,client:OpenAIVoiceClient=OpenAIVoiceClient(),recorder:(any VoiceRecording)?=nil,keyProvider:(()->String)?=nil,microphonePermission:(() async ->Bool)?=nil,captureTarget:((Bool)throws->TextTarget)?=nil,deliverText:VoiceDelivery?=nil,saveCredential:((String)throws->Void)?=nil,removeCredential:(()throws->Void)?=nil,frontApp:(()->(name:String,bundle:String?))?=nil) {
        self.frontApp=frontApp ?? {let app=NSWorkspace.shared.frontmostApplication;return(app?.localizedName ?? "App",app?.bundleIdentifier)}
        self.saveCredential=saveCredential ?? VoiceKeychain.save;self.removeCredential=removeCredential ?? VoiceKeychain.remove
        self.captureTarget=captureTarget ?? {try Sender.capture(selection:$0)}
        self.deliverText=deliverText ?? {text,target,enter,method,guardTerminal,allow,done in Sender.deliver(text,to:target,enter:enter,method:method,guardTerminal:guardTerminal,allow:allow,completion:done)}
        self.storage=storage;self.client=client;self.recorder=recorder ?? VoiceRecorder()
        self.keyProvider=keyProvider ?? {VoiceKeychain.read() ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""}
        self.microphonePermission=microphonePermission ?? {
            switch AVCaptureDevice.authorizationStatus(for:.audio){case .authorized:return true;case .notDetermined:return await AVCaptureDevice.requestAccess(for:.audio);default:return false}
        }
        preferences=storage.loadPreferences();history=storage.loadHistory();refreshKey()
        if let saved=storage.loadDraft(),!saved.text.isEmpty{draft=saved.text;source=saved.source;purpose = .file;phase = .draft;message=T.s("Recovered draft. Copy it or review it; no automatic insertion after restarting.","Borrador recuperado. Cópialo o revísalo; no se inserta automáticamente tras reiniciar.")}
        self.recorder.onLevel = {[weak self] in self?.level=$0}
        self.recorder.onLimit = {[weak self] in self?.stop()}
        self.recorder.onFailure = {[weak self] in self?.cancel();self?.fail(T.s("Microphone recording failed.","Ha fallado la grabación del micrófono."))}
    }
    private func savePreferences() { do{try storage.save(preferences,name:"voice-settings.json")}catch{message=T.s("Could not save voice preferences.","No se han podido guardar los ajustes de voz.")} }
    private func key()->String { keyProvider() }
    func refreshKey() { keyConfigured = !key().isEmpty }
    func saveKey(_ value:String) { guard !active else{message=T.s("Finish voice processing before changing the key.","Termina el procesamiento de voz antes de cambiar la clave.");return};do{try saveCredential(value);refreshKey();message=T.s("Key saved in this Mac's Keychain. It will be checked on the next request.","Clave guardada en el Llavero de este Mac. Se comprobará en la próxima petición.")}catch{message=error.localizedDescription} }
    func removeKey() { guard !active else{message=T.s("Finish voice processing before changing the key.","Termina el procesamiento de voz antes de cambiar la clave.");return};do{try removeCredential();refreshKey();message=T.s("Key removed from Keychain.","Clave eliminada del Llavero.")}catch{message=error.localizedDescription} }
    private func persistDraft(){
        guard draft.utf8.count<=1_000_000 else{message=T.s("This draft is too large to save automatically. Export it before closing.","El borrador es demasiado grande para guardarlo automáticamente. Expórtalo antes de cerrar.");return}
        do{try storage.save(VoiceDraft(text:draft,source:source),name:"voice-draft.json")}catch{message=T.s("Could not save this draft on the Mac. Copy it before closing.","No se ha podido guardar el borrador en el Mac. Cópialo antes de cerrar.")}
    }
    func note(_ text:String) { message=text }
    func toggle() { if phase == .listening || phase == .permission {stop()}else if working{cancel()}else{start()} }
    func start(command:Bool=false) {
        guard !active else{return}
        guard draft.isEmpty && audio == nil else{message=T.s("Copy or discard the pending draft before recording again.","Copia o descarta el borrador pendiente antes de volver a grabar.");showWorkspace?();return}
        snapshot=preferences;purpose=command ? .command:.dictation
        // sin clave de OpenAI, Fn sigue funcionando con el dictado del Mac (en el propio equipo) y sin limpieza
        if !command && key().isEmpty && snapshot.engine == .openAI { snapshot.engine = .apple; snapshot.tone = .verbatim; snapshot.appTones = [:] }
        let app=frontApp()
        do{target = snapshot.autoPaste || command ? try captureTarget(command):nil}catch{fail(error.localizedDescription);showWorkspace?();return}
        capturedBundle=target?.bundle ?? app.bundle
        if snapshot.engine == .openAI || command || snapshot.tone(for:capturedBundle) != .verbatim { guard !key().isEmpty else{fail(VoiceServiceError.missingKey.localizedDescription);showWorkspace?();return} }
        source=target?.app ?? app.name;filename="recording.m4a";audio=nil;raw="";partial="";message="";recordedID=nil
        let id=UUID();sessionID=id;phase = .permission
        operation=Task{[weak self] in
            guard let self else{return}
            let granted=await self.microphonePermission()
            guard self.sessionID==id,!Task.isCancelled else{return}
            guard granted else{self.fail(T.s("Allow Microphone access in System Settings for Agent Deck.","Permite el micrófono para Agent Deck en Ajustes del Sistema."));return}
            if self.snapshot.engine == .apple {self.startApple(id:id)}else{
                do{try self.recorder.start();self.phase = .listening}catch{self.fail(T.s("The microphone could not start.","No se ha podido iniciar el micrófono."))}
            }
        }
    }
    private func startApple(id:UUID) {
        let a=Dictation();apple=a
        a.onLevel={[weak self] value in guard self?.sessionID==id else{return};self?.level=value}
        a.onEvent={[weak self] state,text,reason in
            guard let self,self.sessionID==id else{return}
            switch state {
            case .listening:self.phase = .listening
            case .partial:self.partial=text ?? ""
            case .final:
                self.level=0;self.partial=""
                guard let text,!text.isEmpty else{self.fail(T.s("No speech recognised.","No se ha reconocido voz."));return}
                self.process(text,id:id)
            case .idle:if self.phase == .listening || self.phase == .permission{self.phase = .idle}
            case .unavailable:self.fail(reason=="speech-denied" ? T.s("Allow Speech Recognition or select OpenAI in Voice settings.","Permite Reconocimiento de voz o selecciona OpenAI en los ajustes de Voz."):T.s("Local dictation is unavailable. You can select OpenAI in Voice settings.","El dictado local no está disponible. Puedes seleccionar OpenAI en los ajustes de Voz."))
            }
        }
        a.start()
    }
    func stop() {
        if phase == .permission{cancel();return}
        guard phase == .listening,let id=sessionID else{return}
        phase = .transcribing;level=0
        if snapshot.engine == .apple{apple?.stop();return}
        do{audio=try recorder.finish();transcribe(id:id)}catch{fail(error.localizedDescription)}
    }
    func cancel() {
        sessionID=nil;operation?.cancel();operation=nil;recorder.cancel();apple?.cancel();apple=nil;audio=nil;raw="";draft="";partial="";level=0;target=nil;phase = .idle;message="";recordedID=nil
    }
    private func transcribe(id:UUID) {
        guard let audio else{fail(T.s("No recording available to retry.","No hay una grabación disponible para reintentar."));return}
        phase = .transcribing
        operation=Task{[weak self] in
            guard let self else{return}
            do{let text=try await self.client.transcribe(audio:audio,filename:self.filename,key:self.key(),preferences:self.snapshot);guard self.sessionID==id,!Task.isCancelled else{return};self.process(text,id:id)}catch is CancellationError{}catch{guard self.sessionID==id else{return};self.fail(error.localizedDescription)}
        }
    }
    private func process(_ text:String,id:UUID) {
        raw=text;partial="";draft=purpose == .command ? target?.selectedText ?? "":text
        let tone=snapshot.tone(for:capturedBundle)
        guard purpose == .command || purpose == .summary || tone != .verbatim else{complete(snapshot.expand(text),id:id);return}
        phase = .cleaning
        operation=Task{[weak self] in
            guard let self else{return}
            do{let transformed=try await self.client.transform(text,selection:self.purpose == .command ? self.target?.selectedText:nil,key:self.key(),preferences:self.snapshot,tone:tone,summary:self.purpose == .summary);guard self.sessionID==id,!Task.isCancelled else{return};self.complete(self.snapshot.expand(transformed),id:id)}catch is CancellationError{}catch{guard self.sessionID==id else{return};self.draft=self.purpose == .command ? self.target?.selectedText ?? "":text;self.fail(error.localizedDescription)}
        }
    }
    private func complete(_ text:String,id:UUID) {
        guard sessionID==id else{return}
        draft=text;phase = .draft;message="";audio=nil
        remember(text,id:id,kind:purpose == .summary ? "summary":purpose == .command ? "edit":purpose == .file ? "file":"dictation")
        if purpose != .file && purpose != .summary && snapshot.autoPaste{insertDraft()}
    }
    private func remember(_ text:String,id:UUID,kind:String) {
        guard preferences.saveHistory,recordedID != id else{return};recordedID=id
        history.insert(VoiceRecord(id:id,text:text,source:source,kind:kind),at:0);history=Array(history.prefix(100));persistHistory()
    }
    private func persistHistory(){do{try storage.save(history,name:"voice-history.json")}catch{message=T.s("Text is ready, but history could not be saved.","El texto está listo, pero no se ha podido guardar el historial.")} }
    func insertDraft() {
        guard !active,!draft.isEmpty,let target,let id=sessionID else{message=T.s("Return to the recorded destination or copy this draft.","Vuelve al destino de la grabación o copia este borrador.");return}
        let text=draft
        phase = .inserting
        deliverText(text,target,snapshot.autoEnter && purpose != .command,snapshot.insertion,snapshot.guardTerminal,{[weak self] in self?.sessionID==id}){[weak self] result in
            guard let self,self.sessionID==id else{return}
            switch result{case .success:
                if self.draft==text{self.draft="";self.raw="";self.phase = .idle}else{self.phase = .draft;self.message=T.s("The previous version was inserted. Your edited draft is kept.","Se ha insertado la versión anterior. Se conserva el borrador editado.")}
                if self.snapshot.autoEnter && self.snapshot.guardTerminal && Sender.isTerminal(target){self.message=T.s("Pasted without Enter in a protected terminal/editor. Submit it manually.","Pegado sin Intro en un terminal/editor protegido. Envíalo manualmente.")}
                self.onDelivered?(text)
            case .failure(let error):self.phase = .draft;self.message=error.localizedDescription}
        }
    }
    func copyDraft(){guard !draft.isEmpty else{return};Sender.copy(draft);message=T.s("Copied. The draft remains available.","Copiado. El borrador sigue disponible.")}
    func useOriginal(){guard !active,!raw.isEmpty else{return};draft=purpose == .command ? target?.selectedText ?? "":raw;phase = .draft;if let id=sessionID{remember(draft,id:id,kind:"original")};message=T.s("Original transcript selected. Review before inserting.","Transcripción original seleccionada. Revísala antes de insertar.")}
    func retry(){guard !active,sessionID != nil else{return};snapshot=preferences;message="";let id=UUID();sessionID=id;recordedID=nil;if !raw.isEmpty{process(raw,id:id)}else{transcribe(id:id)}}
    func discardDraft(){cancel()}
    func shutdown(){sessionID=nil;operation?.cancel();operation=nil;recorder.cancel();apple?.cancel();apple=nil;audio=nil;level=0;target=nil;persistDraft()}
    func pasteLast(){guard let record=history.first else{message=T.s("No previous transcript.","No hay transcripción anterior.");return};Sender.send(record.text,enter:false){[weak self] result in if case .failure(let e)=result{self?.message=e.localizedDescription}}}
    func importFile(_ url:URL){
        guard !active,draft.isEmpty,audio == nil else{message=T.s("Finish the current recording or draft first.","Termina primero la grabación o el borrador actual.");return}
        guard !key().isEmpty else{fail(VoiceServiceError.missingKey.localizedDescription);return}
        do{audio=try VoiceAudioFile.read(url)}catch{fail(error.localizedDescription);return}
        filename=url.lastPathComponent;source=url.lastPathComponent;capturedBundle=nil;purpose = .file;target=nil;raw="";snapshot=preferences;let id=UUID();sessionID=id;recordedID=nil;transcribe(id:id)
    }
    func summarize(_ record:VoiceRecord){
        guard !active,draft.isEmpty,audio == nil else{message=T.s("Finish the current draft first.","Termina primero el borrador actual.");return}
        guard !key().isEmpty else{fail(VoiceServiceError.missingKey.localizedDescription);return}
        let id=UUID();sessionID=id;target=nil;source=record.source;capturedBundle=nil;purpose = .summary;snapshot=preferences;recordedID=nil;process(record.text,id:id)
    }

    func removeHistory(_ id:UUID){history.removeAll{$0.id==id};persistHistory()}
    private func fail(_ text:String){phase = .failed;level=0;message=text}
}
