import Foundation
import AppKit
import ApplicationServices
import Darwin

final class MockHTTP: URLProtocol, @unchecked Sendable {
    struct Reply { var status=200; var body:Data;var delay:Double=0 }
    private static let lock=NSLock()
    private static var response: ((URLRequest)->Reply)?
    private var stopped=false
    private let stateLock=NSLock()
    static func configure(_ response:@escaping(URLRequest)->Reply){lock.lock();Self.response=response;lock.unlock()}
    override class func canInit(with request:URLRequest)->Bool{true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest{request}
    override func startLoading(){
        Self.lock.lock();let handler=Self.response;Self.lock.unlock()
        guard let handler else{fatalError("No mock response configured; no real network allowed")}
        let reply=handler(request)
        DispatchQueue.global().asyncAfter(deadline:.now()+reply.delay){[weak self] in
            guard let self else{return};self.stateLock.lock();defer{self.stateLock.unlock()};guard !self.stopped else{return}
            self.client?.urlProtocol(self,didReceive:HTTPURLResponse(url:self.request.url!,statusCode:reply.status,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
            self.client?.urlProtocol(self,didLoad:reply.body);self.client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading(){stateLock.lock();stopped=true;stateLock.unlock()}
}
@MainActor
final class FakeRecorder: VoiceRecording {
    var onLevel:((Float)->Void)?,onLimit:(()->Void)?,onFailure:(()->Void)?
    var starts=0,cancels=0,finishes=0
    func start()throws{starts+=1}
    func finish()throws->Data{finishes+=1;return Data("synthetic recording only".utf8)}
    func cancel(){cancels+=1}
}
@main
struct VoiceChecks {
    @MainActor static var passed=0
    @MainActor static func check(_ name:String,_ value:@autoclosure()->Bool){guard value() else{fatalError("FAIL "+name)};passed+=1;print("PASS "+name)}
    static func json(_ value:Any)->Data{try! JSONSerialization.data(withJSONObject:value)}
    static func response(_ text:String)->Data{json(["status":"completed","output":[["type":"reasoning","summary":[]],["type":"message","content":[["type":"output_text","text":text]]]]])}
    @MainActor static func wait(_ condition:()->Bool,file:StaticString=#fileID,line:UInt=#line)async{for _ in 0..<200{if condition(){return};try? await Task.sleep(nanoseconds:5_000_000)};fatalError("Timed out waiting for synthetic operation at \(file):\(line)")}
    static func body(_ r:URLRequest)->Data{if let d=r.httpBody{return d};guard let s=r.httpBodyStream else{return Data()};s.open();defer{s.close()};var d=Data(),b=[UInt8](repeating:0,count:4096);while s.hasBytesAvailable{let n=s.read(&b,maxLength:b.count);if n<=0{break};d.append(contentsOf:b.prefix(n))};return d}
    @MainActor static func main()async throws{
        setbuf(stdout,nil)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("agentdeck-voice-tests-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        var g=FnGesture()
        check("Fn short tap does not record",g.down(at:0).isEmpty && g.up(at:0.1).isEmpty)
        check("Fn double tap locks recording",g.down(at:0.3)==[.start] && g.state == .locked)
        check("release does not stop locked recording",g.up(at:0.35).isEmpty && g.state == .locked)
        check("next Fn press stops hands-free exactly once",g.down(at:1)==[.stop] && g.up(at:1.1).isEmpty)
        _=g.down(at:2);check("hold waits for threshold",g.held(at:2.1).isEmpty);check("hold starts once",g.held(at:2.2)==[.start] && g.held(at:2.4).isEmpty)
        check("release stops a normal hold",g.up(at:2.5)==[.stop])
        _=g.down(at:3);_=g.held(at:3.2);check("Fn+Control keeps existing recording",g.handsFree().isEmpty && g.state == .locked)
        check("Escape cancels rather than submits",g.cancel()==[.cancel] && g.up(at:3.3).isEmpty)
        _=g.down(at:4);_=g.up(at:4.1);check("expired double tap becomes a fresh hold",g.down(at:5).isEmpty && g.held(at:5.2)==[.start]);_=g.cancel()
        var prefs=VoicePreferences();prefs.expansions="mi correo => test@example.invalid\nfoo => bar\nbar => baz\nprecio => $5\\total";prefs.dictionary="Kemet\n NQ \n<invalid>\n\n"
        check("expansions have word boundaries",prefs.expand("mi correo y micorreo")=="test@example.invalid y micorreo")
        check("expansions do not cascade",prefs.expand("foo bar")=="bar baz")
        check("replacement dollar and slash are literal",prefs.expand("precio")=="$5\\total")
        check("vocabulary filters invalid hint lines",prefs.keywords==["Kemet","NQ"])
        prefs.appTones["com.synthetic.chat"] = .formal;check("tone is scoped to the captured app",prefs.tone(for:"com.synthetic.chat") == .formal && prefs.tone(for:"other") == .clean)
        let storage=VoiceStorage(folder:root.appendingPathComponent("data"));try storage.save(prefs,name:"voice-settings.json");let settingsJSON=try String(contentsOf:storage.folder.appendingPathComponent("voice-settings.json"),encoding:.utf8);check("settings persist without credentials",storage.loadPreferences().expansions==prefs.expansions && !settingsJSON.contains("apiKey"))
        let attributes=try FileManager.default.attributesOfItem(atPath:storage.folder.appendingPathComponent("voice-settings.json").path);check("settings are user-private",(attributes[.posixPermissions] as? NSNumber)?.intValue==0o600)
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[MockHTTP.self];let session=URLSession(configuration:config),api=OpenAIVoiceClient(session:session)
        MockHTTP.configure{r in
            precondition(r.url?.absoluteString=="https://api.openai.com/v1/audio/transcriptions");precondition(r.value(forHTTPHeaderField:"Authorization")=="Bearer sk-synthetic-only")
            let b=String(decoding:body(r),as:UTF8.self);precondition(b.contains("name=\"model\"") && b.contains("gpt-transcribe") && b.contains("recording.m4a") && b.contains("synthetic"))
            return .init(body:json(["text":"  Hola Kemet.  "]))
        }
        let text=try await api.transcribe(audio:Data("synthetic".utf8),filename:"private-name.m4a",key:"sk-synthetic-only",preferences:prefs);check("multipart request and trimmed transcription",text=="Hola Kemet.")
        MockHTTP.configure{r in let b=try! JSONSerialization.jsonObject(with:body(r)) as! [String:Any];precondition(b["store"] as? Bool == false && b["input"] as? String != nil && b["tools"]==nil);return .init(body:response("Hola.\nSiguiente."))}
        let transformed=try await api.transform("hola",key:"sk-synthetic-only",preferences:prefs,tone:.clean);check("Responses aggregates message text after reasoning",transformed=="Hola.\nSiguiente.")
        MockHTTP.configure{_ in .init(status:401,body:json(["error":["message":"DO NOT SHOW private provider text sk-secret"]]))}
        do{_=try await api.transcribe(audio:Data([1]),filename:"a.wav",key:"sk-synthetic-only",preferences:prefs);fatalError("Expected auth error")}catch{check("provider error does not disclose body or key",!error.localizedDescription.contains("sk-secret") && !error.localizedDescription.contains("DO NOT SHOW"))}
        MockHTTP.configure{_ in .init(body:json(["status":"incomplete","output":[]]))};do{_=try await api.transform("original",key:"sk-synthetic-only",preferences:prefs,tone:.clean);fatalError("Expected incomplete error")}catch{check("incomplete AI output is rejected",error.localizedDescription.contains("incomplete") || error.localizedDescription.contains("terminado"))}
        var invalid=prefs;invalid.language="es\r\ninjected";do{_=try await api.transcribe(audio:Data([1]),filename:"a.wav",key:"sk-synthetic-only",preferences:invalid);fatalError("Expected validation error")}catch{check("invalid language rejected before request",true)}
        do{_=try await api.transcribe(audio:Data([1]),filename:"a.exe",key:"sk-synthetic-only",preferences:prefs);fatalError("Expected format error")}catch{check("unsupported file rejected",true)}
        let recorder=FakeRecorder();var permit:CheckedContinuation<Bool,Never>?
        let voice=VoiceController(storage:VoiceStorage(folder:root.appendingPathComponent("controller")),client:api,recorder:recorder,keyProvider:{"sk-synthetic-only"},microphonePermission:{await withCheckedContinuation{permit=$0}},frontApp:{("Synthetic app","test.synthetic")})
        voice.preferences.autoPaste=false;voice.preferences.tone = .verbatim
        voice.start();await wait{permit != nil};voice.stop();permit?.resume(returning:true);try? await Task.sleep(nanoseconds:20_000_000)
        check("release during permission cannot start microphone later",recorder.starts==0 && voice.phase == .idle)
        let ready=VoiceController(storage:VoiceStorage(folder:root.appendingPathComponent("ready")),client:api,recorder:recorder,keyProvider:{"sk-synthetic-only"},microphonePermission:{true},frontApp:{("Synthetic app","test.synthetic")})
        ready.preferences.autoPaste=false;ready.preferences.tone = .verbatim
        MockHTTP.configure{_ in .init(body:json(["text":"Synthetic microphone transcript."]))}
        ready.start();await wait{ready.phase == .listening};ready.stop();await wait{ready.phase == .draft};check("Fn pipeline recording→API→draft→history",ready.draft=="Synthetic microphone transcript." && ready.history.count==1 && recorder.finishes==1)
        check("text history persists",VoiceStorage(folder:root.appendingPathComponent("ready")).loadHistory().first?.text==ready.draft)
        ready.discardDraft();MockHTTP.configure{_ in .init(body:json(["text":"MUST NEVER REAPPEAR"]),delay:0.08)}
        ready.start();await wait{ready.phase == .listening};ready.stop();ready.cancel();try? await Task.sleep(nanoseconds:120_000_000)
        check("Escape discards in-flight response",ready.phase == .idle && ready.draft.isEmpty && ready.history.count==1)
        let audioFile=root.appendingPathComponent("fixture.wav");try Data("synthetic file".utf8).write(to:audioFile)
        ready.preferences.tone = .clean
        MockHTTP.configure{r in r.url!.path.contains("transcriptions") ? .init(body:json(["text":"Original transcript"] )):.init(status:429,body:json(["error":"quota"]))}
        ready.importFile(audioFile);await wait{ready.phase == .failed};check("cleanup failure keeps original draft",ready.draft=="Original transcript" && ready.raw=="Original transcript" && ready.canRetry)
        MockHTTP.configure{r in precondition(r.url!.path=="/v1/responses");return .init(body:response("Clean transcript"))}
        ready.retry();await wait{ready.phase == .draft};check("retry cleanup does not retranscribe audio",ready.draft=="Clean transcript")
        ready.discardDraft();let entry=VoiceRecord(text:"Synthetic meeting text",source:"Fixture",kind:"file")
        MockHTTP.configure{r in let b=String(decoding:body(r),as:UTF8.self);precondition(b.contains("Summarize only"));return .init(status:429,body:json(["error":"quota"]))}
        ready.summarize(entry);await wait{ready.phase == .failed}
        MockHTTP.configure{r in let b=String(decoding:body(r),as:UTF8.self);precondition(b.contains("Summarize only"));return .init(body:response("Summary, synthetic only."))}
        ready.retry();await wait{ready.phase == .draft};check("summary retry preserves its operation",ready.draft=="Summary, synthetic only." && ready.history.first?.kind=="summary")
        let capturedTarget=TextTarget(pid:424242,app:"Synthetic target",bundle:"test.synthetic.chat",field:AXUIElementCreateApplication(424242),window:nil,selection:CFRange(location:0,length:0),selectedText:nil)
        var finishDelivery:((Result<Void,Error>)->Void)?,mayDeliver:(()->Bool)?
        let deliveryVoice=VoiceController(storage:VoiceStorage(folder:root.appendingPathComponent("delivery")),client:api,recorder:FakeRecorder(),keyProvider:{"sk-synthetic-only"},microphonePermission:{true},captureTarget:{_ in capturedTarget},deliverText:{_,_,_,_,_,allow,done in mayDeliver=allow;finishDelivery=done},frontApp:{("Synthetic app","test.synthetic")})
        deliveryVoice.preferences.tone = .verbatim;deliveryVoice.preferences.autoPaste=true
        MockHTTP.configure{_ in .init(body:json(["text":"Original draft"]))}
        deliveryVoice.start();await wait{deliveryVoice.phase == .listening};deliveryVoice.stop();await wait{deliveryVoice.phase == .inserting}
        check("insertion is an active phase",deliveryVoice.active && finishDelivery != nil)
        deliveryVoice.draft="Edited while finishing";finishDelivery?(.success(()))
        check("delivery completion preserves a newer edited draft",deliveryVoice.phase == .draft && deliveryVoice.draft=="Edited while finishing")
        deliveryVoice.insertDraft();await wait{deliveryVoice.phase == .inserting};deliveryVoice.cancel()
        check("cancel invalidates pending insertion",mayDeliver?()==false)
        finishDelivery?(.success(()));check("old insertion callback cannot revive cancelled draft",deliveryVoice.phase == .idle && deliveryVoice.draft.isEmpty)
        deliveryVoice.draft="Edited while finishing"
        deliveryVoice.shutdown()
        let recovered=VoiceController(storage:VoiceStorage(folder:root.appendingPathComponent("delivery")),client:api,recorder:FakeRecorder(),keyProvider:{""},microphonePermission:{false},frontApp:{("Synthetic app","test.synthetic")})
        check("draft survives shutdown and reopening without auto-insertion",recovered.phase == .draft && recovered.draft=="Edited while finishing" && !recovered.active)
        var keyWrites=0
        let credentialVoice=VoiceController(storage:VoiceStorage(folder:root.appendingPathComponent("credentials")),client:api,recorder:FakeRecorder(),keyProvider:{"sk-synthetic-only"},microphonePermission:{true},saveCredential:{_ in keyWrites+=1;throw VoiceServiceError(message:"Synthetic Keychain failure")},removeCredential:{keyWrites+=1;throw VoiceServiceError(message:"Synthetic Keychain failure")},frontApp:{("Synthetic app","test.synthetic")})
        credentialVoice.saveKey("synthetic");check("idle credential failure does not change operation phase",credentialVoice.phase == .idle)
        credentialVoice.preferences.autoPaste=false;credentialVoice.preferences.tone = .verbatim;credentialVoice.start();await wait{credentialVoice.phase == .listening};let priorWrites=keyWrites
        credentialVoice.saveKey("other");credentialVoice.removeKey();check("key mutations are rejected during recording without losing active state",credentialVoice.phase == .listening && keyWrites==priorWrites)
        credentialVoice.cancel()
        ready.discardDraft();MockHTTP.configure{r in r.url!.path.contains("transcriptions") ? .init(body:json(["text":"Recover this transcript"])):.init(body:response("Too late"),delay:0.1)}
        ready.importFile(audioFile);await wait{ready.phase == .cleaning};ready.shutdown()
        let recoveredProcessing=VoiceController(storage:VoiceStorage(folder:root.appendingPathComponent("ready")),client:api,recorder:FakeRecorder(),keyProvider:{""},microphonePermission:{false},frontApp:{("Synthetic app","test.synthetic")})
        check("shutdown during cleanup preserves the original transcript",recoveredProcessing.draft=="Recover this transcript" && recoveredProcessing.phase == .draft)
        try? await Task.sleep(nanoseconds:150_000_000);check("cancelled cleanup cannot overwrite recovered transcript",recoveredProcessing.draft=="Recover this transcript")
        let oldSettings=try? JSONDecoder().decode(VoicePreferences.self,from:Data(#"{"engine":"apple","autoEnter":false,"tone":"formal"}"#.utf8))
        check("older settings files keep their values and get new defaults",oldSettings?.engine == .apple && oldSettings?.autoEnter == false && oldSettings?.tone == .formal && oldSettings?.promptInAIApps == true)
        check("voice sends with Enter by default (Diego, 06/11), terminals stay guarded",VoicePreferences().autoEnter && VoicePreferences().guardTerminal)
        var localPermissionRequests=0
        let localOverride=VoiceController(storage:VoiceStorage(folder:root.appendingPathComponent("tone-local")),client:api,recorder:FakeRecorder(),keyProvider:{""},microphonePermission:{localPermissionRequests+=1;return false},frontApp:{("Synthetic", "test.synthetic")})
        localOverride.preferences.engine = .apple;localOverride.preferences.autoPaste=false;localOverride.preferences.tone = .clean;localOverride.preferences.appTones["test.synthetic"] = .verbatim
        localOverride.start();await wait{localOverride.phase == .failed};check("per-app verbatim override does not require OpenAI key",localPermissionRequests==1)
        var appleAsks=0
        let appleDefault=VoiceController(storage:VoiceStorage(folder:root.appendingPathComponent("apple-default")),client:api,recorder:FakeRecorder(),keyProvider:{""},microphonePermission:{appleAsks+=1;return false},frontApp:{("Synthetic", "test.synthetic")})
        appleDefault.preferences.engine = .apple;appleDefault.preferences.autoPaste=false;appleDefault.preferences.tone = .clean
        appleDefault.start();await wait{appleDefault.phase == .failed};check("Apple works without an OpenAI key on default settings",appleAsks==1)
        let cloudOverride=VoiceController(storage:VoiceStorage(folder:root.appendingPathComponent("tone-cloud")),client:api,recorder:FakeRecorder(),keyProvider:{""},microphonePermission:{localPermissionRequests+=1;return false},frontApp:{("Synthetic", "test.synthetic")})
        cloudOverride.preferences.engine = .apple;cloudOverride.preferences.autoPaste=false;cloudOverride.preferences.tone = .verbatim;cloudOverride.preferences.appTones["test.synthetic"] = .clean
        cloudOverride.start();check("per-app cleanup requires key before recording",cloudOverride.phase == .failed && localPermissionRequests==1)
        check("restored draft offers copy, not insertion into stale target",!recovered.canInsertOriginal)
        let regularAudio=try VoiceAudioFile.read(audioFile);check("regular local audio file is read within cap",regularAudio==Data("synthetic file".utf8))
        let huge=root.appendingPathComponent("huge.wav");FileManager.default.createFile(atPath:huge.path,contents:nil);let writer=try FileHandle(forWritingTo:huge);try writer.truncate(atOffset:26_000_000);try writer.close()
        do{_=try VoiceAudioFile.read(huge);fatalError("Expected size rejection")}catch{check("oversized regular file rejected before allocation/upload",true)}
        let link=root.appendingPathComponent("linked.wav");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:huge)
        ready.discardDraft();ready.importFile(link);check("symlink cannot bypass limit or retain oversized audio",ready.phase == .failed && !ready.canRetry)
        let pipe=root.appendingPathComponent("pipe.wav");guard mkfifo(pipe.path,0o600)==0 else{fatalError("fixture fifo")}
        do{_=try VoiceAudioFile.read(pipe);fatalError("Expected pipe rejection")}catch{check("pipe is rejected without waiting for a writer",true)}
        // órdenes dichas al final
        let c1=SpokenCommands.parse("Revisa el login, y envíalo.");check("spoken «y envíalo» sends and is removed",c1.text=="Revisa el login" && c1.send==true)
        let c2=SpokenCommands.parse("Arregla el test, no lo envíes");check("spoken «no lo envíes» holds Enter",c2.text=="Arregla el test" && c2.send==false)
        check("spoken «cancela» cancels",SpokenCommands.parse("Esto es una prueba, cancela.").cancel)
        check("spoken «nueva línea» becomes a line break",SpokenCommands.parse("uno nueva línea dos").text=="uno\ndos")
        let c3=SpokenCommands.parse("Revisa la PR en inglés y envía");check("spoken rewrite + send combine",c3.text=="Revisa la PR" && c3.send==true && c3.rewrite?.contains("English")==true)
        check("normal sentences with «envío» are untouched",SpokenCommands.parse("La hora de envío es mañana").send==nil && SpokenCommands.parse("No quiero que se envíe nada raro").text=="No quiero que se envíe nada raro")
        session.invalidateAndCancel();print("VOICE_CHECKS_OK \(passed) — synthetic only; no microphone, AX target, Keychain write, real API or external message")
    }
}
