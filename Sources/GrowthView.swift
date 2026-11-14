import AppKit
import SwiftUI

/// Ajustes → Packs de teclas (0.19): la galería curada de getagentbar.com/packs, con buscador y herramientas, y debajo
/// compartir tus teclas y proponerlas para la galería.
@MainActor
struct PacksPane: View {
    @ObservedObject var store: DeskStore
    @ObservedObject var gallery = GalleryStore.shared
    var actions = DashboardActions()
    @State private var query = ""
    @State private var tool: String?

    var body: some View {
        let es = T.es
        let shown = Gallery.filter(gallery.packs, query: query, tool: tool)
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12))
                    TextField(T.s("Search packs", "Buscar packs"), text: $query).textFieldStyle(.plain).font(.system(size: 13))
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain) }
                }
                .padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
                if gallery.loading { ProgressView().controlSize(.small) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(T.s("All", "Todos"), selected: tool == nil) { tool = nil }
                    ForEach(Gallery.tools(gallery.packs), id: \.self) { t in chip(Gallery.toolName(t), selected: tool == t) { tool = tool == t ? nil : t } }
                }
            }
            if shown.isEmpty {
                Text(T.s("No pack matches «\(query)». Propose yours below.", "Ningún pack coincide con «\(query)». Propón el tuyo abajo."))
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 20).frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(shown) { g in card(g, es: es) }
                }
            }
            DashSection(title: T.s("Share", "Compartir"), footer: T.s("A pack link carries the whole pack. Agent Bar always asks before adding it. Proposals are read by hand before they go in the gallery.",
                                                                     "Un enlace de pack lleva el pack entero. Agent Bar siempre pregunta antes de añadirlo. Las propuestas se leen a mano antes de entrar en la galería.")) {
                DashRow(title: T.s("Share my keys", "Compartir mis teclas"), detail: T.s("Copies a link to your keys (not your team's)", "Copia un enlace con tus teclas (no las del equipo)"), symbol: "link") {
                    Button(T.s("Copy link", "Copiar enlace"), action: actions.shareKeys).controlSize(.small)
                }
                DashRow(title: T.s("Propose them for the gallery", "Proponerlas para la galería"), detail: T.s("Opens an email with your pack. You read it and send it.", "Abre un correo con tu pack. Lo lees y lo envías."), symbol: "envelope") {
                    Button(T.s("Propose…", "Proponer…")) { if let u = Gallery.proposal(store.currentPack) { NSWorkspace.shared.open(u) } }
                        .controlSize(.small).disabled(store.currentPack.keys.isEmpty)
                }
                DashRow(title: T.s("On the web", "En la web"), detail: "getagentbar.com/packs", symbol: "safari", divider: false) { Button(T.s("Open", "Abrir"), action: actions.morePacks).controlSize(.small) }
            }
        }
        .onAppear { gallery.refresh() }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { action() } }) {
            Text(title).font(.system(size: 11.5, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 5)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(Capsule().fill(selected ? AnyShapeStyle(Color(hex: 0x5e5ce6)) : AnyShapeStyle(Color.primary.opacity(0.06))))
        }.buttonStyle(.plain)
    }

    private func card(_ g: GalleryPack, es: Bool) -> some View {
        let p = g.pack(spanish: es)
        let have = Set(store.keys.map(\.text))
        let added = p.keys.allSatisfy { have.contains($0.text) }
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(p.name).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text(T.s("\(p.keys.count) keys", "\(p.keys.count) teclas")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text("\(Gallery.toolName(g.tool)) · \(T.s("by", "de")) \(g.by)").font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
            Text(g.summary(spanish: es)).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            FlowChips(keys: p.keys)
            Spacer(minLength: 0)
            Button { actions.offerPack(p) } label: {
                Label(added ? T.s("Added", "Añadido") : T.s("Add to Agent Bar…", "Añadir a Agent Bar…"), systemImage: added ? "checkmark" : "plus").frame(maxWidth: .infinity)
            }.controlSize(.regular).disabled(added)
        }
        .padding(16).frame(minHeight: 200, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}

/// Ajustes → Equipo (0.19): seguir el pack de tu equipo (o crearlo si lo llevas tú) e invitar a otros.
@MainActor
struct TeamPane: View {
    @ObservedObject var store: DeskStore
    @ObservedObject var voice: VoiceController
    @ObservedObject var sync = TeamSync.shared
    @State private var link = ""
    @State private var code = InviteLive.code
    @State private var copied = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let t = sync.team { joined(t) } else { join }
            DashSection(title: T.s("Do you run the team?", "¿Llevas tú el equipo?"), footer: T.s("The file carries your keys (not another team's) and your voice dictionary. Change it and save it again: everyone gets it within 12 hours, or at once with «Check now».",
                                                                                                 "El archivo lleva tus teclas (no las de otro equipo) y tu diccionario de voz. Cámbialo y vuelve a guardarlo: a todos les llega en menos de 12 horas, o al momento con «Comprobar ahora».")) {
                DashRow(title: T.s("Create a team file", "Crear un archivo de equipo"), detail: T.s("\(Team.strip(store.keys).count) keys · \(dictionaryWords.count) words", "\(Team.strip(store.keys).count) teclas · \(dictionaryWords.count) palabras"), symbol: "square.and.arrow.down", divider: false) {
                    Button(T.s("Create…", "Crear…")) { if !store.needsPro(T.s("Creating a team", "Crear un equipo")) { TeamSync.exportDialog(keys: store.keys, vocabulary: dictionaryWords) } }.controlSize(.small)
                }
            }
            invite
        }
    }

    private var dictionaryWords: [String] {
        voice.preferences.dictionary.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.contains("<") }
    }

    // MARK: sin equipo

    private var join: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "person.2.circle.fill").font(.system(size: 30)).foregroundStyle(Color(hex: 0x64d2ff)).symbolRenderingMode(.hierarchical)
                VStack(alignment: .leading, spacing: 3) {
                    Text(T.s("Follow your team's keys", "Sigue las teclas de tu equipo")).font(.system(size: 15, weight: .semibold))
                    Text(T.s("Paste the link your team gave you, or choose its file from a shared folder. Your own keys stay; the team's are added after them and update by themselves.",
                             "Pega el enlace que te ha dado tu equipo o elige su archivo de una carpeta compartida. Tus teclas se quedan; las del equipo se añaden detrás y se actualizan solas."))
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                TextField(T.s("https://… or getagentbar.com/team/#…", "https://… o getagentbar.com/team/#…"), text: $link)
                    .textFieldStyle(.roundedBorder).font(.system(size: 12)).onSubmit(submit)
                Button(T.s("Join…", "Unirme…"), action: submit).buttonStyle(.borderedProminent).disabled(link.trimmingCharacters(in: .whitespaces).isEmpty || sync.working)
                Button(T.s("Choose file…", "Elegir archivo…")) { sync.chooseFile() }.disabled(sync.working)
            }
            if sync.working { HStack(spacing: 6) { ProgressView().controlSize(.small); Text(T.s("Reading the team file…", "Leyendo el archivo del equipo…")).font(.system(size: 11)).foregroundStyle(.secondary) } }
            else if !sync.problem.isEmpty { Label(sync.problem, systemImage: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(Color(hex: 0xff9f0a)) }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x64d2ff).opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(hex: 0x64d2ff).opacity(0.2), lineWidth: 0.5))
    }
    private func submit() {
        var raw = link.trimmingCharacters(in: .whitespacesAndNewlines)
        // el enlace de la web para unirse lleva la dirección del archivo detrás de #
        if raw.contains("getagentbar.com/team"), let h = raw.firstIndex(of: "#") { raw = String(raw[raw.index(after: h)...]).removingPercentEncoding ?? raw }
        Task { await sync.offer(raw); if sync.team != nil { link = "" } }
    }

    // MARK: con equipo

    private func joined(_ t: TeamPack) -> some View {
        let teamKeys = store.keys.filter { $0.team == t.name }
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "person.2.circle.fill").font(.system(size: 30)).foregroundStyle(Color(hex: 0x64d2ff)).symbolRenderingMode(.hierarchical)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t.name).font(.system(size: 15, weight: .semibold))
                        Text(T.s("\(teamKeys.count) keys · \(t.words.count) words for your voice", "\(teamKeys.count) teclas · \(t.words.count) palabras para tu voz"))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button(sync.working ? T.s("Checking…", "Comprobando…") : T.s("Check now", "Comprobar ahora")) { Task { await sync.refresh() } }.disabled(sync.working)
                }
                if let m = t.message, !m.isEmpty {
                    Text("«\(m)»").font(.system(size: 12)).foregroundStyle(.primary.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                }
                if !teamKeys.isEmpty { FlowChips(keys: teamKeys.map { KeyPack.Key(label: $0.label, text: $0.text, icon: $0.icon, enter: $0.sendEnter) }) }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x64d2ff).opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(hex: 0x64d2ff).opacity(0.2), lineWidth: 0.5))

            DashSection(title: T.s("Your team", "Tu equipo"), footer: T.s("Team keys are marked in Keys. If you edit one, the next update puts the team's version back.", "Las teclas del equipo van marcadas en Teclas. Si cambias una, la siguiente actualización vuelve a poner la del equipo.")) {
                DashRow(title: T.s("Comes from", "Viene de"), detail: sync.sourceLabel + (sync.checked.map { " · " + T.s("checked ", "comprobado ") + Doctor.ago($0, now: Date()) } ?? ""), symbol: "arrow.down.circle") {
                    if !sync.problem.isEmpty { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(hex: 0xff9f0a)).help(sync.problem) }
                }
                if let s = sync.source, let l = Team.joinLink(s) {
                    DashRow(title: T.s("Invite a teammate", "Invitar a un compañero"), detail: T.s("A link that opens Agent Bar and asks to join", "Un enlace que abre Agent Bar y pregunta si unirse"), symbol: "link") {
                        Button(copied == "team" ? T.s("Copied", "Copiado") : T.s("Copy link", "Copiar enlace")) { copy(l, "team") }.controlSize(.small)
                    }
                }
                DashRow(title: T.s("Leave the team", "Salir del equipo"), detail: T.s("Its keys and words go; yours stay", "Sus teclas y palabras se van; las tuyas se quedan"), symbol: "rectangle.portrait.and.arrow.right", divider: false) {
                    Button(T.s("Leave…", "Salir…")) { confirmLeave(t) }.controlSize(.small)
                }
            }
        }
    }
    private func confirmLeave(_ t: TeamPack) {
        let a = NSAlert()
        a.messageText = T.s("Leave «\(t.name)»?", "¿Salir de «\(t.name)»?")
        a.informativeText = T.s("Its keys leave your bar. You can join again with the same link.", "Sus teclas se van de tu barra. Puedes volver a unirte con el mismo enlace.")
        a.addButton(withTitle: T.s("Leave", "Salir")); a.addButton(withTitle: T.s("Cancel", "Cancelar"))
        if a.runModal() == .alertFirstButtonReturn { sync.leave() }
    }

    // MARK: invitar

    @ViewBuilder private var invite: some View {
        DashSection(title: T.s("Invite someone", "Invitar a alguien"), footer: Invite.signup == nil
                    ? T.s("A message with the download link, ready to paste.", "Un mensaje con el enlace de descarga, listo para pegar.")
                    : T.s("Join the affiliate program to get your code: purchases through your links are tracked and paid by Lemon Squeezy.", "Apúntate al programa de afiliados para tener tu código: Lemon Squeezy cuenta y paga las compras que lleguen por tus enlaces.")) {
            DashRow(title: T.s("Copy an invitation", "Copiar una invitación"), detail: Invite.link(code: code), symbol: "paperplane", divider: Invite.signup != nil) {
                Button(copied == "invite" ? T.s("Copied", "Copiado") : T.s("Copy", "Copiar")) { copy(Invite.message(code: code, pack: nil), "invite") }.controlSize(.small)
            }
            if let signup = Invite.signup {
                DashRow(title: T.s("Your affiliate code", "Tu código de afiliado"), detail: T.s("It goes in your invitations and pack links", "Va en tus invitaciones y enlaces de packs"), symbol: "number") {
                    TextField("ZylBs", text: $code).textFieldStyle(.roundedBorder).frame(width: 130).font(.system(size: 12))
                        .onChange(of: code) { _, v in InviteLive.code = v }
                }
                DashRow(title: T.s("Become an affiliate", "Hacerme afiliado"), detail: signup.host ?? "", symbol: "person.badge.plus", divider: false) {
                    Button(T.s("Open", "Abrir")) { NSWorkspace.shared.open(signup) }.controlSize(.small)
                }
            }
        }
    }

    private func copy(_ s: String, _ which: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string)
        copied = which; DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if copied == which { copied = "" } }
    }
}
