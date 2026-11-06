import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct VoiceWorkspaceView: View {
    @ObservedObject var voice: VoiceController
    var reviewMode=false
    @State private var tab = "dictation"
    @State private var apiKey = ""
    @State private var appBundle = ""
    @State private var appTone: VoiceTone = .clean
    @State private var deleting: VoiceRecord?
    var body: some View {
        VStack(spacing:0) {
            HStack(alignment:.center) {
                VStack(alignment:.leading,spacing:5){Text("Agent Deck").font(.system(size:24,weight:.semibold));Text(T.s("Your voice. In your workflow.","Tu voz. Dentro de tu flujo.")).font(.system(size:12)).foregroundStyle(Palette.mute)}
                Spacer()
                Label(voice.label,systemImage:voice.active ? "waveform":"mic").font(.system(size:11)).foregroundStyle(voice.active ? Palette.gold:Palette.mute).lineLimit(1)
            }.padding(24)
            Picker("",selection:$tab){Text(T.s("Voice","Voz")).tag("dictation");Text(T.s("History","Historial")).tag("history");Text(T.s("Settings","Ajustes")).tag("settings")}.pickerStyle(.segmented).padding(.horizontal,24).padding(.bottom,18)
            Divider().overlay(Palette.line)
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    if !voice.message.isEmpty{Text(voice.message).font(.system(size:12)).foregroundStyle(voice.phase == .failed ? Color.orange:Palette.text).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding(14).background(Color.white.opacity(0.04),in:RoundedRectangle(cornerRadius:12))}
                    if tab == "settings"{settings}else if tab == "history"{history}else{dictation}
                }.padding(24)
            }
        }.foregroundStyle(Palette.ink).background(Palette.bg).preferredColorScheme(.dark)
        .alert(T.s("Remove this transcript from history?","¿Eliminar esta transcripción del historial?"),isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}})){
            Button(T.s("Cancel","Cancelar"),role:.cancel){deleting=nil}
            Button(T.s("Delete","Eliminar"),role:.destructive){if let deleting{voice.removeHistory(deleting.id)};deleting=nil}
        }
    }
    private func card<Content:View>(_ title:String,@ViewBuilder content:()->Content)->some View {
        VStack(alignment:.leading,spacing:14){Text(title).font(.system(size:13,weight:.semibold));content()}.frame(maxWidth:.infinity,alignment:.leading).padding(18).background(Color.white.opacity(0.035),in:RoundedRectangle(cornerRadius:14)).overlay(RoundedRectangle(cornerRadius:14).stroke(Palette.line,lineWidth:1))
    }
    private var dictation: some View {
        VStack(alignment:.leading,spacing:18) {
            card(T.s("Hold Fn. Speak. Release.","Mantén Fn. Habla. Suelta.")){
                Text(T.s("Hold Fn to dictate, double-tap Fn or use Fn+Control for hands-free. Fn+Option edits selected text. Escape discards the recording or cancels processing. Each dictation supports up to 3 minutes.","Mantén Fn para dictar; doble toque en Fn o Fn+Control para manos libres. Fn+Opción edita el texto seleccionado. Escape descarta la grabación o cancela el procesamiento. Cada dictado admite hasta 3 minutos.")).font(.system(size:12)).foregroundStyle(Palette.mute)
                Text(T.s("Keep the destination text field focused. If you change it, the draft stays here. ⌃⌥M remains available; ⌃⌥L pastes the last transcription.","Mantén el foco en el campo de destino. Si lo cambias, el borrador se queda aquí. ⌃⌥M sigue disponible; ⌃⌥L pega la última transcripción.")).font(.system(size:11)).foregroundStyle(Palette.mute)
                HStack{Button(T.s("Voice settings","Configurar voz")){tab="settings"};Button(T.s("Transcribe a file…","Transcribir archivo…")){chooseFile()}.disabled(reviewMode || voice.active);Spacer();if voice.active{Button(T.s("Cancel","Cancelar")){voice.cancel()}}}
            }
            card(T.s("Current draft","Borrador actual")){
                if voice.active{ProgressView().controlSize(.small)}
                TextEditor(text:$voice.draft).font(.system(size:14)).frame(minHeight:170).scrollContentBackground(.hidden).padding(8).background(Color.black.opacity(0.2),in:RoundedRectangle(cornerRadius:8)).disabled(voice.active)
                Text(voice.canInsertOriginal ? T.s("Return to the original field, then press the arrow on the floating bar. This window does not paste into a background app.","Vuelve al campo original y pulsa la flecha de la barra flotante. Esta ventana no pega en una app en segundo plano."):T.s("For recovered or imported text, use Copy and paste it where you choose. No original field is retained after restarting.","Para textos recuperados o importados, usa Copiar y pégalos donde elijas. Tras reiniciar no se conserva el campo original.")).font(.system(size:10)).foregroundStyle(Palette.mute)
                HStack{
                    Button(T.s("Copy","Copiar")){voice.copyDraft()}.disabled(reviewMode || voice.draft.isEmpty)
                    Button(T.s("Return to the bar","Volver a la barra")){voice.showDeck?()}.disabled(reviewMode || voice.draft.isEmpty||voice.active)
                    if !voice.raw.isEmpty{Button(T.s("Use original","Usar literal")){voice.useOriginal()}.disabled(voice.active)}
                    Spacer()
                    if voice.canRetry{Button(T.s("Retry","Reintentar")){voice.retry()}.disabled(reviewMode)}
                    Button(T.s("Discard","Descartar")){voice.discardDraft()}.disabled(voice.draft.isEmpty && !voice.active && voice.phase != .failed)
                }.controlSize(.small)
            }
            Text(T.s("OpenAI mode sends the audio and, for text cleanup, the transcript directly to OpenAI using your API key. History is stored on this Mac. Apple + Verbatim uses the existing local speech option; availability depends on macOS.","El modo OpenAI envía el audio y, para limpiar el texto, su transcripción directamente a OpenAI con tu clave de la API. El historial se guarda en este Mac. Apple + Literal usa la opción de voz local existente; su disponibilidad depende de macOS.")).font(.system(size:10)).foregroundStyle(Palette.faint)
        }
    }
    private var settings: some View {
        VStack(alignment:.leading,spacing:18){
            card(T.s("Voice engine","Motor de voz")){
                Picker(T.s("Transcription","Transcripción"),selection:$voice.preferences.engine){Text("OpenAI API").tag(VoiceEngine.openAI);Text(T.s("Apple (on the Mac, free, no key)","Apple (del Mac, gratis, sin clave)")).tag(VoiceEngine.apple)}.onChange(of:voice.preferences.engine){_,engine in if engine == .apple{voice.preferences.tone = .verbatim}}
                if voice.preferences.engine == .apple {
                    HStack(spacing:8){Text(voice.appleStatus).font(.system(size:11)).foregroundStyle(Palette.text);Spacer();if !voice.appleStatus.hasPrefix("✓"){Button(T.s("Allow","Permitir")){voice.allowApple()}.controlSize(.small)}}
                        .onAppear{voice.refreshAppleStatus()}
                }
                HStack{SecureField(T.s("OpenAI API key","Clave de la API de OpenAI"),text:$apiKey).textFieldStyle(.roundedBorder).disabled(reviewMode || voice.active);Button(T.s("Save in Keychain","Guardar en Llavero")){voice.saveKey(apiKey);apiKey=""}.disabled(reviewMode || voice.active || apiKey.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}
                HStack{Text(voice.keyConfigured ? T.s("Key configured. Actual access is checked when you use voice.","Clave configurada. El acceso real se comprueba al usar la voz."):T.s("No OpenAI key configured.","No hay clave de OpenAI configurada.")).font(.system(size:10)).foregroundStyle(Palette.mute);Spacer();if voice.keyConfigured{Button(T.s("Remove key","Eliminar clave")){voice.removeKey()}.disabled(reviewMode || voice.active).controlSize(.small)}}
                HStack(spacing:8){Button(T.s("Test key","Probar clave")){voice.testKey()}.disabled(voice.keyTesting || !voice.keyConfigured).controlSize(.small);Text(voice.keyTest).font(.system(size:11)).foregroundStyle(Palette.text).lineLimit(2)}
                TextField(T.s("Transcription model","Modelo de transcripción"),text:$voice.preferences.transcriptionModel)
                TextField(T.s("Text model","Modelo para limpiar/editar"),text:$voice.preferences.textModel)
                TextField(T.s("Language hint (es, en…), blank for automatic","Idioma (es, en…), vacío para automático"),text:$voice.preferences.language)
            }
            card(T.s("Keyboard & insertion","Teclado e inserción")){
                Toggle(T.s("Enable Fn dictation","Activar dictado con Fn"),isOn:$voice.preferences.fnEnabled)
                Text(voice.shortcutStatus).font(.system(size:10)).foregroundStyle(Palette.mute)
                Toggle(T.s("Avoid Fn conflicts while Vowen is running","Evitar conflictos de Fn mientras Vowen está abierto"),isOn:$voice.preferences.avoidVowenConflict)
                Text(T.s("If you have disabled Fn in Vowen yourself, you may disable this guard. Agent Deck does not change Vowen or macOS keyboard settings.","Si ya has desactivado Fn en Vowen, puedes desmarcar esta protección. Agent Deck no modifica Vowen ni el teclado de macOS.")).font(.system(size:10)).foregroundStyle(Palette.mute)
                Toggle(T.s("Insert automatically in the original field","Insertar automáticamente en el campo original"),isOn:$voice.preferences.autoPaste)
                Picker(T.s("Insertion method","Método de inserción"),selection:$voice.preferences.insertion){Text(T.s("Paste (restore clipboard)","Pegar (restaurar portapapeles)")).tag(VoiceInsertion.paste);Text(T.s("Direct (Accessibility)","Directo (Accesibilidad)")).tag(VoiceInsertion.direct)}
                Toggle(T.s("Press Enter after inserting (send chat)","Pulsar Intro después de insertar (enviar chat)"),isOn:$voice.preferences.autoEnter).disabled(!voice.preferences.autoPaste)
                Toggle(T.s("Paste without Enter in known terminal/editor apps","Pegar sin Intro en terminales/editores conocidos"),isOn:$voice.preferences.guardTerminal)
                Text(T.s("The clipboard is restored if it has not changed. The terminal guard covers supported terminal/editor app IDs; it does not identify every embedded shell. A changed destination keeps the text as a draft.","El portapapeles se restaura si no ha cambiado. La protección cubre los IDs de terminales/editores compatibles; no identifica todos los terminales integrados. Si el destino cambia, el texto queda como borrador.")).font(.system(size:10)).foregroundStyle(Palette.mute)
            }
            card(T.s("Your writing style","Tu forma de escribir")){
                Picker(T.s("Tone","Tono"),selection:$voice.preferences.tone){ForEach(VoiceTone.allCases,id:\.self){Text($0.title).tag($0)}}
                Toggle(T.s("In AI chats, turn longer dictation into a clear prompt","En los chats de IA, convertir lo dictado largo en un prompt claro"),isOn:$voice.preferences.promptInAIApps)
                Text(T.s("Verbatim skips AI cleanup. Other tones and selection editing use the configured OpenAI text model.","Literal omite la limpieza con IA. Los demás tonos y la edición de selecciones usan el modelo de texto de OpenAI configurado.")).font(.system(size:10)).foregroundStyle(Palette.mute)
                Text(T.s("Custom style instructions","Instrucciones de estilo")).font(.system(size:11));TextEditor(text:$voice.preferences.instructions).frame(height:65).scrollContentBackground(.hidden).padding(6).background(Color.black.opacity(0.2),in:RoundedRectangle(cornerRadius:7))
                DisclosureGroup(T.s("Tone by app","Tono por aplicación")){
                    HStack{TextField(T.s("App bundle ID (e.g. com.apple.mail)","Bundle ID (p. ej. com.apple.mail)"),text:$appBundle);Picker("",selection:$appTone){ForEach(VoiceTone.allCases,id:\.self){Text($0.title).tag($0)}}.frame(width:120);Button(T.s("Add","Añadir")){let id=appBundle.trimmingCharacters(in:.whitespacesAndNewlines);if !id.isEmpty{voice.preferences.appTones[id]=appTone;appBundle=""}}}
                    ForEach(voice.preferences.appTones.keys.sorted(),id:\.self){id in HStack{Text(id).font(.system(size:10));Spacer();Text(voice.preferences.appTones[id]?.title ?? "");Button(T.s("Remove","Quitar")){voice.preferences.appTones.removeValue(forKey:id)}}.controlSize(.small)}
                }
            }
            card(T.s("Vocabulary & expansions","Vocabulario y expansiones")){
                Text(T.s("Names and technical terms, one per line. These are hints for OpenAI, not guaranteed replacements.","Nombres y términos técnicos, uno por línea. Son pistas para OpenAI, no sustituciones garantizadas.")).font(.system(size:11)).foregroundStyle(Palette.mute)
                TextEditor(text:$voice.preferences.dictionary).frame(height:75).scrollContentBackground(.hidden).padding(6).background(Color.black.opacity(0.2),in:RoundedRectangle(cornerRadius:7))
                Text(T.s("Literal expansions, one per line: phrase => replacement","Expansiones literales, una por línea: frase => sustitución")).font(.system(size:11)).foregroundStyle(Palette.mute)
                TextEditor(text:$voice.preferences.expansions).frame(height:75).scrollContentBackground(.hidden).padding(6).background(Color.black.opacity(0.2),in:RoundedRectangle(cornerRadius:7))
                Toggle(T.s("Save text history on this Mac (last 100)","Guardar historial de texto en este Mac (últimos 100)"),isOn:$voice.preferences.saveHistory)
                Text(T.s("A pending draft is saved separately for recovery. Discard it to remove that pending text.","El borrador pendiente se guarda aparte para recuperarlo. Descártalo para quitar ese texto pendiente.")).font(.system(size:10)).foregroundStyle(Palette.mute)
            }
        }.textFieldStyle(.roundedBorder)
    }
    private var history: some View {
        VStack(alignment:.leading,spacing:12){
            HStack{Text(T.s("Saved on this Mac","Guardado en este Mac")).font(.system(size:12)).foregroundStyle(Palette.mute);Spacer();Button(T.s("Transcribe a file…","Transcribir archivo…")){chooseFile()}.disabled(reviewMode || voice.active)}
            if voice.history.isEmpty{Text(T.s("Your transcriptions will appear here if local history is enabled.","Tus transcripciones aparecerán aquí si activas el historial local.")).foregroundStyle(Palette.mute).padding(.vertical,40)}
            ForEach(voice.history){record in
                card(record.date.formatted(date:.abbreviated,time:.shortened)+" · "+record.source){
                    Text(record.text).font(.system(size:12)).textSelection(.enabled)
                    HStack{Button(T.s("Copy","Copiar")){Sender.copy(record.text)}.disabled(reviewMode);Button(T.s("Export…","Exportar…")){export(record)};Button(T.s("Summarize with AI","Resumir con IA")){voice.summarize(record);tab="dictation"}.disabled(reviewMode || voice.active || !voice.draft.isEmpty);Spacer();Button(T.s("Delete","Eliminar")){deleting=record}}.controlSize(.small)
                }
            }
        }
    }
    private func chooseFile(){let panel=NSOpenPanel();panel.allowsMultipleSelection=false;panel.canChooseDirectories=false;panel.allowedContentTypes=[.audio,.movie];if panel.runModal() == .OK,let url=panel.url{voice.importFile(url);tab="dictation"}}
    private func export(_ record:VoiceRecord){let panel=NSSavePanel();panel.nameFieldStringValue="AgentDeck-\(record.date.formatted(.iso8601.year().month().day())).md";if panel.runModal() == .OK,let url=panel.url{do{try record.text.write(to:url,atomically:true,encoding:.utf8)}catch{voice.note(T.s("Could not save the export.","No se ha podido guardar la exportación."))}}}
}
