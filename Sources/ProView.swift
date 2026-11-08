import AppKit
import SwiftUI

/// La ventana de Agent Bar Pro: qué incluye, comprarla y activar la licencia.
struct ProView: View {
    @ObservedObject var license: License
    /// Dentro del panel de ajustes: sin título propio (lo pone el panel) ni ancho fijo.
    var embedded = false
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                if !embedded { Text("Agent Bar Pro").font(.system(size: 26, weight: .semibold)) }
                Text(T.s("49 € · once · 3 Macs", "49 € · una vez · 3 Macs")).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                if !embedded { Spacer() }
            }
            VStack(alignment: .leading, spacing: 9) {
                row("airplane", T.s("Autopilot: Claude Code keeps going on its own and stops at a real question.", "Piloto automático: Claude Code sigue solo y para ante una pregunta de verdad."))
                row("mic.fill", T.s("Voice included: talk without your own OpenAI key (monthly minutes included).", "Voz incluida: habla sin tu propia clave de OpenAI (minutos al mes incluidos)."))
                row("iphone", T.s("Alerts on your phone, and answer from there.", "Avisos en el móvil, y contestar desde allí."))
                row("keyboard", T.s("Works with Agent Pad when it ships.", "Funciona con Agent Pad cuando salga."))
                row("heart", T.s("Pay once. Updates included. Everything free stays free.", "Pagas una vez. Actualizaciones incluidas. Lo gratis sigue gratis."))
            }
            Divider()
            if license.isPro, let s = license.saved {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(T.s("Pro is on", "Pro activado")).fontWeight(.semibold)
                        Text(s.email.isEmpty ? T.s("On this Mac", "En este Mac") : s.email).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(T.s("Deactivate on this Mac", "Desactivar en este Mac")) { license.deactivate() }.disabled(license.working)
                }
            } else {
                HStack {
                    Button { NSWorkspace.shared.open(License.checkoutURL) } label: { Text(T.s("Buy Pro · 49 €", "Comprar Pro · 49 €")).fontWeight(.semibold).padding(.horizontal, 6) }
                        .controlSize(.large).keyboardShortcut(.defaultAction)
                    Spacer()
                }
                HStack {
                    TextField(T.s("License key from your purchase email", "Clave de licencia del correo de tu compra"), text: $key).textFieldStyle(.roundedBorder)
                    Button(T.s("Activate", "Activar")) { license.activate(key) }.disabled(license.working || key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if !license.message.isEmpty { Text(license.message).font(.callout).foregroundStyle(.secondary) }
            if !License.enforced {
                Text(T.s("During the beta everything is free: you don't need Pro yet.", "Durante la beta todo es gratis: aún no necesitas Pro."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(embedded ? 0 : 28)
        .frame(width: embedded ? nil : 520, alignment: .leading)
        .frame(maxWidth: embedded ? 560 : nil, alignment: .leading)
    }

    private func row(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).frame(width: 20).foregroundStyle(Color(red: 1, green: 0.357, blue: 0.122))
            Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
