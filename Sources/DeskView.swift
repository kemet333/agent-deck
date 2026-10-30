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
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct DeskView: View {
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
        .background(
            ZStack {
                VisualEffect()
                Palette.bg.opacity(0.78)
                LinearGradient(colors: [Color.white.opacity(0.07), Color.white.opacity(0.02), Color.white.opacity(0.01)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { _ in
            target = Sender.targetName()
            accessibility = Sender.accessibilityGranted(prompt: false)
        }
        .sheet(item: $sheet) { key in KeyEditor(key: key, isNew: false) { store.update($0) } }
        .sheet(isPresented: $adding) {
            KeyEditor(key: DeskKey(label: "", text: ""), isNew: true) { store.add(label: $0.label, text: $0.text, sendEnter: $0.sendEnter) }
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
            HStack(alignment: .top, spacing: 6) {
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
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.panel.opacity(hover ? 1 : 0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(hover || key.hotkey == 1 ? Palette.gold.opacity(hover ? 0.9 : 0.55) : Palette.line, lineWidth: 1)
            )
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

struct KeyEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var key: DeskKey
    let isNew: Bool
    let save: (DeskKey) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "Nueva tecla" : "Editar tecla").font(.system(size: 13, weight: .semibold)).foregroundColor(Palette.ink)
            TextField("Nombre corto (lo que se ve)", text: $key.label).textFieldStyle(.roundedBorder)
            TextField("Lo que se escribe en el chat", text: $key.text, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
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
        .frame(width: 320)
    }
}

extension View {
    func pressEvents(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in onPress() }
            .onEnded { _ in onRelease() })
    }
}
