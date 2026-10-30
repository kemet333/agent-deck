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

/// Cristal oscuro: desenfoque real detrás, velo casi negro encima, filo claro arriba.
struct Glass: ViewModifier {
    var radius: CGFloat
    var veil: Double = 0.62
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

// MARK: - Modo dock: la barra en el borde inferior, al estilo de las barras de herramientas de macOS

struct DockView: View {
    @ObservedObject var store: DeskStore
    @State private var sheet: DeskKey? = nil
    @State private var adding = false
    @State private var accessibility = Sender.accessibilityGranted(prompt: false)

    var body: some View {
        HStack(spacing: 2) {
            // cerrar (esconder la barra; ⌃⌥D la devuelve)
            DockGlyph(symbol: "xmark", size: 10, weight: .bold, filled: false, help: "Ocultar la barra (⌃⌥D la devuelve)") { store.hide?() }
                .padding(.leading, 2)
            Divider_()
            DictateItem(store: store)
            Divider_()
            if !accessibility {
                DockItem(icon: "hand.raised.fill", label: "Permiso", hotkey: nil, main: false, editing: false, tint: Palette.gold,
                         help: "Permite Accesibilidad para que el Desk pueda escribir en el chat",
                         press: { _ = Sender.accessibilityGranted(prompt: true) }, edit: {}, remove: {})
                Divider_()
            }
            ForEach(Array(store.groups.enumerated()), id: \.offset) { i, g in
                if i > 0 { Divider_() }
                ForEach(g.keys) { key in
                    DockItem(icon: key.icon, label: key.label, hotkey: key.hotkey, main: key.hotkey == 1, editing: store.editing, tint: nil,
                             help: "⌃⌥\(key.hotkey.map(String.init) ?? "") · \(key.text)",
                             press: { store.press(key) }, edit: { sheet = key }, remove: { store.remove(key) })
                }
            }
            if store.editing {
                if !store.groups.contains(where: { $0.name == "mías" }) { Divider_() }
                DockItem(icon: "plus", label: "Nueva", hotkey: nil, main: false, editing: false, tint: Palette.gold, help: "Añadir una tecla",
                         press: { adding = true }, edit: {}, remove: {})
            }
            Divider_()
            DockGlyph(symbol: store.editing ? "checkmark" : "slider.horizontal.3", size: 12, weight: .semibold, filled: false,
                      help: store.editing ? "Terminar edición" : "Editar teclas", tint: store.editing ? Palette.gold : nil) { store.editing.toggle() }
            DockGlyph(symbol: "gearshape", size: 12, weight: .regular, filled: false, help: "Ajustes de Agent Desk") { store.showMenu?() }
                .padding(.trailing, 2)
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .fixedSize()
        .modifier(Glass(radius: 16, veil: 0.8))
        .shadow(color: .black.opacity(0.4), radius: 22, x: 0, y: 10)
        .padding(.horizontal, 30).padding(.top, 36).padding(.bottom, 14) // sitio para la sombra
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { _ in
            accessibility = Sender.accessibilityGranted(prompt: false)
        }
        .sheet(item: $sheet) { key in KeyEditor(key: key, isNew: false) { store.update($0) } }
        .sheet(isPresented: $adding) {
            KeyEditor(key: DeskKey(label: "", text: "", icon: "sparkles"), isNew: true) { store.add($0) }
        }
    }
}

/// La tecla de dictar: micro en reposo; escuchando, onda dorada que sigue tu voz y el texto parcial debajo.
struct DictateItem: View {
    @ObservedObject var store: DeskStore
    @State private var hover = false
    var body: some View {
        Button(action: { store.toggleDictation() }) {
            VStack(spacing: 6) {
                ZStack {
                    if store.listening {
                        Circle().fill(Palette.gold.opacity(0.18))
                            .frame(width: 18 + CGFloat(min(store.level * 140, 16)), height: 18 + CGFloat(min(store.level * 140, 16)))
                            .animation(.easeOut(duration: 0.08), value: store.level)
                    }
                    Image(systemName: store.listening ? "waveform" : "mic")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(store.listening ? Palette.gold : (hover ? Palette.ink : Palette.text))
                }
                .frame(width: 40, height: 17)
                Text(store.listening ? (store.partial.isEmpty ? "Escuchando…" : store.partial) : (store.dictationNote.isEmpty ? "Dictar" : store.dictationNote))
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
            .animation(.easeOut(duration: 0.14), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Dictar al chat (⌃⌥M): una pulsación escucha, otra envía")
    }
}

struct Divider_: View {
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.09)).frame(width: 1, height: 26).padding(.horizontal, 4)
    }
}

/// Un control redondo pequeño (la aspa, la edición).
struct DockGlyph: View {
    let symbol: String
    let size: CGFloat
    let weight: Font.Weight
    let filled: Bool
    let help: String
    var tint: Color? = nil
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: weight))
                .foregroundColor(tint ?? (filled ? Palette.bg : (hover ? Palette.ink : Palette.mute)))
                .frame(width: 26, height: 26)
                .background(Circle().fill(filled ? Color.white.opacity(hover ? 1 : 0.92) : Color.white.opacity(hover ? 0.10 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

/// Una tecla de la barra: icono grande arriba, etiqueta debajo, el número del atajo en la esquina.
struct DockItem: View {
    let icon: String
    let label: String
    let hotkey: Int?
    let main: Bool
    let editing: Bool
    let tint: Color?
    let help: String
    let press: () -> Void
    let edit: () -> Void
    let remove: () -> Void
    @State private var hover = false
    @State private var pressed = false

    var body: some View {
        Button(action: { editing ? edit() : press() }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(tint ?? (hover || main ? Palette.ink : Palette.text))
                    .frame(height: 17)
                Text(label)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(tint ?? (hover ? Palette.ink : Palette.mute))
                    .lineLimit(1)
            }
            .frame(minWidth: 54)
            .padding(.horizontal, 6).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(hover ? 0.09 : 0)))
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
            .scaleEffect(pressed ? 0.93 : 1)
            .animation(.easeOut(duration: 0.1), value: pressed)
            .animation(.easeOut(duration: 0.14), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .pressEvents(onPress: { pressed = true }, onRelease: { pressed = false })
        .help(help)
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
        .modifier(Glass(radius: 18, veil: 0.5))
        .padding(10)
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
            Text("AGENT DESK").font(.system(size: 11, weight: .medium, design: .monospaced)).tracking(2.2).foregroundColor(Palette.mute)
            Spacer()
            Text(target).font(.system(size: 11, weight: .regular)).foregroundColor(Palette.faint).lineLimit(1)
            Button(action: { store.editing.toggle() }) {
                Image(systemName: store.editing ? "checkmark" : "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(store.editing ? Palette.gold : Palette.mute)
            }
            .buttonStyle(.plain)
            .help(store.editing ? "Terminar edición" : "Editar teclas")
        }
    }

    private var permissionNote: some View {
        Button(action: { _ = Sender.accessibilityGranted(prompt: true) }) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised").foregroundColor(Palette.gold)
                Text("Permite Accesibilidad para que el Desk pueda escribir en el chat.")
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
            Text(store.lastSent.isEmpty ? "pulsa una tecla, o ⌃⌥ y su número" : "enviado \(store.lastSent)")
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
            .animation(.easeOut(duration: 0.12), value: pressed)
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
            Text(isNew ? "Nueva tecla" : "Editar tecla").font(.system(size: 13, weight: .semibold)).foregroundColor(Palette.ink)
            TextField("Nombre corto (lo que se ve)", text: $key.label).textFieldStyle(.roundedBorder)
            TextField("Lo que se escribe en el chat", text: $key.text, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
            Text("Icono").font(.system(size: 11, weight: .medium)).foregroundColor(Palette.mute)
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
            Toggle("Pulsar Intro al enviar", isOn: $key.sendEnter).toggleStyle(.switch).font(.system(size: 12))
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Añadir" : "Guardar") {
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
