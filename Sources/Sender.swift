import AppKit
import ApplicationServices

typealias VoiceDelivery = @MainActor (String,TextTarget,Bool,VoiceInsertion,Bool,@escaping()->Bool,@escaping(Result<Void,Error>)->Void)->Void

/// The target is captured before recording. Processing must never redirect a draft into a different app/field.
@MainActor
struct TextTarget {
    let pid: pid_t
    let app: String
    let bundle: String
    let field: AXUIElement
    let window: AXUIElement?
    let selection: CFRange?
    let selectedText: String?
}
@MainActor
enum Sender {
    static let keyV: CGKeyCode = 9, keyReturn: CGKeyCode = 36, keyC: CGKeyCode = 8

    /// Lo seleccionado en la app de delante: por Accesibilidad si la app lo da y, si no, con ⌘C
    /// (devolviendo después el portapapeles como estaba).
    static func copySelection(_ done: @escaping (String?) -> Void) {
        if let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier,
           let f = focused(app.processIdentifier), let s = attribute(f, kAXSelectedTextAttribute) as? String,
           !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { done(s); return }
        let pb = NSPasteboard.general, before = pb.changeCount
        let saved = pb.pasteboardItems?.map { item in Dictionary(uniqueKeysWithValues: item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }) } ?? []
        tap(keyC, flags: .maskCommand)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard pb.changeCount != before else { done(nil); return }
            let s = pb.string(forType: .string)
            pb.clearContents()
            let items = saved.map { entry -> NSPasteboardItem in let i = NSPasteboardItem(); for (t, d) in entry { i.setData(d, forType: t) }; return i }
            if !items.isEmpty { pb.writeObjects(items) }
            done(s)
        }
    }
    private static var delivering = false
    private static var deliveryRevision=0
    private static var pendingRestore:(()->Void)?
    static func shutdown(){deliveryRevision+=1;pendingRestore?();pendingRestore=nil;delivering=false}
    static func accessibilityGranted(prompt:Bool)->Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:prompt] as CFDictionary)
    }
    private static func attribute(_ element:AXUIElement,_ name:String)->CFTypeRef? {
        var value:CFTypeRef?;guard AXUIElementCopyAttributeValue(element,name as CFString,&value) == .success else { return nil };return value
    }
    private static func focused(_ pid:pid_t)->AXUIElement? {
        guard let value = attribute(AXUIElementCreateApplication(pid),kAXFocusedUIElementAttribute),CFGetTypeID(value)==AXUIElementGetTypeID() else { return nil };return unsafeBitCast(value,to:AXUIElement.self)
    }
    private static func range(_ field:AXUIElement)->CFRange? {
        guard let value = attribute(field,kAXSelectedTextRangeAttribute),CFGetTypeID(value)==AXValueGetTypeID() else { return nil }
        let ax = unsafeBitCast(value,to:AXValue.self);var r = CFRange();guard AXValueGetValue(ax,.cfRange,&r) else { return nil };return r
    }
    /// Algunas apps (Electron, webs) no dicen por Accesibilidad qué campo tiene el cursor.
    static let noFocusedField = VoiceServiceError(message:T.s("Place the cursor in the destination text field first.","Coloca primero el cursor en el campo de texto de destino."))
    /// Destino sin campo conocido: la app de delante. Solo para pegar donde esté el cursor (el camino de las teclas de la barra).
    static func looseTarget()->TextTarget? {
        guard accessibilityGranted(prompt:false),let app = NSWorkspace.shared.frontmostApplication,app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        return TextTarget(pid:app.processIdentifier,app:app.localizedName ?? "App",bundle:app.bundleIdentifier ?? "",field:AXUIElementCreateApplication(app.processIdentifier),window:nil,selection:nil,selectedText:nil)
    }
    static func capture(selection:Bool = false)throws->TextTarget {
        guard accessibilityGranted(prompt:false) else { throw VoiceServiceError(message:T.s("Allow Accessibility to insert text. Your draft is kept.","Permite Accesibilidad para insertar texto. Se conserva el borrador.")) }
        guard let app = NSWorkspace.shared.frontmostApplication,app.bundleIdentifier != Bundle.main.bundleIdentifier,let field = focused(app.processIdentifier) else { throw noFocusedField }
        let role = attribute(field,kAXRoleAttribute) as? String ?? "",subrole = attribute(field,kAXSubroleAttribute) as? String ?? ""
        var settable = DarwinBoolean(false);AXUIElementIsAttributeSettable(field,kAXSelectedTextAttribute as CFString,&settable)
        guard subrole != kAXSecureTextFieldSubrole,([kAXTextFieldRole,kAXTextAreaRole,kAXComboBoxRole].contains(role)||settable.boolValue) else { throw VoiceServiceError(message:T.s("The focused item cannot receive dictation. Password fields are excluded.","El elemento seleccionado no admite dictado. Los campos de contraseña están excluidos.")) }
        let selected = selection ? attribute(field,kAXSelectedTextAttribute) as? String : nil
        if selection && (selected?.isEmpty ?? true) { throw VoiceServiceError(message:T.s("Select text before using Command Mode.","Selecciona texto antes de usar el modo de edición.")) }
        let windowValue = attribute(field,kAXWindowAttribute)
        let window = windowValue.flatMap { CFGetTypeID($0)==AXUIElementGetTypeID() ? unsafeBitCast($0,to:AXUIElement.self) : nil }
        return TextTarget(pid:app.processIdentifier,app:app.localizedName ?? "App",bundle:app.bundleIdentifier ?? "",field:field,window:window,selection:range(field),selectedText:selected)
    }
    static func matches(_ target:TextTarget,selection:Bool)->Bool {
        guard accessibilityGranted(prompt:false),NSWorkspace.shared.frontmostApplication?.processIdentifier==target.pid,let field=focused(target.pid),CFEqual(field,target.field),(attribute(field,kAXSubroleAttribute) as? String) != kAXSecureTextFieldSubrole else { return false }
        if let window=target.window { guard let value=attribute(field,kAXWindowAttribute),CFEqual(value,window) else { return false } }
        if selection {
            if let original=target.selection { guard let now=range(field),original.location==now.location,original.length==now.length else { return false } }
            if let original=target.selectedText,attribute(field,kAXSelectedTextAttribute) as? String != original { return false }
        }
        return true
    }
    /// Las teclas de la barra: el camino sencillo de siempre (pegar, Intro a los 0,12 s y devolver el portapapeles).
    /// Es el que funciona en los chats Electron y web, donde las comprobaciones por Accesibilidad fallan.
    static func send(_ text:String,enter:Bool,completion:((Result<Void,Error>)->Void)? = nil) {
        quickSend(text,enter:enter,completion:completion)
    }
    static func quickSend(_ text:String,enter:Bool,confirmEnter:Bool = false,completion:((Result<Void,Error>)->Void)? = nil) {
        guard accessibilityGranted(prompt:true) else { completion?(.failure(VoiceServiceError(message:T.s("Allow Accessibility so Agent Bar can type into the chat.","Permite Accesibilidad para que Agent Bar pueda escribir en el chat."))));return }
        let pasteboard=NSPasteboard.general
        let previous=pasteboard.pasteboardItems?.map{item in Dictionary(uniqueKeysWithValues:item.types.compactMap{type in item.data(forType:type).map{(type,$0)}})} ?? []
        let item=NSPasteboardItem();item.setString(text,forType:.string)
        for marker in ["org.nspasteboard.TransientType","org.nspasteboard.AutoGeneratedType"] { item.setData(Data(),forType:NSPasteboard.PasteboardType(marker)) }
        pasteboard.clearContents();pasteboard.writeObjects([item]);let written=pasteboard.changeCount
        // El pegado va a la app activa; el panel no activa Agent Deck, así que el chat sigue delante.
        // un texto largo tarda más en entrar en el chat: el Intro espera en proporción (antes, 0,12 s fijos, y un dictado
        // de minuto y medio se quedaba sin enviar, 09/11); el portapapeles se devuelve cuando ya ha entrado todo
        let enterDelay=min(0.9,0.12+Double(text.count)/1500)
        DispatchQueue.main.asyncAfter(deadline:.now()+0.05){
            tap(keyV,flags:.maskCommand)
            if enter { DispatchQueue.main.asyncAfter(deadline:.now()+enterDelay){ tap(keyReturn,flags:[]) } }
            // en apps que no dejan ver su campo (Claude, Electron) no se puede comprobar si el Intro entró: un segundo Intro
            // poco después; si el primero ya envió, el campo está vacío y no hace nada
            if enter && confirmEnter { DispatchQueue.main.asyncAfter(deadline:.now()+enterDelay+0.45){ tap(keyReturn,flags:[]) } }
            DispatchQueue.main.asyncAfter(deadline:.now()+max(0.6,enterDelay+(confirmEnter ? 0.8 : 0.35))){
                if pasteboard.changeCount==written {
                    pasteboard.clearContents()
                    let items=previous.map{entry -> NSPasteboardItem in let i=NSPasteboardItem();for (type,data) in entry{i.setData(data,forType:type)};return i}
                    if !items.isEmpty{pasteboard.writeObjects(items)}
                }
                completion?(.success(()))
            }
        }
    }
    static func deliver(_ text:String,to target:TextTarget,enter:Bool,method:VoiceInsertion = .paste,guardTerminal:Bool = false,verifyBeforeEnter:Bool = true,allow:@escaping()->Bool = {true},completion:@escaping(Result<Void,Error>)->Void) {
        guard !delivering else { completion(.failure(VoiceServiceError(message:T.s("Another insertion is still finishing. Retry shortly.","Otra inserción está terminando. Vuelve a intentarlo en un momento."))));return }
        guard allow(),!text.isEmpty,matches(target,selection:true) else { completion(.failure(VoiceServiceError(message:T.s("The destination changed. Your draft is kept; return to the original field to insert it.","El destino ha cambiado. Se conserva el borrador; vuelve al campo original para insertarlo."))));return }
        delivering=true;deliveryRevision+=1;let epoch=deliveryRevision
        let before=attribute(target.field,kAXValueAttribute) as? String
        let expected:String? = before.flatMap{value in
            guard value.utf16.count<=1_000_000,let range=target.selection,range.location>=0,range.length>=0,range.location<=value.utf16.count,range.length<=value.utf16.count-range.location else{return nil}
            return (value as NSString).replacingCharacters(in:NSRange(location:range.location,length:range.length),with:text)
        }
        if method == .direct {
            let result=AXUIElementSetAttributeValue(target.field,kAXSelectedTextAttribute as CFString,text as CFString)
            guard result == .success else {delivering=false;completion(.failure(VoiceServiceError(message:T.s("This app does not support direct insertion. Choose Paste in Voice settings.","Esta app no admite inserción directa. Elige Pegar en los ajustes de Voz."))));return}
            DispatchQueue.main.asyncAfter(deadline:.now()+0.18){
                defer{if deliveryRevision==epoch{delivering=false}}
                guard deliveryRevision==epoch,allow(),matches(target,selection:false) else{completion(.failure(VoiceServiceError(message:T.s("Text was inserted; the destination changed before Enter. Review the field.","El texto se insertó; el destino cambió antes de Intro. Revisa el campo."))));return}
                if enter && !(guardTerminal && isTerminal(target)){
                    guard !verifyBeforeEnter || pasteLanded(target,before:before,expected:expected) else{completion(.failure(VoiceServiceError(message:T.s("Direct insertion could not be verified, so Enter was not sent. Review the field.","No se ha podido verificar la inserción directa y no se ha pulsado Intro. Revisa el campo."))));return}
                    guard tap(keyReturn,flags:[]) else{completion(.failure(VoiceServiceError(message:T.s("Text inserted, but Enter could not be sent.","El texto se insertó, pero no se ha podido pulsar Intro."))));return}
                }
                completion(.success(()))
            }
            return
        }
        let pasteboard=NSPasteboard.general
        let previous=pasteboard.pasteboardItems?.map{item in Dictionary(uniqueKeysWithValues:item.types.compactMap{type in item.data(forType:type).map{(type,$0)}})} ?? []
        let item=NSPasteboardItem()
        guard item.setString(text,forType:.string) else{delivering=false;completion(.failure(VoiceServiceError(message:T.s("Could not prepare the clipboard.","No se ha podido preparar el portapapeles."))));return}
        for marker in ["org.nspasteboard.ConcealedType","org.nspasteboard.TransientType","org.nspasteboard.AutoGeneratedType"] { item.setData(Data(),forType:NSPasteboard.PasteboardType(marker)) }
        pasteboard.clearContents();let cleared=pasteboard.changeCount
        guard pasteboard.writeObjects([item]) else{
            let items=previous.map{entry -> NSPasteboardItem in let item=NSPasteboardItem();for (type,data) in entry{item.setData(data,forType:type)};return item}
            if pasteboard.changeCount==cleared{pasteboard.clearContents();if !items.isEmpty{pasteboard.writeObjects(items)}};delivering=false
            completion(.failure(VoiceServiceError(message:T.s("Could not write the clipboard. Nothing was pasted.","No se ha podido escribir el portapapeles. No se ha pegado nada."))));return
        }
        let written=pasteboard.changeCount
        func restore() {
            if pasteboard.changeCount==written {
                pasteboard.clearContents()
                let items=previous.map{entry -> NSPasteboardItem in let item=NSPasteboardItem();for (type,data) in entry {item.setData(data,forType:type)};return item}
                if !items.isEmpty { pasteboard.writeObjects(items) }
            }
            if deliveryRevision==epoch{delivering=false;pendingRestore=nil}
        }
        pendingRestore=restore
        DispatchQueue.main.asyncAfter(deadline:.now()+0.05){
            guard deliveryRevision==epoch,allow(),matches(target,selection:true),pasteboard.changeCount==written else { restore();completion(.failure(VoiceServiceError(message:T.s("The destination or clipboard changed before insertion. Your draft is kept.","El destino o el portapapeles cambió antes de insertar. Se conserva el borrador."))));return }
            guard tap(keyV,flags:.maskCommand) else{restore();completion(.failure(VoiceServiceError(message:T.s("The paste event could not be created. Your draft is kept.","No se ha podido crear el evento de pegado. Se conserva el borrador."))));return}
            DispatchQueue.main.asyncAfter(deadline:.now()+0.3){ // los chats Electron/web tardan algo en meter el pegado
                guard deliveryRevision==epoch,allow() else{restore();completion(.failure(CancellationError()));return}
                // Enter is only sent to the same field and never runs a terminal command automatically.
                if enter && !(guardTerminal && isTerminal(target)) {
                    guard allow(),matches(target,selection:false) else { restore();completion(.failure(VoiceServiceError(message:T.s("Text was pasted; the destination changed before Enter. Review it before sending again.","El texto se pegó; el destino cambió antes de Intro. Revísalo antes de enviarlo otra vez."))));return }
                    guard !verifyBeforeEnter || pasteLanded(target,before:before,expected:expected) else{restore();completion(.failure(VoiceServiceError(message:T.s("Paste could not be verified, so Enter was not sent. Review the field before retrying.","No se ha podido verificar el pegado y no se ha pulsado Intro. Revisa el campo antes de reintentar."))));return}
                    guard tap(keyReturn,flags:[]) else{restore();completion(.failure(VoiceServiceError(message:T.s("Text pasted, but Enter could not be sent.","El texto se pegó, pero no se ha podido pulsar Intro."))));return}
                }
                DispatchQueue.main.asyncAfter(deadline:.now()+0.45){restore();completion(.success(()))}
            }
        }
    }
    /// Los chats (Electron, web) no devuelven por Accesibilidad el texto tal cual: solo se da por fallido el pegado
    /// si el campo se puede leer y sigue igual que antes (el texto no ha entrado).
    static func pasteLanded(_ target:TextTarget,before:String?,expected:String?)->Bool{
        let after=attribute(target.field,kAXValueAttribute) as? String
        if let after,let expected,after==expected{return true}
        guard let before,let after else{return true}
        return after != before
    }
    static func isTerminal(_ target:TextTarget)->Bool{["com.apple.Terminal","com.googlecode.iterm2","dev.warp.Warp-Stable","com.mitchellh.ghostty","com.github.wez.wezterm","com.microsoft.VSCode","com.microsoft.VSCodeInsiders","com.todesktop.230313mzl4w4u92","dev.zed.Zed"].contains(target.bundle)}
    static func copy(_ text:String) { NSPasteboard.general.clearContents();NSPasteboard.general.setString(text,forType:.string) }
    @discardableResult
    static func tap(_ key:CGKeyCode,flags:CGEventFlags)->Bool {
        let source=CGEventSource(stateID:.combinedSessionState)
        guard let down=CGEvent(keyboardEventSource:source,virtualKey:key,keyDown:true),let up=CGEvent(keyboardEventSource:source,virtualKey:key,keyDown:false) else {return false}
        down.flags=flags;up.flags=flags;down.post(tap:.cghidEventTap);up.post(tap:.cghidEventTap);return true
    }
    static func targetName()->String { let app=NSWorkspace.shared.frontmostApplication;return app?.bundleIdentifier==Bundle.main.bundleIdentifier ? "…" : app?.localizedName ?? "…" }
}
