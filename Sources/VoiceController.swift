import AppKit
import AVFoundation
import Combine
import Speech

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
    /// Resultado de «Probar clave»: si la clave vale, si hay saldo y si llega a los modelos elegidos.
    @Published var keyTest = ""
    @Published var keyTesting = false
    /// Estado del motor de Apple, en una línea, para los ajustes de Voz.
    @Published var appleStatus = ""

    /// Prueba la clave sin grabar nada: lista el modelo de transcripción y hace una llamada mínima al de texto
    /// (unas centésimas de céntimo), que es la que dice si hay saldo.
    func testKey() {
        let k=key()
        guard !k.isEmpty else { keyTest=T.s("No key saved yet.","Aún no hay ninguna clave guardada.");return }
        keyTesting=true;keyTest=T.s("Testing…","Probando…")
        let tm=preferences.transcriptionModel, xm=preferences.textModel
        Task{ [weak self] in
            func call(_ r:URLRequest) async -> (Int,String) {
                guard let (d,resp)=try? await URLSession.shared.data(for:r),let h=resp as? HTTPURLResponse else{return (-1,"")}
                let m=((try? JSONSerialization.jsonObject(with:d)) as? [String:Any]).flatMap{($0["error"] as? [String:Any])?["code"] as? String ?? ($0["error"] as? [String:Any])?["type"] as? String} ?? ""
                return (h.statusCode,m)
            }
            var a=URLRequest(url:URL(string:"https://api.openai.com/v1/models/\(tm)")!);a.setValue("Bearer \(k)",forHTTPHeaderField:"Authorization")
            let (s1,c1)=await call(a)
            var out:String
            if s1 == -1 { out=T.s("Couldn't reach OpenAI. Check your connection.","No se ha podido conectar con OpenAI. Revisa la conexión.") }
            else if s1 == 401 { out=T.s("OpenAI says the key is wrong. Paste it again (it starts with sk-).","OpenAI dice que la clave no es correcta. Vuelve a pegarla (empieza por sk-).") }
            else if s1 == 404 || s1 == 403 { out=T.s("The key works, but has no access to \(tm). Change the transcription model.","La clave vale, pero no tiene acceso a \(tm). Cambia el modelo de transcripción.") }
            else {
                var b=URLRequest(url:URL(string:"https://api.openai.com/v1/responses")!);b.httpMethod="POST"
                b.setValue("Bearer \(k)",forHTTPHeaderField:"Authorization");b.setValue("application/json",forHTTPHeaderField:"Content-Type")
                b.httpBody=try? JSONSerialization.data(withJSONObject:["model":xm,"input":"ok","max_output_tokens":16,"store":false])
                let (s2,c2)=await call(b)
                if (200..<300).contains(s2) { out=T.s("✓ Key works, with credit, for \(tm) and \(xm).","✓ La clave funciona, con saldo, para \(tm) y \(xm).") }
                else if s2 == 429 && (c2.contains("quota") || c1.contains("quota")) { out=T.s("The key is right but the account has no credit. Add credit at platform.openai.com → Billing.","La clave es correcta, pero la cuenta no tiene saldo. Añádelo en platform.openai.com → Billing.") }
                else if s2 == 429 { out=T.s("OpenAI's rate limit was hit. Try again in a minute.","Has llegado al límite de OpenAI. Prueba otra vez en un minuto.") }
                else if s2 == 404 || s2 == 403 || s2 == 400 { out=T.s("The key works for \(tm), but not for \(xm). Change the text model.","La clave vale para \(tm), pero no para \(xm). Cambia el modelo de texto.") }
                else { out=T.s("OpenAI answered with error \(s2).","OpenAI ha respondido con el error \(s2).") }
            }
            await MainActor.run{ self?.keyTest=out;self?.keyTesting=false;self?.log("probar clave: "+out) }
        }
    }

    /// El motor de Apple, sin jerga: si tiene permiso y si funciona en este Mac.
    func refreshAppleStatus() {
        let speech=SFSpeechRecognizer.authorizationStatus(),mic=AVCaptureDevice.authorizationStatus(for:.audio)
        let r=SFSpeechRecognizer(locale:T.speechLocale)
        if speech == .denied || speech == .restricted { appleStatus=T.s("Speech recognition is blocked. Turn it on in System Settings → Privacy & Security → Speech Recognition.","El reconocimiento de voz está bloqueado. Actívalo en Ajustes del Sistema → Privacidad y seguridad → Reconocimiento de voz.") }
        else if mic == .denied || mic == .restricted { appleStatus=T.s("The microphone is blocked for Agent Bar in System Settings → Privacy & Security → Microphone.","El micrófono está bloqueado para Agent Bar en Ajustes del Sistema → Privacidad y seguridad → Micrófono.") }
        else if speech == .notDetermined || mic == .notDetermined { appleStatus=T.s("Ready once you allow it: press «Allow» (macOS asks once).","Listo en cuanto lo permitas: pulsa «Permitir» (macOS lo pregunta una vez).") }
        else if r?.isAvailable != true { appleStatus=T.s("Apple dictation isn't available right now (check the internet or the language).","El dictado de Apple no está disponible ahora (revisa internet o el idioma).") }
        else { appleStatus=(r?.supportsOnDeviceRecognition == true) ? T.s("✓ Ready, on this Mac, free and without a key.","✓ Listo, en este Mac, gratis y sin clave.") : T.s("✓ Ready, free and without a key (uses Apple's dictation).","✓ Listo, gratis y sin clave (usa el dictado de Apple).") }
    }
    func allowApple() {
        SFSpeechRecognizer.requestAuthorization{ [weak self] _ in
            Task{ @MainActor in
                if AVCaptureDevice.authorizationStatus(for:.audio) == .notDetermined { _ = await AVCaptureDevice.requestAccess(for:.audio) }
                self?.refreshAppleStatus()
            }
        }
    }
    var onShortcutsChanged: (()->Void)?
    var onDelivered: ((String)->Void)?
    /// Desde que se suelta Fn hasta que el texto entra en el chat, y si fue con el tiempo real: «Listo en 0,4 s».
    private var releasedAt: Date?
    private var usedLive = false
    private(set) var lastLatency: TimeInterval?
    /// En la app de verdad, el dictado a un chat va por el camino de las teclas; las pruebas usan su entrega falsa.
    private let usesQuickSend: Bool
    /// Grabadora arrancada al pulsar Fn, antes de saber si es una pulsación larga: así no se pierde el principio.
    private var prewarmed = false

    /// Fn acaba de bajar: si el micro ya tiene permiso y hay clave, se empieza a grabar ya mismo.
    func prewarm() {
        guard usesQuickSend, !active, !prewarmed, draft.isEmpty, preferences.engine == .openAI, !key().isEmpty,
              AVCaptureDevice.authorizationStatus(for:.audio) == .authorized else { return }
        do { try recorder.start(); prewarmed = true; startLive() } catch { prewarmed = false }
    }
    /// Transcribir mientras hablas: conexión en tiempo real con OpenAI, en paralelo a la grabación normal (red de seguridad).
    private let live = RealtimeTranscriber()
    private func startLive() {
        guard usesQuickSend, preferences.streaming, preferences.engine == .openAI, !live.running else { return }
        let k = key(); guard !k.isEmpty else { return }
        live.onPartial = { [weak self] t in guard let self, self.preferences.showLiveText, self.phase == .listening || self.prewarmed else { return }; self.partial = t }
        _ = live.start(key: k, model: preferences.liveModel, languages: preferences.spokenLanguages, keywords: preferences.keywords)
    }
    /// Fn subió sin llegar a dictar (un toque, o un atajo con Fn): se tira lo grabado.
    func dropPrewarm() {
        guard prewarmed, !active else { return }
        prewarmed = false; recorder.cancel(); live.cancel()
    }
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
    /// Por debajo de este pico (dB) solo se oían voces lejanas y no se envía nada.
    static let nearVoiceDB: Float = -34
    private var target: TextTarget?
    /// El destino es solo la app de delante (no se supo el campo): se entrega por el camino rápido.
    private var loose=false
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
        case .failed: return message.isEmpty ? T.s("Review voice","Revisar voz") : message // el motivo real, unos segundos
        case .idle: return T.s("Dictate","Dictar")
        }
    }
    init(storage:VoiceStorage,client:OpenAIVoiceClient=OpenAIVoiceClient(),recorder:(any VoiceRecording)?=nil,keyProvider:(()->String)?=nil,microphonePermission:(() async ->Bool)?=nil,captureTarget:((Bool)throws->TextTarget)?=nil,deliverText:VoiceDelivery?=nil,saveCredential:((String)throws->Void)?=nil,removeCredential:(()throws->Void)?=nil,frontApp:(()->(name:String,bundle:String?))?=nil) {
        self.frontApp=frontApp ?? {let app=NSWorkspace.shared.frontmostApplication;return(app?.localizedName ?? "App",app?.bundleIdentifier)}
        self.saveCredential=saveCredential ?? VoiceKeychain.save;self.removeCredential=removeCredential ?? VoiceKeychain.remove
        self.captureTarget=captureTarget ?? {try Sender.capture(selection:$0)}
        self.usesQuickSend = deliverText == nil
        self.deliverText=deliverText ?? {text,target,enter,method,guardTerminal,allow,done in Sender.deliver(text,to:target,enter:enter,method:method,guardTerminal:guardTerminal,verifyBeforeEnter:false,allow:allow,completion:done)} // los chats tardan en reflejar el pegado: Intro solo exige seguir en el mismo campo
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
    func saveKey(_ value:String) {
        // una clave de OpenAI empieza por «sk-» y es larga: así no se guarda una letra suelta al pegar mal
        let v=value.trimmingCharacters(in:.whitespacesAndNewlines)
        guard v.hasPrefix("sk-"),v.count>=20 else{message=T.s("That doesn't look like an OpenAI key (it starts with sk-). Paste it with ⌘V.","Eso no parece una clave de OpenAI (empieza por sk-). Pégala con ⌘V.");return}
        guard !active else{message=T.s("Finish voice processing before changing the key.","Termina el procesamiento de voz antes de cambiar la clave.");return};do{try saveCredential(value);refreshKey();message=T.s("Key saved on this Mac (only your user can read it). Press «Test key» to check it.","Clave guardada en este Mac (solo tu usuario puede leerla). Pulsa «Probar clave» para comprobarla.")}catch{message=error.localizedDescription} }
    func removeKey() { guard !active else{message=T.s("Finish voice processing before changing the key.","Termina el procesamiento de voz antes de cambiar la clave.");return};do{try removeCredential();refreshKey();message=T.s("Key removed.","Clave eliminada.")}catch{message=error.localizedDescription} }
    private func persistDraft(){
        guard draft.utf8.count<=1_000_000 else{message=T.s("This draft is too large to save automatically. Export it before closing.","El borrador es demasiado grande para guardarlo automáticamente. Expórtalo antes de cerrar.");return}
        do{try storage.save(VoiceDraft(text:draft,source:source),name:"voice-draft.json")}catch{message=T.s("Could not save this draft on the Mac. Copy it before closing.","No se ha podido guardar el borrador en el Mac. Cópialo antes de cerrar.")}
    }
    func note(_ text:String) { message=text }
    func toggle() { if phase == .listening || phase == .permission {stop()}else if working{cancel()}else{start()} }
    func start(command:Bool=false) {
        guard !active else{return}
        if !draft.isEmpty && audio == nil && !active { if recordedID == nil { remember(draft,id:UUID(),kind:"draft") }; cancel() }
        guard draft.isEmpty && audio == nil else{message=T.s("Copy or discard the pending draft before recording again.","Copia o descarta el borrador pendiente antes de volver a grabar.");showWorkspace?();return}
        snapshot=preferences;purpose=command ? .command:.dictation
        // sin clave de OpenAI, Fn sigue funcionando con el dictado del Mac (en el propio equipo) y sin limpieza
        if !command && key().isEmpty && snapshot.engine == .openAI { snapshot.engine = .apple; snapshot.tone = .verbatim; snapshot.appTones = [:] }
        let app=frontApp()
        loose=false
        do{target = snapshot.autoPaste || command ? try captureTarget(command):nil}catch{
            // Sin campo conocido (Claude, ChatGPT y otras apps Electron a veces no lo dicen): se graba igual y se pega
            // donde esté el cursor, como las teclas de la barra. Los campos de contraseña y el modo edición siguen fuera.
            if !command, (error as? VoiceServiceError)?.message == Sender.noFocusedField.message, let t=Sender.looseTarget() { target=t;loose=true;log("sin campo conocido en "+t.app+": se pegará donde esté el cursor") }
            else { fail(error.localizedDescription);log("  ↳ app: "+app.name);showWorkspace?();return }
        }
        capturedBundle=target?.bundle ?? app.bundle
        // Apple sin clave de OpenAI: se escribe tal cual (limpiar necesitaría la clave), salvo un tono puesto a propósito para esa app
        if !command && key().isEmpty && snapshot.engine == .apple && snapshot.appTones[capturedBundle ?? ""] == nil { snapshot.tone = .verbatim }
        if snapshot.engine == .openAI || command || snapshot.tone(for:capturedBundle) != .verbatim { guard !key().isEmpty else{fail(VoiceServiceError.missingKey.localizedDescription);showWorkspace?();return} }
        source=target?.app ?? app.name;filename="recording.m4a";audio=nil;raw="";partial="";message="";recordedID=nil
        let id=UUID();sessionID=id;phase = .permission
        operation=Task{[weak self] in
            guard let self else{return}
            let granted=await self.microphonePermission()
            guard self.sessionID==id,!Task.isCancelled else{return}
            guard granted else{self.fail(T.s("Allow Microphone access in System Settings for Agent Bar.","Permite el micrófono para Agent Bar en Ajustes del Sistema."));return}
            if self.snapshot.engine == .apple {self.startApple(id:id)}else{
                if self.prewarmed { self.prewarmed=false;self.phase = .listening;return } // ya grababa desde que bajó Fn
                do{try self.recorder.start();self.phase = .listening;self.startLive()}catch{self.fail(T.s("The microphone could not start.","No se ha podido iniciar el micrófono."))}
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
        // Solo voces lejanas (la mesa de al lado, una tele): no se envía nada. Tu voz cerca del micro pasa de ~-28 dB;
        // la de otros a un metro se queda por debajo (Diego, 09/11: «se ha colado» varias veces). Cada pico queda en voice.log.
        let loudest=recorder.peakDB
        if snapshot.engine == .openAI && loudest > -160 {
            log(String(format:"pico %.0f dB",loudest))
            if usesQuickSend && loudest < VoiceController.nearVoiceDB {
                cancel();fail(T.s("Only distant voices: nothing was sent.","Solo voces lejanas: no he enviado nada."));return
            }
        }
        phase = .transcribing;level=0;releasedAt=Date();usedLive=false;lastLatency=nil
        if snapshot.engine == .apple{apple?.stop();return}
        // un cuarto de segundo más tras soltar, para no cortar la última palabra (solo en la app de verdad)
        let tail = usesQuickSend ? 0.25 : 0
        let finish = { [weak self] in
            guard let self, self.sessionID==id, self.phase == .transcribing else { return }
            let batch = { do{self.audio=try self.recorder.finish();self.transcribe(id:id)}catch{self.fail(error.localizedDescription)} }
            guard self.live.running else { batch(); return }
            // el texto en tiempo real ya está casi listo; si no llega en 3 s, la grabación normal
            self.live.finish(timeout: 3) { [weak self] text in
                guard let self, self.sessionID==id, self.phase == .transcribing else { return }
                if let text, !text.isEmpty { self.recorder.cancel(); self.audio=nil; self.usedLive=true; self.process(text,id:id) }
                else { if !VoiceServiceError.lastDetail.isEmpty { self.log("tiempo real: sin texto, uso la grabación") }; batch() }
            }
        }
        if tail > 0 { DispatchQueue.main.asyncAfter(deadline:.now()+tail, execute:finish) } else { finish() }
    }
    func cancel() {
        prewarmed=false;live.cancel()
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
        var tone=snapshot.tone(for:capturedBundle)
        // Voz → prompt: en un chat de IA, lo que pasa de 12 palabras se ordena como un prompt (salvo un tono propio para esa app)
        let words=text.split(whereSeparator:{$0.isWhitespace}).count
        if purpose == .dictation, snapshot.promptInAIApps, tone != .verbatim, words > 12,
           let b=capturedBundle, VoicePreferences.aiApps.contains(b), snapshot.appTones[b] == nil { tone = .prompt }
        guard purpose == .command || purpose == .summary || tone != .verbatim else{complete(snapshot.expand(text),id:id);return}
        // una frase corta ya viene bien puntuada de la transcripción: se pega sin esperar a la limpieza
        if purpose == .dictation && text.split(whereSeparator:{$0.isWhitespace}).count <= 6 { complete(snapshot.expand(text),id:id);return }
        phase = .cleaning
        // tope de espera: si la limpieza tarda más de 2,5 s, se pega lo transcrito tal cual
        if purpose == .dictation {
            DispatchQueue.main.asyncAfter(deadline:.now()+(tone == .prompt ? 7 : 2.5)){[weak self] in
                guard let self,self.sessionID==id,self.phase == .cleaning else{return}
                self.operation?.cancel();self.operation=nil
                self.complete(self.snapshot.expand(text),id:id)
            }
        }
        operation=Task{[weak self] in
            guard let self else{return}
            do{let transformed=try await self.client.transform(text,selection:self.purpose == .command ? self.target?.selectedText:nil,key:self.key(),preferences:self.snapshot,tone:tone,summary:self.purpose == .summary);guard self.sessionID==id,!Task.isCancelled else{return};self.complete(self.snapshot.expand(transformed),id:id)}catch is CancellationError{}catch{guard self.sessionID==id else{return}
                // como Vowen: si la limpieza falla en una dictado, se pega lo transcrito tal cual en vez de pararse
                if self.purpose == .dictation { self.note(error.localizedDescription);self.complete(self.snapshot.expand(text),id:id);return }
                self.draft=self.purpose == .command ? self.target?.selectedText ?? "":text;self.fail(error.localizedDescription)}
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
        // Dictado a un chat que sigue delante: el mismo camino que las teclas de la barra, que sí envía en Claude,
        // ChatGPT o Cursor. Los terminales protegidos y la edición de una selección siguen por el camino con comprobaciones.
        let protectedTerminal = snapshot.guardTerminal && Sender.isTerminal(target)
        if usesQuickSend || loose, purpose == .dictation, loose || (snapshot.insertion == .paste && !protectedTerminal),
           NSWorkspace.shared.frontmostApplication?.bundleIdentifier == target.bundle {
            if let r=releasedAt { lastLatency=Date().timeIntervalSince(r)+0.17;releasedAt=nil
                log(String(format:"listo en %.2f s (%@)",lastLatency!,usedLive ? "tiempo real" : "grabación")) }
            Sender.quickSend(text,enter:snapshot.autoEnter && !protectedTerminal){[weak self] result in
                guard let self,self.sessionID==id else{return}
                if case .failure(let e)=result{Sender.copy(text);self.log("envío rápido: "+e.localizedDescription)}
                if self.draft==text{self.draft="";self.raw="";self.phase = .idle}
                self.onDelivered?(text)
            }
            return
        }
        deliverText(text,target,snapshot.autoEnter && purpose != .command,snapshot.insertion,snapshot.guardTerminal,{[weak self] in self?.sessionID==id}){[weak self] result in
            guard let self,self.sessionID==id else{return}
            switch result{case .success:
                if self.draft==text{self.draft="";self.raw="";self.phase = .idle}else{self.phase = .draft;self.message=T.s("The previous version was inserted. Your edited draft is kept.","Se ha insertado la versión anterior. Se conserva el borrador editado.")}
                if self.snapshot.autoEnter && self.snapshot.guardTerminal && Sender.isTerminal(target){self.message=T.s("Pasted without Enter in a protected terminal/editor. Submit it manually.","Pegado sin Intro en un terminal/editor protegido. Envíalo manualmente.")}
                self.onDelivered?(text)
            case .failure(let error):
                // sin «Borrador listo» colgado: el texto queda en el historial y en el portapapeles para pegarlo a mano
                if !(error is CancellationError) { Sender.copy(text);self.log("envío: "+error.localizedDescription) }
                self.draft="";self.raw="";self.phase = .idle;self.message=""}
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
    /// Solo motivos, nunca lo dictado: en Application Support/Agent Deck/voice.log.
    func log(_ text:String){
        let detail=VoiceServiceError.lastDetail;VoiceServiceError.lastDetail=""
        let line="\(ISO8601DateFormatter().string(from:Date())) \(snapshot.engine.rawValue) \(snapshot.transcriptionModel)/\(snapshot.textModel) \(text)\(detail.isEmpty ? "" : " · "+detail)\n"
        let file=storage.folder.appendingPathComponent("voice.log")
        if let h=try? FileHandle(forWritingTo:file){h.seekToEndOfFile();h.write(Data(line.utf8));try? h.close()}else{try? Data(line.utf8).write(to:file)}
    }
    private func fail(_ text:String){
        phase = .failed;level=0;message=text
        // solo el motivo, nunca lo dictado: en Application Support/Agent Deck/voice.log
        log(text)
        // el aviso no se queda para siempre: a los 6 s vuelve a reposo; lo dictado queda en el historial
        let failedSession=sessionID
        DispatchQueue.main.asyncAfter(deadline:.now()+6){[weak self] in
            guard let self,self.phase == .failed,self.sessionID==failedSession else{return}
            if !self.draft.isEmpty{if self.recordedID == nil{self.remember(self.draft,id:UUID(),kind:"draft")};self.draft=""}
            self.raw="";self.audio=nil;self.message="";self.phase = .idle
        }
    }
}
