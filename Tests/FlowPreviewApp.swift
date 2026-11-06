import SwiftUI

@main
@MainActor
struct FlowPreviewApp: App {
    @StateObject private var controller: FlowController
    init() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("agent-deck-flow-preview-"+UUID().uuidString)
        let storage = FlowStorage(folder:folder)
        try? storage.transaction { db in
            var sequence = MessageFlow(); sequence.name = "Revisar → corregir → resumir"; sequence.mode = "sequence"
            db.definitions.append(sequence)
            db.sessions = [FlowSession(id:"chat-ejemplo-1234",cwd:"/Proyecto de ejemplo",lastSeen:Date().timeIntervalSince1970,state:"idle")]
        }
        _controller = StateObject(wrappedValue:FlowController(storage:storage,reviewMode:true))
    }
    var body: some Scene {
        WindowGroup("Agent Deck · Revisión de flujos") { FlowWorkspaceView(flow:controller).frame(minWidth:640,minHeight:540) }.defaultSize(width:760,height:850)
    }
}
