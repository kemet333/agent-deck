import SwiftUI

@MainActor
struct FlowWorkspaceView: View {
    @ObservedObject var flow: FlowController
    @State private var draft = MessageFlow()
    @State private var sessionID = ""
    @State private var confirmingConnection = false
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(T.s("One task after another.", "Una tarea después de otra.")).font(.system(size: 24, weight: .semibold))
                        Text(T.s("Choose what Agent Bar sends when Codex finishes each response.", "Elige qué envía Agent Bar cuando Codex termina cada respuesta.")).font(.system(size: 12)).foregroundStyle(Palette.mute)
                    }
                    Spacer()
                    Label("CODEX", systemImage: "arrow.triangle.branch").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Palette.gold).padding(9).background(Palette.gold.opacity(0.08), in: Capsule())
                }
                if flow.reviewMode { Text("REVISIÓN · DATOS SINTÉTICOS · SIN CONEXIÓN NI ENVÍOS").font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.gold) }
                if !flow.error.isEmpty { Text(flow.error).font(.system(size: 12)).foregroundStyle(Color.orange).textSelection(.enabled) }
                if !flow.connectionNote.isEmpty { Text(flow.connectionNote).font(.system(size: 12)).foregroundStyle(Palette.gold) }
                runStatus
                editor
                destination
                HStack {
                    Button(T.s("Save flow", "Guardar flujo")) { flow.save(draft) }.disabled(flow.active)
                    Spacer()
                    Text(T.s("Next completion · finite sequence", "Próxima respuesta · secuencia limitada")).font(.system(size: 10)).foregroundStyle(Palette.mute)
                    Button(T.s("Schedule flow", "Programar flujo")) { flow.arm(draft, sessionID: sessionID) }
                        .buttonStyle(.borderedProminent).tint(Palette.gold).foregroundStyle(Color.black)
                        .disabled(flow.reviewMode || flow.active || sessionID.isEmpty || (try? draft.messages()) == nil)
                }
                Text(T.s("This schedules additional Codex work and consumes its usual quota. It does not approve permissions, bypass questions or mark a task complete. Pausing stops future messages, not a response already running. Flows expire after 24 hours and require Agent Bar to remain open.", "Programa trabajo adicional en Codex y consume su cuota habitual. No aprueba permisos, contesta preguntas ni marca tareas como completadas. Pausar detiene los siguientes mensajes; la respuesta que ya está en curso sigue. Los flujos caducan a las 24 horas y requieren Agent Bar abierto.")).font(.system(size: 10)).foregroundStyle(Palette.faint)
            }.padding(24)
        }.background(Palette.bg).foregroundStyle(Palette.ink).preferredColorScheme(.dark)
        .onAppear { if !loaded { draft = flow.database.definitions.first ?? MessageFlow(); loaded = true } }
        .alert(T.s("Connect Agent Bar to Codex?", "¿Conectar Agent Bar con Codex?"), isPresented: $confirmingConnection) {
            Button(T.s("Cancel", "Cancelar"), role: .cancel) {}
            Button(T.s("Prepare connection", "Preparar conexión")) { flow.connect() }
        } message: {
            Text("Se creará ~/.codex/hooks.json solo si no existe. Si ya tienes hooks, se guardará un fragmento para combinarlo sin modificar tu archivo. El conector recibe eventos de Codex, guarda solo identificador/directorio/estado y devuelve exclusivamente los mensajes que programes. Después debes revisar y confiar en él desde Codex. No se cambia config.toml ni la política de permisos.")
        }
    }
    private var editor: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(T.s("YOUR FLOW", "TU FLUJO")).font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(Palette.mute)
                Spacer()
                Menu(T.s("Saved flows", "Flujos guardados")) {
                    ForEach(flow.database.definitions) { item in Button(item.name) { draft = item } }
                    Divider(); Button(T.s("New flow", "Nuevo flujo")) { draft = MessageFlow(); draft.name = "Nuevo flujo" }
                }.controlSize(.small)
            }
            TextField(T.s("Flow name", "Nombre del flujo"), text: $draft.name).textFieldStyle(.roundedBorder)
            Picker("Modo", selection: $draft.mode) {
                Text(T.s("Repeat a message", "Repetir mensaje")).tag("repeat")
                Text(T.s("Ordered sequence", "Secuencia de mensajes")).tag("sequence")
            }.pickerStyle(.segmented)
            if draft.mode == "repeat" {
                messageEditor($draft.message, height: 65)
                HStack {
                    Stepper(value: $draft.repetitions, in: 1...50) { Text(T.s("Repetitions", "Repeticiones")) }.frame(width: 200)
                    Spacer()
                    Text("× \(draft.repetitions)").font(.system(size: 28, weight: .medium, design: .monospaced)).foregroundStyle(Palette.gold)
                }
                Text("Un mensaje después de cada respuesta. «5» significa cinco continuaciones, no cinco mensajes de golpe.").font(.system(size: 11)).foregroundStyle(Palette.mute)
            } else {
                ForEach(draft.steps.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 12) {
                        Text(String(format: "%02d", index + 1)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.gold).padding(.top, 10)
                        messageEditor(Binding(get: { draft.steps.indices.contains(index) ? draft.steps[index] : "" }, set: { if draft.steps.indices.contains(index) { draft.steps[index] = $0 } }), height: 60)
                        VStack(spacing: 7) {
                            Button { draft.steps.swapAt(index, index - 1) } label: { Image(systemName: "chevron.up") }.disabled(index == 0)
                            Button { draft.steps.swapAt(index, index + 1) } label: { Image(systemName: "chevron.down") }.disabled(index == draft.steps.count - 1)
                            Button { draft.steps.remove(at: index) } label: { Image(systemName: "minus") }.disabled(draft.steps.count == 1)
                        }.controlSize(.mini).buttonStyle(.borderless).padding(.top, 5)
                    }
                }
                Button(T.s("Add message", "Añadir mensaje"), systemImage: "plus") { draft.steps.append("") }.disabled(draft.steps.count >= 50)
            }
        }.padding(18).background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(Palette.line)).disabled(flow.active)
    }
    private var destination: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(T.s("DESTINATION CHAT", "CHAT DE DESTINO")).font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(Palette.mute)
                Spacer()
                Button(T.s("Connect Codex…", "Conectar Codex…")) { confirmingConnection = true }.controlSize(.small).disabled(flow.reviewMode || flow.active)
            }
            Picker(T.s("Chat", "Chat"), selection: $sessionID) {
                Text(T.s("Choose a detected chat", "Selecciona un chat detectado")).tag("")
                ForEach(flow.database.sessions) { session in
                    Text("\(URL(fileURLWithPath: session.cwd).lastPathComponent) · \(session.id.prefix(8)) · \(sessionLabel(session))").tag(session.id)
                }
            }.disabled(flow.active)
            if flow.database.sessions.isEmpty {
                Text("Tras confiar en el conector, envía una tarea en Codex. Aquí aparecerá su directorio, hora e identificador; el más reciente sale primero. No se importa el historial del chat.").font(.system(size: 11)).foregroundStyle(Palette.mute)
            } else if let selected = flow.database.sessions.first(where: { $0.id == sessionID }) {
                Text("\(selected.cwd)\nChat: \(selected.id)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.mute).textSelection(.enabled)
            }
        }
    }
    @ViewBuilder private var runStatus: some View {
        if let run = flow.database.run {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(run.definition.name, systemImage: run.active ? "arrow.triangle.branch" : "pause.circle").font(.system(size: 13, weight: .medium))
                    Spacer(); Text("\(run.issued) / \(run.messages.count)").font(.system(size: 14, design: .monospaced)).foregroundStyle(Palette.gold)
                }
                ProgressView(value: Double(run.issued), total: Double(max(run.messages.count, 1))).tint(Palette.gold)
                Text(run.note).font(.system(size: 12)).foregroundStyle(Palette.mute)
                HStack {
                    Text(String(run.sessionID.prefix(8))).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.faint)
                    Spacer()
                    if run.active { Button(T.s("Pause", "Pausar")) { flow.pause() } }
                    if run.state == "paused" { Button(T.s("Resume", "Reanudar")) { flow.resume() }.disabled(flow.reviewMode) }
                    if ["armed", "waitingResponse", "paused"].contains(run.state) { Button(T.s("Cancel flow", "Cancelar flujo")) { flow.cancel() } }
                }.controlSize(.small)
            }.padding(18).background(Palette.gold.opacity(0.055), in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(Palette.gold.opacity(0.18)))
        }
    }
    private func messageEditor(_ text: Binding<String>, height: CGFloat) -> some View {
        TextEditor(text: text).font(.system(size: 12)).scrollContentBackground(.hidden).frame(minHeight: height, maxHeight: height + 25).padding(9).background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 9))
    }
    private func sessionLabel(_ session: FlowSession) -> String {
        let state = ["idle":"en espera", "running":"trabajando", "needsInput":"necesita respuesta", "ended":"cerrado", "error":"revisar fallo"][session.state] ?? session.state
        return state + " · " + Date(timeIntervalSince1970: session.lastSeen).formatted(date: .omitted, time: .shortened)
    }
}

@MainActor
struct DeckSettingsView: View {
    @ObservedObject var store: DeskStore
    @State private var section = "voice"
    var body: some View {
        VStack(spacing: 0) {
            Picker("Agent Bar", selection: $section) { Text("Voz").tag("voice"); Text("Flujos").tag("flows") }.pickerStyle(.segmented).padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 10)
            if section == "flows" { FlowWorkspaceView(flow: store.flows) } else { VoiceWorkspaceView(voice: store.voice) }
        }.background(Palette.bg).preferredColorScheme(.dark)
    }
}
