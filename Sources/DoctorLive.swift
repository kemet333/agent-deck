import AppKit
import AVFoundation
import Speech

/// El diagnóstico con los datos de verdad de este Mac (la lógica está en Doctor.swift).
@MainActor
enum DoctorLive {
    /// La última vez que se pulsó Fn para dictar (la apunta VoiceHotkeys).
    static var lastFn: Date?
    /// El tap de Fn está puesto (lo dice el AppDelegate).
    static var fnReady: () -> Bool = { true }

    static func input(voice: VoiceController) -> Doctor.Input {
        var i = Doctor.Input()
        i.version = Updater.current
        i.accessibility = Sender.accessibilityGranted(prompt: false)
        i.mic = perm(AVCaptureDevice.authorizationStatus(for: .audio))
        i.micDevice = AVCaptureDevice.default(for: .audio) != nil
        i.appleEngine = voice.preferences.engine == .apple
        switch SFSpeechRecognizer.authorizationStatus() { case .authorized: i.speech = .granted; case .notDetermined: i.speech = .notAsked; default: i.speech = .denied }
        i.keyConfigured = voice.keyConfigured
        i.proVoice = ProVoice.available
        i.fnEnabled = voice.preferences.fnEnabled
        i.keyName = voice.preferences.talkKey.short
        i.fnReady = fnReady()
        i.lastFn = lastFn
        i.voiceFailures = Doctor.failures(log: (try? String(contentsOf: Autopilot.folder.appendingPathComponent("voice.log"), encoding: .utf8)) ?? "")
        let home = FileManager.default.homeDirectoryForCurrentUser
        i.claudePresent = FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude").path)
        i.hooksInstalled = ClaudeHooks.installed
        i.hooksOld = ClaudeHooks.oldVersion
        i.permissionsInstalled = ClaudeHooks.permissionsInstalled
        i.alertsPaused = ClaudeHooks.paused
        i.permissionsPaused = ClaudeHooks.permissionsPaused
        i.helperOK = FileManager.default.isExecutableFile(atPath: ClaudeHooks.helper)
        if let h = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "agentdeck://alert")!)?.resolvingSymlinksInPath(),
           h.path != Bundle.main.bundleURL.resolvingSymlinksInPath().path { i.urlHandler = Doctor.scrub(h.path) }
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        i.inApplications = path.hasPrefix("/Applications/") || path.hasPrefix(home.path + "/Applications/") || path.hasPrefix(home.path + "/Agent-Deck/")
        i.update = Updater.shared.available?.version
        i.dataWritable = writable()
        i.crash = latestCrash(after: dismissedCrash)
        return i
    }
    private static func perm(_ s: AVAuthorizationStatus) -> Doctor.Perm {
        switch s { case .authorized: return .granted; case .notDetermined: return .notAsked; default: return .denied }
    }
    private static func writable() -> Bool {
        let probe = Autopilot.folder.appendingPathComponent(".doctor-probe")
        try? FileManager.default.createDirectory(at: Autopilot.folder, withIntermediateDirectories: true)
        guard (try? Data().write(to: probe)) != nil else { return false }
        try? FileManager.default.removeItem(at: probe); return true
    }

    static var osLine: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    // MARK: limpieza

    /// Borra lo que dejaron ganchos que ya no esperan (Claude Code cerrado a medias, el Mac reiniciado…).
    @discardableResult
    static func cleanHooks() -> Int {
        let dir = Autopilot.folder.appendingPathComponent("hooks"), fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []).map {
            (name: $0.lastPathComponent, modified: (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date())
        }
        let old = Doctor.stale(files)
        for n in old { try? fm.removeItem(at: dir.appendingPathComponent(n)) }
        return old.count
    }

    // MARK: informes de fallo (los escribe macOS en ~/Library/Logs/DiagnosticReports)

    static var crashFolder: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports") }
    /// Avisar al abrir si la vez anterior se cerró de golpe (Ajustes → Diagnóstico; encendido salvo que se apague).
    static var notifyCrashes: Bool {
        get { UserDefaults.standard.object(forKey: "notifyCrashes") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "notifyCrashes") }
    }
    static var dismissedCrash: Date {
        get { UserDefaults.standard.object(forKey: "crashDismissed") as? Date ?? Date.distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "crashDismissed") }
    }
    /// El último informe de Agent Bar (o de su ayudante) de los últimos 14 días, más nuevo que `after`.
    static func latestCrash(after: Date) -> Doctor.Crash? {
        let fm = FileManager.default
        let limit = max(after, Date().addingTimeInterval(-14 * 86_400))
        let files = ((try? fm.contentsOfDirectory(at: crashFolder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { let n = $0.lastPathComponent; return ($0.pathExtension == "ips" || $0.pathExtension == "crash") && (n.hasPrefix("AgentDesk") || n.hasPrefix("AgentBarClaudeHook") || n.hasPrefix("Agent Bar")) }
            .compactMap { u -> (URL, Date)? in
                guard let d = try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, d > limit else { return nil }
                return (u, d)
            }.sorted { $0.1 > $1.1 }
        guard let (url, modified) = files.first, let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        if let c = Doctor.crash(ips: text, file: url.lastPathComponent) {
            return c.date == .distantPast ? Doctor.Crash(date: modified, version: c.version, os: c.os, kind: c.kind, frames: c.frames, file: c.file) : c
        }
        return Doctor.Crash(date: modified, version: "?", os: "", kind: T.s("unknown", "desconocido"), frames: [], file: url.lastPathComponent)
    }
    /// Al abrir: si hay un fallo nuevo y no se ha avisado ya, una nota en la barra.
    static func checkCrashOnLaunch(note: (String) -> Void) {
        guard notifyCrashes else { return }
        let told = UserDefaults.standard.object(forKey: "crashNoticed") as? Date ?? Date.distantPast
        guard let c = latestCrash(after: max(told, dismissedCrash)) else { return }
        UserDefaults.standard.set(Date(), forKey: "crashNoticed"); _ = c
        note(T.s("Agent Bar quit unexpectedly last time: Settings → Diagnostics", "Agent Bar se cerró de golpe la última vez: Ajustes → Diagnóstico"))
    }

    // MARK: arreglos

    static func openPrivacy(_ anchor: String) {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") { NSWorkspace.shared.open(u) }
    }
    /// Hace que agentdeck:// lo abra esta copia (si había otra registrada).
    static func registerHere() {
        LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "agentdeck") { _ in }
    }
}
