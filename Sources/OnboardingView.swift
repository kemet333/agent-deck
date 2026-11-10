import AVFoundation
import AppKit
import Speech
import SwiftUI

/// El tutorial de la primera vez: explica toda la herramienta y deja configurarla en el momento
/// (permisos con su estado real, voz, avisos y estilo). Se vuelve a abrir desde el menú → Tutorial.
struct OnboardingView: View {
    @ObservedObject var store: DeskStore
    @ObservedObject var voice: VoiceController
    let connectClaude: () -> Void
    let finish: () -> Void

    @State var page = 0
    /// Solo para las capturas de prueba: sin desplazamiento (el renderizador de imágenes no lo pinta).
    var snapshot = false
    @State private var axOK = Sender.accessibilityGranted(prompt: false)
    @State private var micOK = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var speechOK = SFSpeechRecognizer.authorizationStatus() == .authorized
    @State private var claudeOK = ClaudeHooks.installed
    @State private var apiKey = ""
    /// Lo último enviado al abrir: si cambia, el paso «Pruébalo» se marca.
    @State private var sentAtStart = ""
    @State private var started = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let pages = 8

    var body: some View {
        VStack(spacing: 0) {
            if snapshot { content.padding(.horizontal, 36).padding(.top, 30).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) }
            else { ScrollView { content.padding(.horizontal, 36).padding(.top, 30).padding(.bottom, 12).frame(maxWidth: .infinity, alignment: .leading) } }
            Divider()
            HStack {
                HStack(spacing: 6) { ForEach(0..<pages, id: \.self) { i in Circle().fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 6, height: 6) } }
                Spacer()
                if page > 0 { Button(T.s("Back", "Atrás")) { withAnimation { page -= 1 } } }
                if page == 0 {
                    Button(T.s("Full tour", "Recorrido completo")) { withAnimation { page = 1 } }
                    Button(T.s("Start", "Empezar")) { finish() }.keyboardShortcut(.defaultAction)
                } else if page < pages - 1 {
                    Button(T.s("Next", "Siguiente")) { withAnimation { page += 1 } }.keyboardShortcut(.defaultAction)
                } else {
                    Button(T.s("Start using Agent Bar", "Empezar a usar Agent Bar")) { finish() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(width: 620, height: 560)
        .onAppear { if !started { started = true; sentAtStart = store.lastSent } }
        .onReceive(tick) { _ in
            axOK = Sender.accessibilityGranted(prompt: false)
            micOK = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            speechOK = SFSpeechRecognizer.authorizationStatus() == .authorized
            claudeOK = ClaudeHooks.installed
        }
    }

    @ViewBuilder private var content: some View {
        switch page {
        case 0: welcome
        case 1: permissions
        case 2: keys
        case 3: talk
        case 4: explain
        case 5: alerts
        case 6: orb
        default: done
        }
    }

    // MARK: páginas

    /// La primera página (0.17): listo en 60 segundos. Cuatro cosas que se marcan solas al hacerlas; el resto del recorrido
    /// es opcional («Recorrido completo»).
    private var welcome: some View {
        step("bolt.fill", T.s("Ready in 60 seconds", "Lista en 60 segundos"),
             T.s("Agent Bar answers your AI agents for you: one key types «continue», «test it» or «fix it» in the chat in front and sends it, and fn lets you talk. Four steps, each ticks itself when it's done.",
                  "Agent Bar contesta a tus agentes de IA por ti: una tecla escribe «continúa», «pruébalo» o «arréglalo» en el chat de delante y lo envía, y con fn le hablas. Cuatro pasos; cada uno se marca solo al hacerlo.")) {
            permissionRow(axOK, T.s("1 · Let it type", "1 · Déjale escribir"), T.s("Accessibility, so it can paste and press Enter in your chat.", "Accesibilidad, para pegar y pulsar Intro en tu chat."), T.s("Allow", "Permitir")) {
                _ = Sender.accessibilityGranted(prompt: true)
                if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(u) }
            }
            permissionRow(micOK, T.s("2 · Let it hear you", "2 · Déjale oírte"), T.s("The microphone, for fn. You can skip it.", "El micrófono, para fn. Puedes saltártelo."), T.s("Allow", "Permitir")) { voice.allowApple() }
            permissionRow(store.lastSent != sentAtStart, T.s("3 · Try it", "3 · Pruébalo"), T.s("Click in any chat, hold fn and say «hello», or tap a key on the bar.", "Haz clic en cualquier chat, mantén fn y di «hola», o toca una tecla de la barra."), "") {}
            permissionRow(claudeOK, T.s("4 · Claude Code (optional)", "4 · Claude Code (opcional)"), T.s("An alert when it's done, and its permissions from the bar.", "Un aviso cuando termina y sus permisos desde la barra."), T.s("Connect…", "Conectar…"), connectClaude)
        }
    }

    private var permissions: some View {
        step("lock.shield", T.s("Two permissions", "Dos permisos"),
             T.s("Agent Bar types for you, so macOS asks you to allow it once. Nothing is sent anywhere by these permissions.",
                  "Agent Bar escribe por ti, así que macOS te pide permitirlo una vez. Estos permisos no envían nada a ningún sitio.")) {
            permissionRow(axOK, T.s("Accessibility", "Accesibilidad"), T.s("Lets it press ⌘V and Enter in your chat. Required.", "Le deja pulsar ⌘V e Intro en tu chat. Imprescindible."),
                          T.s("Open settings", "Abrir ajustes")) {
                _ = Sender.accessibilityGranted(prompt: true)
                if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(u) }
            }
            permissionRow(micOK && speechOK, T.s("Microphone and speech", "Micrófono y voz"), T.s("For talking with fn. Optional.", "Para hablar con fn. Opcional."),
                          T.s("Allow", "Permitir")) { voice.allowApple() }
            Text(T.s("If Agent Bar doesn't appear in the Accessibility list, make sure it's in your Applications folder, then turn it on there. The ✓ turns green by itself.",
                     "Si Agent Bar no sale en la lista de Accesibilidad, comprueba que está en la carpeta Aplicaciones y actívala allí. El ✓ se pone verde solo."))
                .font(.callout).foregroundStyle(.secondary).padding(.top, 4)
        }
    }

    private var keys: some View {
        step("keyboard", T.s("The keys", "Las teclas"),
             T.s("Put the cursor in your AI chat and tap a key on the bar. It types the words and presses Enter. Your chat stays in front: the bar never takes the focus.",
                  "Pon el cursor en tu chat de IA y toca una tecla de la barra. Escribe las palabras y pulsa Intro. Tu chat sigue delante: la barra nunca se queda el foco.")) {
            ForEach(Array(store.keys.prefix(6).enumerated()), id: \.offset) { _, k in
                HStack(spacing: 10) {
                    Image(systemName: k.icon).frame(width: 20)
                    Text(k.label).fontWeight(.medium).frame(width: 100, alignment: .leading)
                    Text("⌃⌥\(k.hotkey.map(String.init) ?? "")").font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
                    Text("«\(k.text)»").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Text(T.s("To change them, press the sliders icon on the bar: rename a key, change what it types, or add your own. Menu → Restore default keys brings these back.",
                     "Para cambiarlas, pulsa el icono de ajustes deslizantes de la barra: cambia el nombre o lo que escribe una tecla, o añade las tuyas. Menú → Restaurar teclas de fábrica las devuelve."))
                .font(.callout).foregroundStyle(.secondary).padding(.top, 6)
        }
    }

    private var talk: some View {
        step("mic.fill", T.s("Hold fn and talk", "Mantén fn y habla"),
             T.s("Put the cursor in your chat, hold fn, speak, and let go: it's typed and sent. In an AI chat, a long request becomes a clear prompt. Esc cancels.",
                  "Pon el cursor en tu chat, mantén fn, habla y suelta: se escribe y se envía. En un chat de IA, una petición larga se convierte en un prompt claro. Esc cancela.")) {
            Picker(T.s("Voice engine", "Motor de voz"), selection: $voice.preferences.engine) {
                Text(T.s("Apple: free, no key", "Apple: gratis, sin clave")).tag(VoiceEngine.apple)
                Text(T.s("OpenAI: cleaner and faster (your key)", "OpenAI: más limpio y rápido (tu clave)")).tag(VoiceEngine.openAI)
            }
            .pickerStyle(.radioGroup)
            if voice.preferences.engine == .openAI {
                HStack {
                    SecureField(T.s("OpenAI API key (sk-…)", "Clave de la API de OpenAI (sk-…)"), text: $apiKey).textFieldStyle(.roundedBorder)
                    Button(T.s("Save", "Guardar")) { voice.saveKey(apiKey); apiKey = "" }.disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button(T.s("Test key", "Probar clave")) { voice.testKey() }.disabled(!voice.keyConfigured || voice.keyTesting)
                }
                Text(voice.keyTest.isEmpty ? (voice.keyConfigured ? T.s("A key is saved. Press «Test key» to check it.", "Hay una clave guardada. Pulsa «Probar clave» para comprobarla.") : T.s("Create one at platform.openai.com → API keys. It needs credit on that account. It stays on this Mac.", "Créala en platform.openai.com → API keys. Necesita saldo en esa cuenta. Se queda en este Mac.")) : voice.keyTest)
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text(T.s("Apple's dictation types exactly what you say. You can switch to OpenAI any time in the menu → Voice.", "El dictado de Apple escribe tal cual lo que dices. Puedes cambiar a OpenAI cuando quieras en el menú → Voz."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text(T.s("If fn opens emojis or Apple's dictation, set System Settings → Keyboard → «Press 🌐 key to» → Do Nothing.", "Si fn te abre los emojis o el dictado de Apple, pon Ajustes del Sistema → Teclado → «Pulsar la tecla 🌐 para» → No hacer nada."))
                .font(.callout).foregroundStyle(.secondary).padding(.top, 4)
        }
    }

    private var explain: some View {
        step("text.magnifyingglass", T.s("Ask about what you see", "Pregunta por lo que ves"),
             T.s("Both go to the last AI chat you used, or the one you're in, and are sent for you.", "Las dos van al último chat de IA que usaste, o al que tengas delante, y se envían solas.")) {
            bullet("text.magnifyingglass", T.s("Explain (⌃⌥E): select text in any app, an error, a log or a paragraph, and press it. Your chat explains it and tells you what to do.", "Explica (⌃⌥E): selecciona un texto en cualquier app, un error, un registro o un párrafo, y púlsala. Tu chat te lo explica y te dice qué hacer."))
            bullet("camera.viewfinder", T.s("Snap (⌃⌥S): drag over part of the screen. The picture goes to your chat with «What's wrong here?». Esc cancels. macOS asks once for Screen Recording.", "Captura (⌃⌥S): arrastra sobre una zona de la pantalla. La imagen va a tu chat con «¿Qué falla aquí?». Esc cancela. macOS pide una vez Grabación de pantalla."))
        }
    }

    private var alerts: some View {
        step("bell.badge", T.s("Know when Claude Code is done", "Entérate cuando Claude Code termina"),
             T.s("If you use Claude Code, a small one-line alert appears above the orb when a conversation finishes or needs your yes, with a one-sentence summary. Hover it to reply: talk with the mic, press Continue or type. The answer goes to that exact conversation, even with several open.",
                  "Si usas Claude Code, cuando una conversación termina o necesita tu sí aparece encima del orbe un aviso de una línea con un resumen en una frase. Pasa el ratón por encima para contestar: habla con el micro, pulsa Continúa o escribe. La respuesta va a esa conversación exacta, aunque tengas varias abiertas.")) {
            HStack {
                Button(claudeOK ? T.s("Alerts are on", "Avisos activados") : T.s("Turn on Claude Code alerts", "Activar avisos de Claude Code")) { connectClaude() }.disabled(claudeOK)
                if claudeOK { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            }
            Text(T.s("It adds two hooks to ~/.claude/settings.json after asking you, and saves a backup first. Restart Claude Code sessions to pick them up. If you don't use Claude Code, skip this.",
                     "Añade dos ganchos a ~/.claude/settings.json tras preguntarte, y antes guarda una copia. Reinicia las sesiones de Claude Code para que los lean. Si no usas Claude Code, sáltate esto."))
                .font(.callout).foregroundStyle(.secondary)
            bullet("repeat", T.s("Using Codex? Menu → Flows queues «next» several times: each time Codex finishes, the next one goes in.", "¿Usas Codex? Menú → Flujos encadena «siguiente» varias veces: cada vez que Codex termina, entra el siguiente."))
        }
    }

    private var orb: some View {
        step("circle.circle", T.s("The bar, the orb and your style", "La barra, el orbe y tu estilo"),
             T.s("The ✕ on the bar (or ⌃⌥D) folds it into a small orb. Drag the orb anywhere, or fling it to the edge of the screen to tuck it away. Tap it and the bar comes back.",
                  "La ✕ de la barra (o ⌃⌥D) la pliega en un orbe pequeño. Arrastra el orbe donde quieras, o lánzalo al borde de la pantalla para esconderlo. Tócalo y vuelve la barra.")) {
            Picker(T.s("Style", "Estilo"), selection: $store.style) { ForEach(BarStyle.allCases, id: \.self) { Text($0.title).tag($0) } }
                .pickerStyle(.segmented).frame(width: 320)
            bullet("gearshape", T.s("The gear on the bar opens the menu: style, voice, flows, alerts, this tutorial and more.", "El engranaje de la barra abre el menú: estilo, voz, flujos, avisos, este tutorial y más."))
        }
    }

    private var done: some View {
        step("checkmark.seal", T.s("You're set", "Todo listo"),
             T.s("Try it now: open your AI chat, put the cursor in the message box and tap Continue on the bar, or hold fn and say something.",
                  "Pruébalo ya: abre tu chat de IA, pon el cursor en la caja del mensaje y toca Continúa en la barra, o mantén fn y di algo.")) {
            permissionRow(axOK, T.s("Accessibility", "Accesibilidad"), axOK ? T.s("Ready", "Listo") : T.s("Still needed: see the permissions page.", "Aún falta: mira la página de permisos."), T.s("Open settings", "Abrir ajustes")) {
                if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(u) }
            }
            Text(T.s("You can open this tutorial again from the menu → Tutorial. Questions or ideas: hello@workwithprompted.com",
                     "Puedes volver a abrir este tutorial desde el menú → Tutorial. Dudas o ideas: hello@workwithprompted.com"))
                .font(.callout).foregroundStyle(.secondary).padding(.top, 6)
        }
    }

    // MARK: piezas

    private func step<C: View>(_ icon: String, _ title: String, _ text: String, @ViewBuilder _ extra: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon).font(.system(size: 30, weight: .regular)).foregroundStyle(Color(red: 1, green: 0.357, blue: 0.122))
            Text(title).font(.system(size: 24, weight: .semibold))
            Text(text).font(.system(size: 14)).foregroundStyle(.primary.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) { extra() }.padding(.top, 4)
        }
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).frame(width: 20).foregroundStyle(.secondary)
            Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionRow(_ ok: Bool, _ name: String, _ why: String, _ action: String, _ run: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed").font(.system(size: 18)).foregroundStyle(ok ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).fontWeight(.semibold)
                Text(why).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if !ok && !action.isEmpty { Button(action, action: run) }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }
}
