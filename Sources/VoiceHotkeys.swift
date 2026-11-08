import AppKit

/// The event tap lives on the main run loop. It consumes only our Fn gesture and Escape during voice,
/// leaving normal typing and the existing deck shortcuts untouched.
@MainActor
final class VoiceHotkeys {
    private var tap: CFMachPort?
    private var runSource: CFRunLoopSource?
    private var local: Any?
    private var delayed: DispatchWorkItem?
    private var gesture=FnGesture()
    private var command=false,ownsFn=false,suppressEscapeUp=false
    private var revision=0
    private let voice: VoiceController
    var hasTap: Bool { tap != nil }
    init(voice:VoiceController){self.voice=voice}
    func install(){
        uninstall()
        local=NSEvent.addLocalMonitorForEvents(matching:.keyDown){[weak self] event in
            let consumed=MainActor.assumeIsolated{if event.keyCode==53,self?.voice.active==true{self?.cancel();return true};return false}
            return consumed ? nil:event
        }
        guard voice.preferences.fnEnabled else{voice.shortcutStatus=T.s("Fn is disabled. The Dictate button remains available.","Fn está desactivado. El botón Dictar sigue disponible.");return}
        let mask=(1<<CGEventType.flagsChanged.rawValue)|(1<<CGEventType.keyDown.rawValue)|(1<<CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = {_,type,event,ref in
            guard let ref else{return Unmanaged.passUnretained(event)}
            let handler=Unmanaged<VoiceHotkeys>.fromOpaque(ref).takeUnretainedValue()
            let consumed=MainActor.assumeIsolated{handler.handle(type,event)}
            return consumed ? nil:Unmanaged.passUnretained(event)
        }
        guard let port=CGEvent.tapCreate(tap:.cgSessionEventTap,place:.headInsertEventTap,options:.defaultTap,eventsOfInterest:CGEventMask(mask),callback:callback,userInfo:Unmanaged.passUnretained(self).toOpaque()) else{
            voice.shortcutStatus=T.s("Allow Accessibility, then reopen Voice to activate Fn. The Dictate button works without this shortcut.","Permite Accesibilidad y vuelve a abrir Voz para activar Fn. El botón Dictar funciona sin este atajo.");return
        }
        tap=port;runSource=CFMachPortCreateRunLoopSource(kCFAllocatorDefault,port,0)
        if let runSource{CFRunLoopAddSource(CFRunLoopGetMain(),runSource,.commonModes)}
        CGEvent.tapEnable(tap:port,enable:true)
        voice.shortcutStatus=T.s("Fn ready · hold, double-tap or Fn+Control · Fn+Option edits selection","Fn listo · mantener, doble toque o Fn+Control · Fn+Opción edita la selección")
    }
    func uninstall(){
        revision+=1;delayed?.cancel();delayed=nil;_ = gesture.cancel();ownsFn=false
        if let runSource{CFRunLoopRemoveSource(CFRunLoopGetMain(),runSource,.commonModes)}
        if let tap{CGEvent.tapEnable(tap:tap,enable:false);CFMachPortInvalidate(tap)}
        runSource=nil;tap=nil
        if let local{NSEvent.removeMonitor(local)};local=nil
    }
    private func cancel(){revision+=1;delayed?.cancel();_ = gesture.cancel();if voice.active{voice.cancel()};voice.dropPrewarm()}
    private func apply(_ actions:[FnGesture.Action]){
        let edit=command,epoch=revision
        for a in actions{
            if a == .cancel{cancel();continue}
            DispatchQueue.main.async{[weak self] in guard let self,self.revision==epoch else{return};switch a{case .start:self.voice.start(command:edit);case .stop:self.voice.stop();case .cancel:break}}
        }
    }
    private func canUseFn()->Bool{
        if voice.preferences.avoidVowenConflict && NSWorkspace.shared.runningApplications.contains(where:{($0.bundleIdentifier ?? "").lowercased().contains("vowen")}){
            voice.note(T.s("Quit Vowen or disable its Fn shortcut and then the conflict guard in Voice settings. Agent Bar does not change Vowen.","Cierra Vowen o desactiva su Fn y después la protección de conflictos en Voz. Agent Bar no modifica Vowen."));return false
        }
        return true
    }
    private func handle(_ type:CGEventType,_ event:CGEvent)->Bool{
        if type == .tapDisabledByTimeout{if let tap,Sender.accessibilityGranted(prompt:false){CGEvent.tapEnable(tap:tap,enable:true)};return false}
        if type == .tapDisabledByUserInput{cancel();voice.shortcutStatus=T.s("The system disabled Fn. Reopen Voice to enable it again.","El sistema ha desactivado Fn. Vuelve a abrir Voz para reactivarlo.");return false}
        let code=event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp,code==53,suppressEscapeUp{suppressEscapeUp=false;return true}
        if type == .keyDown,code==53,(voice.active || gesture.state == .holding || gesture.state == .locked){cancel();suppressEscapeUp=true;return true}
        guard voice.preferences.fnEnabled else{return false}
        let flags=NSEvent.ModifierFlags(rawValue:UInt(event.flags.rawValue)),fn=flags.contains(.function),mods=flags.intersection([.command,.control,.option,.shift])
        let now=ProcessInfo.processInfo.systemUptime
        // Release order does not matter for Fn+Control: releasing Fn first must not cancel hands-free.
        if type == .flagsChanged,code==63,!fn{
            delayed?.cancel();let owned=ownsFn;ownsFn=false;apply(gesture.up(at:now))
            // si no llegó a dictar (un toque suelto), lo grabado por adelantado se tira cuando ya no hace falta
            DispatchQueue.main.asyncAfter(deadline:.now()+0.6){[weak self] in self?.voice.dropPrewarm()}
            return owned
        }
        if type == .keyDown{if fn && code != 63{delayed?.cancel();apply(gesture.cancel())};return false}
        guard type == .flagsChanged else{return false}
        if fn && mods == [.control],(ownsFn || code==63){
            guard canUseFn() else{return false};ownsFn=true;command=false;delayed?.cancel();apply(gesture.handsFree());return true
        }
        guard mods.isEmpty || mods == [.option] else{delayed?.cancel();apply(gesture.cancel());return false}
        guard fn,(code==63 || (ownsFn && mods == [.option])) else{return false}
        guard canUseFn() else{return false}
        ownsFn=true;command=mods == [.option];if !command && !voice.active{voice.prewarm()};apply(gesture.down(at:now));delayed?.cancel()
        let work=DispatchWorkItem{[weak self] in guard let self else{return};self.apply(self.gesture.held(at:ProcessInfo.processInfo.systemUptime))}
        delayed=work;DispatchQueue.main.asyncAfter(deadline:.now()+0.185,execute:work)
        return true
    }
}
