import AppKit
import ServiceManagement
import SwiftUI

/// El panel de Agent Bar: lo que abre el engranaje de la barra. Barra lateral + paneles en cristal, como los
/// Ajustes del Sistema. No inventa ajustes: cada control usa el mismo almacenamiento y la misma acción que el
/// menú de siempre (UserDefaults, keys.json, preferencias de voz, ganchos de Claude Code, piloto).

/// Lo que solo sabe hacer el AppDelegate (ventanas, diálogos de confirmación, salir).
struct DashboardActions {
    var connectClaude: () -> Void = {}
    var removeClaudeAlerts: () -> Void = {}
    var openVoice: () -> Void = {}
    var openFlows: () -> Void = {}
    var pauseFlow: () -> Void = {}
    var openTutorial: () -> Void = {}
    var openAccessibility: () -> Void = {}
    var offerPack: (KeyPack) -> Void = { _ in }
    var shareKeys: () -> Void = {}
    var morePacks: () -> Void = {}
    var toggleBar: () -> Void = {}
    var quit: () -> Void = {}
    var relaunch: () -> Void = {}
}

enum DashPane: String, CaseIterable, Identifiable {
    case general, keys, voice, alerts, packs, appearance, pro, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return T.s("General", "General")
        case .keys: return T.s("Keys", "Teclas")
        case .voice: return T.s("Voice", "Voz")
        case .alerts: return T.s("Alerts & Autopilot", "Avisos y Autopilot")
        case .packs: return T.s("Key packs", "Packs de teclas")
        case .appearance: return T.s("Appearance", "Aspecto")
        case .pro: return "Agent Bar Pro"
        case .about: return T.s("About", "Acerca de")
        }
    }
    var subtitle: String {
        switch self {
        case .general: return T.s("Startup, permissions and shortcuts.", "Inicio, permisos y atajos.")
        case .keys: return T.s("What each key types into the chat.", "Lo que escribe cada tecla en el chat.")
        case .voice: return T.s("Hold Fn, speak, release.", "Mantén Fn, habla y suelta.")
        case .alerts: return T.s("Know when your agent is done, and let it keep going.", "Entérate cuando tu agente termine y deja que siga solo.")
        case .packs: return T.s("Ready-made keys for the tools you use.", "Teclas listas para las herramientas que usas.")
        case .appearance: return T.s("How the bar looks and where it lives.", "Cómo se ve la barra y dónde vive.")
        case .pro: return T.s("Autopilot, voice included and alerts on your phone.", "Autopilot, voz incluida y avisos en el móvil.")
        case .about: return T.s("Agent Bar, made by PROMPTED.", "Agent Bar, hecho por PROMPTED.")
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .keys: return "keyboard.fill"
        case .voice: return "waveform"
        case .alerts: return "bell.badge.fill"
        case .packs: return "square.stack.3d.up.fill"
        case .appearance: return "paintbrush.fill"
        case .pro: return "seal.fill"
        case .about: return "info.circle.fill"
        }
    }
    var tint: Color {
        switch self {
        case .general: return Color(hex: 0x8e8e93)
        case .keys: return Dash.accent
        case .voice: return Color(hex: 0xff375f)
        case .alerts: return Color(hex: 0xff9f0a)
        case .packs: return Color(hex: 0x5e5ce6)
        case .appearance: return Color(hex: 0x0a84ff)
        case .pro: return Dash.accent
        case .about: return Color(hex: 0x30b0c7)
        }
    }
}

enum Dash {
    static let accent = Color(hex: 0xff5b1f)
    static let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
}

// MARK: - Piezas

/// Icono de sección como en los Ajustes del Sistema: símbolo blanco sobre un cuadrado de color.
struct DashIcon: View {
    let symbol: String; let tint: Color; var size: CGFloat = 22
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.52, weight: .semibold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(LinearGradient(colors: [tint.opacity(0.95), tint], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
    }
}

/// Un grupo de filas en cristal, con título y nota al pie.
struct DashSection<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title { Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4) }
            VStack(spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial))
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.025)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            if let footer { Text(footer).font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 4).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

/// Una fila: título, explicación opcional y el control a la derecha.
struct DashRow<Trailing: View>: View {
    let title: String
    var detail: String? = nil
    var symbol: String? = nil
    var divider = true
    @ViewBuilder var trailing: Trailing
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                if let symbol { Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(.secondary).frame(width: 20) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13))
                    if let detail, !detail.isEmpty { Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 16)
                trailing
            }.padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 40)
            if divider { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 0.5).padding(.leading, 14) }
        }
    }
}

struct DashToggle: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool
    var divider = true
    var body: some View {
        DashRow(title: title, detail: detail, divider: divider) { Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small) }
    }
}

/// Un estado de un vistazo: punto verde o ámbar y una palabra.
struct DashStatus: View {
    let ok: Bool; let text: String
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(ok ? Color(hex: 0x30d158) : Color(hex: 0xff9f0a)).frame(width: 7, height: 7)
                .shadow(color: (ok ? Color(hex: 0x30d158) : Color(hex: 0xff9f0a)).opacity(0.6), radius: 3)
            Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        }
    }
}

struct Shortcut: View {
    let keys: String
    var body: some View {
        Text(keys).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
    }
}

// MARK: - Ventana

@MainActor
struct DashboardView: View {
    @ObservedObject var store: DeskStore
    @ObservedObject var voice: VoiceController
    var actions = DashboardActions()
    @State var pane: DashPane = .general
    /// Se sube después de una acción del AppDelegate (diálogos), para volver a leer el estado real (ganchos, permisos).
    @State private var tick = 0
    @State private var loginOn = SMAppService.mainApp.status == .enabled
    @State private var editingKey: DeskKey?
    @State private var addingKey = false
    @State private var confirmRestore = false
    @State private var apiKey = ""
    @State private var appBundle = ""
    @State private var appTone: VoiceTone = .clean

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 232)
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 0.5)
            content
        }
        .background(VisualEffect(material: .underWindowBackground).ignoresSafeArea())
        .tint(Dash.accent)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .sheet(item: $editingKey) { k in KeyEditor(key: k, isNew: false) { store.update($0) } }
        .sheet(isPresented: $addingKey) { KeyEditor(key: DeskKey(label: "", text: ""), isNew: true) { store.add($0) } }
        .confirmationDialog(T.s("Restore the default keys?", "¿Restaurar las teclas de fábrica?"), isPresented: $confirmRestore) {
            Button(T.s("Restore", "Restaurar"), role: .destructive) { store.restoreDefaults() }
        } message: { Text(T.s("Your current keys are replaced by the original six.", "Tus teclas actuales se sustituyen por las seis originales.")) }
    }

    private func refresh() { tick += 1; loginOn = SMAppService.mainApp.status == .enabled }
    private func after(_ f: @escaping () -> Void) -> () -> Void { { f(); refresh() } }

    // MARK: barra lateral

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(LinearGradient(colors: [Color(hex: 0x2a2a2e), Color(hex: 0x111114)], startPoint: .top, endPoint: .bottom))
                    HStack(spacing: 3) { Circle().fill(.white).frame(width: 4, height: 4); Circle().fill(.white).frame(width: 4, height: 4); Capsule().fill(Dash.accent).frame(width: 9, height: 6) }
                }.frame(width: 32, height: 32).shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Agent Bar").font(.system(size: 14, weight: .semibold))
                    Text(Dash.version.isEmpty ? "" : "v" + Dash.version).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 16).padding(.top, 44).padding(.bottom, 18)
            VStack(spacing: 2) {
                ForEach(DashPane.allCases) { p in
                    Button { withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { pane = p } } label: {
                        HStack(spacing: 10) {
                            DashIcon(symbol: p.symbol, tint: p.tint)
                            Text(p.title).font(.system(size: 13, weight: pane == p ? .semibold : .regular))
                            Spacer()
                        }
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(pane == p ? Color.primary.opacity(0.09) : .clear))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).focusEffectDisabled()
                }
            }.padding(.horizontal, 10)
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                let _ = tick
                DashStatus(ok: Sender.accessibilityGranted(prompt: false), text: T.s("Accessibility", "Accesibilidad"))
                DashStatus(ok: ClaudeHooks.installed && !ClaudeHooks.paused, text: T.s("Claude Code alerts", "Avisos de Claude Code"))
                DashStatus(ok: store.autopilotLeft > 0, text: store.autopilotLeft > 0 ? T.s("Autopilot · \(store.autopilotLeft) left", "Autopilot · quedan \(store.autopilotLeft)") : T.s("Autopilot off", "Autopilot apagado"))
            }.padding(16)
        }
        .background(VisualEffect(material: .sidebar).ignoresSafeArea())
    }

    // MARK: contenido

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    DashIcon(symbol: pane.symbol, tint: pane.tint, size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(pane.title).font(.system(size: 24, weight: .bold))
                        Text(pane.subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }.padding(.bottom, 2)
                Group {
                    switch pane {
                    case .general: general
                    case .keys: keysPane
                    case .voice: voicePane
                    case .alerts: alertsPane
                    case .packs: packsPane
                    case .appearance: appearancePane
                    case .pro: ProView(license: License.shared, embedded: true)
                    case .about: aboutPane
                    }
                }.transition(.opacity.combined(with: .offset(y: 6)))
            }
            .padding(.horizontal, 30).padding(.top, 44).padding(.bottom, 30)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(pane)
        }
    }

    // MARK: General

    private var general: some View {
        VStack(alignment: .leading, spacing: 22) {
            let _ = tick
            let ax = Sender.accessibilityGranted(prompt: false)
            DashSection(title: T.s("Startup", "Inicio")) {
                DashToggle(title: T.s("Open at login", "Abrir al iniciar sesión"), detail: T.s("Agent Bar is ready as soon as you log in.", "Agent Bar está lista nada más entrar."), isOn: Binding(get: { loginOn }, set: { _ in
                    do { if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() } } catch { NSLog("Agent Bar: inicio de sesión: \(error)") }
                    loginOn = SMAppService.mainApp.status == .enabled
                }))
                DashRow(title: T.s("Show or hide the bar", "Mostrar u ocultar la barra")) {
                    Shortcut(keys: "⌃⌥D"); Button(T.s("Toggle", "Alternar"), action: actions.toggleBar).controlSize(.small)
                }
                DashRow(title: T.s("Language", "Idioma"), detail: T.s("Agent Bar restarts to switch. Dictation follows your Mac's language.", "Agent Bar se reinicia para cambiarlo. El dictado sigue el idioma de tu Mac."), divider: false) {
                    Picker("", selection: Binding(get: { T.es ? "es" : "en" }, set: { v in
                        guard v != (T.es ? "es" : "en") else { return }
                        UserDefaults.standard.set(v, forKey: T.languageKey); actions.relaunch()
                    })) { Text("English").tag("en"); Text("Español").tag("es") }.labelsHidden().fixedSize()
                }
            }
            DashSection(title: T.s("Permissions", "Permisos"), footer: T.s("Agent Bar types into the app in front using Accessibility. Nothing leaves your Mac unless you use OpenAI voice with your own key.", "Agent Bar escribe en la app que tienes delante con Accesibilidad. Nada sale de tu Mac salvo la voz de OpenAI con tu propia clave.")) {
                DashRow(title: T.s("Accessibility", "Accesibilidad"), detail: ax ? T.s("Granted", "Concedido") : T.s("Needed to type and send for you", "Hace falta para escribir y enviar por ti"), symbol: "hand.raised.fill", divider: false) {
                    DashStatus(ok: ax, text: ax ? T.s("On", "Activado") : T.s("Off", "Desactivado"))
                    Button(T.s("Open settings", "Abrir ajustes"), action: after(actions.openAccessibility)).controlSize(.small)
                }
            }
            DashSection(title: T.s("Shortcuts", "Atajos")) {
                shortcutRow(T.s("Press key 1…9", "Pulsar tecla 1…9"), "⌃⌥1…9")
                shortcutRow(T.s("Dictate to the chat", "Dictar al chat"), "⌃⌥M")
                shortcutRow(T.s("Paste last transcription", "Pegar última transcripción"), "⌃⌥L")
                shortcutRow(T.s("Explain what I selected", "Explicar lo seleccionado"), "⌃⌥E")
                shortcutRow(T.s("What's wrong on screen?", "¿Qué falla en pantalla?"), "⌃⌥S")
                shortcutRow(T.s("Voice, drafts & history", "Voz, borradores e historial"), "⌃⌥,")
                shortcutRow(T.s("Message flows", "Flujos de mensajes"), "⌃⌥F")
                shortcutRow(T.s("Pause message flow", "Pausar flujo de mensajes"), "⌃⌥P", divider: false)
            }
            DashSection(title: T.s("Help", "Ayuda")) {
                DashRow(title: T.s("Tutorial", "Tutorial"), detail: T.s("Two minutes: permissions, keys and voice.", "Dos minutos: permisos, teclas y voz."), symbol: "graduationcap.fill") { Button(T.s("Open", "Abrir"), action: actions.openTutorial).controlSize(.small) }
                DashRow(title: T.s("Quit Agent Bar", "Salir de Agent Bar"), symbol: "power", divider: false) { Button(T.s("Quit", "Salir"), action: actions.quit).controlSize(.small) }
            }
        }
    }
    private func shortcutRow(_ t: String, _ k: String, divider: Bool = true) -> some View { DashRow(title: t, divider: divider) { Shortcut(keys: k) } }

    // MARK: Teclas

    private var keysPane: some View {
        VStack(alignment: .leading, spacing: 22) {
            DashSection(title: T.s("Your keys", "Tus teclas"), footer: T.s("The first key is the main one: it is also what Autopilot sends. Keys 1–9 have a global shortcut ⌃⌥ + number.", "La primera tecla es la principal: también es lo que manda Autopilot. Las teclas 1–9 tienen atajo global ⌃⌥ + número.")) {
                if store.keys.isEmpty { DashRow(title: T.s("No keys yet", "Aún no hay teclas"), divider: false) { EmptyView() } }
                ForEach(Array(store.keys.enumerated()), id: \.element.id) { i, k in
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Image(systemName: k.icon).font(.system(size: 14, weight: .medium)).foregroundStyle(i == 0 ? .white : .primary)
                                .frame(width: 30, height: 30)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(i == 0 ? AnyShapeStyle(Dash.accent) : AnyShapeStyle(Color.primary.opacity(0.07))))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(k.label).font(.system(size: 13, weight: .medium))
                                Text("«\(k.text)»").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                            }
                            Spacer(minLength: 12)
                            if !k.sendEnter { Image(systemName: "return").font(.system(size: 10)).foregroundStyle(.tertiary).help(T.s("Doesn't press Enter", "No pulsa Intro")) }
                            if let h = k.hotkey { Shortcut(keys: "⌃⌥\(h)") }
                            Button { editingKey = k } label: { Image(systemName: "pencil") }.buttonStyle(.borderless).help(T.s("Edit", "Editar"))
                            Button { store.remove(k) } label: { Image(systemName: "trash") }.buttonStyle(.borderless).foregroundStyle(.secondary).help(T.s("Remove", "Quitar"))
                        }.padding(.horizontal, 14).padding(.vertical, 9)
                        if i < store.keys.count - 1 { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 0.5).padding(.leading, 56) }
                    }
                }
            }
            HStack(spacing: 10) {
                Button { addingKey = true } label: { Label(T.s("Add a key", "Añadir tecla"), systemImage: "plus") }.buttonStyle(.borderedProminent).controlSize(.regular)
                Button(T.s("Restore default keys", "Restaurar teclas de fábrica")) { confirmRestore = true }
                Spacer()
                Button { actions.shareKeys() } label: { Label(T.s("Share my keys", "Compartir mis teclas"), systemImage: "link") }
            }
        }
    }

    // MARK: Voz

    private var voicePane: some View {
        VStack(alignment: .leading, spacing: 22) {
            DashSection(title: T.s("Engine", "Motor"), footer: T.s("OpenAI mode sends the audio and, for cleanup, the transcript to OpenAI with your API key. Apple runs on the Mac, free and without a key.", "El modo OpenAI envía el audio y, para limpiarlo, la transcripción a OpenAI con tu clave. Apple funciona en el Mac, gratis y sin clave.")) {
                DashRow(title: T.s("Transcription", "Transcripción"), divider: voice.preferences.engine == .apple || true) {
                    Picker("", selection: $voice.preferences.engine) { Text("OpenAI").tag(VoiceEngine.openAI); Text("Apple").tag(VoiceEngine.apple) }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                        .onChange(of: voice.preferences.engine) { _, engine in if engine == .apple { voice.preferences.tone = .verbatim } }
                }
                if voice.preferences.engine == .apple {
                    DashRow(title: T.s("Speech on this Mac", "Voz de este Mac"), detail: voice.appleStatus) {
                        if !voice.appleStatus.hasPrefix("✓") { Button(T.s("Allow", "Permitir")) { voice.allowApple() }.controlSize(.small) }
                    }.onAppear { voice.refreshAppleStatus() }
                }
                DashRow(title: T.s("OpenAI API key", "Clave de la API de OpenAI"), detail: voice.keyConfigured ? T.s("Configured. Access is checked when you use voice.", "Configurada. El acceso se comprueba al usar la voz.") : T.s("No key configured.", "No hay clave configurada.")) {
                    if voice.keyConfigured {
                        Button(T.s("Test", "Probar")) { voice.testKey() }.disabled(voice.keyTesting).controlSize(.small)
                        Button(T.s("Remove", "Eliminar")) { voice.removeKey() }.disabled(voice.active).controlSize(.small)
                    }
                }
                HStack(spacing: 8) {
                    SecureField(voice.keyConfigured ? T.s("Replace key…", "Sustituir clave…") : "sk-…", text: $apiKey).textFieldStyle(.roundedBorder).disabled(voice.active)
                    Button(T.s("Save", "Guardar")) { voice.saveKey(apiKey); apiKey = "" }.disabled(voice.active || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(.horizontal, 14).padding(.vertical, 10)
                if !voice.keyTest.isEmpty { Text(voice.keyTest).font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.bottom, 10).frame(maxWidth: .infinity, alignment: .leading) }
            }
            DashSection(title: T.s("While you talk", "Mientras hablas")) {
                DashToggle(title: T.s("Transcribe while I talk", "Transcribir mientras hablo"), detail: T.s("Faster; uses gpt-live-transcribe", "Más rápido; usa gpt-live-transcribe"), isOn: $voice.preferences.streaming)
                DashToggle(title: T.s("Show my words while I talk", "Ver mis palabras mientras hablo"), isOn: $voice.preferences.showLiveText).disabled(!voice.preferences.streaming)
                DashRow(title: T.s("Language", "Idioma"), detail: T.s("es, en… Blank for automatic", "es, en… Vacío para automático"), divider: false) {
                    TextField("auto", text: $voice.preferences.language).textFieldStyle(.roundedBorder).frame(width: 90)
                }
            }
            DashSection(title: T.s("Keyboard & insertion", "Teclado e inserción"), footer: T.s("Hold Fn to dictate; double-tap Fn or Fn+Control for hands-free; Fn+Option edits the selection; Escape cancels. The clipboard is restored if it hasn't changed.", "Mantén Fn para dictar; doble toque o Fn+Control para manos libres; Fn+Opción edita la selección; Escape cancela. El portapapeles se restaura si no ha cambiado.")) {
                DashToggle(title: T.s("Dictate with Fn", "Dictar con Fn"), detail: voice.shortcutStatus, isOn: $voice.preferences.fnEnabled)
                DashRow(title: T.s("Tap feedback", "Toque"), detail: T.s("A short, low knock when it starts listening and when it sends", "Un golpe corto y grave al empezar a escuchar y al enviar")) {
                    Button(T.s("Play", "Escuchar")) { Chime.play("start"); DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { Chime.play("send") } }.controlSize(.small)
                    Toggle("", isOn: Binding(get: { DeskStore.voiceCues }, set: { DeskStore.voiceCues = $0; refresh() })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                DashToggle(title: T.s("Avoid Fn conflicts while Vowen is running", "Evitar conflictos de Fn con Vowen abierto"), isOn: $voice.preferences.avoidVowenConflict)
                DashToggle(title: T.s("Insert automatically in the original field", "Insertar solo en el campo original"), isOn: $voice.preferences.autoPaste)
                DashRow(title: T.s("Insertion method", "Método de inserción")) {
                    Picker("", selection: $voice.preferences.insertion) { Text(T.s("Paste", "Pegar")).tag(VoiceInsertion.paste); Text(T.s("Direct", "Directo")).tag(VoiceInsertion.direct) }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 160)
                }
                DashToggle(title: T.s("Press Enter after inserting", "Pulsar Intro después de insertar"), detail: T.s("Sends the chat message", "Envía el mensaje del chat"), isOn: $voice.preferences.autoEnter).disabled(!voice.preferences.autoPaste)
                DashToggle(title: T.s("No Enter in terminals and editors", "Sin Intro en terminales y editores"), isOn: $voice.preferences.guardTerminal, divider: false)
            }
            DashSection(title: T.s("Your writing style", "Tu forma de escribir"), footer: T.s("Verbatim skips AI cleanup. Other tones and selection editing use the OpenAI text model.", "Literal omite la limpieza con IA. Los demás tonos y la edición de selecciones usan el modelo de texto de OpenAI.")) {
                DashRow(title: T.s("Tone", "Tono")) {
                    Picker("", selection: $voice.preferences.tone) { ForEach(VoiceTone.allCases, id: \.self) { Text($0.title).tag($0) } }.labelsHidden().frame(width: 160)
                }
                DashToggle(title: T.s("Talk, get a prompt", "Habla y sale un prompt"), detail: T.s("In AI chats, longer dictation becomes a clear prompt", "En los chats de IA, lo dictado largo se convierte en un prompt claro"), isOn: $voice.preferences.promptInAIApps)
                editorRow(T.s("Style instructions", "Instrucciones de estilo"), $voice.preferences.instructions, height: 56)
                VStack(alignment: .leading, spacing: 8) {
                    Text(T.s("Tone by app", "Tono por aplicación")).font(.system(size: 13))
                    HStack {
                        TextField(T.s("Bundle ID (e.g. com.apple.mail)", "Bundle ID (p. ej. com.apple.mail)"), text: $appBundle).textFieldStyle(.roundedBorder)
                        Picker("", selection: $appTone) { ForEach(VoiceTone.allCases, id: \.self) { Text($0.title).tag($0) } }.labelsHidden().frame(width: 120)
                        Button(T.s("Add", "Añadir")) { let id = appBundle.trimmingCharacters(in: .whitespacesAndNewlines); if !id.isEmpty { voice.preferences.appTones[id] = appTone; appBundle = "" } }
                    }
                    ForEach(voice.preferences.appTones.keys.sorted(), id: \.self) { id in
                        HStack { Text(id).font(.system(size: 11)); Spacer(); Text(voice.preferences.appTones[id]?.title ?? "").font(.system(size: 11)).foregroundStyle(.secondary); Button { voice.preferences.appTones.removeValue(forKey: id) } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless).foregroundStyle(.tertiary) }
                    }
                }.padding(.horizontal, 14).padding(.vertical, 10)
            }
            DashSection(title: T.s("Vocabulary & history", "Vocabulario e historial")) {
                editorRow(T.s("Names and technical terms, one per line", "Nombres y términos técnicos, uno por línea"), $voice.preferences.dictionary, height: 56)
                editorRow(T.s("Expansions: phrase => replacement", "Expansiones: frase => sustitución"), $voice.preferences.expansions, height: 56)
                DashToggle(title: T.s("Save text history on this Mac", "Guardar historial de texto en este Mac"), detail: T.s("Last 100", "Últimos 100"), isOn: $voice.preferences.saveHistory, divider: false)
            }
            DashSection(title: T.s("Advanced", "Avanzado")) {
                DashRow(title: T.s("Transcription model", "Modelo de transcripción")) { TextField("", text: $voice.preferences.transcriptionModel).textFieldStyle(.roundedBorder).frame(width: 200) }
                DashRow(title: T.s("Text model", "Modelo de texto"), divider: false) { TextField("", text: $voice.preferences.textModel).textFieldStyle(.roundedBorder).frame(width: 200) }
            }
            HStack(spacing: 10) {
                Button { actions.openVoice() } label: { Label(T.s("Drafts & history", "Borradores e historial"), systemImage: "text.bubble") }.buttonStyle(.borderedProminent)
                Button(T.s("Paste last transcription", "Pegar última transcripción")) { voice.pasteLast() }
            }
        }
    }
    private func editorRow(_ title: String, _ text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            TextEditor(text: text).font(.system(size: 12)).scrollContentBackground(.hidden).frame(height: height).padding(6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        }.padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: Avisos y piloto

    private var alertsPane: some View {
        VStack(alignment: .leading, spacing: 22) {
            let _ = tick
            DashSection(title: "Claude Code", footer: T.s("A one-line alert with a summary when a conversation finishes or needs your yes. Agent Bar adds two hooks to ~/.claude/settings.json and saves a backup first.", "Un aviso de una línea con resumen cuando una conversación termina o necesita tu sí. Agent Bar añade dos ganchos a ~/.claude/settings.json y antes guarda una copia.")) {
                if ClaudeHooks.installed {
                    DashToggle(title: T.s("Alerts", "Avisos"), detail: T.s("Turns off instantly, without restarting Claude Code", "Se apagan al momento, sin reiniciar Claude Code"), isOn: Binding(get: { !ClaudeHooks.paused }, set: { on in
                        ClaudeHooks.paused = !on
                        if ClaudeHooks.paused { store.setAutopilot(0) }
                        store.flashNote(ClaudeHooks.paused ? T.s("Claude Code alerts off", "Avisos de Claude Code apagados") : T.s("Claude Code alerts on", "Avisos de Claude Code activados"))
                        refresh()
                    }))
                    DashRow(title: T.s("Try an alert", "Probar un aviso")) {
                        Button(T.s("Try", "Probar")) { store.raiseAlert(app: "Claude Code", ask: false, place: T.s("test", "prueba"), message: T.s("This is how an alert looks.", "Así se ve un aviso.")) }.controlSize(.small)
                    }
                    DashRow(title: T.s("Remove from Claude Code", "Quitar de Claude Code"), divider: false) { Button(T.s("Remove…", "Quitar…"), action: after(actions.removeClaudeAlerts)).controlSize(.small) }
                } else {
                    DashRow(title: ClaudeHooks.oldVersion ? T.s("Update alerts", "Actualizar avisos") : T.s("Turn on alerts", "Activar avisos"), detail: T.s("Off", "Apagados"), divider: false) {
                        Button(ClaudeHooks.oldVersion ? T.s("Update…", "Actualizar…") : T.s("Turn on…", "Activar…"), action: after(actions.connectClaude)).buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
                if FileManager.default.fileExists(atPath: WhatsAppRelay.folder.path) {
                    DashToggle(title: T.s("Alerts to Alfred's WhatsApp when I'm away", "Avisos al WhatsApp de Alfred si no estoy"), isOn: Binding(get: { UserDefaults.standard.object(forKey: "whatsappAlerts") as? Bool ?? true }, set: { UserDefaults.standard.set($0, forKey: "whatsappAlerts"); refresh() }), divider: false)
                }
            }
            DashSection(title: "Autopilot", footer: T.s("Claude Code keeps going on its own, sending your first key, and stops at a real question or a permission. Needs Claude Code alerts.", "Claude Code sigue solo mandando tu primera tecla y se para ante una pregunta de verdad o un permiso. Necesita los avisos de Claude Code.")) {
                DashRow(title: T.s("Keep going", "Seguir solo"), detail: store.autopilotLeft > 0 ? T.s("\(store.autopilotLeft) turns left", "Quedan \(store.autopilotLeft) vueltas") : T.s("Off", "Apagado"), divider: false) {
                    Picker("", selection: Binding(get: { [0, 3, 5, 10, 20].contains(store.autopilotLeft) ? store.autopilotLeft : -1 }, set: { n in
                        guard n >= 0 else { return }
                        if n > 0 && !ClaudeHooks.installed { actions.connectClaude(); refresh(); if !ClaudeHooks.installed { return } }
                        store.setAutopilot(n)
                    })) {
                        Text(T.s("Off", "No")).tag(0); Text("3").tag(3); Text("5").tag(5); Text("10").tag(10); Text("20").tag(20)
                        if ![0, 3, 5, 10, 20].contains(store.autopilotLeft) { Text("\(store.autopilotLeft)").tag(-1) }
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 230)
                }
            }
            DashSection(title: T.s("Message flows", "Flujos de mensajes"), footer: T.s("Queue the next steps for Codex and other agents.", "Encola los siguientes pasos para Codex y otros agentes.")) {
                DashRow(title: T.s("Flows", "Flujos"), symbol: "arrow.triangle.branch") { Shortcut(keys: "⌃⌥F"); Button(T.s("Open", "Abrir"), action: actions.openFlows).controlSize(.small) }
                DashRow(title: T.s("Pause the running flow", "Pausar el flujo en marcha"), symbol: "pause.circle", divider: false) { Shortcut(keys: "⌃⌥P"); Button(T.s("Pause", "Pausar"), action: actions.pauseFlow).controlSize(.small) }
            }
        }
    }

    // MARK: Packs

    private var packsPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(Array(KeyPack.builtIn.enumerated()), id: \.offset) { _, p in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text(p.name).font(.system(size: 15, weight: .semibold)); Spacer(); Text(T.s("\(p.keys.count) keys", "\(p.keys.count) teclas")).font(.system(size: 11)).foregroundStyle(.secondary) }
                        FlowChips(keys: p.keys)
                        Spacer(minLength: 0)
                        Button { actions.offerPack(p) } label: { Text(T.s("Add to Agent Bar…", "Añadir a Agent Bar…")).frame(maxWidth: .infinity) }.controlSize(.regular)
                    }
                    .padding(16).frame(minHeight: 170, alignment: .top)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                }
            }
            DashSection(footer: T.s("A pack link carries the whole pack. Agent Bar always asks before adding it.", "Un enlace de pack lleva el pack entero. Agent Bar siempre pregunta antes de añadirlo.")) {
                DashRow(title: T.s("Share my keys", "Compartir mis teclas"), detail: T.s("Copies a link to your current keys", "Copia un enlace con tus teclas actuales"), symbol: "link") { Button(T.s("Copy link", "Copiar enlace"), action: actions.shareKeys).controlSize(.small) }
                DashRow(title: T.s("More packs", "Más packs"), detail: "getagentbar.com/packs", symbol: "safari", divider: false) { Button(T.s("Open", "Abrir"), action: actions.morePacks).controlSize(.small) }
            }
        }
    }

    // MARK: Aspecto

    private var appearancePane: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text(T.s("Style", "Estilo")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                HStack(spacing: 14) { ForEach(BarStyle.allCases, id: \.self) { st in styleCard(st) } }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(T.s("Where it lives", "Dónde vive")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                HStack(spacing: 14) {
                    modeCard(.dock, T.s("Bar", "Barra"), T.s("At the bottom of the screen", "Abajo de la pantalla"))
                    modeCard(.card, T.s("Floating card", "Tarjeta flotante"), T.s("Anywhere you drag it", "Donde la arrastres"))
                }
            }
            Text(T.s("Drag the orb anywhere, or fling it to the edge to tuck it away.", "Arrastra el orbe donde quieras o lánzalo al borde para esconderlo.")).font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 4)
        }
    }
    private func choiceCard<Preview: View>(selected: Bool, title: String, detail: String, action: @escaping () -> Void, @ViewBuilder preview: () -> Preview) -> some View {
        Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { action() } }) {
            VStack(alignment: .leading, spacing: 10) {
                preview().frame(maxWidth: .infinity).frame(height: 88)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LinearGradient(colors: [Color(hex: 0x2b2420), Color(hex: 0x111114)], startPoint: .bottomLeading, endPoint: .topTrailing)))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                HStack(spacing: 6) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Dash.accent : Color.secondary)
                    VStack(alignment: .leading, spacing: 1) { Text(title).font(.system(size: 13, weight: .semibold)); Text(detail).font(.system(size: 11)).foregroundStyle(.secondary) }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? Dash.accent : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 0.5))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func styleCard(_ st: BarStyle) -> some View {
        let th = Theme.of(st)
        let detail: String = { switch st { case .classic: return T.s("The original, dark", "La de siempre, oscura"); case .glass: return T.s("Smoked glass", "Cristal ahumado"); case .metal: return T.s("Like the Pad", "Como el Pad") } }()
        return choiceCard(selected: store.style == st, title: st.title, detail: detail, action: { store.style = st }) {
            HStack(spacing: 5) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(i == 1 ? th.accent : th.tile).frame(width: 22, height: 22)
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(th.tileLine, lineWidth: 0.5))
                }
            }
            .padding(7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(st == .metal ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xf4f4f2), Color(hex: 0xd6d6d2)], startPoint: .top, endPoint: .bottom)) : st == .glass ? AnyShapeStyle(Color.white.opacity(0.12)) : AnyShapeStyle(Palette.bg.opacity(0.92))))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(st == .metal ? 0.6 : 0.16), lineWidth: 0.5))
        }
    }
    private func modeCard(_ m: DeskMode, _ title: String, _ detail: String) -> some View {
        choiceCard(selected: store.mode == m, title: title, detail: detail, action: { store.mode = m }) {
            ZStack(alignment: m == .dock ? .bottom : .topTrailing) {
                Color.clear
                RoundedRectangle(cornerRadius: m == .dock ? 6 : 8, style: .continuous).fill(Color.white.opacity(0.16))
                    .overlay(RoundedRectangle(cornerRadius: m == .dock ? 6 : 8, style: .continuous).strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
                    .frame(width: m == .dock ? 120 : 54, height: m == .dock ? 16 : 40)
                    .padding(m == .dock ? 10 : 14)
            }
        }
    }

    // MARK: Acerca de

    private var aboutPane: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage()).resizable().frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Agent Bar").font(.system(size: 20, weight: .bold))
                    Text(T.s("Version", "Versión") + " " + Dash.version).font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(T.s("Press one key. Your AI keeps going.", "Pulsa una tecla. Tu IA sigue.")).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            DashSection {
                linkRow("getagentbar.com", "globe", "https://getagentbar.com")
                linkRow(T.s("Agent Pad: the physical keys", "Agent Pad: las teclas físicas"), "keyboard", "https://getagentbar.com/pad/")
                linkRow(T.s("Source code (MIT)", "Código fuente (MIT)"), "chevron.left.forwardslash.chevron.right", "https://github.com/kemet333/agent-deck")
                linkRow("PROMPTED®", "sparkles", "https://www.workwithprompted.com", divider: false)
            }
        }
    }
    private func linkRow(_ t: String, _ s: String, _ url: String, divider: Bool = true) -> some View {
        DashRow(title: t, symbol: s, divider: divider) { Button { if let u = URL(string: url) { NSWorkspace.shared.open(u) } } label: { Image(systemName: "arrow.up.right") }.buttonStyle(.borderless) }
    }
}

/// Las teclas de un pack como fichas que saltan de línea según el ancho: el nombre entero, nunca con «…».
struct FlowChips: View {
    let keys: [KeyPack.Key]
    var body: some View {
        WrapLayout(spacing: 6) {
            ForEach(keys, id: \.label) { k in
                HStack(spacing: 5) { Image(systemName: k.icon).font(.system(size: 10)); Text(k.label).font(.system(size: 11, weight: .medium)).fixedSize() }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            }
        }
    }
}

/// Coloca las vistas en filas y salta de línea cuando no caben.
struct WrapLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let r = rows(proposal.width ?? .infinity, subviews)
        let w = r.map { $0.width }.max() ?? 0
        return CGSize(width: proposal.width ?? w, height: r.map { $0.height }.reduce(0, +) + spacing * CGFloat(max(r.count - 1, 0)))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(bounds.width, subviews) {
            var x = bounds.minX
            for i in row.items {
                let sz = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
                x += sz.width + spacing
            }
            y += row.height + spacing
        }
    }
    private func rows(_ maxW: CGFloat, _ subviews: Subviews) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var out: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        var cur: [Int] = [], w: CGFloat = 0, h: CGFloat = 0
        for i in subviews.indices {
            let sz = subviews[i].sizeThatFits(.unspecified)
            if !cur.isEmpty && w + spacing + sz.width > maxW { out.append((cur, w, h)); cur = []; w = 0; h = 0 }
            w += (cur.isEmpty ? 0 : spacing) + sz.width; h = max(h, sz.height); cur.append(i)
        }
        if !cur.isEmpty { out.append((cur, w, h)) }
        return out
    }
}

/// La ventana del panel: sin barra de título visible, cristal detrás, se mueve arrastrando el fondo.
@MainActor
func makeDashboardWindow(root: some View) -> NSWindow {
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                     styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    w.title = "Agent Bar"
    w.titleVisibility = .hidden
    w.titlebarAppearsTransparent = true
    w.isMovableByWindowBackground = true
    w.isOpaque = false
    w.backgroundColor = .clear
    w.minSize = NSSize(width: 780, height: 520)
    w.isReleasedWhenClosed = false
    w.contentView = NSHostingView(rootView: root)
    w.center()
    return w
}
