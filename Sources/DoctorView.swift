import AppKit
import AVFoundation
import SwiftUI

/// Ajustes → Diagnóstico: arriba, una línea con el estado y el arreglo de lo primero que falla; debajo, lo que hay que
/// arreglar (cada cosa con su botón) y lo que ya está bien, plegado en filas cortas. Se vuelve a mirar cada 3 s mientras
/// está abierto, para que al dar un permiso en Ajustes del Sistema se vea al momento.
@MainActor
struct DoctorPane: View {
    @ObservedObject var voice: VoiceController
    @ObservedObject var updater = Updater.shared
    var actions = DashboardActions()
    var goTo: (DashPane) -> Void = { _ in }
    @State private var input = Doctor.Input()
    @State private var copied = false
    @State private var notify = DoctorLive.notifyCrashes
    @State private var cleaned = 0
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    private var checks: [Doctor.Check] { Doctor.checks(input) }

    var body: some View {
        let all = checks, problems = Doctor.problems(all)
        let fine = all.filter { $0.level < .warn }
        VStack(alignment: .leading, spacing: 22) {
            summary(problems, total: all.count)
            if !problems.isEmpty {
                DashSection(title: T.s("To fix", "Para arreglar")) {
                    ForEach(Array(problems.enumerated()), id: \.element.id) { n, c in row(c, divider: n < problems.count - 1) }
                }
            }
            DashSection(title: T.s("Checked", "Comprobado")) {
                ForEach(Array(fine.enumerated()), id: \.element.id) { n, c in row(c, divider: n < fine.count - 1) }
            }
            DashSection(title: T.s("Support", "Soporte"), footer: T.s("The report has no dictations, no keys and no personal paths. Nothing is sent by itself: a crash report opens as an email you can read before sending.", "El informe no lleva lo dictado, ni claves, ni rutas personales. Nada se envía solo: el informe de un fallo se abre como un correo que lees antes de enviarlo.")) {
                DashRow(title: T.s("Copy a report", "Copiar un informe"), detail: T.s("Everything above, as text, to paste in an email.", "Todo lo de arriba, en texto, para pegarlo en un correo."), symbol: "doc.on.clipboard") {
                    Button(copied ? T.s("Copied", "Copiado") : T.s("Copy", "Copiar")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Doctor.report(all, input, os: DoctorLive.osLine), forType: .string)
                        copied = true; DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                    }.controlSize(.small)
                }
                DashToggle(title: T.s("Tell me if Agent Bar quits unexpectedly", "Avisarme si Agent Bar se cierra de golpe"), detail: T.s("A note in the bar the next time it opens, to send the report if you want.", "Una nota en la barra la próxima vez que se abra, para enviar el informe si quieres."), isOn: Binding(get: { notify }, set: { notify = $0; DoctorLive.notifyCrashes = $0 }), divider: false)
            }
        }
        .onAppear { load(); cleaned = DoctorLive.cleanHooks() }
        .onReceive(timer) { _ in load() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in load() }
    }

    private func load() {
        let fresh = DoctorLive.input(voice: voice)
        // la hora no cuenta: si no cambia nada más, no se redibuja
        var a = fresh, b = input; a.now = .distantPast; b.now = .distantPast
        if a != b || Int(fresh.now.timeIntervalSince(input.now)) >= 60 { input = fresh }
    }

    // MARK: arriba

    private func summary(_ problems: [Doctor.Check], total: Int) -> some View {
        let first = problems.first
        let color = first == nil ? Color(hex: 0x30d158) : first!.level == .fail ? Color(hex: 0xff453a) : Color(hex: 0xff9f0a)
        return HStack(alignment: .center, spacing: 14) {
            Image(systemName: first == nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 30, weight: .regular)).foregroundStyle(color).symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 3) {
                Text(first == nil ? T.s("Everything works", "Todo en orden")
                     : problems.count == 1 ? T.s("1 thing to fix", "1 cosa que arreglar") : T.s("\(problems.count) things to fix", "\(problems.count) cosas que arreglar"))
                    .font(.system(size: 15, weight: .semibold))
                Text(first.map { T.s("First: ", "Lo primero: ") + $0.title } ?? (T.s("\(total) checks", "\(total) comprobaciones") + (cleaned > 0 ? T.s(" · \(cleaned) old alert files cleaned", " · \(cleaned) archivos de avisos viejos limpiados") : "")))
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 12)
            if let a = first?.actions.first {
                Button(a.title) { run(a.fix) }.buttonStyle(.borderedProminent).controlSize(.regular)
            } else {
                Button(T.s("Check again", "Volver a comprobar")) { load(); input.now = Date() }.controlSize(.regular)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(color.opacity(0.22), lineWidth: 0.5))
    }

    // MARK: filas

    private func row(_ c: Doctor.Check, divider: Bool) -> some View {
        let tested = c.id == "voice" && !voice.keyTest.isEmpty
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                icon(c.level).frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title).font(.system(size: 13))
                    let d = tested ? voice.keyTest : c.detail
                    if !d.isEmpty { Text(d).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
                }
                Spacer(minLength: 16)
                ForEach(Array(c.actions.enumerated()), id: \.offset) { n, a in
                    if n == 0 && c.level >= .warn {
                        Button(a.title) { run(a.fix) }.buttonStyle(.borderedProminent).controlSize(.small)
                    } else {
                        Button(a.fix == .testKey && voice.keyTesting ? T.s("Testing…", "Probando…") : a.title) { run(a.fix) }.controlSize(.small).disabled(a.fix == .testKey && voice.keyTesting)
                    }
                }
            }.padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 40)
            if divider { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 0.5).padding(.leading, 46) }
        }
    }
    @ViewBuilder private func icon(_ l: Doctor.Level) -> some View {
        switch l {
        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(hex: 0x30d158))
        case .info: Image(systemName: "minus.circle.fill").foregroundStyle(Color.secondary.opacity(0.6))
        case .warn: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(hex: 0xff9f0a))
        case .fail: Image(systemName: "xmark.circle.fill").foregroundStyle(Color(hex: 0xff453a))
        }
    }

    private func run(_ f: Doctor.Fix) {
        switch f {
        case .accessibility: actions.openAccessibility()
        case .microphone: DoctorLive.openPrivacy("Privacy_Microphone")
        case .microphoneAsk: AVCaptureDevice.requestAccess(for: .audio) { _ in DispatchQueue.main.async { load() } }
        case .speech: DoctorLive.openPrivacy("Privacy_SpeechRecognition")
        case .connectClaude: actions.connectClaude()
        case .resumeAlerts: ClaudeHooks.paused = false
        case .update: updater.install()
        case .moveToApplications: actions.moveToApplications()
        case .registerHere: DoctorLive.registerHere()
        case .testKey: voice.testKey()
        case .voiceSettings: goTo(.voice)
        case .sendCrash: if let c = input.crash, let u = Doctor.crashMail(c) { NSWorkspace.shared.open(u) }
        case .dismissCrash: DoctorLive.dismissedCrash = Date()
        case .reinstall: if let u = URL(string: "https://getagentbar.com") { NSWorkspace.shared.open(u) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { load() }
    }
}
