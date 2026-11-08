import AppKit
import SwiftUI

/// Paleta de colores del Diego Operating System.
enum Palette {
    static let bg = Color(red: 0.043, green: 0.051, blue: 0.063)        // #0b0d10
    static let panel = Color(red: 0.110, green: 0.114, blue: 0.180)     // #1c1d2e
    static let line = Color.white.opacity(0.08)
    static let ink = Color(red: 0.933, green: 0.949, blue: 0.969)       // #eef2f7
    static let text = Color(red: 0.788, green: 0.824, blue: 0.871)      // #c9d2de
    static let mute = Color(red: 0.541, green: 0.588, blue: 0.659)      // #8a96a8
    static let faint = Color(red: 0.373, green: 0.420, blue: 0.486)     // #5f6b7c
    static let gold = Color(red: 0.890, green: 0.788, blue: 0.541)      // #e3c98a
    static let green = Color(red: 0.498, green: 0.820, blue: 0.545)     // #7fd18b
}

/// Las curvas de la casa: un muelle vivo para lo que se toca, uno suave para lo que se mueve solo.
enum Motion {
    static let tap = Animation.spring(response: 0.26, dampingFraction: 0.55)
    static let settle = Animation.spring(response: 0.42, dampingFraction: 0.78)
    static let fold = Animation.spring(response: 0.46, dampingFraction: 0.82)
}

@MainActor
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.material = material }
}

/// Cristal oscuro: desenfoque real detrás, velo casi negro encima, filo claro arriba, sombra propia.
@MainActor
struct Glass: ViewModifier {
    var radius: CGFloat
    var veil: Double = 0.8
    var lift: Lift = .bar
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Backdrop()
                    Color.black.opacity(veil)
                    LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.015), Color.clear],
                                   startPoint: .top, endPoint: .bottom)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).inset(by: 1).stroke(Color.white.opacity(0.03), lineWidth: 1))
            .shadow(color: .black.opacity(lift == .bar ? 0.22 : 0.3), radius: lift == .bar ? 12 : 7, x: 0, y: lift == .bar ? 5 : 3) // suave: en fondos claros no se ve la caja
    }
}

/// Cuánto se despega la superficie. El orbe vive en una ventana justa (30 de margen a los lados, 14 abajo):
/// con la sombra grande de la barra, el borde de la ventana la cortaba y se veía un cuadrado gris alrededor.
enum Lift { case bar, orb }

// MARK: - Estilos de la barra

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: alpha)
    }
}

/// Los colores de cada estilo. Clásico es la barra de siempre; Cristal, el cristal ahumado de Alfred;
/// Metal, el Pad físico: aluminio, teclas de verdad y la principal en naranja.
struct Theme {
    let style: BarStyle
    let ink: Color, text: Color, mute: Color, faint: Color
    let accent: Color      // lo que se enciende al pulsar
    let onAccent: Color    // lo que va encima del acento
    let hover: Color       // relleno de una tecla bajo el ratón
    let divider: Color
    let tile: Color, tileLine: Color
    var keycaps: Bool { style == .metal }

    static func of(_ style: BarStyle) -> Theme {
        switch style {
        case .classic:
            return Theme(style: style, ink: Palette.ink, text: Palette.text, mute: Palette.mute, faint: Palette.faint,
                         accent: Palette.gold, onAccent: Palette.bg, hover: .white.opacity(0.09), divider: .white.opacity(0.09),
                         tile: Palette.panel.opacity(0.85), tileLine: Palette.line)
        case .glass:
            return Theme(style: style, ink: .white, text: .white.opacity(0.86), mute: .white.opacity(0.64), faint: .white.opacity(0.42),
                         accent: .white, onAccent: Color(hex: 0x111114), hover: .white.opacity(0.14), divider: .white.opacity(0.2),
                         tile: .white.opacity(0.08), tileLine: .white.opacity(0.14))
        case .metal:
            return Theme(style: style, ink: Color(hex: 0x1d1d1f), text: Color(hex: 0x3a3a3d), mute: Color(hex: 0x5c5c60), faint: Color(hex: 0x8e8e93),
                         accent: Color(hex: 0xff5b1f), onAccent: Color(hex: 0x2a0d02), hover: .clear, divider: .black.opacity(0.13),
                         tile: Color(hex: 0xf2f2ef), tileLine: .black.opacity(0.1))
        }
    }
}

private struct ThemeKey: EnvironmentKey { static let defaultValue = Theme.of(.classic) }
/// Para las capturas sin pantalla: una imagen que hace de fondo desenfocado en lugar del escritorio real.
private struct BackdropKey: EnvironmentKey { static let defaultValue: NSImage? = nil }
extension EnvironmentValues {
    var barTheme: Theme { get { self[ThemeKey.self] } set { self[ThemeKey.self] = newValue } }
    var snapshotBackdrop: NSImage? { get { self[BackdropKey.self] } set { self[BackdropKey.self] = newValue } }
}

/// El desenfoque de detrás: el escritorio de verdad o, en las capturas, una imagen desenfocada.
struct Backdrop: View {
    @Environment(\.snapshotBackdrop) private var image
    var body: some View {
        if let image { Image(nsImage: image).resizable().scaledToFill().blur(radius: 26, opaque: true) } else { VisualEffect() }
    }
}

/// Aluminio cepillado: un degradado y líneas finas verticales.
struct Brushed: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xededea), Color(hex: 0xd6d6d2), Color(hex: 0xc6c6c2)], startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                var x: CGFloat = 0, i = 0
                while x < size.width {
                    let a = [0.10, 0.03, 0.06, 0.0, 0.08][i % 5]
                    ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(.white.opacity(a)))
                    x += 2; i += 1
                }
            }
        }
    }
}

/// La superficie de la barra, el orbe y la tarjeta, según el estilo.
struct Surface: ViewModifier {
    @Environment(\.barTheme) private var th
    var radius: CGFloat
    var veil: Double = 0.8
    var lift: Lift = .bar
    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch th.style {
        case .classic:
            content.modifier(Glass(radius: radius, veil: veil, lift: lift))
        case .glass:
            content
                .background(ZStack {
                    Backdrop()
                    Color.black.opacity(0.24)
                    LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.04), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom)
                })
                .clipShape(shape)
                .overlay(shape.strokeBorder(.white.opacity(0.22), lineWidth: 1))
                .overlay(shape.inset(by: 1).strokeBorder(LinearGradient(colors: [.white.opacity(0.32), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
                .shadow(color: .black.opacity(lift == .bar ? 0.16 : 0.26), radius: lift == .bar ? 12 : 7, x: 0, y: lift == .bar ? 5 : 3)
        case .metal:
            content
                .background(
                    ZStack {
                        shape.fill(Color(hex: 0x8a8a84)).offset(y: 2)
                            .shadow(color: .black.opacity(lift == .bar ? 0.22 : 0.28), radius: lift == .bar ? 12 : 7, x: 0, y: lift == .bar ? 6 : 3)
                        Brushed().clipShape(shape)
                        shape.strokeBorder(.black.opacity(0.16), lineWidth: 1)
                        shape.inset(by: 1).strokeBorder(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.0)], startPoint: .top, endPoint: .center), lineWidth: 1)
                    }
                )
        }
    }
}

/// El fondo de una tecla: un relleno al pasar el ratón o, en Metal, una tecla física que se hunde al pulsar.
struct KeyFace: ViewModifier {
    @Environment(\.barTheme) private var th
    var hover: Bool
    var pressed: Bool
    var main: Bool = false
    var radius: CGFloat = 10
    var fill: Color? = nil
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if th.keycaps {
            let top = main ? Color(hex: 0xff7a44) : Color(hex: hover ? 0xfafaf8 : 0xf4f4f2)
            let bottom = main ? Color(hex: 0xff5b1f) : Color(hex: 0xdcdcd8)
            content
                .background(
                    ZStack {
                        shape.fill(main ? Color(hex: 0xc7410f) : Color(hex: 0xa8a8a3)).offset(y: pressed ? 0 : 2)
                            .shadow(color: .black.opacity(pressed ? 0.12 : 0.22), radius: pressed ? 1 : 3, x: 0, y: pressed ? 1 : 3)
                        shape.fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
                        shape.inset(by: 0.5).strokeBorder(LinearGradient(colors: [.white.opacity(main ? 0.45 : 1), .clear], startPoint: .top, endPoint: .center), lineWidth: 1)
                    }
                )
                .offset(y: pressed ? 2 : 0)
        } else {
            content.background(shape.fill(fill ?? th.hover.opacity(hover ? 1 : 0)))
        }
    }
}

/// Elige el modo. Es la raíz que el panel dibuja.
@MainActor
struct DeskRoot: View {
    @ObservedObject var store: DeskStore
    var body: some View {
        Group {
            switch store.mode {
            case .dock: DockView(store: store)
            case .card: CardView(store: store)
            }
        }
        .environment(\.barTheme, Theme.of(store.style))
        .animation(Motion.settle, value: store.style)
    }
}

// MARK: - Modo dock: la barra, o el orbe cuando está plegada

@MainActor
struct DockView: View {
    @ObservedObject var store: DeskStore
    @Environment(\.barTheme) private var th
    var body: some View {
        VStack(spacing: 6) {
            if store.alerts.count > 3 {
                Text("+\(store.alerts.count - 3)").font(.system(size: 10.5, weight: .semibold)).foregroundColor(th.mute)
                    .padding(.horizontal, 9).padding(.vertical, 3).modifier(Surface(radius: 10))
            }
            ForEach(store.alerts.suffix(3), id: \.id) { a in
                AlertPill(alert: a, dismiss: { store.dismissAlert(a) }, reply: { store.reply($0, to: a) },
                          autopilot: ClaudeHooks.installed ? { store.setAutopilot(5); store.reply(store.keys.first?.text ?? T.s("continue", "continúa"), to: a) } : nil,
                          talk: { store.talkToAlert(a) }, listening: store.alertListening == a.id, level: store.alertLevel)
                    .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.8, anchor: .bottom)))
            }
        ZStack(alignment: .bottom) {
            if store.collapsed {
                Orb(store: store)
                    .transition(.asymmetric(insertion: .scale(scale: 0.4, anchor: .bottom).combined(with: .opacity),
                                            removal: .scale(scale: 0.6, anchor: .bottom).combined(with: .opacity)))
            } else {
                Bar(store: store)
                    .transition(.asymmetric(insertion: .scale(scale: 0.35, anchor: .bottom).combined(with: .opacity),
                                            removal: .scale(scale: 0.5, anchor: .bottom).combined(with: .opacity)))
            }
        }
        .animation(Motion.fold, value: store.collapsed)
        }
        .animation(Motion.settle, value: store.alerts)
        .padding(.horizontal, 30).padding(.top, 36).padding(.bottom, 26) // sitio para que la sombra se apague entera, sin cortes
        .focusEffectDisabled()
    }
}

/// El aviso de un agente: una cápsula de una línea con el resumen («Claude Code · carpeta — qué ha hecho»).
/// Al pasar el ratón se abre un poco: el resumen entero y las respuestas (hablar, Continúa, ×5, escribir).
struct AlertPill: View {
    let alert: AgentAlert
    let dismiss: () -> Void
    var reply: ((String) -> Void)? = nil
    var autopilot: (() -> Void)? = nil
    var talk: (() -> Void)? = nil
    var listening = false
    var level: Float = 0
    @Environment(\.barTheme) private var th
    @State private var hover = false
    @State private var typing = false
    @State private var answer = ""
    @FocusState private var focused: Bool

    private var dotColor: Color { alert.ask ? Color(hex: 0xff5b1f) : th.accent }
    private var open: Bool { hover || typing || listening }
    private var summary: String { alert.summary.isEmpty ? alert.message : alert.summary }

    var body: some View {
        VStack(alignment: .leading, spacing: open ? 9 : 0) {
            HStack(spacing: 9) {
                TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                    let p = 0.5 + 0.5 * sin(ctx.date.timeIntervalSinceReferenceDate * (alert.ask ? 5 : 2.4))
                    Circle().fill(dotColor).frame(width: 7, height: 7)
                        .shadow(color: dotColor.opacity(0.35 + 0.45 * p), radius: 2 + 5 * p)
                }.frame(width: 9, height: 9)
                Text(alert.place.isEmpty ? alert.app : alert.place)
                    .font(.system(size: 11.5, weight: .semibold)).foregroundColor(th.ink).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: 130, alignment: .leading).fixedSize(horizontal: true, vertical: false)
                    .help(alert.ask ? T.s("Waiting for you", "Te espera") : T.s("Done", "Ha terminado"))
                if !open && !summary.isEmpty {
                    Text(summary).font(.system(size: 11.5)).foregroundColor(th.mute).lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 4)
                if open {
                    Button(action: dismiss) {
                        Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold)).foregroundColor(th.faint)
                            .frame(width: 16, height: 16).contentShape(Rectangle())
                    }.buttonStyle(.plain).help(T.s("Dismiss: that conversation stops as usual", "Quitar: esa conversación se para como siempre"))
                }
            }
            if open {
                if !summary.isEmpty {
                    Text(summary).font(.system(size: 12)).foregroundColor(th.text).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true).transition(.opacity)
                }
                if let reply {
                    if typing {
                        HStack(spacing: 6) {
                            TextField(T.s("Reply…", "Responder…"), text: $answer)
                                .textFieldStyle(.plain).font(.system(size: 12)).foregroundColor(th.ink).focused($focused)
                                .onSubmit { reply(answer); answer = ""; typing = false }
                                .padding(.horizontal, 9).padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(th.hover.opacity(0.9)))
                            chip(T.s("Send", "Enviar"), "arrow.up", primary: true) { reply(answer.isEmpty ? T.s("continue", "continúa") : answer); answer = ""; typing = false }
                        }
                    } else {
                        HStack(spacing: 6) {
                            if let talk {
                                Button(action: talk) {
                                    ZStack {
                                        if listening { VoiceBlob(level: level, size: 20) }
                                        else { Image(systemName: "mic.fill").font(.system(size: 11, weight: .semibold)).foregroundColor(th.ink) }
                                    }
                                    .frame(width: 30, height: 26)
                                    .background(Capsule().fill(th.hover.opacity(listening ? 0 : 0.9)))
                                }.buttonStyle(.plain).help(listening ? T.s("Tap to send what you said", "Toca para enviar lo que has dicho") : T.s("Talk: your answer goes to this conversation", "Habla: tu respuesta va a esta conversación"))
                            }
                            chip(T.s("Continue", "Continúa"), "arrow.right", primary: true) { reply(T.s("continue", "continúa")) }
                            if let autopilot { chip("×5", "airplane", primary: false, action: autopilot) }
                            chip("", "keyboard", primary: false) { typing = true; focused = true }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, open ? 11 : 8)
        .frame(width: 330, alignment: .leading)
        .modifier(Surface(radius: open ? 16 : 18))
        .animation(Motion.settle, value: open)
        .onHover { hover = $0 }
    }

    private func chip(_ text: String, _ icon: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
                if !text.isEmpty { Text(text).font(.system(size: 11.5, weight: .semibold)) }
            }
            .foregroundColor(primary ? Color(hex: 0x2a0d02) : th.ink)
            .padding(.horizontal, text.isEmpty ? 9 : 11).frame(height: 26)
            .background(Capsule().fill(primary ? Color(hex: 0xff5b1f) : th.hover.opacity(0.9)))
        }.buttonStyle(.plain)
    }
}

/// El copiloto plegado: un orbe de cristal con un punto dorado que respira. Clic: se despliega.
/// Si dictas con ⌃⌥M estando plegado, el orbe se abre en una cápsula con la onda y lo que va oyendo.
@MainActor
struct Orb: View {
    @ObservedObject var store: DeskStore
    @Environment(\.barTheme) private var th
    @State private var hover = false
    var body: some View {
        Button(action: { store.toggleCollapsed() }) {
            HStack(spacing: 10) {
                ZStack {
                    if store.listening {
                        VoiceBlob(level: store.level, size: 30).transition(.scale(scale: 0.5).combined(with: .opacity))
                    } else {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate
                        let breath = 0.5 + 0.5 * sin(t * 1.4)
                        Circle()
                            .fill(th.accent)
                            .frame(width: store.listening ? 9 : 7 + 1.5 * breath, height: store.listening ? 9 : 7 + 1.5 * breath)
                            .shadow(color: th.accent.opacity(0.35 + 0.35 * breath), radius: store.listening ? 10 : 4 + 4 * breath)
                    }
                    }
                    if hover && !store.listening {
                        Image(systemName: "chevron.up").font(.system(size: 9, weight: .bold)).foregroundColor(th.ink)
                            .offset(y: -13).transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .frame(width: store.listening ? 30 : 22, height: store.listening ? 30 : 22)
                if store.voiceExpanded {
                    Text(!store.flash.isEmpty && !store.listening ? store.flash : store.partial.isEmpty ? T.s("Listening…", "Escuchando…") : store.partial)
                        .truncationMode(.head) // un mensaje largo: solo las últimas palabras
                        .font(.system(size: 11.5, weight: .medium)).foregroundColor(th.style == .metal ? th.ink : th.accent).lineLimit(1)
                        .frame(maxWidth: 220, alignment: .leading)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(.horizontal, store.voiceExpanded ? 14 : 9).padding(.vertical, 9)
            .modifier(Surface(radius: 22, veil: 0.8, lift: .orb))
            .scaleEffect(hover ? 1.06 : 1)
            .animation(Motion.tap, value: hover)
            .animation(Motion.settle, value: store.listening)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(T.s("Unfold Agent Bar (⌃⌥D)", "Desplegar Agent Bar (⌃⌥D)"))
    }
}

/// Escuchando: luz líquida que gira dentro de una esfera, como Siri, y crece con tu voz.
/// En los naranjas de la marca (Agent Bar), no en el arcoíris de Apple.
struct VoiceBlob: View {
    let level: Float
    var size: CGFloat = 30
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let l = CGFloat(min(level * 7, 1))
            ZStack {
                Circle().fill(Color(hex: 0x1c0c06))
                blob(Color(hex: 0xff5b1f), t, 1.4, 0, l)
                blob(Color(hex: 0xff2f6d), t, 1.9, 2.1, l)
                blob(Color(hex: 0xffb02e), t, 1.15, 4.2, l)
                blob(.white, t, 2.6, 1.0, l).opacity(0.25)
            }
            .frame(width: size, height: size)
            .compositingGroup()
            .blur(radius: size * 0.1)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.32), lineWidth: 0.8))
            .overlay(Circle().inset(by: size * 0.08).strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
            .scaleEffect(1 + 0.2 * l)
            .shadow(color: Color(hex: 0xff5b1f).opacity(0.5 + 0.35 * l), radius: size * (0.25 + 0.35 * l))
            .animation(.easeOut(duration: 0.12), value: l)
        }
        .frame(width: size, height: size)
    }
    private func blob(_ c: Color, _ t: Double, _ speed: Double, _ phase: Double, _ l: CGFloat) -> some View {
        let r = size * (0.16 + 0.14 * l)
        return Ellipse().fill(c.opacity(0.62))
            .frame(width: size * 0.7, height: size * 0.54)
            .rotationEffect(.radians(t * speed * 0.7 + phase))
            .offset(x: CGFloat(cos(t * speed + phase)) * r, y: CGFloat(sin(t * speed * 1.27 + phase)) * r)
            .blendMode(.plusLighter)
    }
}

/// Anillos que respiran con tu voz, alrededor del micro o del orbe.
@MainActor
struct Rings: View {
    let level: Float
    @Environment(\.barTheme) private var th
    var body: some View {
        let l = CGFloat(min(level * 6, 1))
        ZStack {
            Circle().stroke(th.accent.opacity(0.18 + 0.25 * l), lineWidth: 1).frame(width: 26 + 26 * l, height: 26 + 26 * l)
            Circle().stroke(th.accent.opacity(0.10 + 0.15 * l), lineWidth: 1).frame(width: 36 + 40 * l, height: 36 + 40 * l)
            Circle().fill(th.accent.opacity(0.10 + 0.18 * l)).frame(width: 18 + 18 * l, height: 18 + 18 * l)
        }
        .animation(.easeOut(duration: 0.09), value: l)
    }
}

/// La barra desplegada.
@MainActor
struct Bar: View {
    @ObservedObject var store: DeskStore
    @Environment(\.barTheme) private var th
    @State private var sheet: DeskKey? = nil
    @State private var adding = false
    @State private var accessibility = Sender.accessibilityGranted(prompt: false)

    var body: some View {
        HStack(spacing: th.keycaps ? 5 : 2) {
            DockGlyph(symbol: "xmark", size: 10, weight: .bold, help: T.s("Fold the bar into the orb (⌃⌥D)", "Plegar la barra al orbe (⌃⌥D)")) { store.toggleCollapsed() }
                .padding(.leading, 2)
            Divider_()
            DictateItem(store: store)
            // borradores e historial de voz: en el engranaje (Voz, borradores e historial…), no en la barra
            DockItem(id: nil, icon: "text.magnifyingglass", label: T.s("Explain", "Explica"), hotkey: nil, main: false, editing: false, tint: nil, store: store,
                     help: T.s("Sends what you've selected, in any app, to your AI chat to explain it (⌃⌥E)", "Manda lo que tengas seleccionado, en cualquier app, a tu chat de IA para que lo explique (⌃⌥E)"),
                     press: { store.explainSelection() }, edit: {}, remove: {})
            DockItem(id: nil, icon: "camera.viewfinder", label: T.s("Snap", "Captura"), hotkey: nil, main: false, editing: false, tint: nil, store: store,
                     help: T.s("Pick an area of the screen and ask your AI chat what's wrong (⌃⌥S)", "Elige una zona de la pantalla y pregunta a tu chat de IA qué falla (⌃⌥S)"),
                     press: { store.snapScreen() }, edit: {}, remove: {})
            DockItem(id: nil, icon: store.autopilotLeft > 0 ? "airplane.circle.fill" : "airplane.circle",
                     label: store.autopilotLeft > 0 ? T.s("Autopilot · \(store.autopilotLeft)", "Autopilot · \(store.autopilotLeft)") : "Autopilot",
                     hotkey: nil, main: false, editing: false, tint: store.autopilotLeft > 0 ? th.accent : nil, store: store,
                     help: T.s("Autopilot for Claude Code: keeps going on its own up to 5 times and stops at a real question", "Autopilot para Claude Code: sigue solo hasta 5 veces y para ante una pregunta de verdad"),
                     press: { store.toggleAutopilot() }, edit: {}, remove: {})
            Divider_()
            if !accessibility {
                DockItem(id: nil, icon: "hand.raised.fill", label: T.s("Permission", "Permiso"), hotkey: nil, main: false, editing: false, tint: th.accent, store: store,
                         help: T.s("Allow Accessibility so Agent Bar can type into the chat", "Permite Accesibilidad para que Agent Bar pueda escribir en el chat"),
                         press: { _ = Sender.accessibilityGranted(prompt: true) }, edit: {}, remove: {})
                Divider_()
            }
            ForEach(Array(store.groups.enumerated()), id: \.offset) { i, g in
                if i > 0 { Divider_() }
                ForEach(g.keys) { key in
                    DockItem(id: key.id, icon: key.icon, label: key.label, hotkey: key.hotkey, main: key.hotkey == 1, editing: store.editing, tint: nil, store: store,
                             help: "⌃⌥\(key.hotkey.map(String.init) ?? "") · \(key.text)",
                             press: { store.press(key) }, edit: { sheet = key }, remove: { withAnimation(Motion.settle) { store.remove(key) } })
                }
            }
            if store.editing {
                if !store.groups.contains(where: { $0.name == "mías" }) { Divider_() }
                DockItem(id: nil, icon: "plus", label: T.s("New", "Nueva"), hotkey: nil, main: false, editing: false, tint: th.accent, store: store, help: T.s("Add a key", "Añadir una tecla"),
                         press: { adding = true }, edit: {}, remove: {})
            }
            Divider_()
            DockGlyph(symbol: store.editing ? "checkmark" : "slider.horizontal.3", size: 12, weight: .semibold,
                      help: store.editing ? T.s("Done editing", "Terminar edición") : T.s("Edit keys", "Editar teclas"), tint: store.editing ? th.accent : nil) {
                withAnimation(Motion.settle) { store.editing.toggle() }
            }
            DockGlyph(symbol: "arrow.triangle.branch", size: 12, weight: .regular, help: T.s("Message flows", "Flujos de mensajes")) { store.showFlows?() }
            DockGlyph(symbol: "gearshape", size: 12, weight: .regular, help: T.s("Agent Bar settings", "Ajustes de Agent Bar")) { store.showMenu?() }
                .padding(.trailing, 2)
        }
        .padding(.horizontal, th.keycaps ? 8 : 6).padding(.top, th.keycaps ? 7 : 5).padding(.bottom, th.keycaps ? 9 : 5)
        .fixedSize()
        .modifier(Surface(radius: th.keycaps ? 14 : 16))
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { _ in
            accessibility = Sender.accessibilityGranted(prompt: false)
        }
        .sheet(item: $sheet) { key in KeyEditor(key: key, isNew: false) { store.update($0) } }
        .sheet(isPresented: $adding) {
            KeyEditor(key: DeskKey(label: "", text: "", icon: "sparkles"), isNew: true) { k in withAnimation(Motion.settle) { store.add(k) } }
        }
    }
}

@MainActor
struct Divider_: View {
    @Environment(\.barTheme) private var th
    var body: some View {
        Rectangle().fill(th.divider).frame(width: 1, height: 26).padding(.horizontal, 4)
    }
}

/// Un control redondo pequeño (la aspa, la edición, el engranaje).
@MainActor
struct DockGlyph: View {
    let symbol: String
    let size: CGFloat
    let weight: Font.Weight
    let help: String
    var tint: Color? = nil
    let action: () -> Void
    @Environment(\.barTheme) private var th
    @State private var hover = false
    @State private var pressed = false
    var body: some View {
        Button(action: { DeskStore.haptic(); action() }) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: weight))
                .foregroundColor(tint ?? (hover ? th.ink : th.mute))
                .frame(width: 26, height: 26)
                .modifier(KeyFace(hover: hover, pressed: pressed, radius: 13))
                .scaleEffect(pressed && !th.keycaps ? 0.85 : 1)
                .animation(Motion.tap, value: pressed)
                .animation(.easeOut(duration: 0.14), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .pressEvents(onPress: { pressed = true }, onRelease: { pressed = false })
        .help(help)
    }
}

/// Una tecla de la barra: icono arriba, etiqueta debajo, el número del atajo al pasar el ratón.
/// Al pulsar: el icono rebota, la etiqueta se enciende en dorado un instante y un anillo se expande.
@MainActor
struct DockItem: View {
    let id: UUID?
    let icon: String
    let label: String
    let hotkey: Int?
    let main: Bool
    let editing: Bool
    let tint: Color?
    @ObservedObject var store: DeskStore
    let help: String
    let press: () -> Void
    let edit: () -> Void
    let remove: () -> Void
    @Environment(\.barTheme) private var th
    @State private var hover = false
    @State private var pressed = false
    @State private var bursts = 0
    @State private var lit = false
    /// En Metal la tecla principal es naranja: lo de encima va oscuro y se enciende en blanco.
    private var face: Bool { main && th.keycaps }
    private var litColor: Color { face ? .white : th.accent }

    var body: some View {
        Button(action: { editing ? edit() : fire() }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(lit ? litColor : face ? th.onAccent : (tint ?? (hover || main ? th.ink : th.text)))
                    .symbolEffect(.bounce.up.byLayer, value: bursts)
                    .frame(height: 17)
                Text(label)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(lit ? litColor : face ? th.onAccent : (tint ?? (hover ? th.ink : th.mute)))
                    .lineLimit(1)
            }
            .frame(minWidth: 54)
            .padding(.horizontal, 6).padding(.vertical, 6)
            .modifier(KeyFace(hover: hover, pressed: pressed, main: main))
            .overlay(Burst(trigger: bursts))
            .overlay(alignment: .topTrailing) {
                if editing {
                    Button(action: remove) {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundColor(th.onAccent)
                            .frame(width: 13, height: 13).background(Circle().fill(th.accent))
                    }.buttonStyle(.plain).offset(x: 3, y: -3)
                } else if let h = hotkey, hover {
                    Text("\(h)").font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(face ? th.onAccent.opacity(0.6) : th.faint).padding(.trailing, 4).padding(.top, 2)
                }
            }
            .scaleEffect(pressed && !th.keycaps ? 0.9 : 1)
            .animation(Motion.tap, value: pressed)
            .animation(.easeOut(duration: 0.14), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .pressEvents(onPress: { pressed = true }, onRelease: { pressed = false })
        .onChange(of: store.pulse) { _, _ in
            // disparo por atajo de teclado: la misma animación que el clic
            if let id = id, store.lastPressedId == id, !pressed { glow() }
        }
        .help(help)
    }

    private func fire() {
        press()
        if id == nil { glow() } // las teclas sin id (Permiso, Nueva) no pasan por store.press
    }

    private func glow() {
        bursts += 1
        withAnimation(.easeOut(duration: 0.12)) { lit = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { withAnimation(.easeInOut(duration: 0.4)) { lit = false } }
    }
}

/// Un anillo dorado que nace en la tecla y se desvanece al crecer.
@MainActor
struct Burst: View {
    let trigger: Int
    @Environment(\.barTheme) private var th
    @State private var shown = 0
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(th.accent, lineWidth: 1.2)
            .scaleEffect(scale)
            .opacity(opacity)
            .allowsHitTesting(false)
            .onChange(of: trigger) { _, _ in
                scale = 0.8; opacity = 0.9
                withAnimation(.easeOut(duration: 0.55)) { scale = 1.45; opacity = 0 }
            }
    }
}

/// La tecla de dictar: micro en reposo; escuchando, onda dorada y anillos que siguen tu voz, el texto parcial debajo.
@MainActor
struct DictateItem: View {
    @ObservedObject var store: DeskStore
    @Environment(\.barTheme) private var th
    @State private var hover = false
    @State private var pressed = false
    var body: some View {
        Button(action: { DeskStore.haptic(.levelChange); store.toggleDictation() }) {
            VStack(spacing: 4) {
                ZStack {
                    if store.listening {
                        VoiceBlob(level: store.level, size: 22).transition(.scale(scale: 0.5).combined(with: .opacity))
                    } else {
                        Image(systemName: store.voiceWorking ? "hourglass" : "mic")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(hover ? th.ink : th.text)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(width: 40, height: 17)
                Text(store.listening ? (store.partial.isEmpty ? T.s("Listening…", "Escuchando…") : store.partial) : !store.flash.isEmpty ? store.flash : (store.dictationNote.isEmpty ? T.s("Talk", "Hablar") : store.dictationNote))
                    .truncationMode(.head)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(store.listening ? th.accent : (hover ? th.ink : th.mute))
                    .lineLimit(1)
                    .frame(maxWidth: store.voiceExpanded ? 170 : 70)
            }
            .frame(minWidth: 54)
            .padding(.horizontal, 6).padding(.vertical, 6)
            .modifier(KeyFace(hover: hover, pressed: pressed, fill: store.listening ? th.accent.opacity(0.1) : nil))
            .overlay(alignment: .topTrailing) {
                if hover { Text("M").font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundColor(th.faint).padding(.trailing, 4).padding(.top, 2) }
            }
            .scaleEffect(pressed && !th.keycaps ? 0.9 : 1)
            .animation(Motion.tap, value: pressed)
            .animation(Motion.settle, value: store.listening)
            .animation(.easeOut(duration: 0.14), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .pressEvents(onPress: { pressed = true }, onRelease: { pressed = false })
        .help(T.s("Fn: hold to speak. ⌃⌥M toggles recording. Choose paste or send in Voice settings.", "Fn: mantén para hablar. ⌃⌥M alterna la grabación. Elige pegar o enviar en los ajustes de Voz."))
    }
}

// MARK: - Modo tarjeta: la paleta flotante

@MainActor
struct CardView: View {
    @ObservedObject var store: DeskStore
    @Environment(\.barTheme) private var th
    @State private var target = Sender.targetName()
    @State private var sheet: DeskKey? = nil
    @State private var adding = false
    @State private var accessibility = Sender.accessibilityGranted(prompt: false)

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !accessibility { permissionNote }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(store.keys) { key in
                    Tile(key: key, editing: store.editing,
                         press: { store.press(key) },
                         edit: { sheet = key },
                         remove: { store.remove(key) })
                }
                if store.editing { addTile }
            }
            footer
        }
        .padding(16)
        .frame(width: 320)
        .modifier(Surface(radius: 18, veil: 0.6))
        .padding(30)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { _ in
            target = Sender.targetName()
            accessibility = Sender.accessibilityGranted(prompt: false)
        }
        .sheet(item: $sheet) { key in KeyEditor(key: key, isNew: false) { store.update($0) } }
        .sheet(isPresented: $adding) {
            KeyEditor(key: DeskKey(label: "", text: "", icon: "sparkles"), isNew: true) { store.add($0) }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(th.accent).frame(width: 7, height: 7)
            Text("AGENT DECK").font(.system(size: 11, weight: .medium, design: .monospaced)).tracking(2.2).foregroundColor(th.mute)
            Spacer()
            Text(target).font(.system(size: 11, weight: .regular)).foregroundColor(th.faint).lineLimit(1)
            Button(action: { store.editing.toggle() }) {
                Image(systemName: store.editing ? "checkmark" : "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(store.editing ? th.accent : th.mute)
            }
            .buttonStyle(.plain)
            .help(store.editing ? T.s("Done editing", "Terminar edición") : T.s("Edit keys", "Editar teclas"))
        }
    }

    private var permissionNote: some View {
        Button(action: { _ = Sender.accessibilityGranted(prompt: true) }) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised").foregroundColor(th.accent)
                Text(T.s("Allow Accessibility so the deck can type into the chat.", "Permite Accesibilidad para que el Desk pueda escribir en el chat."))
                    .font(.system(size: 11)).foregroundColor(th.text).multilineTextAlignment(.leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(th.accent.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    private var addTile: some View {
        Button(action: { adding = true }) {
            HStack { Spacer(); Image(systemName: "plus").foregroundColor(th.accent); Spacer() }
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(th.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            Text(store.lastSent.isEmpty ? T.s("press a key, or ⌃⌥ and its number", "pulsa una tecla, o ⌃⌥ y su número") : T.s("sent", "enviado") + " \(store.lastSent)")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(store.lastSent.isEmpty ? th.faint : (th.style == .metal ? th.accent : Palette.green))
                .lineLimit(1)
            Spacer()
            Button { store.showFlows?() } label: { Label(T.s("Flows", "Flujos"), systemImage: "arrow.triangle.branch") }.buttonStyle(.plain).font(.system(size: 10)).foregroundColor(Palette.gold)
        }
    }
}

@MainActor
struct Tile: View {
    let key: DeskKey
    let editing: Bool
    let press: () -> Void
    let edit: () -> Void
    let remove: () -> Void
    @Environment(\.barTheme) private var th
    @State private var hover = false
    @State private var pressed = false

    var body: some View {
        Button(action: { editing ? edit() : press() }) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: key.icon).font(.system(size: 16)).foregroundColor(hover ? th.ink : th.text).frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(key.label).font(.system(size: 13, weight: .medium)).foregroundColor(th.ink).lineLimit(1)
                    Text(key.hotkey.map { "⌃⌥\($0)" } ?? " ")
                        .font(.system(size: 9.5, weight: .regular, design: .monospaced)).foregroundColor(th.faint)
                }
                Spacer(minLength: 0)
                if editing {
                    Button(action: remove) {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundColor(th.mute)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(th.tile.opacity(hover ? 1 : 0.92)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(hover || key.hotkey == 1 ? th.accent.opacity(hover ? 0.9 : 0.55) : th.tileLine, lineWidth: 1))
            .scaleEffect(pressed ? 0.96 : 1)
            .animation(Motion.tap, value: pressed)
            .animation(.easeOut(duration: 0.15), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .pressEvents(onPress: { pressed = true }, onRelease: { pressed = false })
        .help(key.text)
    }
}

// MARK: - Editor de una tecla

@MainActor
struct KeyEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var key: DeskKey
    let isNew: Bool
    let save: (DeskKey) -> Void
    private let cols = [GridItem(.adaptive(minimum: 34), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? T.s("New key", "Nueva tecla") : T.s("Edit key", "Editar tecla")).font(.system(size: 13, weight: .semibold)).foregroundColor(Palette.ink)
            TextField(T.s("Short name (what you see)", "Nombre corto (lo que se ve)"), text: $key.label).textFieldStyle(.roundedBorder)
            TextField(T.s("What gets typed into the chat", "Lo que se escribe en el chat"), text: $key.text, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
            Text(T.s("Icon", "Icono")).font(.system(size: 11, weight: .medium)).foregroundColor(Palette.mute)
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(deskIcons, id: \.self) { name in
                    Button(action: { key.icon = name }) {
                        Image(systemName: name).font(.system(size: 15))
                            .foregroundColor(key.icon == name ? Palette.bg : Palette.text)
                            .frame(width: 34, height: 30)
                            .background(RoundedRectangle(cornerRadius: 8).fill(key.icon == name ? Palette.gold : Color.white.opacity(0.06)))
                    }.buttonStyle(.plain)
                }
            }
            Toggle(T.s("Press Enter after typing", "Pulsar Intro al enviar"), isOn: $key.sendEnter).toggleStyle(.switch).font(.system(size: 12))
            HStack {
                Spacer()
                Button(T.s("Cancel", "Cancelar")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? T.s("Add", "Añadir") : T.s("Save", "Guardar")) {
                    guard !key.text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    save(key); dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}

extension View {
    func pressEvents(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in onPress() }
            .onEnded { _ in onRelease() })
    }
}
