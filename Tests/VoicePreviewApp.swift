import AppKit
import SwiftUI

// Visual-only harness. Separate bundle, temporary fixtures; no AppDelegate, event tap, credentials,
// microphone, provider calls, installed-app preferences or real text targets are used.
@main
@MainActor
struct VoicePreviewApp:App {
    @StateObject private var voice:VoiceController
    init(){
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("agentdeck-visual-review-"+UUID().uuidString,isDirectory:true)
        let storage=VoiceStorage(folder:folder)
        var prefs=VoicePreferences();prefs.autoPaste=false
        try? storage.save(prefs,name:"voice-settings.json")
        try? storage.save([VoiceRecord(text:"Continúa con la implementación y muéstrame el resultado antes de publicar.",source:"App de prueba",kind:"dictation"),VoiceRecord(text:"Decisiones: preparar la revisión. Siguiente paso: comprobar el flujo completo con la API configurada.",source:"Reunión de ejemplo (transcripción importada)",kind:"summary")],name:"voice-history.json")
        try? storage.save(VoiceDraft(text:"Continúa con la implementación y conserva los cambios anteriores.",source:"App de prueba"),name:"voice-draft.json")
        let controller=VoiceController(storage:storage,keyProvider:{""},microphonePermission:{false},frontApp:{("App de prueba","test.synthetic")})
        controller.shortcutStatus="REVISIÓN: los atajos no están instalados en esta app de prueba."
        _voice=StateObject(wrappedValue:controller)
    }
    var body:some Scene{
        WindowGroup("Agent Deck · Voice review"){
            VoiceWorkspaceView(voice:voice,reviewMode:true).frame(minWidth:700,minHeight:620).overlay(alignment:.bottom){Text("REVISIÓN · TEXTO SINTÉTICO · SIN ATAJOS, MICRÓFONO NI API").font(.system(size:8,weight:.medium,design:.monospaced)).foregroundStyle(Color.yellow.opacity(0.7)).padding(5).background(Color.black.opacity(0.95)).allowsHitTesting(false)}
        }.defaultSize(width:780,height:740)
    }
}
