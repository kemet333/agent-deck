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
    static let keyV: CGKeyCode = 9, keyReturn: CGKeyCode = 36
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
    static func capture(selection:Bool = false)throws->TextTarget {
        guard accessibilityGranted(prompt:false) else { throw VoiceServiceError(message:T.s("Allow Accessibility to insert text. Your draft is kept.","Permite Accesibilidad para insertar texto. Se conserva el borrador.")) }
        guard let app = NSWorkspace.shared.frontmostApplication,app.bundleIdentifier != Bundle.main.bundleIdentifier,let field = focused(app.processIdentifier) else { throw VoiceServiceError(message:T.s("Place the cursor in the destination text field first.","Coloca primero el cursor en el campo de texto de destino.")) }
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
    static func send(_ text:String,enter:Bool,completion:((Result<Void,Error>)->Void)? = nil) {
        do { deliver(text,to:try capture(),enter:enter,verifyBeforeEnter:false,completion:completion ?? {_ in}) }
        catch { completion?(.failure(error)) }
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
