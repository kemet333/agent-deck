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
struct Glass: ViewModifier {
    var radius: CGFloat
    var veil: Double = 0.8
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    VisualEffect()
                    Color.black.opacity(veil)
                    LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.015), Color.clear],
                                   startPoint: .top, endPoint: .bottom)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).inset(by: 1).stroke(Color.white.opacity(0.03), lineWidth: 1))
            .shadow(color: .black.opacity(0.42), radius: 22, x: 0, y: 10)
    }
}

/// Elige el modo. Es la raíz que el panel dibuja.
struct DeskRoot: View {
    @ObservedObject var store: DeskStore
    var body: some View {
        switch store.mode {
        case .dock: DockView(store: store)
        case .card: CardView(store: store)
        }
    }
}

// MARK: - Modo dock: la barra, o el orbe cuando está plegada

struct DockView: View {
    @ObservedObject var store: DeskStore
    var body: some View {
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
        .padding(.horizontal, 30).padding(.top, 36).padding(.bottom, 14) // sitio para la sombra y los rebotes
        .focusEffectDisabled()
    }
}

/// El copiloto plegado: un orbe de cristal con un punto dorado que respira. Clic: se despliega.
/// Si dictas con ⌃⌥M estando plegado, el orbe se abre en una cápsula con la onda y lo que va oyendo.
struct Orb: View {
    @ObservedObject var store: DeskStore
    @State private var hover = false
    var body: some View {
        Button(action: { store.toggleCollapsed() }) {
            HStack(spacing: 10) {
                ZStack {
                    if store.listening { Rings(level: store.level) }
                    TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate
                        let breath = 0.5 + 0.5 * sin(t * 1.4)
                        Circle()
                            .fill(Palette.gold)
                            .frame(width: store.listening ? 9 : 7 + 1.5 * breath, height: store.listening ? 9 : 7 + 1.5 * breath)
                            .shadow(color: Palette.gold.opacity(0.35 + 0.35 * breath), radius: store.listening ? 10 : 4 + 4 * breath)
                    }
                    if hover && !store.listening {
                        Image(systemName: "chevron.up").font(.system(size: 9, weight: .bold)).foregroundColor(Palette.ink)
                            .offset(y: -13).transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .frame(width: 22, height: 22)
                if store.listening {
                    Text(store.partial.isEmpty ? T.s("Listening…", "Escuchando…") : store.partial)
                        .font(.system(size: 11.5, weight: .medium)).foregroundColor(Palette.gold).lineLimit(1)
                        .frame(maxWidth: 260, alignment: .leading)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(.horizontal, store.listening ? 14 : 9).padding(.vertical, 9)
            .modifier(Glass(radius: 22, veil: 0.8))
            .scaleEffect(hover ? 1.06 : 1)
            .animation(Motion.tap, value: hover)
            .animation(Motion.settle, value: store.listening)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(T.s("Unfold Agent Deck (⌃⌥D)", "Desplegar Agent Deck (⌃⌥D)"))
    }
}

/// Anillos que respiran con tu voz, alrededor del micro o del orbe.
struct Rings: View {
    let level: Float
    var body: some View {
        let l = CGFloat(min(level * 6, 1))
        ZStack {
            Circle().stroke(Palette.gold.opacity(0.18 + 0.25 * l), lineWidth: 1).frame(width: 26 + 26 * l, height: 26 + 26 * l)
            Circle().stroke(Palette.gold.opacity(0.10 + 0.15 * l), lineWidth: 1).frame(width: 36 + 40 * l, height: 36 + 40 * l)
            Circle().fill(Palette.gold.opacity(0.10 + 0.18 * l)).frame(width: 18 + 18 * l, height: 18 + 18 * l)
        }
        .animation(.easeOut(duration: 0.09), value: l)
    }
}

/// La barra desplegada.
struct Bar: View {
    @ObservedObject var store: DeskStore
    @State private var sheet: DeskKey? = nil
    @State private var adding = false
    @State private var accessibility = Sender.accessibilityGranted(prompt: false)

    var body: some View {
        HStack(spacing: 2) {
            DockGlyph(symbol: "xmark", size: 10, weight: .bold, help: T.s("Fold the bar into the orb (⌃⌥D)", "Plegar la barra al orbe (⌃⌥D)")) { store.toggleCollapsed() }
                .padding(.leading, 2)
            Divider_()
            DictateItem(store: store)
            DockItem(id: nil, icon: "tray.and.arrow.down", label: "Inbox", hotkey: nil, main: false, editing: false, tint: nil, store: store,
                     help: T.s("Sends the last transcribed voice note from your inbox to the chat", "Manda al chat la última nota de voz del inbox, ya transcrita"),
                     press: { store.sendInbox() }, edit: {}, remove: {})
            Divider_()
            if !accessibility {
                DockItem(id: nil, icon: "hand.raised.fill", label: T.s("Permission", "Permiso"), hotkey: nil, main: false, editing: false, tint: Palette.gold, store: store,
                         help: T.s("Allow Accessibility so the deck can type into the chat", "Permite Accesibilidad para que el Desk pueda escribir en el chat"),
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
                DockItem(id: nil, icon: "plus", label: T.s("New", "Nueva"), hotkey: nil, main: false, editing: false, tint: Palette.gold, store: store, help: T.s("Add a key", "Añadir una tecla"),
                         press: { adding = true }, edit: {}, remove: {})
            }
            Divider_()
            DockGlyph(symbol: store.editing ? "checkmark" : "slider.horizontal.3", size: 12, weight: .semibold,
                      help: store.editing ? T.s("Done editing", "Terminar edición") : T.s("Edit keys", "Editar teclas"), tint: store.editing ? Palette.gold : nil) {
                withAnimation(Motion.settle) { store.editing.toggle() }
            }
            DockGlyph(symbol: "gearshape", size: 12, weight: .regular, help: T.s("Agent Deck settings", "Ajustes de Agent Deck")) { store.showMenu?() }
                .padding(.trailing, 2)
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .fixedSize()
        .modifier(Glass(radius: 16))
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { _ in
            accessibility = Sender.accessibilityGranted(prompt: false)
        }
        .sheet(item: $sheet) { key in KeyEditor(key: key, isNew: false) { store.update($0) } }
        .sheet(isPresented: $adding) {
            KeyEditor(key: DeskKey(label: "", text: "", icon: "sparkles"), isNew: true) { k in withAnimation(Motion.settle) { store.add(k) } }
        }
    }
}

struct Divider_: View {
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.09)).frame(width: 1, height: 26).padding(.horizontal, 4)
    }
}

/// Un control redondo pequeño (la aspa, la edición, el engranaje).
struct DockGlyph: View {
    let symbol: String
    let size: CGFloat
    let weight: Font.Weight
    let help: String
    var tint: Color? = nil
    let action: () -> Void
    @State private var hover = false
    @State private var pressed = false
    var body: some View {
        Button(action: { DeskStore.haptic(); action() }) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: weight))
                .foregroundColor(tint ?? (hover ? Palette.ink : Palette.mute))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(hover ? 0.10 : 0)))
                .scaleEffect(pressed ? 0.85 : 1)
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
    @State private var hover = false
    @State private var pressed = false
    @State private var bursts = 0
    @State private var lit = false

    var body: some View {
        Button(action: { editing ? edit() : fire() }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(lit ? Palette.gold : (tint ?? (hover || main ? Palette.ink : Palette.text)))
                    .symbolEffect(.bounce.up.byLayer, value: bursts)
                    .frame(height: 17)
                Text(label)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(lit ? Palette.gold : (tint ?? (hover ? Palette.ink : Palette.mute)))
                    .lineLimit(1)
            }
            .frame(minWidth: 54)
            .padding(.horizontal, 6).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(hover ? 0.09 : 0)))
            .overlay(Burst(trigger: bursts))
            .overlay(alignment: .topTrailing) {
                if editing {
                    Button(action: remove) {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundColor(Palette.bg)
                            .frame(width: 13, height: 13).background(Circle().fill(Palette.gold))
                    }.buttonStyle(.plain).offset(x: 3, y: -3)
                } else if let h = hotkey, hover {
                    Text("\(h)").font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(Palette.faint).padding(.trailing, 4).padding(.top, 2)
                }
            }
            .scaleEffect(pressed ? 0.9 : 1)
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
struct Burst: View {
    let trigger: Int
    @State private var shown = 0
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Palette.gold, lineWidth: 1.2)
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
struct DictateItem: View {
    @ObservedObject var store: DeskStore
    @State private var hover = false
    @State private var pressed = false
    var body: some View {
        Button(action: { DeskStore.haptic(.levelChange); store.toggleDictation() }) {
            VStack(spacing: 4) {
                ZStack {
                    if store.listening { Rings(level: store.level) }
                    Image(systemName: store.listening ? "waveform" : "mic")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(store.listening ? Palette.gold : (hover ? Palette.ink : Palette.text))
                        .symbolEffect(.variableColor.iterative.dimInactiveLayers, isActive: store.listening)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 40, height: 17)
                Text(store.listening ? (store.partial.isEmpty ? T.s("Listening…", "Escuchando…") : store.partial) : (store.dictationNote.isEmpty ? T.s("Dictate", "Dictar") : store.dictationNote))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(store.listening ? Palette.gold : (hover ? Palette.ink : Palette.mute))
                    .lineLimit(1)
                    .frame(maxWidth: store.listening ? 200 : 70)
            }
            .frame(minWidth: 54)
            .padding(.horizontal, 6).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(store.listening ? Palette.gold.opacity(0.08) : Color.white.opacity(hover ? 0.09 : 0)))
            .overlay(alignment: .topTrailing) {
                if hover { Text("M").font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundColor(Palette.faint).padding(.trailing, 4).padding(.top, 2) }
            }
            .scaleEffect(pressed ? 0.9 : 1)
            .animation(Motion.tap, value: pressed)
            .animation(Motion.settle, value: store.listening)
            .animation(.easeOut(duration: 0.14), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .pressEvents(onPress: { pressed = true }, onRelease: { pressed = false })
        .help(T.s("Dictate to the chat (⌃⌥M): one press listens, the next sends", "Dictar al chat (⌃⌥M): una pulsación escucha, otra envía"))
    }
}

// MARK: - Modo tarjeta: la paleta flotante

struct CardView: View {
    @ObservedObject var store: DeskStore
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
        .modifier(Glass(radius: 18, veil: 0.6))
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
            Circle().fill(Palette.gold).frame(width: 7, height: 7)
            Text("AGENT DECK").font(.system(size: 11, weight: .medium, design: .monospaced)).tracking(2.2).foregroundColor(Palette.mute)
            Spacer()
            Text(target).font(.system(size: 11, weight: .regular)).foregroundColor(Palette.faint).lineLimit(1)
            Button(action: { store.editing.toggle() }) {
                Image(systemName: store.editing ? "checkmark" : "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(store.editing ? Palette.gold : Palette.mute)
            }
            .buttonStyle(.plain)
            .help(store.editing ? T.s("Done editing", "Terminar edición") : T.s("Edit keys", "Editar teclas"))
        }
    }

    private var permissionNote: some View {
        Button(action: { _ = Sender.accessibilityGranted(prompt: true) }) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised").foregroundColor(Palette.gold)
                Text(T.s("Allow Accessibility so the deck can type into the chat.", "Permite Accesibilidad para que el Desk pueda escribir en el chat."))
                    .font(.system(size: 11)).foregroundColor(Palette.text).multilineTextAlignment(.leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.gold.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    private var addTile: some View {
        Button(action: { adding = true }) {
            HStack { Spacer(); Image(systemName: "plus").foregroundColor(Palette.gold); Spacer() }
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.gold.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            Text(store.lastSent.isEmpty ? T.s("press a key, or ⌃⌥ and its number", "pulsa una tecla, o ⌃⌥ y su número") : T.s("sent", "enviado") + " \(store.lastSent)")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(store.lastSent.isEmpty ? Palette.faint : Palette.green)
                .lineLimit(1)
            Spacer()
        }
    }
}

struct Tile: View {
    let key: DeskKey
    let editing: Bool
    let press: () -> Void
    let edit: () -> Void
    let remove: () -> Void
    @State private var hover = false
    @State private var pressed = false

    var body: some View {
        Button(action: { editing ? edit() : press() }) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: key.icon).font(.system(size: 16)).foregroundColor(hover ? Palette.ink : Palette.text).frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(key.label).font(.system(size: 13, weight: .medium)).foregroundColor(Palette.ink).lineLimit(1)
                    Text(key.hotkey.map { "⌃⌥\($0)" } ?? " ")
                        .font(.system(size: 9.5, weight: .regular, design: .monospaced)).foregroundColor(Palette.faint)
                }
                Spacer(minLength: 0)
                if editing {
                    Button(action: remove) {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundColor(Palette.mute)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.panel.opacity(hover ? 1 : 0.85)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(hover || key.hotkey == 1 ? Palette.gold.opacity(hover ? 0.9 : 0.55) : Palette.line, lineWidth: 1))
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
